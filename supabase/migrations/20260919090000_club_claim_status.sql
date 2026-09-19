-- Estado de un club para quien lo mira, sin revelar quien lo dirige:
--   mine    = ya sos miembro activo
--   pending = tu solicitud espera aprobacion
--   claimed = otro usuario ya lo dirige (hay un admin activo)
--   free    = nadie lo dirige todavia
create or replace function public.club_claim_status(target_club_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (
      select 1 from club_memberships
      where club_id = target_club_id and user_id = auth.uid() and status = 'active'
    ) then 'mine'
    when exists (
      select 1 from club_memberships
      where club_id = target_club_id and user_id = auth.uid() and status = 'pending'
    ) then 'pending'
    when exists (
      select 1 from club_memberships
      where club_id = target_club_id and status = 'active'
        and role in ('platform_admin', 'club_admin')
    ) then 'claimed'
    else 'free'
  end;
$$;

revoke all on function public.club_claim_status(uuid) from public, anon;
grant execute on function public.club_claim_status(uuid) to authenticated;
