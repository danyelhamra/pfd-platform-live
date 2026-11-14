create table public.pfd_clubs (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  location text not null default '' check (char_length(location) <= 160),
  contact_email text not null default '' check (char_length(contact_email) <= 254),
  description text not null default '' check (char_length(description) <= 2000),
  status text not null default 'active' check (status in ('active','archived')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index pfd_clubs_status_created_idx on public.pfd_clubs(status, created_at desc);
create index pfd_clubs_created_idx on public.pfd_clubs(created_at desc);
create index pfd_clubs_created_by_idx on public.pfd_clubs(created_by);

create table public.pfd_club_admins (
  club_id uuid not null references public.pfd_clubs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (club_id,user_id)
);
create index pfd_club_admins_user_idx on public.pfd_club_admins(user_id,club_id);
create index pfd_club_admins_granted_by_idx on public.pfd_club_admins(granted_by);
alter table public.pfd_clubs enable row level security;
alter table public.pfd_club_admins enable row level security;
revoke all on public.pfd_clubs, public.pfd_club_admins from public,anon,authenticated;
grant select on public.pfd_clubs, public.pfd_club_admins to authenticated;
grant all on public.pfd_clubs, public.pfd_club_admins to service_role;

create policy club_admins_read_own_grants on public.pfd_club_admins for select to authenticated
using (
  user_id=(select auth.uid()) or
  exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))
);
create policy clubs_read_scoped on public.pfd_clubs for select to authenticated
using (
  exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())) or
  (status='active' and exists(select 1 from public.pfd_club_admins a where a.club_id=pfd_clubs.id and a.user_id=(select auth.uid())))
);
