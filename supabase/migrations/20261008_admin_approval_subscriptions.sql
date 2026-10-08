-- GesApp: approval-first registration and prepaid renewable school access.
-- Existing establishments remain "legacy" until explicitly enrolled by Super Admin.
create extension if not exists pgcrypto with schema extensions;

alter table public.organizations
  add column if not exists subscription_status text not null default 'legacy',
  add column if not exists subscription_cycle text,
  add column if not exists subscription_started_at timestamptz,
  add column if not exists subscription_expires_at timestamptz,
  add column if not exists subscription_confirmed_at timestamptz,
  add column if not exists subscription_confirmed_by uuid references auth.users(id);

do $$ begin
  if not exists (select 1 from pg_constraint where conname='organizations_subscription_status_check') then
    alter table public.organizations add constraint organizations_subscription_status_check
      check (subscription_status in ('legacy','active','suspended'));
  end if;
  if not exists (select 1 from pg_constraint where conname='organizations_subscription_cycle_check') then
    alter table public.organizations add constraint organizations_subscription_cycle_check
      check (subscription_cycle is null or subscription_cycle in ('monthly','annual'));
  end if;
end $$;
create index if not exists organizations_subscription_expires_idx
  on public.organizations(subscription_expires_at) where subscription_status='active';

create table if not exists public.admin_registration_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  email text not null,
  display_name text not null,
  school_name text not null,
  preferred_code text,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  organization_id uuid references public.organizations(id),
  created_at timestamptz not null default now()
);
create unique index if not exists admin_registration_one_pending
 on public.admin_registration_requests(user_id) where status='pending';
create index if not exists admin_registration_status_created_idx
 on public.admin_registration_requests(status,created_at desc);
alter table public.admin_registration_requests enable row level security;
revoke all on public.admin_registration_requests from anon,authenticated;
grant select on public.admin_registration_requests to authenticated;
grant insert(user_id,email,display_name,school_name,preferred_code)
 on public.admin_registration_requests to authenticated;
drop policy if exists admin_registration_own_select on public.admin_registration_requests;
create policy admin_registration_own_select on public.admin_registration_requests
 for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists admin_registration_own_insert on public.admin_registration_requests;
create policy admin_registration_own_insert on public.admin_registration_requests
 for insert to authenticated with check (
  user_id=(select auth.uid())
  and lower(email)=lower((select auth.jwt()->>'email'))
  and status='pending'
  and reviewed_by is null and reviewed_at is null and organization_id is null
  and length(trim(school_name))>=3 and length(trim(display_name))>=2
  and not exists(select 1 from public.organization_members m where m.user_id=(select auth.uid()))
 );

-- Protect tenant billing and account provisioning against direct client writes.
revoke insert,delete,update on public.organizations from anon,authenticated;
grant update(name) on public.organizations to authenticated;
revoke insert,delete,update on public.organization_members from anon,authenticated;
-- The old bootstrap SECURITY DEFINER RPC must not remain callable by a normal user.
revoke execute on function public.bootstrap_organization(text,text,text) from public,anon,authenticated;

-- Tenant members can read subscription status even after expiration; a suspended
-- tenant may still sign in to see the renewal explanation.
create or replace function public.get_my_subscription()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
   'organization_id',o.id,
   'status',o.subscription_status,
   'cycle',o.subscription_cycle,
   'starts_at',o.subscription_started_at,
   'expires_at',o.subscription_expires_at,
   'organization_active',o.active,
   'server_now',now()
 )
 from public.organization_members m
 join public.organizations o on o.id=m.organization_id
 where m.user_id=(select auth.uid()) and m.active=true and m.status='active'
 limit 1;
$$;
revoke execute on function public.get_my_subscription() from public,anon;
grant execute on function public.get_my_subscription() to authenticated;

