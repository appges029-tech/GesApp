-- GesApp 2.1.4 — schéma Supabase multitenant consolidé.
-- Source de vérité reproductible alignée sur le projet layuzuqhmidwvcydvvre.
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  backup_secret text not null default encode(extensions.gen_random_bytes(32),'hex'),
  active boolean not null default true
);

create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','manager')),
  status text not null default 'active' check (status in ('active','disabled')),
  username text,
  must_change_password boolean not null default false,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  display_name text not null,
  active boolean not null default true,
  unique (organization_id,user_id),
  unique (organization_id,username)
);
create unique index if not exists organization_members_one_tenant_per_user on public.organization_members(user_id);
create index if not exists organization_members_org_role_idx on public.organization_members(organization_id,role,status);
create index if not exists organization_members_created_by_idx on public.organization_members(created_by);

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_key text not null,
  platform text,
  app_version text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(organization_id,device_key)
);
create index if not exists devices_org_user_idx on public.devices(organization_id,user_id);

create table if not exists public.sync_metadata (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  revision bigint not null default 0,
  checksum text,
  object_path text,
  object_size bigint,
  updated_by uuid references auth.users(id),
  updated_from_device text,
  updated_at timestamptz not null default now(),
  current_path text,
  checksum_sha256 text,
  size_bytes bigint,
  uploaded_by uuid references auth.users(id),
  uploaded_at timestamptz
);
create index if not exists sync_metadata_updated_by_idx on public.sync_metadata(updated_by);
create index if not exists sync_metadata_uploaded_by_idx on public.sync_metadata(uploaded_by);

create or replace function private.is_active_member(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=(select auth.uid()) and m.status='active' and m.active=true);
$$;
create or replace function private.is_active_admin(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=(select auth.uid()) and m.role='admin' and m.status='active' and m.active=true);
$$;
create or replace function private.is_active_manager(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=(select auth.uid()) and m.role='manager' and m.status='active' and m.active=true);
$$;
revoke all on schema private from public;
grant usage on schema private to authenticated;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.devices enable row level security;
alter table public.sync_metadata enable row level security;

-- Recrée uniquement les politiques officielles GesApp.
drop policy if exists organizations_member_select on public.organizations;
drop policy if exists organizations_creator_insert on public.organizations;
drop policy if exists organizations_admin_update on public.organizations;
create policy organizations_member_select on public.organizations for select to authenticated using ((select private.is_active_member(id)));
create policy organizations_creator_insert on public.organizations for insert to authenticated with check (created_by=(select auth.uid()));
create policy organizations_admin_update on public.organizations for update to authenticated using ((select private.is_active_admin(id))) with check ((select private.is_active_admin(id)));

drop policy if exists members_same_org_select on public.organization_members;
drop policy if exists members_admin_insert on public.organization_members;
drop policy if exists members_manager_self_password_update on public.organization_members;
create policy members_same_org_select on public.organization_members for select to authenticated using ((select private.is_active_member(organization_id)));
create policy members_admin_insert on public.organization_members for insert to authenticated with check (
 (user_id=(select auth.uid()) and role='admin' and exists(select 1 from public.organizations o where o.id=organization_id and o.created_by=(select auth.uid())))
 or (select private.is_active_admin(organization_id))
);
create policy members_manager_self_password_update on public.organization_members for update to authenticated using (user_id=(select auth.uid()) and role='manager' and active=true) with check (user_id=(select auth.uid()) and role='manager' and active=true);

drop policy if exists devices_member_all on public.devices;
create policy devices_member_all on public.devices for all to authenticated using ((select private.is_active_member(organization_id))) with check ((select private.is_active_member(organization_id)));

drop policy if exists sync_member_select on public.sync_metadata;
drop policy if exists sync_manager_insert on public.sync_metadata;
drop policy if exists sync_manager_update on public.sync_metadata;
create policy sync_member_select on public.sync_metadata for select to authenticated using ((select private.is_active_member(organization_id)));
create policy sync_manager_insert on public.sync_metadata for insert to authenticated with check ((select private.is_active_manager(organization_id)));
create policy sync_manager_update on public.sync_metadata for update to authenticated using ((select private.is_active_manager(organization_id))) with check ((select private.is_active_manager(organization_id)));

