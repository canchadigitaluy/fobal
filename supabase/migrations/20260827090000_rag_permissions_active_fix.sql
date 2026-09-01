create extension if not exists vector;

alter table public.club_memberships
  add column if not exists category_ids text[] not null default '{}';

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
        or target_category_id is null
        or cm.category_ids = '{}'
        or target_category_id = any(cm.category_ids)
      )
  );
$$;

create table if not exists public.training_context_documents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid,
  category_id text,
  user_id uuid references auth.users(id) on delete set null,
  content text not null,
  metadata jsonb not null default '{}'::jsonb,
  embedding vector(768),
  created_at timestamptz not null default now()
);

alter table public.training_context_documents enable row level security;

drop policy if exists "training_context_select_by_club_membership" on public.training_context_documents;
create policy "training_context_select_by_club_membership"
on public.training_context_documents
for select
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = training_context_documents.club_id
      and cm.user_id = auth.uid()
      and cm.status = 'active'
  )
);

drop policy if exists "training_context_insert_own_or_club" on public.training_context_documents;
create policy "training_context_insert_own_or_club"
on public.training_context_documents
for insert
with check (
  user_id = auth.uid()
  or exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = training_context_documents.club_id
      and cm.user_id = auth.uid()
      and cm.status = 'active'
      and cm.role in ('platform_admin', 'club_admin', 'coach', 'assistant', 'physical_trainer')
  )
);

create or replace function public.match_training_context(
  query_embedding vector(768),
  match_count int default 8,
  filter_user_id uuid default null,
  filter_club_id text default null
)
returns table (
  id uuid,
  content text,
  metadata jsonb,
  similarity float
)
language sql
stable
as $$
  select
    d.id,
    d.content,
    d.metadata,
    1 - (d.embedding <=> query_embedding) as similarity
  from public.training_context_documents d
  where d.embedding is not null
    and (
      filter_user_id is null
      or d.user_id = filter_user_id
      or exists (
        select 1
        from public.club_memberships cm
        where cm.club_id = d.club_id
          and cm.user_id = filter_user_id
          and cm.status = 'active'
      )
    )
    and (
      filter_club_id is null
      or filter_club_id = ''
      or d.club_id::text = filter_club_id
    )
  order by d.embedding <=> query_embedding
  limit greatest(1, least(match_count, 20));
$$;
