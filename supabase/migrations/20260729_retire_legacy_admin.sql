-- Apply only after the Google OAuth administrator has been verified.
-- Removes the legacy password administrator while preserving patient auth.

REVOKE EXECUTE ON FUNCTION public.resolve_patient_id_secure(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_download_by_hosp_secure(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_records_secure(
    p_user TEXT,
    p_pw TEXT,
    p_target TEXT,
    p_start DATE,
    p_end DATE
)
RETURNS TABLE(record_date DATE, category TEXT, value TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_stored_pw TEXT;
BEGIN
    SELECT u.password
    INTO v_stored_pw
    FROM public.users AS u
    WHERE u.username = p_user;

    IF v_stored_pw IS NULL OR v_stored_pw != p_pw THEN
        RAISE EXCEPTION 'Auth failed';
    END IF;

    RETURN QUERY
    SELECT r.record_date, r.category, r.value
    FROM public.records AS r
    WHERE r.username = p_user
      AND r.record_date BETWEEN p_start AND p_end
    ORDER BY r.record_date, r.category;
END;
$$;

CREATE OR REPLACE FUNCTION public.register_user_secure(
    p_id TEXT,
    p_pw TEXT,
    p_hosp TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF lower(trim(COALESCE(p_id, ''))) IN ('admin', 'administrator') THEN
        RETURN 'duplicate_id';
    END IF;

    PERFORM 1 FROM public.users WHERE username = p_id;
    IF FOUND THEN
        RETURN 'duplicate_id';
    END IF;

    IF p_hosp IS NOT NULL AND trim(p_hosp) != '' THEN
        PERFORM 1 FROM public.users WHERE hospital_id = p_hosp;
        IF FOUND THEN
            RETURN 'duplicate_hosp';
        END IF;
    END IF;

    INSERT INTO public.users (username, password, hospital_id, points, created_at)
    VALUES (p_id, p_pw, p_hosp, 0, now());

    RETURN 'success';
EXCEPTION
    WHEN unique_violation THEN
        RETURN 'duplicate';
END;
$$;

DELETE FROM public.mood_persistent_logins WHERE username = 'admin';
DELETE FROM public.users WHERE username = 'admin';
