-- Secure the email-confirmation check used by the public bootstrap RPC.
-- Apply through the Supabase migration role (normally postgres/supabase_admin),
-- which owns this SECURITY DEFINER function and can read auth.users.

create or replace function private.current_user_email_is_confirmed()
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, auth
as $$
declare
  v_user uuid := auth.uid();
  v_confirmed_at timestamptz;
begin
  -- Never let the definer privilege be used without a request user identity.
  if v_user is null then
    return false;
  end if;

  select u.email_confirmed_at
    into v_confirmed_at
    from auth.users as u
   where u.id = v_user;

  return v_confirmed_at is not null;
end;
$$;

-- The helper is private implementation detail: callers cannot invoke it directly.
revoke all on function private.current_user_email_is_confirmed() from public;
revoke all on function private.current_user_email_is_confirmed() from anon;
revoke all on function private.current_user_email_is_confirmed() from authenticated;

create or replace function public.bootstrap_organization(
  p_name text,
  p_preferred_code text default null,
  p_display_name text default 'Administrateur'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_code text;
begin
  -- This must be checked in the public entry point as well as in the helper.
  if v_user is null then
    raise exception 'authentication_required';
  end if;

  if not private.current_user_email_is_confirmed() then
    raise exception 'email_confirmation_required';
  end if;

  if length(trim(p_name)) < 3 then
    raise exception 'invalid_organization_name';
  end if;

  if exists (
    select 1
      from public.organization_members
     where user_id = v_user
  ) then
    raise exception 'user_already_has_organization';
  end if;

  v_code := upper(
    regexp_replace(
      trim(coalesce(nullif(p_preferred_code, ''), p_name)),
      '[^A-Za-z0-9]+',
      '-',
      'g'
    )
  );
  v_code := trim(both '-' from v_code);
  if length(v_code) < 3 then
    v_code := 'ECOLE';
  end if;
  v_code := left(v_code, 20) || '-' || upper(
    substr(encode(extensions.gen_random_bytes(3), 'hex'), 1, 6)
  );

  insert into public.organizations (code, name, created_by)
  values (v_code, trim(p_name), v_user)
  returning id into v_org;

  insert into public.organization_members (
    organization_id,
    user_id,
    display_name,
    role,
    status,
    active,
    must_change_password,
    created_by
  )
  values (
    v_org,
    v_user,
    coalesce(nullif(trim(p_display_name), ''), 'Administrateur'),
    'admin',
    'active',
    true,
    false,
    v_user
  );

  insert into public.sync_metadata (organization_id, revision)
  values (v_org, 0);

  return v_org;
end;
$$;

-- PostgreSQL grants EXECUTE to PUBLIC by default when a function is created.
revoke all on function public.bootstrap_organization(text, text, text) from public;
revoke all on function public.bootstrap_organization(text, text, text) from anon;
grant execute on function public.bootstrap_organization(text, text, text) to authenticated;
