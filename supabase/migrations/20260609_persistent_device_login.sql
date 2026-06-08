-- Persistent device login for moodchart.
-- The browser stores only a random device token. The database stores its hash
-- plus the existing app password hash so current secure RPCs can still be used.
-- Device tokens expire after 30 days and can be revoked on logout/password change.

CREATE TABLE IF NOT EXISTS public.mood_persistent_logins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'patient' CHECK (role IN ('patient', 'doctor')),
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL
);

ALTER TABLE public.mood_persistent_logins ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.mood_persistent_logins FROM anon;
REVOKE ALL ON TABLE public.mood_persistent_logins FROM authenticated;

CREATE INDEX IF NOT EXISTS idx_mood_persistent_logins_username
  ON public.mood_persistent_logins(username);
CREATE INDEX IF NOT EXISTS idx_mood_persistent_logins_expires_at
  ON public.mood_persistent_logins(expires_at);

CREATE OR REPLACE FUNCTION public.create_mood_persistent_login(
  p_user TEXT,
  p_pw TEXT,
  p_role TEXT,
  p_token_hash TEXT,
  p_user_agent TEXT DEFAULT '',
  p_days INTEGER DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days INTEGER := LEAST(GREATEST(COALESCE(p_days, 30), 1), 30);
  v_role TEXT := 'patient';
  v_expires_at TIMESTAMPTZ := now() + (v_days || ' days')::interval;
BEGIN
  IF NULLIF(TRIM(p_user), '') IS NULL OR NULLIF(TRIM(p_pw), '') IS NULL THEN
    RAISE EXCEPTION 'Auth failed';
  END IF;
  IF NULLIF(TRIM(p_token_hash), '') IS NULL OR char_length(p_token_hash) < 40 THEN
    RAISE EXCEPTION 'Invalid device token';
  END IF;

  PERFORM *
  FROM public.get_records_secure(p_user, p_pw, p_user, '2000-01-01', '2000-01-01')
  LIMIT 1;

  BEGIN
    PERFORM *
    FROM public.resolve_patient_id_secure(p_user, p_pw, '')
    LIMIT 1;
    v_role := 'doctor';
  EXCEPTION WHEN OTHERS THEN
    v_role := CASE WHEN p_role = 'doctor' THEN 'patient' ELSE COALESCE(NULLIF(p_role, ''), 'patient') END;
  END;

  DELETE FROM public.mood_persistent_logins WHERE expires_at <= now();

  INSERT INTO public.mood_persistent_logins (
    username, token_hash, password_hash, role, user_agent, expires_at
  ) VALUES (
    p_user, p_token_hash, p_pw, v_role, LEFT(COALESCE(p_user_agent, ''), 500), v_expires_at
  )
  ON CONFLICT (token_hash) DO UPDATE
  SET username = EXCLUDED.username,
      password_hash = EXCLUDED.password_hash,
      role = EXCLUDED.role,
      user_agent = EXCLUDED.user_agent,
      expires_at = EXCLUDED.expires_at,
      last_used_at = now();

  RETURN jsonb_build_object('status', 'ok', 'expires_at', v_expires_at, 'role', v_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_mood_persistent_login(
  p_token_hash TEXT,
  p_user_agent TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.mood_persistent_logins%ROWTYPE;
BEGIN
  DELETE FROM public.mood_persistent_logins WHERE expires_at <= now();

  SELECT *
  INTO v_row
  FROM public.mood_persistent_logins
  WHERE token_hash = p_token_hash
    AND expires_at > now()
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Device login expired';
  END IF;

  UPDATE public.mood_persistent_logins
  SET last_used_at = now(),
      user_agent = LEFT(COALESCE(p_user_agent, user_agent, ''), 500)
  WHERE id = v_row.id;

  RETURN jsonb_build_object(
    'username', v_row.username,
    'password_hash', v_row.password_hash,
    'role', v_row.role,
    'expires_at', v_row.expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_mood_persistent_login(p_token_hash TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.mood_persistent_logins
  WHERE token_hash = p_token_hash;
  RETURN jsonb_build_object('status', 'ok');
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_mood_persistent_login(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_mood_persistent_login(TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_mood_persistent_login(TEXT) TO anon, authenticated;