grant select,insert,update on public.organizations to authenticated;
grant select,insert,update on public.organization_members to authenticated;
grant select,insert,update,delete on public.devices to authenticated;
grant select,insert,update on public.sync_metadata to authenticated;

create or replace function public.bootstrap_organization(p_name text,p_preferred_code text default null,p_display_name text default 'Administrateur')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_org uuid; v_code text; v_confirmed_at timestamptz;
begin
 if v_user is null then raise exception 'authentication_required'; end if;
 select u.email_confirmed_at into v_confirmed_at from auth.users u where u.id=v_user;
 if v_confirmed_at is null then raise exception 'email_confirmation_required'; end if;
 if length(trim(p_name))<3 then raise exception 'invalid_organization_name'; end if;
 if exists(select 1 from public.organization_members where user_id=v_user) then raise exception 'user_already_has_organization'; end if;
 v_code:=upper(regexp_replace(trim(coalesce(nullif(p_preferred_code,''),p_name)),'[^A-Za-z0-9]+','-','g'));
 v_code:=trim(both '-' from v_code); if length(v_code)<3 then v_code:='ECOLE'; end if;
 v_code:=left(v_code,20)||'-'||upper(substr(encode(extensions.gen_random_bytes(3),'hex'),1,6));
 insert into public.organizations(code,name,created_by) values(v_code,trim(p_name),v_user) returning id into v_org;
 insert into public.organization_members(organization_id,user_id,display_name,role,status,active,must_change_password,created_by)
 values(v_org,v_user,coalesce(nullif(trim(p_display_name),''),'Administrateur'),'admin','active',true,false,v_user);
 insert into public.sync_metadata(organization_id,revision) values(v_org,0);
 return v_org;
end; $$;

create or replace function public.get_my_organization()
returns table(organization_id uuid,organization_code text,organization_name text,display_name text,username text,role text,active boolean,must_change_password boolean,backup_secret text)
language sql stable security definer set search_path='' as $$
 select o.id,o.code,o.name,m.display_name,m.username,m.role,m.active,m.must_change_password,o.backup_secret
 from public.organization_members m join public.organizations o on o.id=m.organization_id
 where m.user_id=(select auth.uid()) and m.active=true and m.status='active' and o.active=true limit 1;
$$;

create or replace function public.mark_password_changed()
returns void language plpgsql security definer set search_path='' as $$
begin update public.organization_members set must_change_password=false,updated_at=now() where user_id=(select auth.uid()) and role='manager' and active=true and status='active'; end; $$;

grant execute on function public.bootstrap_organization(text,text,text) to authenticated;
grant execute on function public.get_my_organization() to authenticated;
grant execute on function public.mark_password_changed() to authenticated;

insert into storage.buckets(id,name,public,file_size_limit) values('gesapp-backups','gesapp-backups',false,104857600)
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit;

drop policy if exists gesapp_backup_read on storage.objects;
drop policy if exists gesapp_backup_insert on storage.objects;
drop policy if exists gesapp_backup_update on storage.objects;
drop policy if exists gesapp_backup_delete on storage.objects;
create policy gesapp_backup_read on storage.objects for select to authenticated using (bucket_id='gesapp-backups' and (select private.is_active_member(((storage.foldername(name))[1])::uuid)));
create policy gesapp_backup_insert on storage.objects for insert to authenticated with check (bucket_id='gesapp-backups' and (select private.is_active_manager(((storage.foldername(name))[1])::uuid)));
create policy gesapp_backup_update on storage.objects for update to authenticated using (bucket_id='gesapp-backups' and (select private.is_active_manager(((storage.foldername(name))[1])::uuid))) with check (bucket_id='gesapp-backups' and (select private.is_active_manager(((storage.foldername(name))[1])::uuid)));
create policy gesapp_backup_delete on storage.objects for delete to authenticated using (bucket_id='gesapp-backups' and (select private.is_active_manager(((storage.foldername(name))[1])::uuid)));
