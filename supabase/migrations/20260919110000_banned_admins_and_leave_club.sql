-- Un director suspendido (auth.users.banned_until en el futuro) no cuenta como
-- director: el club vuelve a quedar libre para que lo reclame el verdadero DT.
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
      where user_id = auth.uid() and club_id <> target_club_id
        and status in ('active', 'pending')
    ) and not exists (
      select 1 from platform_admins pa
      where pa.user_id = auth.uid()
    ) then 'other'
    when exists (
      select 1 from club_memberships cm
      join auth.users u on u.id = cm.user_id
      where cm.club_id = target_club_id and cm.status = 'active'
        and cm.role in ('platform_admin', 'club_admin')
        and (u.banned_until is null or u.banned_until <= now())
    ) then 'claimed'
    else 'free'
  end;
$$;

create or replace function public.request_club_access(target_club_id uuid, desired_role text, invite_code text default null)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  invite_record public.club_invites%rowtype;
  final_role text := coalesce(nullif(desired_role, ''), 'coach');
  final_status text := 'pending';
  has_admin boolean;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if final_role not in ('coach', 'assistant', 'physical_trainer', 'viewer') then
    final_role := 'coach';
  end if;

  if exists (
    select 1 from public.club_memberships cm
    where cm.user_id = auth.uid() and cm.club_id <> target_club_id
      and cm.status in ('active', 'pending')
  ) and not exists (
    select 1 from public.platform_admins pa
    where pa.user_id = auth.uid()
  ) then
    raise exception 'already_in_another_club';
  end if;

  if invite_code is not null and length(trim(invite_code)) > 0 then
    select *
    into invite_record
    from public.club_invites ci
    where ci.club_id = target_club_id
      and (ci.expires_at is null or ci.expires_at > now())
      and ci.used_count < ci.max_uses
      and ci.code_hash = crypt(trim(invite_code), ci.code_hash)
    order by ci.created_at desc
    limit 1;

    if invite_record.id is not null then
      final_role := invite_record.role;
      final_status := 'active';

      update public.club_invites
      set used_count = used_count + 1
      where id = invite_record.id;
    end if;
  end if;

  if final_status = 'pending' then
    select exists (
      select 1 from public.club_memberships cm
      join auth.users u on u.id = cm.user_id
      where cm.club_id = target_club_id
        and cm.status = 'active'
        and cm.role in ('platform_admin', 'club_admin')
        and (u.banned_until is null or u.banned_until <= now())
    ) into has_admin;
    if not has_admin then
      final_role := 'club_admin';
      final_status := 'active';
    end if;
  end if;

  insert into public.club_memberships (user_id, club_id, role, status)
  values (auth.uid(), target_club_id, final_role, final_status)
  on conflict (user_id, club_id) do update set
    role = case
      when club_memberships.status = 'active' then club_memberships.role
      else excluded.role
    end,
    status = case
      when club_memberships.status = 'active' then 'active'
      else excluded.status
    end,
    updated_at = now();

  return final_status;
end;
$function$;

-- Dejar un club: borra la membresia propia. Si sos el unico director y el
-- club tiene otros miembros activos, primero hay que designar a otro.
create or replace function public.leave_club(target_club_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me record;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select role, status into me
  from club_memberships
  where club_id = target_club_id and user_id = auth.uid();
  if not found then
    return;
  end if;

  if me.status = 'active' and me.role in ('platform_admin', 'club_admin')
     and not exists (
       select 1 from club_memberships
       where club_id = target_club_id and user_id <> auth.uid()
         and status = 'active' and role in ('platform_admin', 'club_admin')
     )
     and exists (
       select 1 from club_memberships
       where club_id = target_club_id and user_id <> auth.uid() and status = 'active'
     ) then
    raise exception 'last_admin_has_members';
  end if;

  delete from club_memberships
  where club_id = target_club_id and user_id = auth.uid();
end;
$$;

revoke all on function public.leave_club(uuid) from public, anon;
grant execute on function public.leave_club(uuid) to authenticated;
