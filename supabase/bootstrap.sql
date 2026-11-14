create table public.pfd_signup_limits (
  bucket text primary key,
  attempts integer not null default 1 check (attempts between 1 and 10),
  created_at timestamptz not null default now()
);
create index pfd_signup_limits_created_at_idx on public.pfd_signup_limits(created_at);
alter table public.pfd_signup_limits enable row level security;
revoke all on public.pfd_signup_limits from anon, authenticated;
grant all on public.pfd_signup_limits to service_role;

create function public.pfd_take_signup_slot(p_bucket text)
returns boolean language plpgsql set search_path = '' as $$
begin
  delete from public.pfd_signup_limits where created_at < now() - interval '2 days';
  insert into public.pfd_signup_limits(bucket, attempts) values (p_bucket, 1)
  on conflict(bucket) do update set attempts = public.pfd_signup_limits.attempts + 1
  where public.pfd_signup_limits.attempts < 10;
  return found;
end;
$$;
revoke all on function public.pfd_take_signup_slot(text) from public, anon, authenticated;
grant execute on function public.pfd_take_signup_slot(text) to service_role;
