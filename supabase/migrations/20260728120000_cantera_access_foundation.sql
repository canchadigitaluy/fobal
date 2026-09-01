create extension if not exists pgcrypto;

create table if not exists public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lud_teams (
  id uuid primary key default gen_random_uuid(),
  lud_team_id integer not null unique,
  name text not null,
  short_name text,
  logo_url text,
  division text,
  season text,
  source_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.lud_players (
  id uuid primary key default gen_random_uuid(),
  lud_player_id integer not null unique,
  lud_team_id integer references public.lud_teams(lud_team_id) on update cascade,
  full_name text not null,
  position text,
  season text,
  source_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.lud_team_categories (
  id uuid primary key default gen_random_uuid(),
  lud_team_id integer not null references public.lud_teams(lud_team_id) on update cascade,
  lud_category_id integer,
  name text not null,
  source_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(lud_team_id, name)
);

create table if not exists public.cantera_clubs (
  id uuid primary key default gen_random_uuid(),
  lud_team_id integer unique references public.lud_teams(lud_team_id) on update cascade,
  display_name text not null,
  status text not null default 'active' check (status in ('active', 'disabled')),
  created_at timestamptz not null default now()
);

create table if not exists public.club_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  club_id uuid not null references public.cantera_clubs(id) on delete cascade,
  role text not null check (
    role in ('platform_admin', 'club_admin', 'coach', 'assistant', 'physical_trainer', 'viewer')
  ),
  status text not null default 'pending' check (status in ('pending', 'active', 'rejected', 'disabled')),
  approved_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, club_id)
);

create table if not exists public.club_invites (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.cantera_clubs(id) on delete cascade,
  code_hash text not null,
  role text not null default 'coach' check (
    role in ('club_admin', 'coach', 'assistant', 'physical_trainer', 'viewer')
  ),
  expires_at timestamptz,
  max_uses integer not null default 1 check (max_uses > 0),
  used_count integer not null default 0 check (used_count >= 0),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.club_tactical_data (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.cantera_clubs(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('session', 'match_plan', 'rival_report', 'staff_note')),
  title text not null,
  content jsonb not null default '{}'::jsonb,
  related_lud_team_id integer references public.lud_teams(lud_team_id) on update cascade,
  related_lud_player_ids integer[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists club_memberships_user_status_idx
  on public.club_memberships(user_id, status);

create index if not exists club_tactical_data_club_idx
  on public.club_tactical_data(club_id, created_at desc);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id, email, full_name, avatar_url)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do update set
    email = excluded.email,
    full_name = coalesce(excluded.full_name, public.user_profiles.full_name),
    avatar_url = coalesce(excluded.avatar_url, public.user_profiles.avatar_url),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert or update on auth.users
for each row execute function public.handle_new_user();

create or replace function public.is_active_member(target_club_id uuid)
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
  );
$$;

create or replace function public.is_club_admin(target_club_id uuid)
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
      and cm.role in ('platform_admin', 'club_admin')
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

  if final_role not in ('coach', 'assistant', 'physical_trainer', 'viewer') then
    final_role := 'coach';
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

alter table public.user_profiles enable row level security;
alter table public.lud_teams enable row level security;
alter table public.lud_players enable row level security;
alter table public.lud_team_categories enable row level security;
alter table public.cantera_clubs enable row level security;
alter table public.club_memberships enable row level security;
alter table public.club_invites enable row level security;
alter table public.club_tactical_data enable row level security;

drop policy if exists "profiles_read_own" on public.user_profiles;
create policy "profiles_read_own" on public.user_profiles
for select using (id = auth.uid());

drop policy if exists "profiles_update_own" on public.user_profiles;
create policy "profiles_update_own" on public.user_profiles
for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "public_lud_teams_read" on public.lud_teams;
create policy "public_lud_teams_read" on public.lud_teams
for select using (true);

drop policy if exists "public_lud_players_read" on public.lud_players;
create policy "public_lud_players_read" on public.lud_players
for select using (true);

drop policy if exists "public_lud_team_categories_read" on public.lud_team_categories;
create policy "public_lud_team_categories_read" on public.lud_team_categories
for select using (true);

drop policy if exists "active_cantera_clubs_read" on public.cantera_clubs;
create policy "active_cantera_clubs_read" on public.cantera_clubs
for select using (status = 'active');

drop policy if exists "memberships_read_own_or_admin" on public.club_memberships;
create policy "memberships_read_own_or_admin" on public.club_memberships
for select using (
  user_id = auth.uid() or public.is_club_admin(club_id)
);

drop policy if exists "club_invites_read_admin" on public.club_invites;
create policy "club_invites_read_admin" on public.club_invites
for select using (public.is_club_admin(club_id));

drop policy if exists "tactical_data_read_members" on public.club_tactical_data;
create policy "tactical_data_read_members" on public.club_tactical_data
for select using (public.is_active_member(club_id));

drop policy if exists "tactical_data_insert_members" on public.club_tactical_data;
create policy "tactical_data_insert_members" on public.club_tactical_data
for insert with check (
  public.is_active_member(club_id) and created_by = auth.uid()
);

drop policy if exists "tactical_data_update_author_or_admin" on public.club_tactical_data;
create policy "tactical_data_update_author_or_admin" on public.club_tactical_data
for update using (
  public.is_club_admin(club_id) or created_by = auth.uid()
) with check (
  public.is_active_member(club_id)
);

drop policy if exists "tactical_data_delete_author_or_admin" on public.club_tactical_data;
create policy "tactical_data_delete_author_or_admin" on public.club_tactical_data
for delete using (
  public.is_club_admin(club_id) or created_by = auth.uid()
);
