-- GesApp 2.2.4 - réconciliation pré-production du backend Supabase.
-- Migration additive/idempotente : ne supprime aucune donnée métier.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create or replace function private.is_active_member(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id=p_organization_id
      and m.user_id=(select auth.uid())
      and m.status='active'
      and m.active=true
  );
$$;

create or replace function private.is_active_admin(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id=p_organization_id
      and m.user_id=(select auth.uid())
      and m.role='admin'
      and m.status='active'
      and m.active=true
  );
$$;

create or replace function private.is_active_manager(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id=p_organization_id
      and m.user_id=(select auth.uid())
      and m.role='manager'
      and m.status='active'
      and m.active=true
  );
$$;

revoke all on function private.is_active_member(uuid) from public, anon;
revoke all on function private.is_active_admin(uuid) from public, anon;
revoke all on function private.is_active_manager(uuid) from public, anon;
grant execute on function private.is_active_member(uuid) to authenticated;
grant execute on function private.is_active_admin(uuid) to authenticated;
grant execute on function private.is_active_manager(uuid) to authenticated;

create or replace function public.get_my_organization()
returns table(
  organization_id uuid,
  organization_code text,
  organization_name text,
  display_name text,
  username text,
  role text,
  active boolean,
  must_change_password boolean,
  backup_secret text
)
language sql
stable
security invoker
set search_path=''
as $$
  select o.id,o.code,o.name,m.display_name,m.username,m.role,m.active,
         m.must_change_password,o.backup_secret
  from public.organization_members m
  join public.organizations o on o.id=m.organization_id
  where m.user_id=(select auth.uid())
    and m.active=true
    and m.status='active'
    and o.active=true
  limit 1;
$$;
revoke all on function public.get_my_organization() from public, anon;
grant execute on function public.get_my_organization() to authenticated;

create or replace function public.bootstrap_organization(
  p_name text,
  p_preferred_code text default null,
  p_display_name text default 'Administrateur'
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_org uuid;
  v_code text;
begin
  if v_user is null then raise exception 'authentication_required'; end if;
  if not private.current_user_email_is_confirmed() then
    raise exception 'email_confirmation_required';
  end if;
  if length(trim(p_name)) < 3 then raise exception 'invalid_organization_name'; end if;
  if exists(select 1 from public.organization_members where user_id=v_user) then
    raise exception 'user_already_has_organization';
  end if;
  v_code := upper(regexp_replace(trim(coalesce(nullif(p_preferred_code,''),p_name)),'[^A-Za-z0-9]+','-','g'));
  v_code := trim(both '-' from v_code);
  if length(v_code) < 3 then v_code := 'ECOLE'; end if;
  v_code := left(v_code,20)||'-'||upper(substr(encode(extensions.gen_random_bytes(3),'hex'),1,6));
  insert into public.organizations(code,name,created_by)
  values(v_code,trim(p_name),v_user) returning id into v_org;
  insert into public.organization_members(
    organization_id,user_id,display_name,role,status,active,must_change_password,created_by
  ) values(
    v_org,v_user,coalesce(nullif(trim(p_display_name),''),'Administrateur'),
    'admin','active',true,false,v_user
  );
  insert into public.sync_metadata(organization_id,revision) values(v_org,0);
  return v_org;
end;
$$;
revoke all on function public.bootstrap_organization(text,text,text) from public, anon;
grant execute on function public.bootstrap_organization(text,text,text) to authenticated;

create or replace function public.mark_password_changed()
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  update public.organization_members
  set must_change_password=false, updated_at=now()
  where user_id=(select auth.uid())
    and role='manager'
    and active=true
    and status='active';
end;
$$;
revoke all on function public.mark_password_changed() from public, anon;
grant execute on function public.mark_password_changed() to authenticated;

create table if not exists public.platform_super_admins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  email text not null unique,
  pin_salt text not null,
  pin_hash text not null,
  pin_iterations integer not null default 210000 check (pin_iterations >= 100000),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  failed_attempts integer not null default 0,
  locked_until timestamptz
);
create index if not exists platform_super_admins_email_idx
  on public.platform_super_admins(lower(email));

create table if not exists public.platform_super_admin_sessions (
  id uuid primary key default gen_random_uuid(),
  super_admin_id uuid not null references public.platform_super_admins(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists platform_super_admin_sessions_active_idx
  on public.platform_super_admin_sessions(super_admin_id,expires_at)
  where revoked_at is null;

create table if not exists public.platform_activity_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  module text not null default 'system',
  message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists platform_activity_events_created_idx
  on public.platform_activity_events(created_at desc);
create index if not exists platform_activity_events_org_created_idx
  on public.platform_activity_events(organization_id,created_at desc);
create index if not exists platform_activity_events_actor_user_id_idx
  on public.platform_activity_events(actor_user_id);

alter table public.platform_super_admins enable row level security;
alter table public.platform_super_admin_sessions enable row level security;
alter table public.platform_activity_events enable row level security;

drop policy if exists platform_super_admins_deny_client on public.platform_super_admins;
create policy platform_super_admins_deny_client
on public.platform_super_admins for all to anon, authenticated
using (false) with check (false);

drop policy if exists platform_super_admin_sessions_deny_client on public.platform_super_admin_sessions;
create policy platform_super_admin_sessions_deny_client
on public.platform_super_admin_sessions for all to anon, authenticated
using (false) with check (false);

drop policy if exists platform_activity_member_insert on public.platform_activity_events;
create policy platform_activity_member_insert
on public.platform_activity_events for insert to authenticated
with check (
  actor_user_id=(select auth.uid())
  and exists(
    select 1 from public.organization_members m
    where m.user_id=(select auth.uid())
      and m.organization_id=platform_activity_events.organization_id
      and m.active=true
      and m.status='active'
  )
);

revoke all on public.platform_super_admins from anon, authenticated;
revoke all on public.platform_super_admin_sessions from anon, authenticated;
revoke all on public.platform_activity_events from anon, authenticated;
grant insert on public.platform_activity_events to authenticated;
