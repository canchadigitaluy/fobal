create or replace function public.can_write_club_data(target_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = target_club_id
      and cm.user_id = auth.uid()
      and cm.status = 'active'
      and cm.role in (
        'platform_admin',
        'club_admin',
        'coach',
        'assistant',
        'physical_trainer'
      )
  );
$$;

drop policy if exists "tactical_data_insert_members" on public.club_tactical_data;
create policy "tactical_data_insert_writers" on public.club_tactical_data
for insert with check (
  public.can_write_club_data(club_id) and created_by = auth.uid()
);

drop policy if exists "tactical_data_update_author_or_admin" on public.club_tactical_data;
create policy "tactical_data_update_author_or_admin" on public.club_tactical_data
for update using (
  public.can_write_club_data(club_id)
  and (public.is_club_admin(club_id) or created_by = auth.uid())
) with check (
  public.can_write_club_data(club_id)
  and (public.is_club_admin(club_id) or created_by = auth.uid())
);

drop policy if exists "tactical_data_delete_author_or_admin" on public.club_tactical_data;
create policy "tactical_data_delete_author_or_admin" on public.club_tactical_data
for delete using (
  public.can_write_club_data(club_id)
  and (public.is_club_admin(club_id) or created_by = auth.uid())
);
