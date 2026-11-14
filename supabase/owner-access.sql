create table public.pfd_platform_owners (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);
alter table public.pfd_platform_owners enable row level security;
revoke all on public.pfd_platform_owners from public, anon, authenticated;
grant select on public.pfd_platform_owners to authenticated;
grant all on public.pfd_platform_owners to service_role;
create policy owner_can_read_own_grant on public.pfd_platform_owners
for select to authenticated using ((select auth.uid()) = user_id);
