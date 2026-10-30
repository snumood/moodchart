-- 2026-10-31: device logins no longer keep the reusable SHA-256 password value in clear.
-- The client now also sends the raw device token; the server checks it against p_token_hash and stores
-- the SHA-256 value encrypted with that token ('enc:' prefix). A database copy alone no longer yields a
-- credential. Rows written by older clients (clear value) are upgraded on their next device login and
-- Existing clear rows are deleted here; those devices log in with the password once more.
begin;

drop function if exists public.create_mood_persistent_login(text, text, text, text, text, integer);
create function public.create_mood_persistent_login(p_user text, p_pw text, p_role text, p_token_hash text,
  p_user_agent text default '', p_days integer default 30, p_token text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_days integer := least(greatest(coalesce(p_days, 30), 1), 30);
  v_expires_at timestamptz := now() + (v_days || ' days')::interval;
begin
  if nullif(trim(p_user), '') is null or nullif(trim(p_pw), '') is null then
    raise exception 'Auth failed';
  end if;
  -- Older clients do not send the raw token; they keep working without a device login.
  if p_token is null or char_length(p_token) < 32
     or encode(extensions.digest('moodchart-device-token-v1:' || p_token, 'sha256'), 'hex') is distinct from p_token_hash then
    raise exception 'Invalid device token';
  end if;
  if public.mood_pw_check(p_user, p_pw) <> 'ok' then
    perform set_config('response.status', '401', true);
    return jsonb_build_object('message', 'Auth failed', 'code', 'P0001');
  end if;

  delete from public.mood_persistent_logins where expires_at <= now();

  insert into public.mood_persistent_logins (username, token_hash, password_hash, role, user_agent, expires_at)
  values (p_user, p_token_hash, 'enc:' || encode(extensions.pgp_sym_encrypt(p_pw, p_token), 'base64'),
          'patient', left(coalesce(p_user_agent, ''), 500), v_expires_at)
  on conflict (token_hash) do update
  set username = excluded.username,
      password_hash = excluded.password_hash,
      role = excluded.role,
      user_agent = excluded.user_agent,
      expires_at = excluded.expires_at,
      last_used_at = now();

  return jsonb_build_object('status', 'ok', 'expires_at', v_expires_at, 'role', 'patient');
end;
$function$;
revoke all on function public.create_mood_persistent_login(text, text, text, text, text, integer, text) from public;
grant execute on function public.create_mood_persistent_login(text, text, text, text, text, integer, text) to anon, authenticated;

drop function if exists public.consume_mood_persistent_login(text, text);
create function public.consume_mood_persistent_login(p_token_hash text, p_user_agent text default '', p_token text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_row public.mood_persistent_logins%rowtype;
  v_pw text;
  v_token_ok boolean := p_token is not null
    and encode(extensions.digest('moodchart-device-token-v1:' || p_token, 'sha256'), 'hex') = p_token_hash;
begin
  delete from public.mood_persistent_logins where expires_at <= now();

  select * into v_row from public.mood_persistent_logins
  where token_hash = p_token_hash and expires_at > now()
  limit 1;
  if not found then
    raise exception 'Device login expired';
  end if;

  if not v_token_ok or v_row.password_hash not like 'enc:%' then
    raise exception 'Device login expired';
  end if;
  v_pw := extensions.pgp_sym_decrypt(decode(substr(v_row.password_hash, 5), 'base64'), p_token);

  update public.mood_persistent_logins
  set last_used_at = now(),
      user_agent = left(coalesce(p_user_agent, user_agent, ''), 500)
  where id = v_row.id;

  return jsonb_build_object('username', v_row.username, 'password_hash', v_pw, 'role', v_row.role,
                            'expires_at', v_row.expires_at);
end;
$function$;
revoke all on function public.consume_mood_persistent_login(text, text, text) from public;
grant execute on function public.consume_mood_persistent_login(text, text, text) to anon, authenticated;

delete from public.mood_persistent_logins where password_hash not like 'enc:%';

notify pgrst, 'reload schema';
commit;
