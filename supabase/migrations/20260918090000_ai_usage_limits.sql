create table if not exists public.ai_usage_counters (
  key text primary key,
  n integer not null default 0,
  updated_at timestamptz not null default now()
);

-- Solo service_role (API de Vercel) toca esta tabla: RLS activo, sin policies.
alter table public.ai_usage_counters enable row level security;

-- Consume 1 generacion de IA si no se pasa ningun tope. Los topes globales
-- protegen la cuota gratuita de Gemini (que es por proyecto, no por usuario).
-- Ventanas en hora de Pacifico: Google resetea la cuota diaria a medianoche PT.
create or replace function public.ai_usage_consume(
  p_user text,
  p_user_day integer,
  p_global_day integer,
  p_global_minute integer
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  pt timestamp := now() at time zone 'America/Los_Angeles';
  d text := to_char(pt, 'YYYY-MM-DD');
  m text := to_char(pt, 'YYYY-MM-DD"T"HH24:MI');
  ku text := 'u:' || p_user || ':' || d;
  kg text := 'g:' || d;
  km text := 'gm:' || m;
begin
  perform pg_advisory_xact_lock(hashtext('ai_usage_consume'));

  if coalesce((select n from ai_usage_counters where key = kg), 0) >= p_global_day then
    return 'global_day';
  end if;
  if coalesce((select n from ai_usage_counters where key = km), 0) >= p_global_minute then
    return 'global_minute';
  end if;
  if coalesce((select n from ai_usage_counters where key = ku), 0) >= p_user_day then
    return 'user_day';
  end if;

  insert into ai_usage_counters (key, n) values (ku, 1), (kg, 1), (km, 1)
  on conflict (key) do update
    set n = ai_usage_counters.n + 1, updated_at = now();

  delete from ai_usage_counters where updated_at < now() - interval '3 days';
  return 'ok';
end;
$$;

revoke all on function public.ai_usage_consume(text, integer, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_usage_consume(text, integer, integer, integer) to service_role;
