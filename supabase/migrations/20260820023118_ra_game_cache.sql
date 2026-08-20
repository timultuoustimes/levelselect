-- Durable cache for RetroAchievements per-console game lists.
--
-- RA's own docs say of API_GetGameList: "Consider aggressively caching this
-- endpoint's response... Frequent calls to this endpoint may prompt us to look
-- into your bandwidth usage." The edge function cached in memory, which dies
-- with every cold start — so a quiet app could still re-download the whole NES
-- list many times a day, all of it attributed to one personal API key.
--
-- Rows are keyed by console and refreshed on age, so a cold instance reads
-- Postgres instead of RA.
create table if not exists public.ra_game_cache (
  console_id  integer primary key,
  payload     jsonb       not null,
  fetched_at  timestamptz not null default now()
);

-- No policies, on purpose: the edge function reaches this with the service
-- role, which bypasses RLS. Nothing else should ever read or write it.
alter table public.ra_game_cache enable row level security;