-- Only managers of a paid, unexpired (or grandfathered) school can write cloud snapshots.
create or replace function private.is_active_manager(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.organization_members m
  join public.organizations o on o.id=m.organization_id
  where m.organization_id=p_organization_id
  and m.user_id=(select auth.uid()) and m.role='manager'
  and m.status='active' and m.active=true and o.active=true
  and (
   o.subscription_status='legacy'
   or (o.subscription_status='active' and o.subscription_expires_at>now())
  )
 );
$$;
revoke all on function private.is_active_manager(uuid) from public,anon;
grant execute on function private.is_active_manager(uuid) to authenticated;

-- Storage reads are also prevented after expiry, but metadata is readable for renewal.
drop policy if exists gesapp_backup_read on storage.objects;
create policy gesapp_backup_read on storage.objects for select to authenticated
using (
 bucket_id='gesapp-backups'
 and (select private.is_active_member(((storage.foldername(storage.objects.name))[1])::uuid))
 and exists(
   select 1 from public.organizations o
   where o.id=((storage.foldername(storage.objects.name))[1])::uuid and o.active=true
     and (o.subscription_status='legacy'
       or (o.subscription_status='active' and o.subscription_expires_at>now()))
 )
);
-- Keep the existing admin recovery write/read semantics subject to subscription validity.
create or replace function private.is_active_admin(p_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.organization_members m
  join public.organizations o on o.id=m.organization_id
  where m.organization_id=p_organization_id
    and m.user_id=(select auth.uid()) and m.role='admin'
    and m.status='active' and m.active=true and o.active=true
    and (o.subscription_status='legacy'
       or (o.subscription_status='active' and o.subscription_expires_at>now()))
 );
$$;
revoke all on function private.is_active_admin(uuid) from public,anon;
grant execute on function private.is_active_admin(uuid) to authenticated;

create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  cycle text not null check(cycle in ('monthly','annual')),
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  confirmed_by uuid not null references auth.users(id),
  confirmed_at timestamptz not null default now(),
  reference text,
  event_type text not null check(event_type in ('activation','renewal'))
);
create index if not exists subscription_payments_org_created
 on public.subscription_payments(organization_id,confirmed_at desc);
alter table public.subscription_payments enable row level security;
revoke all on public.subscription_payments from anon,authenticated;

