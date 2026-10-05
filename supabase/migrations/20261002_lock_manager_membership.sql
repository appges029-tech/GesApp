-- GesApp 2.1.9 - ferme le contournement RLS de l'appartenance tenant.
-- Les gestionnaires ne doivent jamais modifier directement organization_members.
-- Le changement de must_change_password passe exclusivement par le RPC
-- public.mark_password_changed() en SECURITY DEFINER.

drop policy if exists members_manager_self_password_update on public.organization_members;

revoke update on public.organization_members from authenticated;
grant select, insert on public.organization_members to authenticated;

-- Réaffirme le RPC minimal autorisé : il ne peut modifier ni tenant, ni rôle,
-- ni utilisateur, ni statut/activation.
create or replace function public.mark_password_changed()
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required';
  end if;

  update public.organization_members
  set must_change_password=false, updated_at=now()
  where user_id=(select auth.uid())
    and role='manager'
    and active=true
    and status='active';
end;
$$;

revoke all on function public.mark_password_changed() from public;
grant execute on function public.mark_password_changed() to authenticated;
