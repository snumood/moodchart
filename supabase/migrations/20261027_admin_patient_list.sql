-- Patient list for the Google OAuth moodchart administrator, plus an access log.
-- Apply after 20260729_admin_google_oauth.sql. Patient auth is unchanged.
--
-- Security model:
--   * Every function checks public.is_moodchart_admin() (Google-verified, allow-listed email).
--   * EXECUTE is revoked from PUBLIC/anon; only authenticated may call, then the admin check applies.
--   * The list returns only username, hospital_id, created_at and record activity.
--     Passwords, points, inventory and record values are never returned by the list.
--   * Listing, selecting, viewing and downloading write rows to an admin-only access log.

CREATE TABLE IF NOT EXISTS public.moodchart_admin_access_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_user_id UUID NOT NULL,
    admin_email TEXT NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('list', 'select', 'view', 'download')),
    target_username TEXT,
    result_count INTEGER,
    range_start DATE,
    range_end DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.moodchart_admin_access_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.moodchart_admin_access_log FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS idx_moodchart_admin_access_log_created_at
    ON public.moodchart_admin_access_log(created_at);

CREATE OR REPLACE FUNCTION public.moodchart_admin_log_access(
    p_action TEXT,
    p_target TEXT,
    p_count INTEGER DEFAULT NULL,
    p_start DATE DEFAULT NULL,
    p_end DATE DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_email TEXT;
BEGIN
    SELECT lower(u.email) INTO v_email FROM auth.users AS u WHERE u.id = v_uid;
    INSERT INTO public.moodchart_admin_access_log
        (admin_user_id, admin_email, action, target_username, result_count, range_start, range_end)
    VALUES (v_uid, COALESCE(v_email, ''), p_action, p_target, p_count, p_start, p_end);
END;
$$;

REVOKE ALL ON FUNCTION public.moodchart_admin_log_access(TEXT, TEXT, INTEGER, DATE, DATE) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.moodchart_admin_list_patients(
    p_search TEXT DEFAULT '',
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE(
    username TEXT,
    hospital_id TEXT,
    created_at TIMESTAMPTZ,
    last_record_date DATE,
    record_days INTEGER,
    total_count INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
    v_search TEXT := btrim(COALESCE(p_search, ''));
    v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
    v_offset INTEGER := LEAST(GREATEST(COALESCE(p_offset, 0), 0), 100000);
    v_pattern TEXT;
    v_rows INTEGER;
BEGIN
    IF NOT public.is_moodchart_admin() THEN
        RAISE EXCEPTION 'Admin authorization required' USING ERRCODE = '42501';
    END IF;

    IF char_length(v_search) > 100 THEN
        RAISE EXCEPTION 'Search text too long' USING ERRCODE = '22023';
    END IF;

    -- Escape LIKE wildcards so the search is a plain substring match.
    v_pattern := '%' || replace(replace(replace(v_search, '\', '\\'), '%', '\%'), '_', '\_') || '%';

    RETURN QUERY
    WITH matched AS (
        SELECT u.username::TEXT AS username,
               NULLIF(btrim(COALESCE(u.hospital_id::TEXT, '')), '') AS hospital_id,
               u.created_at::TIMESTAMPTZ AS created_at
        FROM public.users AS u
        WHERE lower(u.username) NOT IN ('admin', 'administrator')
          AND (
              v_search = ''
              OR u.username ILIKE v_pattern ESCAPE '\'
              OR COALESCE(u.hospital_id::TEXT, '') ILIKE v_pattern ESCAPE '\'
          )
    ),
    activity AS (
        SELECT r.username,
               max(r.record_date) AS last_record_date,
               count(DISTINCT r.record_date)::INTEGER AS record_days
        FROM public.records AS r
        INNER JOIN matched AS m ON m.username = r.username
        WHERE r.category <> 'dummy'
          AND NULLIF(btrim(COALESCE(r.value, '')), '') IS NOT NULL
        GROUP BY r.username
    )
    SELECT m.username,
           m.hospital_id,
           m.created_at,
           a.last_record_date,
           COALESCE(a.record_days, 0),
           (count(*) OVER ())::INTEGER
    FROM matched AS m
    LEFT JOIN activity AS a ON a.username = m.username
    ORDER BY a.last_record_date DESC NULLS LAST, m.username
    LIMIT v_limit OFFSET v_offset;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM public.moodchart_admin_log_access('list', NULL, v_rows);
END;
$$;

-- Selection from the list: exact username only (no trimming, no hospital-id fallback).
CREATE OR REPLACE FUNCTION public.moodchart_admin_select_patient(p_username TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_target TEXT;
BEGIN
    IF NOT public.is_moodchart_admin() THEN
        RAISE EXCEPTION 'Admin authorization required' USING ERRCODE = '42501';
    END IF;

    IF p_username IS NULL OR char_length(p_username) > 200 THEN
        RETURN NULL;
    END IF;

    SELECT u.username INTO v_target FROM public.users AS u WHERE u.username = p_username;

    IF v_target IS NOT NULL THEN
        PERFORM public.moodchart_admin_log_access('select', v_target, NULL);
    END IF;

    RETURN v_target;
END;
$$;

-- Same contract as before; now records each record read (patient, range, row count).
CREATE OR REPLACE FUNCTION public.moodchart_admin_get_records(
    p_target TEXT,
    p_start DATE,
    p_end DATE
)
RETURNS TABLE(record_date DATE, category TEXT, value TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_rows INTEGER;
BEGIN
    IF NOT public.is_moodchart_admin() THEN
        RAISE EXCEPTION 'Admin authorization required' USING ERRCODE = '42501';
    END IF;

    IF p_target IS NULL OR p_start IS NULL OR p_end IS NULL OR p_start > p_end THEN
        RAISE EXCEPTION 'Invalid query';
    END IF;

    RETURN QUERY
    SELECT r.record_date, r.category, r.value
    FROM public.records AS r
    WHERE r.username = p_target
      AND r.record_date BETWEEN p_start AND p_end
    ORDER BY r.record_date, r.category;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    PERFORM public.moodchart_admin_log_access('view', p_target, v_rows, p_start, p_end);
END;
$$;

-- Same contract as before; now records which patient the administrator opened.
CREATE OR REPLACE FUNCTION public.moodchart_admin_resolve_patient(p_query TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_query TEXT := trim(COALESCE(p_query, ''));
    v_target TEXT;
BEGIN
    IF NOT public.is_moodchart_admin() THEN
        RAISE EXCEPTION 'Admin authorization required' USING ERRCODE = '42501';
    END IF;

    IF v_query = '' OR char_length(v_query) > 200 THEN
        RETURN NULL;
    END IF;

    SELECT u.username
    INTO v_target
    FROM public.users AS u
    WHERE u.username = v_query OR u.hospital_id = v_query
    ORDER BY CASE WHEN u.username = v_query THEN 0 ELSE 1 END
    LIMIT 1;

    IF v_target IS NOT NULL THEN
        PERFORM public.moodchart_admin_log_access('select', v_target, NULL);
    END IF;

    RETURN v_target;
END;
$$;

-- Same contract as before; now records the recovery download.
CREATE OR REPLACE FUNCTION public.moodchart_admin_download_by_hosp(p_hosp_id TEXT)
RETURNS TABLE(record_date DATE, category TEXT, value TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_hosp_id TEXT := trim(COALESCE(p_hosp_id, ''));
    v_target TEXT;
BEGIN
    IF NOT public.is_moodchart_admin() THEN
        RAISE EXCEPTION 'Admin authorization required' USING ERRCODE = '42501';
    END IF;

    IF v_hosp_id = '' OR char_length(v_hosp_id) > 200 THEN
        RAISE EXCEPTION 'Invalid hospital id';
    END IF;

    SELECT u.username
    INTO v_target
    FROM public.users AS u
    WHERE u.hospital_id = v_hosp_id
    LIMIT 1;

    IF v_target IS NULL THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    PERFORM public.moodchart_admin_log_access('download', v_target, NULL);

    RETURN QUERY
    SELECT r.record_date, r.category, r.value
    FROM public.records AS r
    WHERE r.username = v_target
    ORDER BY r.record_date, r.category;
END;
$$;

REVOKE ALL ON FUNCTION public.moodchart_admin_list_patients(TEXT, INTEGER, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_select_patient(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_get_records(TEXT, DATE, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_resolve_patient(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_download_by_hosp(TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.moodchart_admin_list_patients(TEXT, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_select_patient(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_get_records(TEXT, DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_resolve_patient(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_download_by_hosp(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