-- These RPCs are invoker-only and executable exclusively with the backend service role.
create or replace function public.admin_approve_registration(
 p_request_id uuid, p_cycle text, p_approver uuid
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 v_request public.admin_registration_requests%rowtype;
 v_org uuid;
 v_code text;
 v_start timestamptz := clock_timestamp();
 v_end timestamptz;
begin
 if current_user <> 'service_role' then raise exception 'service_role_required'; end if;
 if p_cycle not in ('monthly','annual') then raise exception 'invalid_subscription_cycle'; end if;
 select * into v_request from public.admin_registration_requests
   where id=p_request_id for update;
 if not found or v_request.status<>'pending' then raise exception 'request_not_pending'; end if;
 if exists(select 1 from public.organization_members where user_id=v_request.user_id) then
   raise exception 'administrator_already_registered';
 end if;
 v_end := v_start + (case when p_cycle='monthly' then interval '1 month' else interval '1 year' end);
 v_code := upper(regexp_replace(trim(coalesce(nullif(v_request.preferred_code,''),v_request.school_name)),'[^A-Za-z0-9]+','-','g'));
 v_code := left(trim(both '-' from v_code),20)||'-'||upper(substr(encode(extensions.gen_random_bytes(3),'hex'),1,6));
 insert into public.organizations(
   code,name,created_by,active,subscription_status,subscription_cycle,
   subscription_started_at,subscription_expires_at,subscription_confirmed_at,subscription_confirmed_by
 ) values (
   v_code,v_request.school_name,v_request.user_id,true,'active',p_cycle,
   v_start,v_end,v_start,p_approver
 ) returning id into v_org;
 insert into public.organization_members(
   organization_id,user_id,role,display_name,status,active,created_by,must_change_password
 ) values(v_org,v_request.user_id,'admin',v_request.display_name,'active',true,p_approver,false);
 insert into public.sync_metadata(organization_id,revision) values(v_org,0);
 update public.admin_registration_requests
  set status='approved',reviewed_by=p_approver,reviewed_at=v_start,organization_id=v_org
  where id=p_request_id;
 insert into public.subscription_payments(
   organization_id,cycle,starts_at,expires_at,confirmed_by,confirmed_at,event_type
 ) values(v_org,p_cycle,v_start,v_end,p_approver,v_start,'activation');
 insert into public.platform_activity_events(
   organization_id,actor_user_id,event_type,module,message,metadata
 ) values(v_org,p_approver,'subscription_activated','billing','Compte administrateur approuvé et abonnement activé',
          jsonb_build_object('cycle',p_cycle,'expires_at',v_end));
 return jsonb_build_object('organization_id',v_org,'code',v_code,'expires_at',v_end);
end;
$$;
revoke execute on function public.admin_approve_registration(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.admin_approve_registration(uuid,text,uuid) to service_role;

create or replace function public.admin_reject_registration(
 p_request_id uuid,p_reviewer uuid,p_note text default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare v_user uuid;
begin
 if current_user <> 'service_role' then raise exception 'service_role_required'; end if;
 update public.admin_registration_requests
 set status='rejected',reviewed_by=p_reviewer,reviewed_at=clock_timestamp(),review_note=left(p_note,500)
 where id=p_request_id and status='pending'
 returning user_id into v_user;
 if not found then raise exception 'request_not_pending'; end if;
 insert into public.platform_activity_events(actor_user_id,event_type,module,message,metadata)
 values(p_reviewer,'administrator_request_rejected','billing','Demande administrateur refusée',
        jsonb_build_object('request_id',p_request_id));
 return jsonb_build_object('ok',true);
end;
$$;
revoke execute on function public.admin_reject_registration(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.admin_reject_registration(uuid,uuid,text) to service_role;

create or replace function public.admin_confirm_subscription(
 p_organization_id uuid,p_cycle text,p_approver uuid,p_reference text default null
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 v_org public.organizations%rowtype;
 v_start timestamptz;
 v_end timestamptz;
 v_now timestamptz := clock_timestamp();
begin
 if current_user <> 'service_role' then raise exception 'service_role_required'; end if;
 if p_cycle not in ('monthly','annual') then raise exception 'invalid_subscription_cycle'; end if;
 select * into v_org from public.organizations where id=p_organization_id for update;
 if not found then raise exception 'school_not_found'; end if;
 v_start := greatest(v_now,coalesce(v_org.subscription_expires_at,v_now));
 v_end := v_start + (case when p_cycle='monthly' then interval '1 month' else interval '1 year' end);
 update public.organizations
 set active=true,subscription_status='active',subscription_cycle=p_cycle,
     subscription_started_at=v_start,subscription_expires_at=v_end,
     subscription_confirmed_at=v_now,subscription_confirmed_by=p_approver,
     updated_at=v_now
 where id=p_organization_id;
 insert into public.subscription_payments(
  organization_id,cycle,starts_at,expires_at,confirmed_by,confirmed_at,reference,event_type
 ) values(p_organization_id,p_cycle,v_start,v_end,p_approver,v_now,left(p_reference,200),
          case when v_org.subscription_status='legacy' or v_org.subscription_expires_at is null
               then 'activation' else 'renewal' end);
 insert into public.platform_activity_events(
  organization_id,actor_user_id,event_type,module,message,metadata
 ) values(p_organization_id,p_approver,'subscription_renewed','billing','Abonnement activé ou renouvelé',
   jsonb_build_object('cycle',p_cycle,'expires_at',v_end,'reference',left(p_reference,200)));
 return jsonb_build_object('organization_id',p_organization_id,
   'cycle',p_cycle,'starts_at',v_start,'expires_at',v_end);
end;
$$;
revoke execute on function public.admin_confirm_subscription(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.admin_confirm_subscription(uuid,text,uuid,text) to service_role;
