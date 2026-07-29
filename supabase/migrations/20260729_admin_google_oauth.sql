-- Google OAuth administrator authorization for moodchart.
-- Patient username/password authentication remains unchanged.

CREATE TABLE IF NOT EXISTS public.moodchart_admins (
    email TEXT PRIMARY KEY,
    user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE RESTRICT,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    bound_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    CONSTRAINT moodchart_admins_email_lowercase CHECK (email = lower(email))
);

ALTER TABLE public.moodchart_admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.moodchart_admins FROM PUBLIC, anon, authenticated;

INSERT INTO public.moodchart_admins (email, enabled)
VALUES ('snumood@gmail.com', TRUE)
ON CONFLICT (email) DO UPDATE SET enabled = EXCLUDED.enabled;

CREATE OR REPLACE FUNCTION public.is_moodchart_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_email TEXT;
    v_is_confirmed BOOLEAN := FALSE;
    v_is_google BOOLEAN := FALSE;
BEGIN
    IF v_uid IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT
        lower(u.email),
        u.email_confirmed_at IS NOT NULL,
        COALESCE(u.raw_app_meta_data ->> 'provider', '') = 'google'
            OR COALESCE(u.raw_app_meta_data -> 'providers', '[]'::jsonb) ? 'google'
    INTO v_email, v_is_confirmed, v_is_google
    FROM auth.users AS u
    WHERE u.id = v_uid;

    IF v_email IS NULL OR NOT v_is_confirmed OR NOT v_is_google THEN
        RETURN FALSE;
    END IF;

    UPDATE public.moodchart_admins
    SET
        user_id = v_uid,
        bound_at = COALESCE(bound_at, now()),
        last_login_at = now()
    WHERE email = v_email
      AND enabled
      AND (user_id IS NULL OR user_id = v_uid);

    RETURN EXISTS (
        SELECT 1
        FROM public.moodchart_admins AS a
        WHERE a.email = v_email
          AND a.user_id = v_uid
          AND a.enabled
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.moodchart_admin_session()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
    SELECT public.is_moodchart_admin();
$$;

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

    RETURN v_target;
END;
$$;

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
END;
$$;

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

    RETURN QUERY
    SELECT r.record_date, r.category, r.value
    FROM public.records AS r
    WHERE r.username = v_target
    ORDER BY r.record_date, r.category;
END;
$$;

REVOKE ALL ON FUNCTION public.is_moodchart_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_session() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_resolve_patient(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_get_records(TEXT, DATE, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.moodchart_admin_download_by_hosp(TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.is_moodchart_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_session() TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_resolve_patient(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_get_records(TEXT, DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.moodchart_admin_download_by_hosp(TEXT) TO authenticated;
