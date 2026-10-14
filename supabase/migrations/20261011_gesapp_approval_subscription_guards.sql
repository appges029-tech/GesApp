-- GesApp: protect fresh/replayed deployments from legacy pre-production SQL.
-- The 20261008_preproduction_security_reconciliation migration historically
-- recreates a user-executable bootstrap and subscription-unaware RLS helpers.
-- Apply this AFTER every 20261008 migration. No business data is modified.
-- Do NOT remove the 20261010 cross-school quarantine policies here.
begin;

-- School creation is ONLY performed by the Super Admin's service-role API.
revoke execute on function public.bootstrap_organization(text,text,text)
  from public, anon, authenticated;
revoke insert, delete, update on public.organizations
  from public, anon, authenticated;
grant update(name) on public.organizations to authenticated;
revoke insert, delete, update on public.organization_members
  from public, anon, authenticated;

-- Even a valid membership must lose cloud permissions when the subscription
-- is expired/suspended or the organization has been disabled.
create or replace function private.is_active_manager(p_organization_id uuid)
returns boolean
language sql stable security definer set search_path='' as $$
  select exists (
    select 1
    from public.organization_members m
    join public.organizations o on o.id = m.organization_id
    where m.organization_id = p_organization_id
      and m.user_id = (select auth.uid())
      and m.role = 'manager'
      and m.status = 'active' and m.active = true
      and o.active = true
      and (
        o.subscription_status = 'legacy'
        or (o.subscription_status = 'active'
            and o.subscription_expires_at > now())
      )
  );
$$;

create or replace function private.is_active_admin(p_organization_id uuid)
returns boolean
language sql stable security definer set search_path='' as $$
  select exists (
    select 1
    from public.organization_members m
    join public.organizations o on o.id = m.organization_id
    where m.organization_id = p_organization_id
      and m.user_id = (select auth.uid())
      and m.role = 'admin'
      and m.status = 'active' and m.active = true
      and o.active = true
      and (
        o.subscription_status = 'legacy'
        or (o.subscription_status = 'active'
            and o.subscription_expires_at > now())
      )
  );
$$;
revoke all on function private.is_active_manager(uuid) from public, anon;
revoke all on function private.is_active_admin(uuid) from public, anon;
grant execute on function private.is_active_manager(uuid) to authenticated;
grant execute on function private.is_active_admin(uuid) to authenticated;

-- Reads must obey the subscription too, not only storage write policies.
drop policy if exists gesapp_backup_read on storage.objects;
create policy gesapp_backup_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'gesapp-backups'
    and (select private.is_active_member(
      ((storage.foldername(storage.objects.name))[1])::uuid))
    and exists (
      select 1 from public.organizations o
      where o.id = ((storage.foldername(storage.objects.name))[1])::uuid
        and o.active = true
        and (
          o.subscription_status = 'legacy'
          or (o.subscription_status = 'active'
              and o.subscription_expires_at > now())
        )
    )
  );

-- Intentionally keep:
--   gesapp_incident_quarantine_sync
--   gesapp_incident_quarantine_backups
-- Both must remain in force until the affected school snapshots are audited.
commit;
