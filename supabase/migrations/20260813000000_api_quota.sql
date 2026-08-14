-- Quota store for the public edge functions (igdb-proxy, ai-tracker-generator,
-- map-finder). Those run with verify_jwt = false, so this table is the spend
-- ceiling that keeps an open endpoint from turning into an open wallet.
--
-- One row per (function, caller, window). The bucket key encodes the window
-- start, so a new window simply starts a new row and old rows are swept.

create table if not exists public.api_quota (
  bucket      text primary key,
  count       integer not null default 0,
  expires_at  timestamptz not null
);

create index if not exists api_quota_expires_at_idx on public.api_quota (expires_at);

-- Nothing but the service role (used by the edge functions) touches this.
alter table public.api_quota enable row level security;
revoke all on table public.api_quota from anon, authenticated;

-- Atomically increment every bucket and report the first one over its limit.
-- Buckets/limits/ttls are parallel arrays; checked in order.
create or replace function public.consume_quota(
  p_buckets text[],
  p_limits  integer[],
  p_ttls    integer[]
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  i       integer;
  v_count integer;
begin
  -- Opportunistic sweep; cheap because of the expires_at index.
  delete from public.api_quota where expires_at < now() - interval '1 hour';

  for i in 1 .. coalesce(array_length(p_buckets, 1), 0) loop
    insert into public.api_quota as q (bucket, count, expires_at)
    values (p_buckets[i], 1, now() + make_interval(secs => p_ttls[i]))
    on conflict (bucket) do update
      set count = case when q.expires_at < now() then 1 else q.count + 1 end,
          expires_at = case when q.expires_at < now()
                            then now() + make_interval(secs => p_ttls[i])
                            else q.expires_at end
    returning q.count into v_count;

    if v_count > p_limits[i] then
      return jsonb_build_object(
        'allowed', false,
        'bucket',  p_buckets[i],
        'count',   v_count,
        'limit',   p_limits[i]
      );
    end if;
  end loop;

  return jsonb_build_object('allowed', true);
end;
$$;

revoke all on function public.consume_quota(text[], integer[], integer[])
  from public, anon, authenticated;
