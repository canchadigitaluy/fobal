alter table public.club_memberships
  add column if not exists category_ids text[] not null default '{}';

alter table public.club_tactical_data
  add column if not exists category_id text;

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

update public.club_tactical_data
set category_id = nullif(content->>'categoryId', '')
where category_id is null;

create table if not exists public.club_subscriptions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null unique references public.cantera_clubs(id) on delete cascade,
  plan text not null default 'club_all_categories'
    check (plan in ('trial', 'club_all_categories', 'suspended')),
  status text not null default 'trial'
    check (status in ('trial', 'active', 'past_due', 'cancelled', 'suspended')),
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  max_categories_per_coach integer not null default 2
    check (max_categories_per_coach between 1 and 4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.club_subscriptions (club_id, plan, status, trial_ends_at)
select id, 'trial', 'trial', now() + interval '30 days'
from public.cantera_clubs
on conflict (club_id) do nothing;

create or replace function public.can_access_club_category(
  target_club_id uuid,
  target_category_id text
)
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
      and (
        cm.role in ('platform_admin', 'club_admin')
        or (
          target_category_id is not null
          and target_category_id = any(cm.category_ids)
        )
      )
  );
$$;

create or replace function public.request_club_access(
  target_club_id uuid,
  desired_role text,
  invite_code text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  invite_record public.club_invites%rowtype;
  final_role text := coalesce(nullif(desired_role, ''), 'coach');
  final_status text := 'pending';
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if exists (
    select 1 from public.club_memberships cm
    where cm.user_id = auth.uid()
      and cm.club_id <> target_club_id
      and cm.status in ('pending', 'active')
      and cm.role not in ('platform_admin')
  ) then
    return 'already_linked';
  end if;

  if final_role not in ('coach', 'assistant', 'physical_trainer', 'viewer') then
    final_role := 'coach';
  end if;

  if invite_code is not null and length(trim(invite_code)) > 0 then
    select * into invite_record
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
$$;

alter table public.club_subscriptions enable row level security;

drop policy if exists "subscriptions_read_members" on public.club_subscriptions;
create policy "subscriptions_read_members" on public.club_subscriptions
for select using (public.is_active_member(club_id));

drop policy if exists "tactical_data_read_members" on public.club_tactical_data;
drop policy if exists "tactical_data_read_category" on public.club_tactical_data;
create policy "tactical_data_read_category" on public.club_tactical_data
for select using (
  public.is_club_admin(club_id)
  or public.can_access_club_category(club_id, category_id)
);

drop policy if exists "tactical_data_insert_writers" on public.club_tactical_data;
drop policy if exists "tactical_data_insert_category_writers" on public.club_tactical_data;
create policy "tactical_data_insert_category_writers" on public.club_tactical_data
for insert with check (
  public.can_write_club_data(club_id)
  and created_by = auth.uid()
  and (
    public.is_club_admin(club_id)
    or public.can_access_club_category(club_id, category_id)
  )
);

drop policy if exists "tactical_data_update_author_or_admin" on public.club_tactical_data;
drop policy if exists "tactical_data_update_category_author" on public.club_tactical_data;
create policy "tactical_data_update_category_author" on public.club_tactical_data
for update using (
  public.can_write_club_data(club_id)
  and (
    public.is_club_admin(club_id)
    or (
      created_by = auth.uid()
      and public.can_access_club_category(club_id, category_id)
    )
  )
) with check (
  public.can_write_club_data(club_id)
  and (
    public.is_club_admin(club_id)
    or (
      created_by = auth.uid()
      and public.can_access_club_category(club_id, category_id)
    )
  )
);

drop policy if exists "tactical_data_delete_author_or_admin" on public.club_tactical_data;
drop policy if exists "tactical_data_delete_category_author" on public.club_tactical_data;
create policy "tactical_data_delete_category_author" on public.club_tactical_data
for delete using (
  public.can_write_club_data(club_id)
  and (
    public.is_club_admin(club_id)
    or (
      created_by = auth.uid()
      and public.can_access_club_category(club_id, category_id)
    )
  )
);
