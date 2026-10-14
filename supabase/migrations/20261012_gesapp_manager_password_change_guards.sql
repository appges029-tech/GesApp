-- Password-reset hardening; release after manager-change-password Edge Function
-- and compatible GesApp clients are deployed.
-- No school, user, or business data is deleted.
begin;

-- The historical RPC cleared the mandatory-change flag without proving
-- that an actual Supabase Auth password change had occurred.
-- The server-side manager-change-password function now performs both steps.
revoke execute on function public.mark_password_changed()
  from public, anon, authenticated;

-- While a password reset is pending, an already-issued manager JWT must not
-- be sufficient to synchronize or read the school's encrypted snapshots.
create or replace function private.is_active_manager(p_organization_id uuid)
returns boolean
language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.organization_members m
    join public.organizations o on o.id = m.organization_id
    where m.organization_id = p_organization_id
      and m.user_id = (select auth.uid())
      and m.role = 'manager'
      and m.status = 'active' and m.active = true
      and m.must_change_password = false
      and o.active = true
      and (
        o.subscription_status = 'legacy'
        or (o.subscription_status = 'active'
            and o.subscription_expires_at > now())
      )
  );
$$;

revoke all on function private.is_active_manager(uuid) from public, anon;
grant execute on function private.is_active_manager(uuid) to authenticated;

-- The Gustave Flaubert and Mageste snapshot quarantines are intentionally
-- left untouched by this change.
commit;
