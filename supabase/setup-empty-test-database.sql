-- Run ONCE in the SQL editor of the NEW EMPTY TEST project only.
-- Never run this against the ChatGPT test backend or any existing PFD database.
begin;
do $$begin if to_regclass('public.pfd_platform_owners') is not null then
 raise exception 'PFD tables already exist. Stop: this setup is for an empty test project only.';
end if;end$$;

-- SOURCE: supabase/bootstrap.sql
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


-- SOURCE: supabase/owner-access.sql
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


-- SOURCE: supabase/clubs.sql
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


-- SOURCE: supabase/club-required-details.sql
alter table public.pfd_clubs
  add column city text not null default '',
  add column state text not null default '',
  add column country text not null default '',
  add column contact_number text not null default '',
  add column league text not null default '',
  add column sport text not null default '';
alter table public.pfd_clubs drop constraint pfd_clubs_location_check;
alter table public.pfd_clubs add constraint pfd_clubs_location_check check(char_length(location)<=320);
-- Existing clubs are preserved without inventing their missing details.
-- NOT VALID still enforces this constraint on every new INSERT or UPDATE.
alter table public.pfd_clubs add constraint pfd_clubs_required_details check (
  char_length(btrim(city)) between 1 and 80 and
  char_length(btrim(state)) between 1 and 80 and
  char_length(btrim(country)) between 1 and 80 and
  char_length(btrim(league)) between 1 and 160 and
  char_length(btrim(sport)) between 1 and 80 and
  char_length(contact_email) between 3 and 254 and
  contact_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' and
  char_length(contact_number) between 7 and 32 and
  contact_number ~ '^[+0-9() .-]+$' and
  char_length(regexp_replace(contact_number,'[^0-9]','','g')) between 7 and 15
) not valid;


-- SOURCE: supabase/permissions.sql
-- Apply after owner-access.sql, clubs.sql and club-required-details.sql.
-- Permissions define abilities; membership records remain the source of scope.
create table public.pfd_permission_catalog (
 key text primary key,
 category text not null,
 label text not null,
 description text not null,
 available boolean not null default false,
 owner_only boolean not null default false,
 sort_order integer not null
);
create table public.pfd_role_permissions (
 role_key text not null check (role_key in ('club_admin','coach','player')),
 permission_key text not null references public.pfd_permission_catalog(key),
 enabled boolean not null default false,
 primary key(role_key,permission_key)
);
create index pfd_role_permissions_permission_idx on public.pfd_role_permissions(permission_key);
create table public.pfd_permission_settings (
 singleton boolean primary key default true check(singleton),
 revision bigint not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);
create index pfd_permission_settings_actor_idx on public.pfd_permission_settings(updated_by);
create table public.pfd_permission_audit (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references auth.users(id) on delete set null,
 revision bigint not null,
 changes jsonb not null,
 created_at timestamptz not null default now()
);
create index pfd_permission_audit_actor_idx on public.pfd_permission_audit(actor_id);
create index pfd_permission_audit_created_idx on public.pfd_permission_audit(created_at desc);
insert into public.pfd_permission_catalog(key,category,label,description,available,owner_only,sort_order) values
('clubs.view','Club & people','View club details','Assigned active club only.',true,false,0),
('clubs.create','Platform administration','Create clubs','Platform owner only.',true,true,1),
('clubs.manage','Platform administration','Manage clubs and club administrators','Platform owner only.',true,true,2),
('users.view_all','Platform administration','View all platform accounts','Platform owner only.',true,true,3),
('roles.manage','Platform administration','Manage roles and permissions','Platform owner only.',true,true,4),
('teams.view','Club & people','View teams','Assigned club for club admins; joined teams for coaches and players.',false,false,5),
('teams.create','Club & people','Create and edit teams','Assigned club only.',false,false,6),
('coaches.approve','Club & people','Approve coaches','Assigned club only.',false,false,7),
('players.approve','Club & people','Approve player requests','Assigned club or coached team only.',false,false,8),
('members.view','Club & people','View member directory','Assigned club or coached team only; no platform directory.',false,false,9),
('reports.view_team','Reports','View team player reports','Assigned club or coached team only; players cannot browse teammates’ private reports.',false,false,10),
('reports.create','Reports','Create player reports','Assigned club or coached team only.',false,false,11),
('reports.view_own','Reports','View own reports','Reports belonging to the signed-in account only.',false,false,12),
('reports.self_assess','Reports','Submit self-assessments','The signed-in account’s own assessments only.',false,false,13),
('homework.assign','Homework','Assign homework','Assigned club or coached team only.',false,false,14),
('homework.review','Homework','Review submissions and give feedback','Assigned club or coached team only.',false,false,15),
('homework.view','Homework','View assigned homework','Homework assigned to the account or its teams only.',false,false,16),
('homework.submit','Homework','Submit homework and videos','Own submissions only.',false,false,17),
('events.manage','Training & games','Manage training and games','Assigned club or coached team only.',false,false,18),
('events.view','Training & games','View training and games','Joined teams only, or assigned club for club admins.',false,false,19),
('plans.manage','Training & games','Create training plans and templates','Assigned club or coached team only.',false,false,20),
('library.view','Development library','Browse shared resources','Resources shared with the account’s club or teams.',false,false,21),
('library.manage_club','Development library','Manage club resources','Assigned club only; does not grant control of the PFD-wide library.',false,false,22),
('announcements.publish','Announcements','Publish announcements','Assigned club or coached team only.',false,false,23),
('announcements.view','Announcements','View announcements','Announcements shared with the account’s club or teams.',false,false,24);
insert into public.pfd_role_permissions(role_key,permission_key,enabled)
select r.role_key,c.key,false from public.pfd_permission_catalog c
cross join (values ('club_admin'),('coach'),('player')) as r(role_key);
update public.pfd_role_permissions set enabled=true where role_key='club_admin' and permission_key in ('clubs.view','teams.view','teams.create','coaches.approve','players.approve','members.view','reports.view_team','reports.create','reports.view_own','reports.self_assess','homework.assign','homework.review','homework.view','homework.submit','events.manage','events.view','plans.manage','library.view','library.manage_club','announcements.publish','announcements.view');
update public.pfd_role_permissions set enabled=true where role_key='coach' and permission_key in ('teams.view','players.approve','members.view','reports.view_team','reports.create','reports.view_own','reports.self_assess','homework.assign','homework.review','homework.view','homework.submit','events.manage','events.view','plans.manage','library.view','announcements.publish','announcements.view');
update public.pfd_role_permissions set enabled=true where role_key='player' and permission_key in ('teams.view','reports.view_own','reports.self_assess','homework.view','homework.submit','events.view','library.view','announcements.view');
insert into public.pfd_permission_settings(singleton) values(true);
alter table public.pfd_permission_catalog enable row level security;
alter table public.pfd_role_permissions enable row level security;
alter table public.pfd_permission_settings enable row level security;
alter table public.pfd_permission_audit enable row level security;
revoke all on public.pfd_permission_catalog,public.pfd_role_permissions,public.pfd_permission_settings,public.pfd_permission_audit from public,anon,authenticated;
grant select on public.pfd_permission_catalog,public.pfd_role_permissions to authenticated;
grant update(enabled) on public.pfd_role_permissions to authenticated;
grant select on public.pfd_permission_settings,public.pfd_permission_audit to authenticated;
grant update(revision,updated_at,updated_by) on public.pfd_permission_settings to authenticated;
grant insert(actor_id,revision,changes) on public.pfd_permission_audit to authenticated;
grant all on public.pfd_permission_catalog,public.pfd_role_permissions,public.pfd_permission_settings,public.pfd_permission_audit to service_role;
create policy permission_catalog_read on public.pfd_permission_catalog for select to authenticated using(true);
create policy role_permissions_read on public.pfd_role_permissions for select to authenticated using(true);
create policy role_permissions_owner_update on public.pfd_role_permissions for update to authenticated
using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())))
with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))
 and (not enabled or exists(select 1 from public.pfd_permission_catalog c where c.key=permission_key and not c.owner_only)));
create policy permission_settings_owner_read on public.pfd_permission_settings for select to authenticated
using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy permission_settings_owner_update on public.pfd_permission_settings for update to authenticated
using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())))
with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())) and updated_by=(select auth.uid()));
create policy permission_audit_owner_read on public.pfd_permission_audit for select to authenticated
using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy permission_audit_owner_insert on public.pfd_permission_audit for insert to authenticated
with check(actor_id=(select auth.uid()) and exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));

-- Invoker keeps all RLS checks in force. No elevated database privileges.
create function public.pfd_save_role_permissions(expected_revision bigint, changes jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare config public.pfd_permission_settings; item jsonb; changed integer;
begin
 if not exists(select 1 from public.pfd_platform_owners o where o.user_id=auth.uid()) then
  raise exception 'PFD Owner access is required.' using errcode='42501';
 end if;
 if jsonb_typeof(changes) is distinct from 'array' then
  raise exception 'Invalid permission changes.' using errcode='22023';
 end if;
 if jsonb_array_length(changes) not between 1 and 150 then
  raise exception 'Choose between 1 and 150 permission changes.' using errcode='22023';
 end if;
 if (select count(*) from jsonb_array_elements(changes)) <>
    (select count(distinct (e->>'role_key',e->>'permission_key')) from jsonb_array_elements(changes) e) then
  raise exception 'Duplicate permission changes.' using errcode='22023';
 end if;
 select * into config from public.pfd_permission_settings where singleton for update;
 if config.revision is distinct from expected_revision then
  raise exception 'Permissions changed elsewhere. Reload the latest settings before saving.' using errcode='40001';
 end if;
 for item in select value from jsonb_array_elements(changes) loop
  if jsonb_typeof(item) is distinct from 'object' or
     jsonb_typeof(item->'enabled') is distinct from 'boolean' or
     not coalesce(item->>'role_key' in ('club_admin','coach','player'),false) or
     not exists(select 1 from public.pfd_permission_catalog c where c.key=item->>'permission_key' and not c.owner_only) then
   raise exception 'This role or permission is protected or invalid.' using errcode='22023';
  end if;
  update public.pfd_role_permissions set enabled=(item->>'enabled')::boolean
  where role_key=item->>'role_key' and permission_key=item->>'permission_key';
  get diagnostics changed=row_count;
  if changed<>1 then raise exception 'Permission not found.' using errcode='22023'; end if;
 end loop;
 update public.pfd_permission_settings set revision=config.revision+1,updated_at=now(),updated_by=auth.uid() where singleton
 returning * into config;
 insert into public.pfd_permission_audit(actor_id,revision,changes) values(auth.uid(),config.revision,changes);
 return jsonb_build_object('revision',config.revision,'updated_at',config.updated_at);
end $$;
revoke all on function public.pfd_save_role_permissions(bigint,jsonb) from public,anon;
grant execute on function public.pfd_save_role_permissions(bigint,jsonb) to authenticated;

-- Enforce the first live delegated permission at the database boundary.
alter policy clubs_read_scoped on public.pfd_clubs to authenticated using (
 exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())) or
 (status='active'
  and exists(select 1 from public.pfd_club_admins a where a.club_id=pfd_clubs.id and a.user_id=(select auth.uid()))
  and exists(select 1 from public.pfd_role_permissions p where p.role_key='club_admin' and p.permission_key='clubs.view' and p.enabled))
);

-- The caller's identity is always auth.uid(); a caller cannot pass a different user.
-- This currently supports existing club-admin assignments. Coach/player scope is
-- deliberately denied until their membership models and feature policies exist.
create function public.pfd_has_club_permission(target_club uuid, requested_permission text)
returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.pfd_permission_catalog c where c.key=requested_permission and c.available)
 and (
  exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())) or
  exists(select 1 from public.pfd_clubs c
   join public.pfd_club_admins a on a.club_id=c.id
   join public.pfd_role_permissions p on p.role_key='club_admin' and p.permission_key=requested_permission and p.enabled
   join public.pfd_permission_catalog pc on pc.key=p.permission_key and not pc.owner_only
   where c.id=target_club and c.status='active' and a.user_id=(select auth.uid()))
 );
$$;
revoke all on function public.pfd_has_club_permission(uuid,text) from public,anon;
grant execute on function public.pfd_has_club_permission(uuid,text) to authenticated;

-- One statement gives the editor a consistent matrix + revision snapshot.
create function public.pfd_get_role_permissions()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.pfd_platform_owners o where o.user_id=auth.uid()) then
  raise exception 'PFD Owner access is required.' using errcode='42501';
 end if;
 select jsonb_build_object(
  'permissions',(select jsonb_agg(to_jsonb(c) order by c.sort_order) from public.pfd_permission_catalog c),
  'grants',(select jsonb_agg(to_jsonb(p) order by p.role_key,p.permission_key) from public.pfd_role_permissions p),
  'settings',(select to_jsonb(s) from public.pfd_permission_settings s where singleton),
  'history',(select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at desc),'[]'::jsonb) from
   (select id,revision,created_at,jsonb_array_length(changes) as change_count from public.pfd_permission_audit order by created_at desc limit 5) h)
 ) into result;
 return result;
end $$;
revoke all on function public.pfd_get_role_permissions() from public,anon;
grant execute on function public.pfd_get_role_permissions() to authenticated;

-- PFD-wide controls stay owner-only as the remaining dashboard sections arrive.
insert into public.pfd_permission_catalog(key,category,label,description,available,owner_only,sort_order) values
 ('requests.review_all','Platform administration','Review platform access requests','Platform owner only.',false,true,25),
 ('reports.view_all','Platform administration','View reports across all clubs','Platform owner only.',false,true,26),
 ('library.manage_platform','Platform administration','Manage the PFD development library','Platform owner only.',false,true,27),
 ('settings.manage','Platform administration','Manage platform settings','Platform owner only.',true,true,28);
insert into public.pfd_role_permissions(role_key,permission_key,enabled)
select r.role_key,c.key,false from public.pfd_permission_catalog c
cross join (values ('club_admin'),('coach'),('player')) as r(role_key)
where c.key in ('requests.review_all','reports.view_all','library.manage_platform','settings.manage');


-- SOURCE: supabase/owner-workspace.sql
-- Owner workspace: read-only account directory, requests, original reports and resources.
create schema if not exists pfd_private;
revoke all on schema pfd_private from public,anon,authenticated;
create table public.pfd_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null default '',email text not null default '',
 created_at timestamptz not null,last_sign_in_at timestamptz
);
-- Auth data never receives a client SELECT grant. This narrow trigger copies only
-- directory-safe fields. It cannot be called by clients and grants no roles.
create function pfd_private.sync_pfd_profile() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 insert into public.pfd_profiles(id,name,email,created_at,last_sign_in_at)
 values(new.id,left(coalesce(new.raw_user_meta_data->>'full_name',''),150),coalesce(new.email,''),new.created_at,new.last_sign_in_at)
 on conflict(id) do update set name=excluded.name,email=excluded.email,last_sign_in_at=excluded.last_sign_in_at;
 return new;
end $$;
revoke all on function pfd_private.sync_pfd_profile() from public,anon,authenticated;
create trigger pfd_sync_profile after insert or update of raw_user_meta_data,email,last_sign_in_at on auth.users for each row execute function pfd_private.sync_pfd_profile();
insert into public.pfd_profiles(id,name,email,created_at,last_sign_in_at)
select id,left(coalesce(raw_user_meta_data->>'full_name',''),150),coalesce(email,''),created_at,last_sign_in_at from auth.users;

create table public.pfd_teams (
 id uuid primary key default gen_random_uuid(),club_id uuid not null references public.pfd_clubs(id),
 name text not null check(length(btrim(name)) between 1 and 120),age_group text not null default '',season text not null default '',
 status text not null default 'active' check(status in ('active','archived')),created_at timestamptz not null default now(),unique(id,club_id)
);
create index pfd_teams_club_idx on public.pfd_teams(club_id);
create table public.pfd_team_memberships (
 team_id uuid not null references public.pfd_teams(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,
 role_key text not null check(role_key in ('coach','player')),granted_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),primary key(team_id,user_id,role_key)
);
create index pfd_team_memberships_user_idx on public.pfd_team_memberships(user_id);
create index pfd_team_memberships_actor_idx on public.pfd_team_memberships(granted_by);
create table public.pfd_access_requests (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.pfd_profiles(id) on delete cascade,
 club_id uuid not null references public.pfd_clubs(id),team_id uuid,
 role_key text not null check(role_key in ('club_admin','coach','player')),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 message text not null default '' check(length(message)<=2000),reason text not null default '' check(length(reason)<=2000),
 created_by uuid references auth.users(id) on delete set null,reviewed_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),reviewed_at timestamptz,
 foreign key(team_id,club_id) references public.pfd_teams(id,club_id),
 check((role_key='club_admin' and team_id is null) or (role_key in ('coach','player') and team_id is not null))
);
create unique index pfd_access_requests_pending_idx on public.pfd_access_requests(user_id,club_id,coalesce(team_id,'00000000-0000-0000-0000-000000000000'::uuid),role_key) where status='pending';
create index pfd_access_requests_club_idx on public.pfd_access_requests(club_id);
create index pfd_access_requests_team_idx on public.pfd_access_requests(team_id,club_id);
create index pfd_access_requests_created_by_idx on public.pfd_access_requests(created_by);
create index pfd_access_requests_reviewed_by_idx on public.pfd_access_requests(reviewed_by);
create index pfd_access_requests_status_idx on public.pfd_access_requests(status,created_at desc);
create table public.pfd_report_templates (
 key text primary key,label text not null,definition jsonb not null,source_commit text not null
);
create table public.pfd_reports (
 id uuid primary key,subject_id uuid not null references public.pfd_profiles(id),club_id uuid references public.pfd_clubs(id),team_id uuid,
 template_key text not null references public.pfd_report_templates(key),template_snapshot jsonb not null,
 report_date date not null,status text not null check(status in ('draft','submitted','archived')),
 data jsonb not null,created_by uuid references public.pfd_profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(team_id,club_id) references public.pfd_teams(id,club_id),check(team_id is null or club_id is not null)
);
create index pfd_reports_subject_idx on public.pfd_reports(subject_id);
create index pfd_reports_club_idx on public.pfd_reports(club_id);
create index pfd_reports_team_idx on public.pfd_reports(team_id,club_id);
create index pfd_reports_template_idx on public.pfd_reports(template_key);
create index pfd_reports_author_idx on public.pfd_reports(created_by);
create index pfd_reports_date_idx on public.pfd_reports(report_date desc,created_at desc);
create table public.pfd_resources (
 id uuid primary key,title text not null check(length(btrim(title)) between 1 and 160),
 kind text not null check(kind in ('drill','homework','training_plan','report_template')),
 category text not null default '' check(length(category)<=80),difficulty text not null default 'all' check(difficulty in ('all','beginner','intermediate','advanced')),
 instructions text not null default '' check(length(instructions)<=12000),video_url text not null default '' check(video_url='' or video_url ~ '^https?://'),
 attachments jsonb not null default '[]' check(jsonb_typeof(attachments)='array' and jsonb_array_length(attachments)<=5),
 audience text not null default 'all_clubs' check(audience in ('all_clubs','selected_clubs')),
 status text not null default 'draft' check(status in ('draft','published','archived')),
 created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.pfd_resource_clubs (
 resource_id uuid not null references public.pfd_resources(id) on delete cascade,club_id uuid not null references public.pfd_clubs(id),primary key(resource_id,club_id)
);
create index pfd_resource_clubs_club_idx on public.pfd_resource_clubs(club_id);
create index pfd_resources_author_idx on public.pfd_resources(created_by);
create index pfd_resources_status_idx on public.pfd_resources(status,kind,updated_at desc);
insert into public.pfd_report_templates(key,label,definition,source_commit) values('player','Player report','{"title": "Player development report", "short": "Player report", "intro": "Every player. A step forward.", "desc": "Record progress, celebrate strengths and agree on the next development focus.", "categories": {"Tactical": ["The player understands their position on the field.", "In their position, do they understand where to position themselves according to which teammate has the ball? (Tactical decision)", "In their position, do they understand where to position themselves according to which opponent has the ball? (Off-ball / Possession \u2013 Opponent)", "The player is developing and learning their tactical role.", "For their age, the player has a good understanding of their position on and off the ball."], "Training": ["Does the player quickly understand the coach\u2019s concepts?", "Does the player train hard?", "Is the player learning to find self-motivation to train and learn the concepts at training?", "Does the player try to excel in different activities?", "Is the player competitive in various games?"], "Technical": ["Does the player have outstanding technique for their position?", "Does the player use both feet to solve situations?", "Does the player manage their body position correctly before receiving the ball?", "Does the player have a good passing game?", "Is the player developing and learning technical abilities?"], "Features": ["Is the player dynamic?", "Is the player good at duelling? (1 v 1 or passing game)", "Is the player fearless or willing to take risks?", "Is the player responsible? (Uniform, schedules, game attendance)", "Does the player accept the coach\u2019s decisions?"]}, "notes": ["Coach notes & next development focus", "Player strengths", "Agreed actions & practice plan", "Player feedback"], "behaviours": {"Attitude": ["Positive", "Great willingness", "Optimistic"], "Resilience": ["Acceptance of defeats", "Overcoming challenges", "Emotionally strong"], "Teamwork": ["Helping others", "Supporting", "Caring"], "Attendance": ["Trainings", "Games", "Events"]}, "exercises": [["Technique Individual", "20 sec"], ["Team Passing Challenge", "1 min"], ["Accuracy", "5 m \u00b7 10 m \u00b7 15 m"]]}'::jsonb,'a1890fb76f404244e9512faebe9c9d803da75791');
insert into public.pfd_report_templates(key,label,definition,source_commit) values('fitness','Fitness report','{"title": "Fitness report", "short": "Fitness report", "intro": "Build the engine. Support the player.", "desc": "Record observable fitness qualities and repeatable test results. Use the findings to plan appropriate training.", "categories": {"Movement": ["Moves with balance and control", "Changes direction with control", "Uses sound landing mechanics", "Maintains coordination under fatigue"], "Conditioning": ["Sustains effort through training", "Recovers between repeated efforts", "Shows speed over short distances", "Maintains quality during repeated sprints"], "Habits": ["Completes the warm-up with focus", "Uses correct technique in conditioning drills", "Communicates fatigue or discomfort", "Shows consistency in fitness work"]}, "notes": ["Fitness strengths", "Development priorities", "Agreed conditioning plan", "Test conditions & observations"], "behaviours": {}, "exercises": []}'::jsonb,'a1890fb76f404244e9512faebe9c9d803da75791');
insert into public.pfd_report_templates(key,label,definition,source_commit) values('tactical','Tactical report','{"title": "Tactical report", "short": "Tactical report", "intro": "See the game. Make the difference.", "desc": "Assess decision-making in and out of possession, then choose clear tactical actions for the next session.", "categories": {"Possession": ["Scans before receiving the ball", "Creates useful passing angles", "Chooses when to pass, carry or dribble", "Maintains appropriate team width and depth", "Recognises opportunities to break lines"], "Defending": ["Understands their defensive role", "Applies pressure at the right moment", "Provides cover and balance", "Tracks runners and protects space", "Communicates with teammates"], "Transitions": ["Reacts quickly after losing possession", "Recognises when to counter-press or recover", "Offers an outlet after regaining possession", "Makes purposeful forward runs", "Supports the team shape during transitions"]}, "notes": ["Match / session context & observations", "Tactical strengths", "Priority decisions to improve", "Next-session actions"], "behaviours": {}, "exercises": []}'::jsonb,'a1890fb76f404244e9512faebe9c9d803da75791');
insert into public.pfd_report_templates(key,label,definition,source_commit) values('parent','Parent report','{"title": "Parent report", "short": "Parent report", "intro": "A stronger connection. A happier player.", "desc": "A parent or carer perspective on the player\u2019s experience, enjoyment and support needs. Honest feedback helps the coaching team.", "categories": {"Experience": ["My child enjoys attending training", "My child feels included in the team", "My child feels comfortable asking the coach for help", "The training environment feels supportive"], "Communication": ["I understand the training and match schedule", "I receive timely and clear club updates", "I understand my child\u2019s development goals", "I know how to contact the coaching team"], "Development": ["My child is growing in confidence", "My child shows enthusiasm for football", "My child is developing positive team habits", "The programme supports my child\u2019s learning"]}, "notes": ["What is working well for your child?", "Any concerns or support needs?", "Your child\u2019s goals & feedback", "Questions or suggestions for the coaching team"], "behaviours": {}, "exercises": []}'::jsonb,'a1890fb76f404244e9512faebe9c9d803da75791');
insert into public.pfd_report_templates(key,label,definition,source_commit) values('coaches','Coaches report','{"title": "Coaches report", "short": "Coaches report", "intro": "Reflect on the session. Raise the standard.", "desc": "Review coaching practice, session delivery and the team\u2019s response. Record evidence and agree useful next steps.", "categories": {"Planning": ["Sets clear, age-appropriate learning objectives", "Prepares suitable activities and progressions", "Uses equipment, space and time effectively", "Plans adaptations for different player needs"], "Delivery": ["Gives clear explanations and demonstrations", "Uses helpful questions and specific feedback", "Keeps players engaged and active", "Adapts the session in response to learning"], "Environment": ["Builds respectful relationships with players", "Creates an inclusive and supportive environment", "Reinforces appropriate behaviour consistently", "Communicates professionally with families and staff"], "Reflection": ["Checks whether players understood the objective", "Recognises what worked and what needs changing", "Acts on feedback from other coaches", "Sets a practical goal for the next session"]}, "notes": ["Session objectives & evidence", "What worked well?", "What could be improved?", "Agreed coaching development actions"], "behaviours": {}, "exercises": []}'::jsonb,'a1890fb76f404244e9512faebe9c9d803da75791');
alter table public.pfd_profiles enable row level security;
revoke all on public.pfd_profiles from public,anon,authenticated;
grant select on public.pfd_profiles to authenticated;
grant all on public.pfd_profiles to service_role;
create policy pfd_profiles_owner_read on public.pfd_profiles for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
alter table public.pfd_teams enable row level security;
revoke all on public.pfd_teams from public,anon,authenticated;
grant select on public.pfd_teams to authenticated;
grant all on public.pfd_teams to service_role;
create policy pfd_teams_owner_read on public.pfd_teams for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
alter table public.pfd_team_memberships enable row level security;
revoke all on public.pfd_team_memberships from public,anon,authenticated;
grant select on public.pfd_team_memberships to authenticated;
grant all on public.pfd_team_memberships to service_role;
create policy pfd_team_memberships_owner_read on public.pfd_team_memberships for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
alter table public.pfd_access_requests enable row level security;
revoke all on public.pfd_access_requests from public,anon,authenticated;
grant select on public.pfd_access_requests to authenticated;
grant all on public.pfd_access_requests to service_role;
create policy pfd_access_requests_owner_read on public.pfd_access_requests for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
alter table public.pfd_report_templates enable row level security;
revoke all on public.pfd_report_templates from public,anon,authenticated;
grant select on public.pfd_report_templates to authenticated;
grant all on public.pfd_report_templates to service_role;
create policy pfd_report_templates_owner_read on public.pfd_report_templates for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
alter table public.pfd_reports enable row level security;
revoke all on public.pfd_reports from public,anon,authenticated;
grant select on public.pfd_reports to authenticated;
grant all on public.pfd_reports to service_role;
create policy pfd_reports_owner_read on public.pfd_reports for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
alter table public.pfd_resources enable row level security;
revoke all on public.pfd_resources from public,anon,authenticated;
grant select on public.pfd_resources to authenticated;
grant all on public.pfd_resources to service_role;
create policy pfd_resources_owner_read on public.pfd_resources for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
alter table public.pfd_resource_clubs enable row level security;
revoke all on public.pfd_resource_clubs from public,anon,authenticated;
grant select on public.pfd_resource_clubs to authenticated;
grant all on public.pfd_resource_clubs to service_role;
create policy pfd_resource_clubs_owner_read on public.pfd_resource_clubs for select to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
grant insert,update,delete on public.pfd_access_requests to authenticated;
create policy pfd_access_requests_owner_insert on public.pfd_access_requests for insert to authenticated with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_access_requests_owner_update on public.pfd_access_requests for update to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))) with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_access_requests_owner_delete on public.pfd_access_requests for delete to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
grant insert,update,delete on public.pfd_reports to authenticated;
create policy pfd_reports_owner_insert on public.pfd_reports for insert to authenticated with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_reports_owner_update on public.pfd_reports for update to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))) with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_reports_owner_delete on public.pfd_reports for delete to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
grant insert,update,delete on public.pfd_resources to authenticated;
create policy pfd_resources_owner_insert on public.pfd_resources for insert to authenticated with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_resources_owner_update on public.pfd_resources for update to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))) with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_resources_owner_delete on public.pfd_resources for delete to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
grant insert,update,delete on public.pfd_resource_clubs to authenticated;
create policy pfd_resource_clubs_owner_insert on public.pfd_resource_clubs for insert to authenticated with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_resource_clubs_owner_update on public.pfd_resource_clubs for update to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))) with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_resource_clubs_owner_delete on public.pfd_resource_clubs for delete to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
grant insert,update,delete on public.pfd_team_memberships to authenticated;
create policy pfd_team_memberships_owner_insert on public.pfd_team_memberships for insert to authenticated with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_team_memberships_owner_update on public.pfd_team_memberships for update to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))) with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_team_memberships_owner_delete on public.pfd_team_memberships for delete to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
grant insert,update,delete on public.pfd_club_admins to authenticated;
create policy pfd_club_admins_owner_insert on public.pfd_club_admins for insert to authenticated with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_club_admins_owner_update on public.pfd_club_admins for update to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid()))) with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_club_admins_owner_delete on public.pfd_club_admins for delete to authenticated using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));

-- Private files: the bucket has no public URL. Only the canonical owner can upload/read.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pfd-development-resources','pfd-development-resources',false,52428800,array['application/pdf','image/jpeg','image/png','image/webp','video/mp4','video/webm']);
create policy pfd_resources_files_owner on storage.objects for all to authenticated
using(bucket_id='pfd-development-resources' and exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())))
with check(bucket_id='pfd-development-resources' and exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));

create function public.pfd_owner_workspace(action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 actor uuid:=auth.uid(); q text:=left(coalesce(payload->>'query',''),160);
 page_no integer:=coalesce((payload->>'page')::integer,1); page_size integer:=20;
 offset_no integer; result jsonb; item jsonb; definition jsonb; entry record;
 req public.pfd_access_requests; old_report public.pfd_reports; old_resource public.pfd_resources;
 record_id uuid; subject uuid; club uuid; team uuid; role_name text; state text; template text;
 info jsonb; report_data jsonb; revision_time timestamptz; selected_clubs uuid[];
begin
 if not exists(select 1 from public.pfd_platform_owners o where o.user_id=actor) then
  raise exception 'PFD Owner access is required.' using errcode='42501';
 end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>150000 or page_no not between 1 and 100000 then
  raise exception 'Invalid request.' using errcode='22023';
 end if;
 offset_no:=(page_no-1)*page_size;
 if action='options' then
  return jsonb_build_object(
   'clubs',(select coalesce(jsonb_agg(to_jsonb(c) order by c.name),'[]') from (select id,name,status from public.pfd_clubs order by name limit 1000)c),
   'teams',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name),'[]') from (select id,club_id,name,age_group,season,status from public.pfd_teams order by name limit 2000)t),
   'templates',(select jsonb_agg(to_jsonb(t) order by t.key) from public.pfd_report_templates t)
  );
 elsif action='users_list' then
  with accounts as (
   select p.*,
    array_remove(array[
     case when exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) then 'owner' end,
     case when exists(select 1 from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id and c.status='active' where a.user_id=p.id) then 'club_admin' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='coach') then 'coach' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='player') then 'player' end
    ],null) as roles,
    (select count(*) from public.pfd_reports r where r.subject_id=p.id and r.status='submitted') as report_count
   from public.pfd_profiles p
   where (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0)
    and (coalesce(payload->>'club_id','')='' or exists(select 1 from public.pfd_club_admins a where a.user_id=p.id and a.club_id=(payload->>'club_id')::uuid)
      or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=p.id and t.club_id=(payload->>'club_id')::uuid))
  ), filtered as(select * from accounts where coalesce(payload->>'role','')='' or (payload->>'role'='member' and cardinality(roles)=0) or payload->>'role'=any(roles))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),
   'total',(select count(*) from filtered),'total_accounts',(select count(*) from public.pfd_profiles),'page',page_no) into result;
  return result;
 elsif action='user_detail' then
  subject:=(payload->>'id')::uuid;
  if not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Account not found.' using errcode='P0002'; end if;
  return jsonb_build_object('profile',(select to_jsonb(p) from public.pfd_profiles p where p.id=subject),
   'is_owner',exists(select 1 from public.pfd_platform_owners o where o.user_id=subject),
   'memberships',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from (
    select a.club_id,c.name as club_name,null::uuid as team_id,null::text as team_name,'club_admin'::text as role_key,c.status,a.created_at from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id where a.user_id=subject
    union all select t.club_id,c.name,m.team_id,t.name,m.role_key,case when c.status='archived' then 'archived' else t.status end,m.created_at from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.user_id=subject
   )m),
   'report_count',(select count(*) from public.pfd_reports where subject_id=subject and status='submitted'),
   'created_reports',(select count(*) from public.pfd_reports where created_by=subject and status='submitted'),
   'pending_requests',(select count(*) from public.pfd_access_requests where user_id=subject and status='pending'),
   'recent_reports',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (select id,template_key,report_date,status from public.pfd_reports where subject_id=subject order by report_date desc,created_at desc limit 10)r)
  );
 elsif action='requests_list' then
  with filtered as (
   select r.*,p.name,p.email,c.name as club_name,t.name as team_name,reviewer.name as reviewer_name from public.pfd_access_requests r
   join public.pfd_profiles p on p.id=r.user_id join public.pfd_clubs c on c.id=r.club_id
   left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles reviewer on reviewer.id=r.reviewed_by
   where (coalesce(payload->>'status','')='' or r.status=payload->>'status')
   and (coalesce(payload->>'role','')='' or r.role_key=payload->>'role')
   and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
   and (q='' or strpos(lower(p.name||' '||p.email||' '||c.name),lower(q))>0)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'pending',(select count(*) from public.pfd_access_requests where status='pending'),'page',page_no) into result;
  return result;
 elsif action='request_create' then
  subject:=(payload->>'user_id')::uuid;club:=(payload->>'club_id')::uuid;team:=nullif(payload->>'team_id','')::uuid;role_name:=payload->>'role_key';
  if not exists(select 1 from public.pfd_profiles where id=subject) or not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an existing account and active club.' using errcode='22023'; end if;
  if role_name not in ('club_admin','coach','player') or role_name is null or (role_name='club_admin' and team is not null) or (role_name<>'club_admin' and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active')) then raise exception 'Choose a valid role and team for this club.' using errcode='22023'; end if;
  if exists(select 1 from public.pfd_club_admins where user_id=subject and club_id=club and role_name='club_admin') or exists(select 1 from public.pfd_team_memberships where user_id=subject and team_id=team and role_key=role_name) then raise exception 'This account already has the requested membership.' using errcode='22023'; end if;
  insert into public.pfd_access_requests(user_id,club_id,team_id,role_key,message,created_by) values(subject,club,team,role_name,coalesce(payload->>'message',''),actor) returning id into record_id;
  return jsonb_build_object('id',record_id);
 elsif action='request_review' then
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Request not found.' using errcode='P0002'; end if;
  if req.status<>'pending' then raise exception 'This request has already been reviewed. Refresh the list.' using errcode='40001'; end if;
  state:=payload->>'decision';
  if state not in ('approved','rejected') or state is null then raise exception 'Choose approve or reject.' using errcode='22023'; end if;
  if state='rejected' and length(btrim(coalesce(payload->>'reason','')))=0 then raise exception 'Add a reason for rejecting this request.' using errcode='22023'; end if;
  if state='approved' then
   -- Lock the parent status while granting membership to avoid archive/approval races.
   perform 1 from public.pfd_clubs where id=req.club_id and status='active' for share;
   if not found then raise exception 'Restore the club before approving access.' using errcode='22023'; end if;
   if not exists(select 1 from public.pfd_clubs c where c.id=req.club_id and length(btrim(c.city))>0 and length(btrim(c.state))>0 and length(btrim(c.country))>0 and length(btrim(c.contact_email))>0 and length(btrim(c.contact_number))>0 and length(btrim(c.league))>0 and length(btrim(c.sport))>0) then raise exception 'Complete the club details before approving access.' using errcode='22023'; end if;
   if req.role_key='club_admin' then
    insert into public.pfd_club_admins(club_id,user_id,granted_by) values(req.club_id,req.user_id,actor) on conflict do nothing;
   else
    perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id and status='active' for share;
    if not found then raise exception 'Restore the team before approving access.' using errcode='22023'; end if;
    insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(req.team_id,req.user_id,req.role_key,actor) on conflict do nothing;
   end if;
  end if;
  update public.pfd_access_requests set status=state,reason=coalesce(payload->>'reason',''),reviewed_by=actor,reviewed_at=now() where id=req.id;
  return jsonb_build_object('ok',true);
 elsif action='reports_list' then
  with filtered as (
   select r.id,r.subject_id,r.club_id,r.team_id,r.template_key,r.report_date,r.status,r.created_at,r.updated_at,p.name as subject_name,p.email as subject_email,c.name as club_name,t.name as team_name,a.name as author_name
   from public.pfd_reports r join public.pfd_profiles p on p.id=r.subject_id left join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles a on a.id=r.created_by
   where (q='' or strpos(lower(p.name||' '||p.email||' '||coalesce(c.name,'')),lower(q))>0)
    and (coalesce(payload->>'template_key','')='' or r.template_key=payload->>'template_key')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
    and (coalesce(payload->>'team_id','')='' or r.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or r.report_date>=(payload->>'from_date')::date)
    and (coalesce(payload->>'to_date','')='' or r.report_date<=(payload->>'to_date')::date)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by report_date desc,created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'submitted',(select count(*) from public.pfd_reports where status='submitted'),'page',page_no) into result;
  return result;
 elsif action='report_get' then
  select to_jsonb(r) into result from public.pfd_reports r where id=(payload->>'id')::uuid;
  if result is null then raise exception 'Report not found.' using errcode='P0002'; end if;
  return result;
 elsif action='report_save' then
  record_id:=(payload->>'id')::uuid;subject:=(payload->>'subject_id')::uuid;
  club:=nullif(payload->>'club_id','')::uuid;team:=nullif(payload->>'team_id','')::uuid;
  template:=payload->>'template_key';state:=payload->>'status';report_data:=payload->'data';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,42));
  select * into old_report from public.pfd_reports where id=record_id for update;
  if found and (old_report.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'This report changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if old_report.id is not null and old_report.status<>'draft' then raise exception 'Submitted reports are read-only. Create a new report for the next assessment.' using errcode='22023'; end if;
  select t.definition into definition from public.pfd_report_templates t where t.key=template;
  if definition is null or state not in ('draft','submitted') or state is null or jsonb_typeof(report_data) is distinct from 'object' then raise exception 'Invalid report template or status.' using errcode='22023'; end if;
  if not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Choose an existing account for this report.' using errcode='22023'; end if;
  if club is not null and not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an active club.' using errcode='22023'; end if;
  if team is not null and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active') then raise exception 'Choose a team in this club.' using errcode='22023'; end if;
  info:=report_data->'info';
  if jsonb_typeof(info) is distinct from 'object' or jsonb_typeof(report_data->'ratings') is distinct from 'object' or jsonb_typeof(report_data->'notes') is distinct from 'array' or jsonb_array_length(report_data->'notes')<>4 then raise exception 'Report sections are missing.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(info) loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid report detail.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'ratings') loop
   if jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (1,2,3,4,5) or not exists(
    select 1 from jsonb_each(definition->'categories') c cross join lateral jsonb_array_elements(c.value) with ordinality question where c.key||'-'||(question.ordinality-1)::text=entry.key
   ) then raise exception 'Ratings must match the original questions and use 1–5.' using errcode='22023'; end if;
  end loop;
  for item in select value from jsonb_array_elements(report_data->'notes') loop
   if jsonb_typeof(item)<>'string' or length(item#>>'{}')>6000 then raise exception 'Report notes must be text of at most 6000 characters.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(report_data->'extra') is distinct from 'object' or jsonb_typeof(report_data->'values') is distinct from 'object' or jsonb_typeof(report_data->'progress') is distinct from 'object' then raise exception 'Invalid report detail sections.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(report_data->'extra') loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid fitness test value.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'progress') loop
   if entry.key !~ '^[0-2]-[0-2]-[0-2]$' or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (0,1,2,3) then raise exception 'Invalid exercise progress marker.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'values') loop
   if jsonb_typeof(entry.value)<>'boolean' or not exists(select 1 from jsonb_each(definition->'behaviours') b cross join lateral jsonb_array_elements_text(b.value) v where v.value=entry.key) then raise exception 'Invalid player behaviour value.' using errcode='22023'; end if;
  end loop;
  if length(coalesce(report_data->>'prepared_by',''))>250 or length(coalesce(report_data->>'reviewer',''))>250 then raise exception 'Report author details are too long.' using errcode='22023'; end if;
  if state='submitted' and (length(btrim(coalesce(info->>'name','')))=0 or length(btrim(coalesce(report_data->>'prepared_by','')))=0 or report_data->'consent' is distinct from 'true'::jsonb) then raise exception 'Complete the name, prepared-by field and submission consent.' using errcode='22023'; end if;
  insert into public.pfd_reports(id,subject_id,club_id,team_id,template_key,template_snapshot,report_date,status,data,created_by)
   values(record_id,subject,club,team,template,definition,(payload->>'report_date')::date,state,report_data,actor)
   on conflict(id) do update set subject_id=excluded.subject_id,club_id=excluded.club_id,team_id=excluded.team_id,template_key=excluded.template_key,template_snapshot=excluded.template_snapshot,report_date=excluded.report_date,status=excluded.status,data=excluded.data,updated_at=clock_timestamp()
   returning to_jsonb(pfd_reports) into result;
  return result;
 elsif action='resources_list' then
  with filtered as (
   select r.*,(select coalesce(jsonb_agg(c.club_id),'[]') from public.pfd_resource_clubs c where c.resource_id=r.id) as club_ids from public.pfd_resources r
   where (q='' or strpos(lower(r.title||' '||r.category||' '||r.instructions),lower(q))>0)
    and (coalesce(payload->>'kind','')='' or r.kind=payload->>'kind')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'difficulty','')='' or r.difficulty=payload->>'difficulty')
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by updated_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'published',(select count(*) from public.pfd_resources where status='published'),'page',page_no) into result;
  return result;
 elsif action='resource_save' then
  record_id:=(payload->>'id')::uuid;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,43));
  select * into old_resource from public.pfd_resources where id=record_id for update;
  if found and old_resource.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This resource changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if coalesce(payload->>'video_url','')<>'' and payload->>'video_url' !~ '^https?://[^[:space:]]+$' then raise exception 'Use a valid http or https video link.' using errcode='22023'; end if;
  if jsonb_typeof(payload->'attachments') is distinct from 'array' or jsonb_array_length(payload->'attachments')>5 then raise exception 'A resource can have up to five files.' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(payload->'attachments') loop
   if jsonb_typeof(item) is distinct from 'object' or length(coalesce(item->>'name','')) not between 1 and 250 or length(coalesce(item->>'path','')) not between 1 and 350
    or not exists(select 1 from storage.objects o where o.bucket_id='pfd-development-resources' and o.name=item->>'path') then raise exception 'An attached file is missing. Upload it again.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(payload->'club_ids') is distinct from 'array' then raise exception 'Invalid club selection.' using errcode='22023'; end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into selected_clubs from jsonb_array_elements_text(payload->'club_ids');
  if payload->>'audience'='selected_clubs' and (cardinality(selected_clubs)=0 or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_clubs c where c.id=id and c.status='active'))) then raise exception 'Select at least one active club.' using errcode='22023'; end if;
  if payload->>'status'='published' and length(btrim(coalesce(payload->>'instructions','')))=0 then raise exception 'Add instructions before publishing.' using errcode='22023'; end if;
  insert into public.pfd_resources(id,title,kind,category,difficulty,instructions,video_url,attachments,audience,status,created_by)
   values(record_id,btrim(payload->>'title'),payload->>'kind',btrim(coalesce(payload->>'category','')),payload->>'difficulty',coalesce(payload->>'instructions',''),coalesce(payload->>'video_url',''),payload->'attachments',payload->>'audience',payload->>'status',actor)
   on conflict(id) do update set title=excluded.title,kind=excluded.kind,category=excluded.category,difficulty=excluded.difficulty,instructions=excluded.instructions,video_url=excluded.video_url,attachments=excluded.attachments,audience=excluded.audience,status=excluded.status,updated_at=clock_timestamp()
   returning to_jsonb(pfd_resources) into result;
  delete from public.pfd_resource_clubs where resource_id=record_id;
  if payload->>'audience'='selected_clubs' then insert into public.pfd_resource_clubs(resource_id,club_id) select record_id,id from (select distinct unnest(selected_clubs) id)x; end if;
  return result;
 elsif action='stats' then
  return jsonb_build_object('coaches',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='coach' and t.status='active' and c.status='active'),
   'players',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='player' and t.status='active' and c.status='active'),
   'reports',(select count(*) from public.pfd_reports where status='submitted'),'requests',(select count(*) from public.pfd_access_requests where status='pending'));
 end if;
 raise exception 'Unknown workspace action.' using errcode='22023';
end $$;
revoke all on function public.pfd_owner_workspace(text,jsonb) from public,anon;
grant execute on function public.pfd_owner_workspace(text,jsonb) to authenticated;
update public.pfd_permission_catalog set available=true where key in ('requests.review_all','reports.view_all','library.manage_platform');

-- Row locks used during approval require a narrow UPDATE grant. RLS keeps it owner-only.
grant update(status) on public.pfd_clubs,public.pfd_teams to authenticated;
create policy pfd_clubs_owner_status_update on public.pfd_clubs for update to authenticated
using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())))
with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));
create policy pfd_teams_owner_status_update on public.pfd_teams for update to authenticated
using(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())))
with check(exists(select 1 from public.pfd_platform_owners o where o.user_id=(select auth.uid())));


-- SOURCE: supabase/library-plans-and-match-reports.sql
alter table public.pfd_resources drop constraint pfd_resources_kind_check;
update public.pfd_resources set kind='individual_drill' where kind in ('drill','homework');
alter table public.pfd_resources add constraint pfd_resources_kind_check check(kind in ('individual_drill','team_drill','training_plan','report_template'));
alter table public.pfd_resources add column duration_minutes numeric(6,1) check(duration_minutes>0 and duration_minutes<=240);
alter table public.pfd_resources add column plan_blocks jsonb not null default '[]'::jsonb check(jsonb_typeof(plan_blocks)='array' and jsonb_array_length(plan_blocks)<=100);
alter table public.pfd_reports alter column subject_id drop not null;
insert into public.pfd_report_templates(key,label,definition,source_commit) values('performance','Player Performance','{"title": "Player Performance Report", "short": "Player Performance", "intro": "Review the performance. Guide the next step.", "desc": "Record match contributions, playing time and development observations. Ratings use the same 1\u20135 scale across assessments.", "categories": {"Performance": ["Overall player performance"]}, "notes": ["Performance strengths", "Development priorities", "Injury details & follow-up", "Next-match focus"], "fields": [{"key": "name", "label": "Player name", "type": "text"}, {"key": "date", "label": "Date", "type": "date"}, {"key": "opposition", "label": "Opposition name", "type": "text"}, {"key": "position", "label": "Position", "type": "text"}, {"key": "number", "label": "Shirt number", "type": "number", "min": 0, "max": 999, "step": 1}, {"key": "minutes_played", "label": "Minutes played", "type": "number", "unit": "min", "min": 0, "max": 240, "step": 0.1}, {"key": "goals", "label": "Goals", "type": "number", "min": 0, "max": 100, "step": 1}, {"key": "assists", "label": "Assists", "type": "number", "min": 0, "max": 100, "step": 1}, {"key": "yellow_cards", "label": "Yellow cards", "type": "number", "min": 0, "max": 2, "step": 1}, {"key": "red_cards", "label": "Red cards", "type": "number", "min": 0, "max": 1, "step": 1}, {"key": "injury", "label": "Injury / discomfort", "type": "text"}, {"key": "shots", "label": "Shots", "type": "number", "min": 0, "max": 100, "step": 1}, {"key": "shots_on_target", "label": "Shots on target", "type": "number", "min": 0, "max": 100, "step": 1}, {"key": "key_passes", "label": "Key passes", "type": "number", "min": 0, "max": 200, "step": 1}, {"key": "tackles", "label": "Tackles", "type": "number", "min": 0, "max": 200, "step": 1}, {"key": "interceptions", "label": "Interceptions", "type": "number", "min": 0, "max": 200, "step": 1}, {"key": "saves", "label": "Saves", "type": "number", "min": 0, "max": 100, "step": 1}], "behaviours": {}, "exercises": []}'::jsonb,'pfd-owner-dashboard-2026-11-13');
insert into public.pfd_report_templates(key,label,definition,source_commit) values('match_review','Match Review','{"title": "Match Review Report", "short": "Match Review", "intro": "Reflect as a team. Improve together.", "desc": "Record the match context, outcome and team standards. Individual ratings are linked to player accounts in the selected team.", "team_report": true, "categories": {"Team standards": ["Team teamwork", "Team fairplay", "Team discipline", "Team culture"]}, "notes": ["Match issues & incidents", "What worked well?", "What needs improvement?", "Notes & next-session actions"], "fields": [{"key": "name", "label": "Team name", "type": "text"}, {"key": "date", "label": "Date", "type": "date"}, {"key": "opposition", "label": "Opposition", "type": "text"}, {"key": "location", "label": "Location", "type": "text"}, {"key": "weather", "label": "Weather / pitch conditions", "type": "text"}, {"key": "score_for", "label": "Our score", "type": "number", "min": 0, "max": 100, "step": 1}, {"key": "score_against", "label": "Opposition score", "type": "number", "min": 0, "max": 100, "step": 1}, {"key": "goals", "label": "Goals / scorers", "type": "text"}, {"key": "assists", "label": "Assists / providers", "type": "text"}, {"key": "formation", "label": "Formation", "type": "text"}, {"key": "match_type", "label": "Competition / match type", "type": "text"}], "behaviours": {}, "exercises": []}'::jsonb,'pfd-owner-dashboard-2026-11-13');
insert into public.pfd_report_templates(key,label,definition,source_commit) values('gps','GPS Data','{"title": "GPS Data Report", "short": "GPS Data", "intro": "Understand the load. Support development.", "desc": "Record measured GPS values with explicit units. Leave unavailable measurements blank; an empty field is not zero.", "categories": {}, "notes": ["GPS data / additional measurements", "Session context & conditions", "Load observations", "Follow-up actions"], "fields": [{"key": "name", "label": "Player name", "type": "text"}, {"key": "date", "label": "Date", "type": "date"}, {"key": "opposition", "label": "Opposition name", "type": "text"}, {"key": "minutes_played", "label": "Minutes played", "type": "number", "unit": "min", "min": 0, "max": 240, "step": 0.1}, {"key": "total_distance_m", "label": "Total distance", "type": "number", "unit": "m", "min": 0, "max": 100000, "step": 0.1}, {"key": "high_speed_distance_m", "label": "High-speed running distance", "type": "number", "unit": "m", "min": 0, "max": 100000, "step": 0.1}, {"key": "sprint_distance_m", "label": "Sprint distance", "type": "number", "unit": "m", "min": 0, "max": 100000, "step": 0.1}, {"key": "top_speed_kmh", "label": "Top speed", "type": "number", "unit": "km/h", "min": 0, "max": 60, "step": 0.1}, {"key": "average_speed_kmh", "label": "Average speed", "type": "number", "unit": "km/h", "min": 0, "max": 60, "step": 0.1}, {"key": "sprint_count", "label": "Sprint count", "type": "number", "min": 0, "max": 1000, "step": 1}, {"key": "accelerations", "label": "Accelerations", "type": "number", "min": 0, "max": 10000, "step": 1}, {"key": "decelerations", "label": "Decelerations", "type": "number", "min": 0, "max": 10000, "step": 1}, {"key": "player_load", "label": "Player load", "type": "number", "unit": "AU", "min": 0, "max": 10000, "step": 0.1}, {"key": "rpe", "label": "Player-reported effort", "type": "number", "unit": "0\u201310", "min": 0, "max": 10, "step": 0.1}, {"key": "device", "label": "Device / source", "type": "text"}, {"key": "speed_threshold", "label": "High-speed / sprint threshold definition", "type": "text"}], "behaviours": {}, "exercises": []}'::jsonb,'pfd-owner-dashboard-2026-11-13');

create or replace function public.pfd_owner_workspace(action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 actor uuid:=auth.uid(); q text:=left(coalesce(payload->>'query',''),160);
 page_no integer:=coalesce((payload->>'page')::integer,1); page_size integer:=20;
 offset_no integer; result jsonb; item jsonb; definition jsonb; entry record;
 req public.pfd_access_requests; old_report public.pfd_reports; old_resource public.pfd_resources;
 record_id uuid; subject uuid; club uuid; team uuid; role_name text; state text; template text;
 info jsonb; report_data jsonb; field_config jsonb; block jsonb; drill public.pfd_resources; plan_minutes numeric; normalized_blocks jsonb:='[]'::jsonb; is_team boolean; revision_time timestamptz; selected_clubs uuid[];
begin
 if not exists(select 1 from public.pfd_platform_owners o where o.user_id=actor) then
  raise exception 'PFD Owner access is required.' using errcode='42501';
 end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>150000 or page_no not between 1 and 100000 then
  raise exception 'Invalid request.' using errcode='22023';
 end if;
 offset_no:=(page_no-1)*page_size;
 if action='options' then
  return jsonb_build_object(
   'clubs',(select coalesce(jsonb_agg(to_jsonb(c) order by c.name),'[]') from (select id,name,status from public.pfd_clubs order by name limit 1000)c),
   'teams',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name),'[]') from (select id,club_id,name,age_group,season,status from public.pfd_teams order by name limit 2000)t),
   'templates',(select jsonb_agg(to_jsonb(t) order by t.key) from public.pfd_report_templates t)
  );
 elsif action='team_roster' then
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (
   select p.id,p.name,p.email from public.pfd_team_memberships m join public.pfd_profiles p on p.id=m.user_id join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id
   where m.team_id=(payload->>'team_id')::uuid and m.role_key='player' and t.status='active' and c.status='active'
  )x);
 elsif action='drill_catalog' then
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.title),'[]') from (select id,title,kind,duration_minutes,status,category from public.pfd_resources where kind in ('individual_drill','team_drill') and status<>'archived' order by title limit 1000)x);
 elsif action='users_list' then
  with accounts as (
   select p.*,
    array_remove(array[
     case when exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) then 'owner' end,
     case when exists(select 1 from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id and c.status='active' where a.user_id=p.id) then 'club_admin' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='coach') then 'coach' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='player') then 'player' end
    ],null) as roles,
    (select count(*) from public.pfd_reports r where (r.subject_id=p.id or coalesce(r.data->'team_ratings','{}'::jsonb) ? p.id::text) and r.status='submitted') as report_count
   from public.pfd_profiles p
   where (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0)
    and (coalesce(payload->>'club_id','')='' or exists(select 1 from public.pfd_club_admins a where a.user_id=p.id and a.club_id=(payload->>'club_id')::uuid)
      or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=p.id and t.club_id=(payload->>'club_id')::uuid))
  ), filtered as(select * from accounts where coalesce(payload->>'role','')='' or (payload->>'role'='member' and cardinality(roles)=0) or payload->>'role'=any(roles))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),
   'total',(select count(*) from filtered),'total_accounts',(select count(*) from public.pfd_profiles),'page',page_no) into result;
  return result;
 elsif action='user_detail' then
  subject:=(payload->>'id')::uuid;
  if not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Account not found.' using errcode='P0002'; end if;
  return jsonb_build_object('profile',(select to_jsonb(p) from public.pfd_profiles p where p.id=subject),
   'is_owner',exists(select 1 from public.pfd_platform_owners o where o.user_id=subject),
   'memberships',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from (
    select a.club_id,c.name as club_name,null::uuid as team_id,null::text as team_name,'club_admin'::text as role_key,c.status,a.created_at from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id where a.user_id=subject
    union all select t.club_id,c.name,m.team_id,t.name,m.role_key,case when c.status='archived' then 'archived' else t.status end,m.created_at from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.user_id=subject
   )m),
   'report_count',(select count(*) from public.pfd_reports where (subject_id=subject or coalesce(data->'team_ratings','{}'::jsonb) ? subject::text) and status='submitted'),
   'created_reports',(select count(*) from public.pfd_reports where created_by=subject and status='submitted'),
   'pending_requests',(select count(*) from public.pfd_access_requests where user_id=subject and status='pending'),
   'recent_reports',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (select id,template_key,report_date,status from public.pfd_reports where (subject_id=subject or coalesce(data->'team_ratings','{}'::jsonb) ? subject::text) order by report_date desc,created_at desc limit 10)r)
  );
 elsif action='requests_list' then
  with filtered as (
   select r.*,p.name,p.email,c.name as club_name,t.name as team_name,reviewer.name as reviewer_name from public.pfd_access_requests r
   join public.pfd_profiles p on p.id=r.user_id join public.pfd_clubs c on c.id=r.club_id
   left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles reviewer on reviewer.id=r.reviewed_by
   where (coalesce(payload->>'status','')='' or r.status=payload->>'status')
   and (coalesce(payload->>'role','')='' or r.role_key=payload->>'role')
   and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
   and (q='' or strpos(lower(p.name||' '||p.email||' '||c.name),lower(q))>0)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'pending',(select count(*) from public.pfd_access_requests where status='pending'),'page',page_no) into result;
  return result;
 elsif action='request_create' then
  subject:=(payload->>'user_id')::uuid;club:=(payload->>'club_id')::uuid;team:=nullif(payload->>'team_id','')::uuid;role_name:=payload->>'role_key';
  if not exists(select 1 from public.pfd_profiles where id=subject) or not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an existing account and active club.' using errcode='22023'; end if;
  if role_name not in ('club_admin','coach','player') or role_name is null or (role_name='club_admin' and team is not null) or (role_name<>'club_admin' and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active')) then raise exception 'Choose a valid role and team for this club.' using errcode='22023'; end if;
  if exists(select 1 from public.pfd_club_admins where user_id=subject and club_id=club and role_name='club_admin') or exists(select 1 from public.pfd_team_memberships where user_id=subject and team_id=team and role_key=role_name) then raise exception 'This account already has the requested membership.' using errcode='22023'; end if;
  insert into public.pfd_access_requests(user_id,club_id,team_id,role_key,message,created_by) values(subject,club,team,role_name,coalesce(payload->>'message',''),actor) returning id into record_id;
  return jsonb_build_object('id',record_id);
 elsif action='request_review' then
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Request not found.' using errcode='P0002'; end if;
  if req.status<>'pending' then raise exception 'This request has already been reviewed. Refresh the list.' using errcode='40001'; end if;
  state:=payload->>'decision';
  if state not in ('approved','rejected') or state is null then raise exception 'Choose approve or reject.' using errcode='22023'; end if;
  if state='rejected' and length(btrim(coalesce(payload->>'reason','')))=0 then raise exception 'Add a reason for rejecting this request.' using errcode='22023'; end if;
  if state='approved' then
   -- Lock the parent status while granting membership to avoid archive/approval races.
   perform 1 from public.pfd_clubs where id=req.club_id and status='active' for share;
   if not found then raise exception 'Restore the club before approving access.' using errcode='22023'; end if;
   if not exists(select 1 from public.pfd_clubs c where c.id=req.club_id and length(btrim(c.city))>0 and length(btrim(c.state))>0 and length(btrim(c.country))>0 and length(btrim(c.contact_email))>0 and length(btrim(c.contact_number))>0 and length(btrim(c.league))>0 and length(btrim(c.sport))>0) then raise exception 'Complete the club details before approving access.' using errcode='22023'; end if;
   if req.role_key='club_admin' then
    insert into public.pfd_club_admins(club_id,user_id,granted_by) values(req.club_id,req.user_id,actor) on conflict do nothing;
   else
    perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id and status='active' for share;
    if not found then raise exception 'Restore the team before approving access.' using errcode='22023'; end if;
    insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(req.team_id,req.user_id,req.role_key,actor) on conflict do nothing;
   end if;
  end if;
  update public.pfd_access_requests set status=state,reason=coalesce(payload->>'reason',''),reviewed_by=actor,reviewed_at=now() where id=req.id;
  return jsonb_build_object('ok',true);
 elsif action='reports_list' then
  with filtered as (
   select r.id,r.subject_id,r.club_id,r.team_id,r.template_key,r.report_date,r.status,r.created_at,r.updated_at,coalesce(p.name,t.name,'Team match review') as subject_name,coalesce(p.email,'') as subject_email,c.name as club_name,t.name as team_name,a.name as author_name
   from public.pfd_reports r left join public.pfd_profiles p on p.id=r.subject_id left join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles a on a.id=r.created_by
   where (q='' or strpos(lower(coalesce(p.name,'')||' '||coalesce(p.email,'')||' '||coalesce(t.name,'')||' '||coalesce(c.name,'')),lower(q))>0)
    and (coalesce(payload->>'template_key','')='' or r.template_key=payload->>'template_key')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
    and (coalesce(payload->>'team_id','')='' or r.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or r.report_date>=(payload->>'from_date')::date)
    and (coalesce(payload->>'to_date','')='' or r.report_date<=(payload->>'to_date')::date)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by report_date desc,created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'submitted',(select count(*) from public.pfd_reports where status='submitted'),'page',page_no) into result;
  return result;
 elsif action='report_get' then
  select to_jsonb(r) into result from public.pfd_reports r where id=(payload->>'id')::uuid;
  if result is null then raise exception 'Report not found.' using errcode='P0002'; end if;
  return result;
 elsif action='report_save' then
  record_id:=(payload->>'id')::uuid;subject:=nullif(payload->>'subject_id','')::uuid;
  club:=nullif(payload->>'club_id','')::uuid;team:=nullif(payload->>'team_id','')::uuid;
  template:=payload->>'template_key';state:=payload->>'status';report_data:=payload->'data';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,42));
  select * into old_report from public.pfd_reports where id=record_id for update;
  if found and (old_report.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'This report changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if old_report.id is not null and old_report.status<>'draft' then raise exception 'Submitted reports are read-only. Create a new report for the next assessment.' using errcode='22023'; end if;
  select t.definition into definition from public.pfd_report_templates t where t.key=template;
  if definition is null or state not in ('draft','submitted') or state is null or jsonb_typeof(report_data) is distinct from 'object' then raise exception 'Invalid report template or status.' using errcode='22023'; end if;
  is_team:=coalesce((definition->>'team_report')::boolean,false);
  if is_team then
   subject:=null;
   if state='submitted' and team is null then raise exception 'Select a team before submitting a match review.' using errcode='22023'; end if;
  elsif not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Choose an existing account for this report.' using errcode='22023'; end if;
  if club is not null and not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an active club.' using errcode='22023'; end if;
  if team is not null and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active') then raise exception 'Choose a team in this club.' using errcode='22023'; end if;
  info:=report_data->'info';
  if jsonb_typeof(info) is distinct from 'object' or jsonb_typeof(report_data->'ratings') is distinct from 'object' or jsonb_typeof(report_data->'notes') is distinct from 'array' or jsonb_array_length(report_data->'notes')<>4 then raise exception 'Report sections are missing.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(info) loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid report detail.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'ratings') loop
   if jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (1,2,3,4,5) or not exists(
    select 1 from jsonb_each(definition->'categories') c cross join lateral jsonb_array_elements(c.value) with ordinality question where c.key||'-'||(question.ordinality-1)::text=entry.key
   ) then raise exception 'Ratings must match the original questions and use 1–5.' using errcode='22023'; end if;
  end loop;
  for item in select value from jsonb_array_elements(report_data->'notes') loop
   if jsonb_typeof(item)<>'string' or length(item#>>'{}')>6000 then raise exception 'Report notes must be text of at most 6000 characters.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(report_data->'extra') is distinct from 'object' or jsonb_typeof(report_data->'values') is distinct from 'object' or jsonb_typeof(report_data->'progress') is distinct from 'object' then raise exception 'Invalid report detail sections.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(report_data->'extra') loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid fitness test value.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'progress') loop
   if entry.key !~ '^[0-2]-[0-2]-[0-2]$' or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (0,1,2,3) then raise exception 'Invalid exercise progress marker.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'values') loop
   if jsonb_typeof(entry.value)<>'boolean' or not exists(select 1 from jsonb_each(definition->'behaviours') b cross join lateral jsonb_array_elements_text(b.value) v where v.value=entry.key) then raise exception 'Invalid player behaviour value.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(coalesce(report_data->'metrics','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(report_data->'team_ratings','{}'::jsonb))<>'object' then raise exception 'Invalid structured report data.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'metrics','{}'::jsonb)) loop
   select value into field_config from jsonb_array_elements(coalesce(definition->'fields','[]')) where value->>'key'=entry.key and value->>'type'='number';
   if field_config is null or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric < (field_config->>'min')::numeric or (entry.value#>>'{}')::numeric > (field_config->>'max')::numeric then raise exception 'A numeric report field is outside its allowed range.' using errcode='22023'; end if;
   if (field_config->>'step')::numeric=1 and mod((entry.value#>>'{}')::numeric,1)<>0 then raise exception 'Counts must be whole numbers.' using errcode='22023'; end if;
  end loop;
  if report_data->'metrics' ? 'shots' and report_data->'metrics' ? 'shots_on_target' and (report_data->'metrics'->>'shots_on_target')::numeric>(report_data->'metrics'->>'shots')::numeric then raise exception 'Shots on target cannot exceed shots.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'total_distance_m' and report_data->'metrics' ? 'high_speed_distance_m' and (report_data->'metrics'->>'high_speed_distance_m')::numeric>(report_data->'metrics'->>'total_distance_m')::numeric then raise exception 'High-speed distance cannot exceed total distance.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'top_speed_kmh' and report_data->'metrics' ? 'average_speed_kmh' and (report_data->'metrics'->>'average_speed_kmh')::numeric>(report_data->'metrics'->>'top_speed_kmh')::numeric then raise exception 'Average speed cannot exceed top speed.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'team_ratings','{}'::jsonb)) loop
   if not is_team or jsonb_typeof(entry.value->'rating') is distinct from 'number' or (entry.value->>'rating')::numeric not in (1,2,3,4,5) or not exists(select 1 from public.pfd_team_memberships m where m.team_id=team and m.user_id=entry.key::uuid and m.role_key='player') then raise exception 'Player ratings must be 1–5 and belong to this team roster.' using errcode='22023'; end if;
   report_data:=jsonb_set(report_data,array['team_ratings',entry.key,'name'],to_jsonb((select name from public.pfd_profiles where id=entry.key::uuid)));
  end loop;
  if length(coalesce(report_data->>'prepared_by',''))>250 or length(coalesce(report_data->>'reviewer',''))>250 then raise exception 'Report author details are too long.' using errcode='22023'; end if;
  if state='submitted' and (length(btrim(coalesce(info->>'name','')))=0 or length(btrim(coalesce(report_data->>'prepared_by','')))=0 or report_data->'consent' is distinct from 'true'::jsonb) then raise exception 'Complete the name, prepared-by field and submission consent.' using errcode='22023'; end if;
  insert into public.pfd_reports(id,subject_id,club_id,team_id,template_key,template_snapshot,report_date,status,data,created_by)
   values(record_id,subject,club,team,template,definition,(payload->>'report_date')::date,state,report_data,actor)
   on conflict(id) do update set subject_id=excluded.subject_id,club_id=excluded.club_id,team_id=excluded.team_id,template_key=excluded.template_key,template_snapshot=excluded.template_snapshot,report_date=excluded.report_date,status=excluded.status,data=excluded.data,updated_at=clock_timestamp()
   returning to_jsonb(pfd_reports) into result;
  return result;
 elsif action='resources_list' then
  with filtered as (
   select r.*,(select coalesce(jsonb_agg(c.club_id),'[]') from public.pfd_resource_clubs c where c.resource_id=r.id) as club_ids from public.pfd_resources r
   where (q='' or strpos(lower(r.title||' '||r.category||' '||r.instructions),lower(q))>0)
    and (coalesce(payload->>'kind','')='' or r.kind=payload->>'kind')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'difficulty','')='' or r.difficulty=payload->>'difficulty')
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by updated_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'published',(select count(*) from public.pfd_resources where status='published'),'page',page_no) into result;
  return result;
 elsif action='resource_save' then
  record_id:=(payload->>'id')::uuid;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,43));
  select * into old_resource from public.pfd_resources where id=record_id for update;
  if found and old_resource.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This resource changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if coalesce(payload->>'video_url','')<>'' and payload->>'video_url' !~ '^https?://[^[:space:]]+$' then raise exception 'Use a valid http or https video link.' using errcode='22023'; end if;
  if jsonb_typeof(payload->'attachments') is distinct from 'array' or jsonb_array_length(payload->'attachments')>5 then raise exception 'A resource can have up to five files.' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(payload->'attachments') loop
   if jsonb_typeof(item) is distinct from 'object' or length(coalesce(item->>'name','')) not between 1 and 250 or length(coalesce(item->>'path','')) not between 1 and 350
    or not exists(select 1 from storage.objects o where o.bucket_id='pfd-development-resources' and o.name=item->>'path') then raise exception 'An attached file is missing. Upload it again.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(payload->'club_ids') is distinct from 'array' then raise exception 'Invalid club selection.' using errcode='22023'; end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into selected_clubs from jsonb_array_elements_text(payload->'club_ids');
  if payload->>'audience'='selected_clubs' and (cardinality(selected_clubs)=0 or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_clubs c where c.id=id and c.status='active'))) then raise exception 'Select at least one active club.' using errcode='22023'; end if;
  if payload->>'status'='published' and length(btrim(coalesce(payload->>'instructions','')))=0 then raise exception 'Add instructions before publishing.' using errcode='22023'; end if;
  plan_minutes:=0;
  if payload->>'kind' in ('individual_drill','team_drill') and (nullif(payload->>'duration_minutes','') is null or (payload->>'duration_minutes')::numeric not between 0.1 and 240) then raise exception 'Add an estimated drill duration between 0.1 and 240 minutes.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(payload->'plan_blocks','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(payload->'plan_blocks','[]'::jsonb))>100 then raise exception 'A plan can contain up to 100 drills.' using errcode='22023'; end if;
  if payload->>'kind'='training_plan' then
   if payload->>'status'='published' and coalesce(jsonb_array_length(payload->'plan_blocks'),0)=0 then raise exception 'Add at least one drill before publishing a training plan.' using errcode='22023'; end if;
   for block in select value from jsonb_array_elements(coalesce(payload->'plan_blocks','[]'::jsonb)) loop
    select * into drill from public.pfd_resources where id=(block->>'resource_id')::uuid and kind in ('individual_drill','team_drill');
    if not found or (payload->>'status'='published' and drill.status<>'published') then raise exception 'Use available drills; published plans require published drills.' using errcode='22023'; end if;
    if jsonb_typeof(block->'minutes') is distinct from 'number' or (block->>'minutes')::numeric not between 0.1 and 240 then raise exception 'Set a valid duration for each plan drill.' using errcode='22023'; end if;
    if payload->>'status'='published' and drill.audience='selected_clubs' and (payload->>'audience'='all_clubs' or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=drill.id and rc.club_id=id))) then raise exception 'A plan cannot be shared more widely than its included drills.' using errcode='22023'; end if;
    normalized_blocks:=normalized_blocks||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'resource_id',drill.id,'title',drill.title,'kind',drill.kind,'minutes',(block->>'minutes')::numeric,'instructions',drill.instructions,'video_url',drill.video_url,'attachments',drill.attachments));
    plan_minutes:=plan_minutes+(block->>'minutes')::numeric;
   end loop;
  end if;
  insert into public.pfd_resources(id,title,kind,category,difficulty,instructions,video_url,attachments,audience,status,created_by,duration_minutes,plan_blocks)
   values(record_id,btrim(payload->>'title'),payload->>'kind',btrim(coalesce(payload->>'category','')),payload->>'difficulty',coalesce(payload->>'instructions',''),coalesce(payload->>'video_url',''),payload->'attachments',payload->>'audience',payload->>'status',actor,case when payload->>'kind'='training_plan' then null else nullif(payload->>'duration_minutes','')::numeric end,case when payload->>'kind'='training_plan' then normalized_blocks else '[]'::jsonb end)
   on conflict(id) do update set title=excluded.title,kind=excluded.kind,category=excluded.category,difficulty=excluded.difficulty,instructions=excluded.instructions,video_url=excluded.video_url,attachments=excluded.attachments,audience=excluded.audience,status=excluded.status,duration_minutes=excluded.duration_minutes,plan_blocks=excluded.plan_blocks,updated_at=clock_timestamp()
   returning to_jsonb(pfd_resources) into result;
  delete from public.pfd_resource_clubs where resource_id=record_id;
  if payload->>'audience'='selected_clubs' then insert into public.pfd_resource_clubs(resource_id,club_id) select record_id,id from (select distinct unnest(selected_clubs) id)x; end if;
  return result;
 elsif action='stats' then
  return jsonb_build_object('coaches',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='coach' and t.status='active' and c.status='active'),
   'players',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='player' and t.status='active' and c.status='active'),
   'reports',(select count(*) from public.pfd_reports where status='submitted'),'requests',(select count(*) from public.pfd_access_requests where status='pending'));
 end if;
 raise exception 'Unknown workspace action.' using errcode='22023';
end $$;


-- SOURCE: supabase/club-teams.sql
-- Authenticated clients keep their existing SELECT-only, owner-scoped policies.
-- Delegated mutations go through a verified-user Edge Function and service-only RPC.
alter table public.pfd_teams add column description text not null default '' check(length(description)<=2000);
alter table public.pfd_teams add column created_by uuid references auth.users(id) on delete set null;
alter table public.pfd_teams add column updated_at timestamptz not null default now();
create index pfd_teams_created_by_idx on public.pfd_teams(created_by);
alter table public.pfd_teams add constraint pfd_teams_required_details check(length(btrim(name)) between 1 and 120 and length(btrim(age_group)) between 1 and 80 and length(btrim(season)) between 1 and 40) not valid;
create unique index pfd_teams_club_name_season_unique on public.pfd_teams(club_id,lower(btrim(name)),lower(btrim(season)));
create index pfd_teams_club_status_idx on public.pfd_teams(club_id,status,created_at desc);

create function public.pfd_club_teams(actor_id uuid,target_club uuid,action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare t public.pfd_teams; record_id uuid; target_user uuid; role_name text; required_permission text;
 page_no integer:=coalesce((payload->>'page')::integer,1);offset_no integer; q text:=btrim(coalesce(payload->>'query','')); filter_status text:=coalesce(payload->>'status','active');
 result jsonb; can_manage boolean; can_members boolean; can_coaches boolean; can_players boolean; member_name text; email_query text:=lower(btrim(coalesce(payload->>'email','')));
begin
 if actor_id is null or exists(select 1 from public.pfd_platform_owners where user_id=actor_id) then raise exception 'Use your separate Club Administrator account.' using errcode='42501';end if;
 perform 1 from public.pfd_club_admins where user_id=actor_id and club_id=target_club for share;
 if not found then raise exception 'Club Administrator access is required for this club.' using errcode='42501';end if;
 perform 1 from public.pfd_clubs where id=target_club and status='active' for share;
 if not found then raise exception 'This club is not active.' using errcode='42501';end if;
 perform 1 from public.pfd_role_permissions where role_key='club_admin' for share;
 if not exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='clubs.view' and enabled) or
    not exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='teams.view' and enabled) then
  raise exception 'View clubs and View teams permissions are required.' using errcode='42501';end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>12000 or page_no not between 1 and 100000 or length(q)>160 or length(email_query)>254 then raise exception 'Invalid team request.' using errcode='22023';end if;
 offset_no:=(page_no-1)*20;
 select enabled into can_manage from public.pfd_role_permissions where role_key='club_admin' and permission_key='teams.create';
 select enabled into can_members from public.pfd_role_permissions where role_key='club_admin' and permission_key='members.view';
 select enabled into can_coaches from public.pfd_role_permissions where role_key='club_admin' and permission_key='coaches.approve';
 select enabled into can_players from public.pfd_role_permissions where role_key='club_admin' and permission_key='players.approve';
 if action='stats' then
  return jsonb_build_object('teams',(select count(*) from public.pfd_teams where club_id=target_club and status='active'),
   'coaches',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams st on st.id=m.team_id where st.club_id=target_club and st.status='active' and m.role_key='coach'),
   'players',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams st on st.id=m.team_id where st.club_id=target_club and st.status='active' and m.role_key='player'));
 elsif action='list' then
  if filter_status not in ('active','archived','all') then raise exception 'Invalid team status.' using errcode='22023';end if;
  with filtered as(select listed.*,
    (select count(*) from public.pfd_team_memberships m where m.team_id=listed.id and m.role_key='coach') as coach_count,
    (select count(*) from public.pfd_team_memberships m where m.team_id=listed.id and m.role_key='player') as player_count
   from public.pfd_teams listed where listed.club_id=target_club and (filter_status='all' or listed.status=filter_status)
    and (q='' or strpos(lower(listed.name||' '||listed.age_group||' '||listed.season),lower(q))>0)
    and (coalesce(payload->>'season','')='' or listed.season=payload->>'season'))
   select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit 20 offset offset_no)x),
    'total',(select count(*) from filtered),'page',page_no,'permissions',jsonb_build_object('manage',coalesce(can_manage,false),'members',coalesce(can_members,false),'coaches',coalesce(can_coaches,false),'players',coalesce(can_players,false)),
    'seasons',(select coalesce(jsonb_agg(s.season order by s.season desc),'[]') from (select distinct season from public.pfd_teams where club_id=target_club)s)) into result;
  return result;
 elsif action in ('create','update','set_status') then
  if not coalesce(can_manage,false) then raise exception 'Create and edit teams permission is required.' using errcode='42501';end if;
 elsif action in ('candidates','add_member','remove_member') then
  role_name:=payload->>'role_key';
  if not coalesce(can_members,false) or role_name is null or role_name not in ('coach','player') or (role_name='coach' and not coalesce(can_coaches,false)) or (role_name='player' and not coalesce(can_players,false)) then raise exception 'Member directory and approval permission for this role are required.' using errcode='42501';end if;
 elsif action='members' then
  if not coalesce(can_members,false) then raise exception 'View member directory permission is required.' using errcode='42501';end if;
 elsif action<>'get' then raise exception 'Unknown team action.' using errcode='22023';
 end if;
 if action='create' then
  record_id:=(payload->>'id')::uuid;
  insert into public.pfd_teams(id,club_id,name,age_group,season,description,created_by) values(record_id,target_club,btrim(payload->>'name'),btrim(payload->>'age_group'),btrim(payload->>'season'),btrim(coalesce(payload->>'description','')),actor_id) returning to_jsonb(pfd_teams) into result;
  return result;
 end if;
 select * into t from public.pfd_teams where id=(payload->>'team_id')::uuid and club_id=target_club for update;
 if not found then raise exception 'Team not found in this club.' using errcode='P0002';end if;
 if action='get' then
  return to_jsonb(t)||jsonb_build_object('coach_count',(select count(*) from public.pfd_team_memberships where team_id=t.id and role_key='coach'),
   'player_count',(select count(*) from public.pfd_team_memberships where team_id=t.id and role_key='player'),
   'permissions',jsonb_build_object('manage',coalesce(can_manage,false),'members',coalesce(can_members,false),'coaches',coalesce(can_coaches,false),'players',coalesce(can_players,false)));
 elsif action='members' then
  role_name:=payload->>'role_key';if role_name is null or role_name not in ('coach','player') then raise exception 'Choose coaches or players.' using errcode='22023';end if;
  with filtered as(select m.user_id,m.role_key,m.created_at,p.name,p.email from public.pfd_team_memberships m join public.pfd_profiles p on p.id=m.user_id
   where m.team_id=t.id and m.role_key=role_name and (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by name,user_id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;
  return result;
 elsif action='update' then
  if t.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This team changed elsewhere. Reopen it before saving.' using errcode='40001';end if;
  update public.pfd_teams set name=btrim(payload->>'name'),age_group=btrim(payload->>'age_group'),season=btrim(payload->>'season'),description=btrim(coalesce(payload->>'description','')),updated_at=clock_timestamp() where id=t.id returning to_jsonb(pfd_teams) into result;
  return result;
 elsif action='set_status' then
  if t.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This team changed elsewhere. Reopen it before saving.' using errcode='40001';end if;
  if payload->>'status' not in ('active','archived') or payload->>'status' is null then raise exception 'Choose archive or restore.' using errcode='22023';end if;
  update public.pfd_teams set status=payload->>'status',updated_at=clock_timestamp() where id=t.id returning to_jsonb(pfd_teams) into result;
  return result;
 end if;
 if t.status<>'active' then raise exception 'Restore this team before changing its membership.' using errcode='22023';end if;
 if action='candidates' then
  if email_query<>'' and email_query !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Enter a complete email address.' using errcode='22023';end if;
  with candidates as(select p.id,p.name,p.email from public.pfd_profiles p
   where not exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id)
    and not exists(select 1 from public.pfd_team_memberships m where m.team_id=t.id and m.user_id=p.id and m.role_key=role_name)
    and ((email_query<>'' and lower(p.email)=email_query) or (email_query='' and (
      exists(select 1 from public.pfd_club_admins a where a.user_id=p.id and a.club_id=target_club)
      or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams mt on mt.id=m.team_id where m.user_id=p.id and mt.club_id=target_club))))
    and (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from candidates order by name,id limit 20 offset offset_no)x),'total',(select count(*) from candidates),'page',page_no) into result;
  return result;
 elsif action='add_member' then
  target_user:=(payload->>'user_id')::uuid;
  if not exists(select 1 from public.pfd_profiles where id=target_user) or exists(select 1 from public.pfd_platform_owners where user_id=target_user) then raise exception 'Choose an existing club account.' using errcode='22023';end if;
  -- Accounts outside this club can be added only when their exact email was supplied.
  if not exists(select 1 from public.pfd_club_admins where user_id=target_user and club_id=target_club)
   and not exists(select 1 from public.pfd_team_memberships m join public.pfd_teams mt on mt.id=m.team_id where m.user_id=target_user and mt.club_id=target_club)
   and not exists(select 1 from public.pfd_profiles where id=target_user and email_query<>'' and lower(email)=email_query) then raise exception 'Find this account using its full email address first.' using errcode='22023';end if;
  insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(t.id,target_user,role_name,actor_id);
  update public.pfd_teams set updated_at=clock_timestamp() where id=t.id;
  return jsonb_build_object('ok',true);
 elsif action='remove_member' then
  delete from public.pfd_team_memberships where team_id=t.id and user_id=(payload->>'user_id')::uuid and role_key=role_name and created_at=(payload->>'created_at')::timestamptz;
  if not found then raise exception 'This membership has already changed. Refresh the list.' using errcode='40001';end if;
  update public.pfd_teams set updated_at=clock_timestamp() where id=t.id;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Unknown team action.' using errcode='22023';
end $$;
revoke all on function public.pfd_club_teams(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pfd_club_teams(uuid,uuid,text,jsonb) to service_role;
update public.pfd_permission_catalog set available=true where key in ('teams.view','teams.create','members.view','coaches.approve','players.approve');


-- SOURCE: supabase/club-first-membership.sql
-- Club admission is distinct from team membership and roles.
create table public.pfd_club_memberships (
 club_id uuid not null references public.pfd_clubs(id),user_id uuid not null references auth.users(id) on delete cascade,
 approved_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),primary key(club_id,user_id)
);
create index pfd_club_memberships_user_idx on public.pfd_club_memberships(user_id,club_id);
create index pfd_club_memberships_approver_idx on public.pfd_club_memberships(approved_by);
alter table public.pfd_club_memberships enable row level security;
revoke all on public.pfd_club_memberships from public,anon,authenticated;
grant select,insert on public.pfd_club_memberships to authenticated;
grant all on public.pfd_club_memberships to service_role;
create policy club_memberships_read_own_or_owner on public.pfd_club_memberships for select to authenticated
using(user_id=(select auth.uid()) or exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create policy club_memberships_owner_insert on public.pfd_club_memberships for insert to authenticated
with check(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
-- Preserve already-approved administrators and team members as club members.
insert into public.pfd_club_memberships(club_id,user_id)
select club_id,user_id from public.pfd_club_admins union select t.club_id,m.user_id from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id;
-- Assigning a club administrator is itself an explicit owner approval of club access.
create function pfd_private.admit_club_administrator() returns trigger language plpgsql security definer set search_path='' as $$ begin
 insert into public.pfd_club_memberships(club_id,user_id,approved_by) values(new.club_id,new.user_id,new.granted_by) on conflict do nothing;
 return new;
end $$;
revoke all on function pfd_private.admit_club_administrator() from public,anon,authenticated;
create trigger pfd_admit_club_admin after insert on public.pfd_club_admins for each row execute function pfd_private.admit_club_administrator();
alter table public.pfd_access_requests drop constraint pfd_access_requests_role_key_check;
alter table public.pfd_access_requests add constraint pfd_access_requests_role_key_check check(role_key in ('member','club_admin','coach','player'));
alter table public.pfd_access_requests drop constraint pfd_access_requests_check;
alter table public.pfd_access_requests add constraint pfd_access_requests_check check((role_key in ('member','club_admin') and team_id is null) or (role_key in ('coach','player') and team_id is not null));
insert into public.pfd_permission_catalog(key,category,label,description,available,owner_only,sort_order) values('members.approve','Club & people','Approve club membership','Approve admission to an assigned club; this does not assign a team or grant Owner access.',true,false,29);
insert into public.pfd_role_permissions(role_key,permission_key,enabled) values('club_admin','members.approve',true),('coach','members.approve',false),('player','members.approve',false);

create or replace function public.pfd_club_teams(actor_id uuid,target_club uuid,action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare t public.pfd_teams; record_id uuid; target_user uuid; role_name text; required_permission text;
 page_no integer:=coalesce((payload->>'page')::integer,1);offset_no integer; q text:=btrim(coalesce(payload->>'query','')); filter_status text:=coalesce(payload->>'status','active');
 result jsonb; can_manage boolean; can_members boolean; can_coaches boolean; can_players boolean; member_name text; email_query text:=lower(btrim(coalesce(payload->>'email','')));
begin
 if actor_id is null or exists(select 1 from public.pfd_platform_owners where user_id=actor_id) then raise exception 'Use your separate Club Administrator account.' using errcode='42501';end if;
 perform 1 from public.pfd_club_admins where user_id=actor_id and club_id=target_club for share;
 if not found then raise exception 'Club Administrator access is required for this club.' using errcode='42501';end if;
 perform 1 from public.pfd_clubs where id=target_club and status='active' for share;
 if not found then raise exception 'This club is not active.' using errcode='42501';end if;
 perform 1 from public.pfd_role_permissions where role_key='club_admin' for share;
 if not exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='clubs.view' and enabled) or
    not exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='teams.view' and enabled) then
  raise exception 'View clubs and View teams permissions are required.' using errcode='42501';end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>12000 or page_no not between 1 and 100000 or length(q)>160 or length(email_query)>254 then raise exception 'Invalid team request.' using errcode='22023';end if;
 offset_no:=(page_no-1)*20;
 select enabled into can_manage from public.pfd_role_permissions where role_key='club_admin' and permission_key='teams.create';
 select enabled into can_members from public.pfd_role_permissions where role_key='club_admin' and permission_key='members.view';
 select enabled into can_coaches from public.pfd_role_permissions where role_key='club_admin' and permission_key='coaches.approve';
 select enabled into can_players from public.pfd_role_permissions where role_key='club_admin' and permission_key='players.approve';
 if action='stats' then
  return jsonb_build_object('teams',(select count(*) from public.pfd_teams where club_id=target_club and status='active'),
   'coaches',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams st on st.id=m.team_id where st.club_id=target_club and st.status='active' and m.role_key='coach'),
   'players',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams st on st.id=m.team_id where st.club_id=target_club and st.status='active' and m.role_key='player'));
 elsif action='list' then
  if filter_status not in ('active','archived','all') then raise exception 'Invalid team status.' using errcode='22023';end if;
  with filtered as(select listed.*,
    (select count(*) from public.pfd_team_memberships m where m.team_id=listed.id and m.role_key='coach') as coach_count,
    (select count(*) from public.pfd_team_memberships m where m.team_id=listed.id and m.role_key='player') as player_count
   from public.pfd_teams listed where listed.club_id=target_club and (filter_status='all' or listed.status=filter_status)
    and (q='' or strpos(lower(listed.name||' '||listed.age_group||' '||listed.season),lower(q))>0)
    and (coalesce(payload->>'season','')='' or listed.season=payload->>'season'))
   select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit 20 offset offset_no)x),
    'total',(select count(*) from filtered),'page',page_no,'permissions',jsonb_build_object('manage',coalesce(can_manage,false),'members',coalesce(can_members,false),'coaches',coalesce(can_coaches,false),'players',coalesce(can_players,false)),
    'seasons',(select coalesce(jsonb_agg(s.season order by s.season desc),'[]') from (select distinct season from public.pfd_teams where club_id=target_club)s)) into result;
  return result;
 elsif action in ('create','update','set_status') then
  if not coalesce(can_manage,false) then raise exception 'Create and edit teams permission is required.' using errcode='42501';end if;
 elsif action in ('candidates','add_member','remove_member') then
  role_name:=payload->>'role_key';
  if not coalesce(can_members,false) or role_name is null or role_name not in ('coach','player') or (role_name='coach' and not coalesce(can_coaches,false)) or (role_name='player' and not coalesce(can_players,false)) then raise exception 'Member directory and approval permission for this role are required.' using errcode='42501';end if;
 elsif action='members' then
  if not coalesce(can_members,false) then raise exception 'View member directory permission is required.' using errcode='42501';end if;
 elsif action<>'get' then raise exception 'Unknown team action.' using errcode='22023';
 end if;
 if action='create' then
  record_id:=(payload->>'id')::uuid;
  insert into public.pfd_teams(id,club_id,name,age_group,season,description,created_by) values(record_id,target_club,btrim(payload->>'name'),btrim(payload->>'age_group'),btrim(payload->>'season'),btrim(coalesce(payload->>'description','')),actor_id) returning to_jsonb(pfd_teams) into result;
  return result;
 end if;
 select * into t from public.pfd_teams where id=(payload->>'team_id')::uuid and club_id=target_club for update;
 if not found then raise exception 'Team not found in this club.' using errcode='P0002';end if;
 if action='get' then
  return to_jsonb(t)||jsonb_build_object('coach_count',(select count(*) from public.pfd_team_memberships where team_id=t.id and role_key='coach'),
   'player_count',(select count(*) from public.pfd_team_memberships where team_id=t.id and role_key='player'),
   'permissions',jsonb_build_object('manage',coalesce(can_manage,false),'members',coalesce(can_members,false),'coaches',coalesce(can_coaches,false),'players',coalesce(can_players,false)));
 elsif action='members' then
  role_name:=payload->>'role_key';if role_name is null or role_name not in ('coach','player') then raise exception 'Choose coaches or players.' using errcode='22023';end if;
  with filtered as(select m.user_id,m.role_key,m.created_at,p.name,p.email from public.pfd_team_memberships m join public.pfd_profiles p on p.id=m.user_id
   where m.team_id=t.id and m.role_key=role_name and (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by name,user_id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;
  return result;
 elsif action='update' then
  if t.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This team changed elsewhere. Reopen it before saving.' using errcode='40001';end if;
  update public.pfd_teams set name=btrim(payload->>'name'),age_group=btrim(payload->>'age_group'),season=btrim(payload->>'season'),description=btrim(coalesce(payload->>'description','')),updated_at=clock_timestamp() where id=t.id returning to_jsonb(pfd_teams) into result;
  return result;
 elsif action='set_status' then
  if t.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This team changed elsewhere. Reopen it before saving.' using errcode='40001';end if;
  if payload->>'status' not in ('active','archived') or payload->>'status' is null then raise exception 'Choose archive or restore.' using errcode='22023';end if;
  update public.pfd_teams set status=payload->>'status',updated_at=clock_timestamp() where id=t.id returning to_jsonb(pfd_teams) into result;
  return result;
 end if;
 if t.status<>'active' then raise exception 'Restore this team before changing its membership.' using errcode='22023';end if;
 if action='candidates' then
  if email_query<>'' then raise exception 'Only approved club members can be selected.' using errcode='22023';end if;
  with candidates as(select p.id,p.name,p.email from public.pfd_profiles p join public.pfd_club_memberships cm on cm.user_id=p.id and cm.club_id=target_club
   where not exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id)
    and not exists(select 1 from public.pfd_team_memberships m where m.team_id=t.id and m.user_id=p.id and m.role_key=role_name)
    and (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from candidates order by name,id limit 20 offset offset_no)x),'total',(select count(*) from candidates),'page',page_no) into result;
  return result;
 elsif action='add_member' then
  target_user:=(payload->>'user_id')::uuid;
  perform 1 from public.pfd_club_memberships where user_id=target_user and club_id=target_club for share;
  if not found or exists(select 1 from public.pfd_platform_owners where user_id=target_user) then raise exception 'This account must be approved into this club before it can join a team.' using errcode='22023';end if;
  insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(t.id,target_user,role_name,actor_id);
  update public.pfd_access_requests set status='approved',reviewed_by=actor_id,reviewed_at=clock_timestamp(),reason='Assigned to the team by a club administrator.' where user_id=target_user and club_id=target_club and team_id=t.id and role_key=role_name and status='pending';
  update public.pfd_teams set updated_at=clock_timestamp() where id=t.id;
  return jsonb_build_object('ok',true);
 elsif action='remove_member' then
  delete from public.pfd_team_memberships where team_id=t.id and user_id=(payload->>'user_id')::uuid and role_key=role_name and created_at=(payload->>'created_at')::timestamptz;
  if not found then raise exception 'This membership has already changed. Refresh the list.' using errcode='40001';end if;
  update public.pfd_teams set updated_at=clock_timestamp() where id=t.id;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Unknown team action.' using errcode='22023';
end $$;

create or replace function public.pfd_owner_workspace(action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 actor uuid:=auth.uid(); q text:=left(coalesce(payload->>'query',''),160);
 page_no integer:=coalesce((payload->>'page')::integer,1); page_size integer:=20;
 offset_no integer; result jsonb; item jsonb; definition jsonb; entry record;
 req public.pfd_access_requests; old_report public.pfd_reports; old_resource public.pfd_resources;
 record_id uuid; subject uuid; club uuid; team uuid; role_name text; state text; template text;
 info jsonb; report_data jsonb; field_config jsonb; block jsonb; drill public.pfd_resources; plan_minutes numeric; normalized_blocks jsonb:='[]'::jsonb; is_team boolean; revision_time timestamptz; selected_clubs uuid[];
begin
 if not exists(select 1 from public.pfd_platform_owners o where o.user_id=actor) then
  raise exception 'PFD Owner access is required.' using errcode='42501';
 end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>150000 or page_no not between 1 and 100000 then
  raise exception 'Invalid request.' using errcode='22023';
 end if;
 offset_no:=(page_no-1)*page_size;
 if action='options' then
  return jsonb_build_object(
   'clubs',(select coalesce(jsonb_agg(to_jsonb(c) order by c.name),'[]') from (select id,name,status from public.pfd_clubs order by name limit 1000)c),
   'teams',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name),'[]') from (select id,club_id,name,age_group,season,status from public.pfd_teams order by name limit 2000)t),
   'templates',(select jsonb_agg(to_jsonb(t) order by t.key) from public.pfd_report_templates t)
  );
 elsif action='team_roster' then
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (
   select p.id,p.name,p.email from public.pfd_team_memberships m join public.pfd_profiles p on p.id=m.user_id join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id
   where m.team_id=(payload->>'team_id')::uuid and m.role_key='player' and t.status='active' and c.status='active'
  )x);
 elsif action='drill_catalog' then
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.title),'[]') from (select id,title,kind,duration_minutes,status,category from public.pfd_resources where kind in ('individual_drill','team_drill') and status<>'archived' order by title limit 1000)x);
 elsif action='users_list' then
  with accounts as (
   select p.*,
    array_remove(array[
     case when exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) then 'owner' end,
     case when exists(select 1 from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id and c.status='active' where a.user_id=p.id) then 'club_admin' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='coach') then 'coach' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='player') then 'player' end
    ],null) as roles,
    (select count(*) from public.pfd_reports r where (r.subject_id=p.id or coalesce(r.data->'team_ratings','{}'::jsonb) ? p.id::text) and r.status='submitted') as report_count
   from public.pfd_profiles p
   where (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0)
    and (coalesce(payload->>'club_id','')='' or exists(select 1 from public.pfd_club_memberships cm where cm.user_id=p.id and cm.club_id=(payload->>'club_id')::uuid) or exists(select 1 from public.pfd_club_admins a where a.user_id=p.id and a.club_id=(payload->>'club_id')::uuid)
      or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=p.id and t.club_id=(payload->>'club_id')::uuid))
  ), filtered as(select * from accounts where coalesce(payload->>'role','')='' or (payload->>'role'='member' and cardinality(roles)=0) or payload->>'role'=any(roles))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),
   'total',(select count(*) from filtered),'total_accounts',(select count(*) from public.pfd_profiles),'page',page_no) into result;
  return result;
 elsif action='user_detail' then
  subject:=(payload->>'id')::uuid;
  if not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Account not found.' using errcode='P0002'; end if;
  return jsonb_build_object('profile',(select to_jsonb(p) from public.pfd_profiles p where p.id=subject),
   'is_owner',exists(select 1 from public.pfd_platform_owners o where o.user_id=subject),
   'memberships',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from (
    select a.club_id,c.name as club_name,null::uuid as team_id,null::text as team_name,'club_admin'::text as role_key,c.status,a.created_at from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id where a.user_id=subject
    union all select t.club_id,c.name,m.team_id,t.name,m.role_key,case when c.status='archived' then 'archived' else t.status end,m.created_at from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.user_id=subject
    union all select cm.club_id,c.name,null::uuid,null::text,'member',c.status,cm.created_at from public.pfd_club_memberships cm join public.pfd_clubs c on c.id=cm.club_id where cm.user_id=subject and not exists(select 1 from public.pfd_club_admins ca where ca.club_id=cm.club_id and ca.user_id=subject)
   )m),
   'report_count',(select count(*) from public.pfd_reports where (subject_id=subject or coalesce(data->'team_ratings','{}'::jsonb) ? subject::text) and status='submitted'),
   'created_reports',(select count(*) from public.pfd_reports where created_by=subject and status='submitted'),
   'pending_requests',(select count(*) from public.pfd_access_requests where user_id=subject and status='pending'),
   'recent_reports',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (select id,template_key,report_date,status from public.pfd_reports where (subject_id=subject or coalesce(data->'team_ratings','{}'::jsonb) ? subject::text) order by report_date desc,created_at desc limit 10)r)
  );
 elsif action='requests_list' then
  with filtered as (
   select r.*,p.name,p.email,c.name as club_name,t.name as team_name,reviewer.name as reviewer_name from public.pfd_access_requests r
   join public.pfd_profiles p on p.id=r.user_id join public.pfd_clubs c on c.id=r.club_id
   left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles reviewer on reviewer.id=r.reviewed_by
   where (coalesce(payload->>'status','')='' or r.status=payload->>'status')
   and (coalesce(payload->>'role','')='' or r.role_key=payload->>'role')
   and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
   and (q='' or strpos(lower(p.name||' '||p.email||' '||c.name),lower(q))>0)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'pending',(select count(*) from public.pfd_access_requests where status='pending'),'page',page_no) into result;
  return result;
 elsif action='request_create' then
  subject:=(payload->>'user_id')::uuid;club:=(payload->>'club_id')::uuid;team:=nullif(payload->>'team_id','')::uuid;role_name:=payload->>'role_key';
  if not exists(select 1 from public.pfd_profiles where id=subject) or not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an existing account and active club.' using errcode='22023'; end if;
  if role_name not in ('member','club_admin','coach','player') or role_name is null or (role_name in ('member','club_admin') and team is not null) or (role_name in ('coach','player') and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active')) then raise exception 'Choose a valid role and team for this club.' using errcode='22023'; end if;
  if exists(select 1 from public.pfd_club_admins where user_id=subject and club_id=club and role_name='club_admin') or exists(select 1 from public.pfd_team_memberships where user_id=subject and team_id=team and role_key=role_name) then raise exception 'This account already has the requested membership.' using errcode='22023'; end if;
  if role_name='member' and exists(select 1 from public.pfd_club_memberships where user_id=subject and club_id=club) then raise exception 'This account already belongs to the club.' using errcode='22023';end if;
  if role_name in ('coach','player') and not exists(select 1 from public.pfd_club_memberships where user_id=subject and club_id=club) then raise exception 'Approve club membership before requesting a team.' using errcode='22023';end if;
  insert into public.pfd_access_requests(user_id,club_id,team_id,role_key,message,created_by) values(subject,club,team,role_name,coalesce(payload->>'message',''),actor) returning id into record_id;
  return jsonb_build_object('id',record_id);
 elsif action='request_review' then
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid;
  if not found then raise exception 'Request not found.' using errcode='P0002';end if;
  -- Match direct team assignment's lock order: club, team, then request.
  if req.team_id is not null then perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id for update;end if;
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Request not found.' using errcode='P0002'; end if;
  if req.status<>'pending' then raise exception 'This request has already been reviewed. Refresh the list.' using errcode='40001'; end if;
  state:=payload->>'decision';
  if state not in ('approved','rejected') or state is null then raise exception 'Choose approve or reject.' using errcode='22023'; end if;
  if state='rejected' and length(btrim(coalesce(payload->>'reason','')))=0 then raise exception 'Add a reason for rejecting this request.' using errcode='22023'; end if;
  if state='approved' then
   -- Lock the parent status while granting membership to avoid archive/approval races.
   perform 1 from public.pfd_clubs where id=req.club_id and status='active' for share;
   if not found then raise exception 'Restore the club before approving access.' using errcode='22023'; end if;
   if not exists(select 1 from public.pfd_clubs c where c.id=req.club_id and length(btrim(c.city))>0 and length(btrim(c.state))>0 and length(btrim(c.country))>0 and length(btrim(c.contact_email))>0 and length(btrim(c.contact_number))>0 and length(btrim(c.league))>0 and length(btrim(c.sport))>0) then raise exception 'Complete the club details before approving access.' using errcode='22023'; end if;
   if req.role_key='member' then
    insert into public.pfd_club_memberships(club_id,user_id,approved_by) values(req.club_id,req.user_id,actor) on conflict do nothing;
   elsif req.role_key='club_admin' then
    insert into public.pfd_club_admins(club_id,user_id,granted_by) values(req.club_id,req.user_id,actor) on conflict do nothing;
   else
    if not exists(select 1 from public.pfd_club_memberships where club_id=req.club_id and user_id=req.user_id) then raise exception 'Approve club membership before team access.' using errcode='22023';end if;
    perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id and status='active' for share;
    if not found then raise exception 'Restore the team before approving access.' using errcode='22023'; end if;
    insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(req.team_id,req.user_id,req.role_key,actor) on conflict do nothing;
   end if;
  end if;
  update public.pfd_access_requests set status=state,reason=coalesce(payload->>'reason',''),reviewed_by=actor,reviewed_at=now() where id=req.id;
  return jsonb_build_object('ok',true);
 elsif action='reports_list' then
  with filtered as (
   select r.id,r.subject_id,r.club_id,r.team_id,r.template_key,r.report_date,r.status,r.created_at,r.updated_at,coalesce(p.name,t.name,'Team match review') as subject_name,coalesce(p.email,'') as subject_email,c.name as club_name,t.name as team_name,a.name as author_name
   from public.pfd_reports r left join public.pfd_profiles p on p.id=r.subject_id left join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles a on a.id=r.created_by
   where (q='' or strpos(lower(coalesce(p.name,'')||' '||coalesce(p.email,'')||' '||coalesce(t.name,'')||' '||coalesce(c.name,'')),lower(q))>0)
    and (coalesce(payload->>'template_key','')='' or r.template_key=payload->>'template_key')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
    and (coalesce(payload->>'team_id','')='' or r.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or r.report_date>=(payload->>'from_date')::date)
    and (coalesce(payload->>'to_date','')='' or r.report_date<=(payload->>'to_date')::date)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by report_date desc,created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'submitted',(select count(*) from public.pfd_reports where status='submitted'),'page',page_no) into result;
  return result;
 elsif action='report_get' then
  select to_jsonb(r) into result from public.pfd_reports r where id=(payload->>'id')::uuid;
  if result is null then raise exception 'Report not found.' using errcode='P0002'; end if;
  return result;
 elsif action='report_save' then
  record_id:=(payload->>'id')::uuid;subject:=nullif(payload->>'subject_id','')::uuid;
  club:=nullif(payload->>'club_id','')::uuid;team:=nullif(payload->>'team_id','')::uuid;
  template:=payload->>'template_key';state:=payload->>'status';report_data:=payload->'data';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,42));
  select * into old_report from public.pfd_reports where id=record_id for update;
  if found and (old_report.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'This report changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if old_report.id is not null and old_report.status<>'draft' then raise exception 'Submitted reports are read-only. Create a new report for the next assessment.' using errcode='22023'; end if;
  select t.definition into definition from public.pfd_report_templates t where t.key=template;
  if definition is null or state not in ('draft','submitted') or state is null or jsonb_typeof(report_data) is distinct from 'object' then raise exception 'Invalid report template or status.' using errcode='22023'; end if;
  is_team:=coalesce((definition->>'team_report')::boolean,false);
  if is_team then
   subject:=null;
   if state='submitted' and team is null then raise exception 'Select a team before submitting a match review.' using errcode='22023'; end if;
  elsif not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Choose an existing account for this report.' using errcode='22023'; end if;
  if club is not null and not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an active club.' using errcode='22023'; end if;
  if team is not null and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active') then raise exception 'Choose a team in this club.' using errcode='22023'; end if;
  info:=report_data->'info';
  if jsonb_typeof(info) is distinct from 'object' or jsonb_typeof(report_data->'ratings') is distinct from 'object' or jsonb_typeof(report_data->'notes') is distinct from 'array' or jsonb_array_length(report_data->'notes')<>4 then raise exception 'Report sections are missing.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(info) loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid report detail.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'ratings') loop
   if jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (1,2,3,4,5) or not exists(
    select 1 from jsonb_each(definition->'categories') c cross join lateral jsonb_array_elements(c.value) with ordinality question where c.key||'-'||(question.ordinality-1)::text=entry.key
   ) then raise exception 'Ratings must match the original questions and use 1–5.' using errcode='22023'; end if;
  end loop;
  for item in select value from jsonb_array_elements(report_data->'notes') loop
   if jsonb_typeof(item)<>'string' or length(item#>>'{}')>6000 then raise exception 'Report notes must be text of at most 6000 characters.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(report_data->'extra') is distinct from 'object' or jsonb_typeof(report_data->'values') is distinct from 'object' or jsonb_typeof(report_data->'progress') is distinct from 'object' then raise exception 'Invalid report detail sections.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(report_data->'extra') loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid fitness test value.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'progress') loop
   if entry.key !~ '^[0-2]-[0-2]-[0-2]$' or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (0,1,2,3) then raise exception 'Invalid exercise progress marker.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'values') loop
   if jsonb_typeof(entry.value)<>'boolean' or not exists(select 1 from jsonb_each(definition->'behaviours') b cross join lateral jsonb_array_elements_text(b.value) v where v.value=entry.key) then raise exception 'Invalid player behaviour value.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(coalesce(report_data->'metrics','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(report_data->'team_ratings','{}'::jsonb))<>'object' then raise exception 'Invalid structured report data.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'metrics','{}'::jsonb)) loop
   select value into field_config from jsonb_array_elements(coalesce(definition->'fields','[]')) where value->>'key'=entry.key and value->>'type'='number';
   if field_config is null or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric < (field_config->>'min')::numeric or (entry.value#>>'{}')::numeric > (field_config->>'max')::numeric then raise exception 'A numeric report field is outside its allowed range.' using errcode='22023'; end if;
   if (field_config->>'step')::numeric=1 and mod((entry.value#>>'{}')::numeric,1)<>0 then raise exception 'Counts must be whole numbers.' using errcode='22023'; end if;
  end loop;
  if report_data->'metrics' ? 'shots' and report_data->'metrics' ? 'shots_on_target' and (report_data->'metrics'->>'shots_on_target')::numeric>(report_data->'metrics'->>'shots')::numeric then raise exception 'Shots on target cannot exceed shots.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'total_distance_m' and report_data->'metrics' ? 'high_speed_distance_m' and (report_data->'metrics'->>'high_speed_distance_m')::numeric>(report_data->'metrics'->>'total_distance_m')::numeric then raise exception 'High-speed distance cannot exceed total distance.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'top_speed_kmh' and report_data->'metrics' ? 'average_speed_kmh' and (report_data->'metrics'->>'average_speed_kmh')::numeric>(report_data->'metrics'->>'top_speed_kmh')::numeric then raise exception 'Average speed cannot exceed top speed.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'team_ratings','{}'::jsonb)) loop
   if not is_team or jsonb_typeof(entry.value->'rating') is distinct from 'number' or (entry.value->>'rating')::numeric not in (1,2,3,4,5) or not exists(select 1 from public.pfd_team_memberships m where m.team_id=team and m.user_id=entry.key::uuid and m.role_key='player') then raise exception 'Player ratings must be 1–5 and belong to this team roster.' using errcode='22023'; end if;
   report_data:=jsonb_set(report_data,array['team_ratings',entry.key,'name'],to_jsonb((select name from public.pfd_profiles where id=entry.key::uuid)));
  end loop;
  if length(coalesce(report_data->>'prepared_by',''))>250 or length(coalesce(report_data->>'reviewer',''))>250 then raise exception 'Report author details are too long.' using errcode='22023'; end if;
  if state='submitted' and (length(btrim(coalesce(info->>'name','')))=0 or length(btrim(coalesce(report_data->>'prepared_by','')))=0 or report_data->'consent' is distinct from 'true'::jsonb) then raise exception 'Complete the name, prepared-by field and submission consent.' using errcode='22023'; end if;
  insert into public.pfd_reports(id,subject_id,club_id,team_id,template_key,template_snapshot,report_date,status,data,created_by)
   values(record_id,subject,club,team,template,definition,(payload->>'report_date')::date,state,report_data,actor)
   on conflict(id) do update set subject_id=excluded.subject_id,club_id=excluded.club_id,team_id=excluded.team_id,template_key=excluded.template_key,template_snapshot=excluded.template_snapshot,report_date=excluded.report_date,status=excluded.status,data=excluded.data,updated_at=clock_timestamp()
   returning to_jsonb(pfd_reports) into result;
  return result;
 elsif action='resources_list' then
  with filtered as (
   select r.*,(select coalesce(jsonb_agg(c.club_id),'[]') from public.pfd_resource_clubs c where c.resource_id=r.id) as club_ids from public.pfd_resources r
   where (q='' or strpos(lower(r.title||' '||r.category||' '||r.instructions),lower(q))>0)
    and (coalesce(payload->>'kind','')='' or r.kind=payload->>'kind')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'difficulty','')='' or r.difficulty=payload->>'difficulty')
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by updated_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'published',(select count(*) from public.pfd_resources where status='published'),'page',page_no) into result;
  return result;
 elsif action='resource_save' then
  record_id:=(payload->>'id')::uuid;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,43));
  select * into old_resource from public.pfd_resources where id=record_id for update;
  if found and old_resource.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This resource changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if coalesce(payload->>'video_url','')<>'' and payload->>'video_url' !~ '^https?://[^[:space:]]+$' then raise exception 'Use a valid http or https video link.' using errcode='22023'; end if;
  if jsonb_typeof(payload->'attachments') is distinct from 'array' or jsonb_array_length(payload->'attachments')>5 then raise exception 'A resource can have up to five files.' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(payload->'attachments') loop
   if jsonb_typeof(item) is distinct from 'object' or length(coalesce(item->>'name','')) not between 1 and 250 or length(coalesce(item->>'path','')) not between 1 and 350
    or not exists(select 1 from storage.objects o where o.bucket_id='pfd-development-resources' and o.name=item->>'path') then raise exception 'An attached file is missing. Upload it again.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(payload->'club_ids') is distinct from 'array' then raise exception 'Invalid club selection.' using errcode='22023'; end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into selected_clubs from jsonb_array_elements_text(payload->'club_ids');
  if payload->>'audience'='selected_clubs' and (cardinality(selected_clubs)=0 or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_clubs c where c.id=id and c.status='active'))) then raise exception 'Select at least one active club.' using errcode='22023'; end if;
  if payload->>'status'='published' and length(btrim(coalesce(payload->>'instructions','')))=0 then raise exception 'Add instructions before publishing.' using errcode='22023'; end if;
  plan_minutes:=0;
  if payload->>'kind' in ('individual_drill','team_drill') and (nullif(payload->>'duration_minutes','') is null or (payload->>'duration_minutes')::numeric not between 0.1 and 240) then raise exception 'Add an estimated drill duration between 0.1 and 240 minutes.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(payload->'plan_blocks','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(payload->'plan_blocks','[]'::jsonb))>100 then raise exception 'A plan can contain up to 100 drills.' using errcode='22023'; end if;
  if payload->>'kind'='training_plan' then
   if payload->>'status'='published' and coalesce(jsonb_array_length(payload->'plan_blocks'),0)=0 then raise exception 'Add at least one drill before publishing a training plan.' using errcode='22023'; end if;
   for block in select value from jsonb_array_elements(coalesce(payload->'plan_blocks','[]'::jsonb)) loop
    select * into drill from public.pfd_resources where id=(block->>'resource_id')::uuid and kind in ('individual_drill','team_drill');
    if not found or (payload->>'status'='published' and drill.status<>'published') then raise exception 'Use available drills; published plans require published drills.' using errcode='22023'; end if;
    if jsonb_typeof(block->'minutes') is distinct from 'number' or (block->>'minutes')::numeric not between 0.1 and 240 then raise exception 'Set a valid duration for each plan drill.' using errcode='22023'; end if;
    if payload->>'status'='published' and drill.audience='selected_clubs' and (payload->>'audience'='all_clubs' or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=drill.id and rc.club_id=id))) then raise exception 'A plan cannot be shared more widely than its included drills.' using errcode='22023'; end if;
    normalized_blocks:=normalized_blocks||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'resource_id',drill.id,'title',drill.title,'kind',drill.kind,'minutes',(block->>'minutes')::numeric,'instructions',drill.instructions,'video_url',drill.video_url,'attachments',drill.attachments));
    plan_minutes:=plan_minutes+(block->>'minutes')::numeric;
   end loop;
  end if;
  insert into public.pfd_resources(id,title,kind,category,difficulty,instructions,video_url,attachments,audience,status,created_by,duration_minutes,plan_blocks)
   values(record_id,btrim(payload->>'title'),payload->>'kind',btrim(coalesce(payload->>'category','')),payload->>'difficulty',coalesce(payload->>'instructions',''),coalesce(payload->>'video_url',''),payload->'attachments',payload->>'audience',payload->>'status',actor,case when payload->>'kind'='training_plan' then null else nullif(payload->>'duration_minutes','')::numeric end,case when payload->>'kind'='training_plan' then normalized_blocks else '[]'::jsonb end)
   on conflict(id) do update set title=excluded.title,kind=excluded.kind,category=excluded.category,difficulty=excluded.difficulty,instructions=excluded.instructions,video_url=excluded.video_url,attachments=excluded.attachments,audience=excluded.audience,status=excluded.status,duration_minutes=excluded.duration_minutes,plan_blocks=excluded.plan_blocks,updated_at=clock_timestamp()
   returning to_jsonb(pfd_resources) into result;
  delete from public.pfd_resource_clubs where resource_id=record_id;
  if payload->>'audience'='selected_clubs' then insert into public.pfd_resource_clubs(resource_id,club_id) select record_id,id from (select distinct unnest(selected_clubs) id)x; end if;
  return result;
 elsif action='stats' then
  return jsonb_build_object('coaches',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='coach' and t.status='active' and c.status='active'),
   'players',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='player' and t.status='active' and c.status='active'),
   'reports',(select count(*) from public.pfd_reports where status='submitted'),'requests',(select count(*) from public.pfd_access_requests where status='pending'));
 end if;
 raise exception 'Unknown workspace action.' using errcode='22023';
end $$;

create function public.pfd_membership_flow(actor_id uuid,action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare club uuid:=nullif(payload->>'club_id','')::uuid;team uuid:=nullif(payload->>'team_id','')::uuid;
 req public.pfd_access_requests;role_name text:=payload->>'role_key';decision text:=payload->>'decision';result jsonb;
 page_no integer:=coalesce((payload->>'page')::integer,1);offset_no integer;q text:=btrim(coalesce(payload->>'query',''));
 members_allowed boolean;coaches_allowed boolean;players_allowed boolean;state text:=coalesce(payload->>'status','pending');
begin
 if actor_id is null or not exists(select 1 from public.pfd_profiles where id=actor_id) or exists(select 1 from public.pfd_platform_owners where user_id=actor_id) then raise exception 'Use your separate club account.' using errcode='42501';end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>10000 or page_no not between 1 and 100000 or length(q)>160 then raise exception 'Invalid membership request.' using errcode='22023';end if;
 offset_no:=(page_no-1)*20;
 if action='my_access' then
  return jsonb_build_object(
   'clubs',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select c.id,c.name,c.status,c.city,c.state,c.country,c.sport,c.league,cm.created_at as joined_at from public.pfd_club_memberships cm join public.pfd_clubs c on c.id=cm.club_id where cm.user_id=actor_id)x),
   'teams',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select t.id,t.name,t.club_id,t.age_group,t.season,t.status,m.role_key from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_club_memberships cm on cm.club_id=t.club_id and cm.user_id=m.user_id where m.user_id=actor_id)x),
   'requests',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') from (select r.id,r.club_id,c.name as club_name,r.team_id,t.name as team_name,r.role_key,r.status,r.message,r.reason,r.created_at,r.reviewed_at from public.pfd_access_requests r join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id where r.user_id=actor_id order by r.created_at desc limit 100)x)
  );
 elsif action='browse_clubs' then
  with filtered as(select c.id,c.name,c.city,c.state,c.country,c.sport,c.league,
    exists(select 1 from public.pfd_club_memberships cm where cm.club_id=c.id and cm.user_id=actor_id) as joined,
    exists(select 1 from public.pfd_access_requests r where r.user_id=actor_id and r.club_id=c.id and r.role_key='member' and r.status='pending') as pending
   from public.pfd_clubs c where c.status='active' and (q='' or strpos(lower(c.name||' '||c.city||' '||c.sport),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by name,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
 end if;
 perform 1 from public.pfd_clubs where id=club and status='active' for share;
 if not found then raise exception 'Choose an active club.' using errcode='22023';end if;
 if action in ('admin_requests','review_request') then
  perform 1 from public.pfd_club_admins where club_id=club and user_id=actor_id for share;
  if not found or not exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='clubs.view' and enabled) then raise exception 'Club Administrator access is required.' using errcode='42501';end if;
  perform 1 from public.pfd_role_permissions where role_key='club_admin' for share;
  select enabled into members_allowed from public.pfd_role_permissions where role_key='club_admin' and permission_key='members.approve';
  select enabled into coaches_allowed from public.pfd_role_permissions where role_key='club_admin' and permission_key='coaches.approve';
  select enabled into players_allowed from public.pfd_role_permissions where role_key='club_admin' and permission_key='players.approve';
  if action='admin_requests' then
   if not coalesce(members_allowed,false) and not coalesce(coaches_allowed,false) and not coalesce(players_allowed,false) then raise exception 'Request approval permission is required.' using errcode='42501';end if;
   if state not in ('pending','approved','rejected','all') then raise exception 'Invalid request status.' using errcode='22023';end if;
   with filtered as(select r.id,r.user_id,r.role_key,r.club_id,r.team_id,r.status,r.message,r.reason,r.created_at,r.reviewed_at,p.name,p.email,t.name as team_name,
      reviewer.name as reviewer_name
    from public.pfd_access_requests r join public.pfd_profiles p on p.id=r.user_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles reviewer on reviewer.id=r.reviewed_by
    where r.club_id=club and (state='all' or r.status=state)
     and ((r.role_key='member' and coalesce(members_allowed,false)) or (r.role_key='coach' and coalesce(coaches_allowed,false)) or (r.role_key='player' and coalesce(players_allowed,false)))
     and (coalesce(payload->>'role_key','')='' or r.role_key=payload->>'role_key')
     and (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0))
   select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
  end if;
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid and club_id=club;
  if not found then raise exception 'Request not found.' using errcode='P0002';end if;
  -- Match direct team assignment's lock order: club, team, then request.
  if req.team_id is not null then perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id for update;end if;
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid and club_id=club for update;
  if not found then raise exception 'Request not found in this club.' using errcode='P0002';end if;
  if not ((req.role_key='member' and coalesce(members_allowed,false)) or (req.role_key='coach' and coalesce(coaches_allowed,false)) or (req.role_key='player' and coalesce(players_allowed,false))) then raise exception 'You cannot approve this role.' using errcode='42501';end if;
  if req.status<>'pending' then raise exception 'This request has already been reviewed. Refresh the list.' using errcode='40001';end if;
  if decision is null or decision not in ('approved','rejected') then raise exception 'Choose approve or reject.' using errcode='22023';end if;
  if decision='rejected' and length(btrim(coalesce(payload->>'reason','')))=0 then raise exception 'Add a rejection reason.' using errcode='22023';end if;
  if decision='approved' then
   if req.role_key='member' then
    insert into public.pfd_club_memberships(club_id,user_id,approved_by) values(club,req.user_id,actor_id) on conflict do nothing;
   else
    perform 1 from public.pfd_club_memberships where club_id=club and user_id=req.user_id for share;
    if not found then raise exception 'Approve this account into the club first.' using errcode='22023';end if;
    perform 1 from public.pfd_teams where id=req.team_id and club_id=club and status='active' for share;
    if not found then raise exception 'Choose an active team in this club.' using errcode='22023';end if;
    insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(req.team_id,req.user_id,req.role_key,actor_id) on conflict do nothing;
    update public.pfd_teams set updated_at=clock_timestamp() where id=req.team_id;
   end if;
  end if;
  update public.pfd_access_requests set status=decision,reason=coalesce(payload->>'reason',''),reviewed_at=clock_timestamp(),reviewed_by=actor_id where id=req.id;
  return jsonb_build_object('ok',true);
 elsif action='request_club' then
  if exists(select 1 from public.pfd_club_memberships where club_id=club and user_id=actor_id) then raise exception 'You already belong to this club.' using errcode='22023';end if;
  insert into public.pfd_access_requests(user_id,club_id,role_key,message,created_by) values(actor_id,club,'member',coalesce(payload->>'message',''),actor_id) returning id into team;
  return jsonb_build_object('id',team);
 elsif action in ('club_teams','request_team') then
  perform 1 from public.pfd_club_memberships where club_id=club and user_id=actor_id for share;
  if not found then raise exception 'Your club request must be approved before you can join a team.' using errcode='42501';end if;
  if action='club_teams' then
   return (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select t.id,t.name,t.age_group,t.season,
     (select coalesce(jsonb_agg(m.role_key),'[]') from public.pfd_team_memberships m where m.team_id=t.id and m.user_id=actor_id) as roles,
     (select coalesce(jsonb_agg(r.role_key),'[]') from public.pfd_access_requests r where r.team_id=t.id and r.user_id=actor_id and r.status='pending') as pending_roles
    from public.pfd_teams t where t.club_id=club and t.status='active' order by name limit 1000)x);
  end if;
  if role_name is null or role_name not in ('coach','player') then raise exception 'Choose coach or player access.' using errcode='22023';end if;
  perform 1 from public.pfd_teams where id=team and club_id=club and status='active' for share;
  if not found then raise exception 'Choose an active team in this club.' using errcode='22023';end if;
  if exists(select 1 from public.pfd_team_memberships where team_id=team and user_id=actor_id and role_key=role_name) then raise exception 'You already have this team membership.' using errcode='22023';end if;
  insert into public.pfd_access_requests(user_id,club_id,team_id,role_key,message,created_by) values(actor_id,club,team,role_name,coalesce(payload->>'message',''),actor_id) returning id into team;
  return jsonb_build_object('id',team);
 end if;
 raise exception 'Unknown membership action.' using errcode='22023';
end $$;
revoke all on function public.pfd_membership_flow(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pfd_membership_flow(uuid,text,jsonb) to service_role;


-- SOURCE: supabase/club-workspace.sql
-- Club workspaces use verified actor IDs supplied by the Edge Function.
alter table public.pfd_resources add column club_id uuid references public.pfd_clubs(id);
create index pfd_resources_club_idx on public.pfd_resources(club_id,status);
create table public.pfd_club_events (
 id uuid primary key,club_id uuid not null references public.pfd_clubs(id),team_id uuid,
 kind text not null check(kind in ('training','game','event')),title text not null check(length(btrim(title)) between 1 and 160),
 starts_at timestamptz not null,ends_at timestamptz not null,timezone text not null default 'Australia/Adelaide',location text not null default '' check(length(location)<=250),
 notes text not null default '' check(length(notes)<=6000),plan_id uuid references public.pfd_resources(id),plan_snapshot jsonb,
 team_ids uuid[] not null default '{}',role_keys text[] not null default '{}',user_ids uuid[] not null default '{}',
 status text not null default 'scheduled' check(status in ('scheduled','cancelled')),created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(team_id,club_id) references public.pfd_teams(id,club_id),check(ends_at>starts_at),check(kind='event' or team_id is not null)
);
create table public.pfd_event_recipients(event_id uuid not null references public.pfd_club_events(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,response text not null default 'pending' check(response in ('pending','attending','declined')),primary key(event_id,user_id));
create table public.pfd_attendance(event_id uuid not null references public.pfd_club_events(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,status text not null check(status in ('present','absent','late','excused')),notes text not null default '' check(length(notes)<=1000),marked_by uuid references auth.users(id) on delete set null,updated_at timestamptz not null default now(),primary key(event_id,user_id));
create table public.pfd_announcements (
 id uuid primary key,club_id uuid not null references public.pfd_clubs(id),title text not null check(length(btrim(title)) between 1 and 160),body text not null check(length(body) between 1 and 12000),
 team_ids uuid[] not null default '{}',role_keys text[] not null default '{}',user_ids uuid[] not null default '{}',status text not null check(status in ('draft','published','archived')),
 created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.pfd_announcement_recipients(announcement_id uuid not null references public.pfd_announcements(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,primary key(announcement_id,user_id));
create table public.pfd_homework (
 id uuid primary key,club_id uuid not null references public.pfd_clubs(id),title text not null check(length(btrim(title)) between 1 and 160),instructions text not null default '' check(length(instructions)<=12000),
 resource_id uuid references public.pfd_resources(id),resource_snapshot jsonb,due_at timestamptz not null,team_ids uuid[] not null default '{}',user_ids uuid[] not null default '{}',
 status text not null default 'active' check(status in ('active','archived')),created_by uuid references auth.users(id) on delete set null,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.pfd_homework_recipients(homework_id uuid not null references public.pfd_homework(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,primary key(homework_id,user_id));
create table public.pfd_homework_submissions (
 id uuid primary key,homework_id uuid not null,user_id uuid not null,notes text not null default '' check(length(notes)<=6000),attachments jsonb not null default '[]' check(jsonb_typeof(attachments)='array' and jsonb_array_length(attachments)<=3),
 feedback text not null default '' check(length(feedback)<=6000),review_status text not null default 'submitted' check(review_status in ('submitted','reviewed','resubmit')),reviewed_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),foreign key(homework_id,user_id) references public.pfd_homework_recipients(homework_id,user_id),unique(homework_id,user_id)
);
create table public.pfd_chat_rooms (
 id uuid primary key,club_id uuid not null references public.pfd_clubs(id),team_id uuid,title text not null check(length(btrim(title)) between 1 and 160),
 created_by uuid references auth.users(id) on delete set null,status text not null default 'active' check(status in ('active','archived')),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),foreign key(team_id,club_id) references public.pfd_teams(id,club_id)
);
create unique index pfd_chat_room_team_unique on public.pfd_chat_rooms(team_id) where team_id is not null;
create table public.pfd_chat_members(room_id uuid not null references public.pfd_chat_rooms(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,primary key(room_id,user_id));
create table public.pfd_chat_messages(id uuid primary key,room_id uuid not null references public.pfd_chat_rooms(id) on delete cascade,user_id uuid not null references auth.users(id),body text not null check(length(btrim(body)) between 1 and 4000),created_at timestamptz not null default now());
create index pfd_club_events_lookup_0 on public.pfd_club_events(club_id,starts_at);
create index pfd_club_events_lookup_1 on public.pfd_club_events(team_id,club_id);
create index pfd_club_events_lookup_2 on public.pfd_club_events(plan_id);
create index pfd_club_events_lookup_3 on public.pfd_club_events(created_by);
alter table public.pfd_club_events enable row level security;
revoke all on public.pfd_club_events from public,anon,authenticated;
grant all on public.pfd_club_events to service_role;
grant select on public.pfd_club_events to authenticated;
create policy pfd_club_events_owner_read on public.pfd_club_events for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_event_recipients_lookup_0 on public.pfd_event_recipients(user_id);
alter table public.pfd_event_recipients enable row level security;
revoke all on public.pfd_event_recipients from public,anon,authenticated;
grant all on public.pfd_event_recipients to service_role;
grant select on public.pfd_event_recipients to authenticated;
create policy pfd_event_recipients_owner_read on public.pfd_event_recipients for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_attendance_lookup_0 on public.pfd_attendance(user_id);
create index pfd_attendance_lookup_1 on public.pfd_attendance(marked_by);
alter table public.pfd_attendance enable row level security;
revoke all on public.pfd_attendance from public,anon,authenticated;
grant all on public.pfd_attendance to service_role;
grant select on public.pfd_attendance to authenticated;
create policy pfd_attendance_owner_read on public.pfd_attendance for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_announcements_lookup_0 on public.pfd_announcements(club_id,created_at desc);
create index pfd_announcements_lookup_1 on public.pfd_announcements(created_by);
alter table public.pfd_announcements enable row level security;
revoke all on public.pfd_announcements from public,anon,authenticated;
grant all on public.pfd_announcements to service_role;
grant select on public.pfd_announcements to authenticated;
create policy pfd_announcements_owner_read on public.pfd_announcements for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_announcement_recipients_lookup_0 on public.pfd_announcement_recipients(user_id);
alter table public.pfd_announcement_recipients enable row level security;
revoke all on public.pfd_announcement_recipients from public,anon,authenticated;
grant all on public.pfd_announcement_recipients to service_role;
grant select on public.pfd_announcement_recipients to authenticated;
create policy pfd_announcement_recipients_owner_read on public.pfd_announcement_recipients for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_homework_lookup_0 on public.pfd_homework(club_id,due_at);
create index pfd_homework_lookup_1 on public.pfd_homework(resource_id);
create index pfd_homework_lookup_2 on public.pfd_homework(created_by);
alter table public.pfd_homework enable row level security;
revoke all on public.pfd_homework from public,anon,authenticated;
grant all on public.pfd_homework to service_role;
grant select on public.pfd_homework to authenticated;
create policy pfd_homework_owner_read on public.pfd_homework for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_homework_recipients_lookup_0 on public.pfd_homework_recipients(user_id);
alter table public.pfd_homework_recipients enable row level security;
revoke all on public.pfd_homework_recipients from public,anon,authenticated;
grant all on public.pfd_homework_recipients to service_role;
grant select on public.pfd_homework_recipients to authenticated;
create policy pfd_homework_recipients_owner_read on public.pfd_homework_recipients for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_homework_submissions_lookup_0 on public.pfd_homework_submissions(reviewed_by);
alter table public.pfd_homework_submissions enable row level security;
revoke all on public.pfd_homework_submissions from public,anon,authenticated;
grant all on public.pfd_homework_submissions to service_role;
grant select on public.pfd_homework_submissions to authenticated;
create policy pfd_homework_submissions_owner_read on public.pfd_homework_submissions for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_chat_rooms_lookup_0 on public.pfd_chat_rooms(club_id);
create index pfd_chat_rooms_lookup_1 on public.pfd_chat_rooms(team_id,club_id);
create index pfd_chat_rooms_lookup_2 on public.pfd_chat_rooms(created_by);
alter table public.pfd_chat_rooms enable row level security;
revoke all on public.pfd_chat_rooms from public,anon,authenticated;
grant all on public.pfd_chat_rooms to service_role;
grant select on public.pfd_chat_rooms to authenticated;
create policy pfd_chat_rooms_owner_read on public.pfd_chat_rooms for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_chat_members_lookup_0 on public.pfd_chat_members(user_id);
alter table public.pfd_chat_members enable row level security;
revoke all on public.pfd_chat_members from public,anon,authenticated;
grant all on public.pfd_chat_members to service_role;
grant select on public.pfd_chat_members to authenticated;
create policy pfd_chat_members_owner_read on public.pfd_chat_members for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create index pfd_chat_messages_lookup_0 on public.pfd_chat_messages(room_id,created_at desc);
create index pfd_chat_messages_lookup_1 on public.pfd_chat_messages(user_id);
alter table public.pfd_chat_messages enable row level security;
revoke all on public.pfd_chat_messages from public,anon,authenticated;
grant all on public.pfd_chat_messages to service_role;
grant select on public.pfd_chat_messages to authenticated;
create policy pfd_chat_messages_owner_read on public.pfd_chat_messages for select to authenticated using(exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
insert into public.pfd_permission_catalog(key,category,label,description,available,owner_only,sort_order) values('clubs.edit','Club & people','Edit club details','Assigned club and authorised conversations only.',true,false,30);
insert into public.pfd_role_permissions(role_key,permission_key,enabled) values('club_admin','clubs.edit',true),('coach','clubs.edit',false),('player','clubs.edit',false);
insert into public.pfd_permission_catalog(key,category,label,description,available,owner_only,sort_order) values('chats.view','Chats','Read and send chat messages','Assigned club and authorised conversations only.',true,false,31);
insert into public.pfd_role_permissions(role_key,permission_key,enabled) values('club_admin','chats.view',true),('coach','chats.view',true),('player','chats.view',true);
insert into public.pfd_permission_catalog(key,category,label,description,available,owner_only,sort_order) values('chats.manage','Chats','Manage chat groups','Assigned club and authorised conversations only.',true,false,32);
insert into public.pfd_role_permissions(role_key,permission_key,enabled) values('club_admin','chats.manage',true),('coach','chats.manage',false),('player','chats.manage',false);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pfd-club-files','pfd-club-files',false,52428800,array['application/pdf','image/jpeg','image/png','image/webp','video/mp4','video/webm']);
create policy pfd_club_resource_files on storage.objects for all to authenticated
using(bucket_id='pfd-club-files' and (storage.foldername(name))[2]='resources' and exists(select 1 from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id where a.user_id=(select auth.uid()) and a.club_id::text=(storage.foldername(name))[1] and c.status='active') and exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='library.manage_club' and enabled))
with check(bucket_id='pfd-club-files' and (storage.foldername(name))[2]='resources' and exists(select 1 from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id where a.user_id=(select auth.uid()) and a.club_id::text=(storage.foldername(name))[1] and c.status='active') and exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='library.manage_club' and enabled));
create function pfd_private.club_audience(c uuid,teams uuid[],roles text[],people uuid[])
returns table(user_id uuid) language sql stable security invoker set search_path='' as $$
 select cm.user_id from public.pfd_club_memberships cm where cm.club_id=c
 and not exists(select 1 from public.pfd_platform_owners o where o.user_id=cm.user_id)
 and (cardinality(people)=0 or cm.user_id=any(people))
 and (cardinality(teams)=0 or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=cm.user_id and t.club_id=c and t.status='active' and m.team_id=any(teams)) or exists(select 1 from public.pfd_club_admins a where a.user_id=cm.user_id and a.club_id=c))
 and (cardinality(roles)=0 or 'member'=any(roles)
  or ('club_admin'=any(roles) and exists(select 1 from public.pfd_club_admins a where a.user_id=cm.user_id and a.club_id=c))
  or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=cm.user_id and t.club_id=c and t.status='active' and m.role_key=any(roles) and (cardinality(teams)=0 or m.team_id=any(teams))))
$$;
revoke all on function pfd_private.club_audience(uuid,uuid[],text[],uuid[]) from public,anon,authenticated;
grant usage on schema pfd_private to service_role;
grant execute on function pfd_private.club_audience(uuid,uuid[],text[],uuid[]) to service_role;

create function public.pfd_club_workspace(actor_id uuid,target_club uuid,action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor uuid:=actor_id;club uuid:=target_club;team uuid;subject uuid;record_id uuid;role_name text;state text;template text;
 result jsonb;definition jsonb;report_data jsonb;info jsonb;field_config jsonb;item jsonb;entry record;block jsonb;
 old_report public.pfd_reports;old_resource public.pfd_resources;drill public.pfd_resources;
 plan_minutes numeric;normalized_blocks jsonb:='[]';is_team boolean;selected_clubs uuid[];
 page_no integer:=coalesce((payload->>'page')::integer,1);page_size integer:=20;offset_no integer; q text:=btrim(coalesce(payload->>'query',''));
 is_admin boolean;perms text[];required_key text;teams uuid[];roles text[];people uuid[];recipients uuid[];
 event_row public.pfd_club_events;post_row public.pfd_announcements;hw public.pfd_homework;submission public.pfd_homework_submissions;room public.pfd_chat_rooms;
begin
 if actor is null or exists(select 1 from public.pfd_platform_owners where user_id=actor) then raise exception 'Use your separate club account.' using errcode='42501';end if;
 perform 1 from public.pfd_clubs where id=club and status='active' for share;
 if not found or not exists(select 1 from public.pfd_club_memberships where club_id=club and user_id=actor) then raise exception 'Approved access to this active club is required.' using errcode='42501';end if;
 select exists(select 1 from public.pfd_club_admins where club_id=club and user_id=actor) into is_admin;
 select coalesce(array_agg(distinct p.permission_key),'{}') into perms from public.pfd_role_permissions p where p.enabled and (
  (is_admin and p.role_key='club_admin') or (not is_admin and exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=actor and m.role_key=p.role_key and t.club_id=club and t.status='active')));
 if not is_admin and action not in ('my_context','my_calendar','my_homework','my_announcements','homework_upload_access','submit_homework','rooms_list','room_messages','send_message','file_access') then raise exception 'Club Administrator access is required.' using errcode='42501';end if;
 if is_admin and not ('clubs.view'=any(perms)) then raise exception 'View club permission is required.' using errcode='42501';end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>180000 or page_no not between 1 and 100000 or length(q)>160 then raise exception 'Invalid workspace request.' using errcode='22023';end if;
 offset_no:=(page_no-1)*20;
 required_key:=case
 when action in ('users_list','people_list','person_detail') then 'members.view'
 when action in ('reports_list','report_get') then 'reports.view_team'
 when action='report_save' then 'reports.create'
 when action in ('resources_list','drill_catalog','resource_file_access') then 'library.view'
 when action='resource_save' then 'library.manage_club'
 when action in ('events_list','event_detail') then 'events.view'
 when action in ('event_save','attendance_save') then 'events.manage'
 when action='homework_list' then 'homework.view'
 when action='homework_save' then 'homework.assign'
 when action in ('homework_detail','homework_review') then 'homework.review'
 when action in ('homework_upload_access','submit_homework') then 'homework.submit'
 when action='announcements_list' then 'announcements.view'
 when action='announcement_save' then 'announcements.publish'
 when action in ('rooms_list','room_messages','send_message') then 'chats.view'
 when action in ('room_save','team_chat') then 'chats.manage'
 when action='settings_get' then 'clubs.view'
 when action='settings_save' then 'clubs.edit' else null end;
 if required_key is not null and not(required_key=any(perms)) then raise exception 'Your role does not have permission for this action.' using errcode='42501';end if;
 if action='my_context' then return jsonb_build_object('permissions',to_jsonb(perms));end if;
 if action in ('options','users_list','people_list','person_detail','stats') then
  if action='options' then return jsonb_build_object(
   'clubs',(select jsonb_build_array(jsonb_build_object('id',c.id,'name',c.name,'status',c.status)) from public.pfd_clubs c where c.id=club),
   'teams',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name),'[]') from (select id,name,club_id,age_group,season,status from public.pfd_teams where club_id=club and status='active')t),
   'templates',(select jsonb_agg(to_jsonb(t) order by t.key) from public.pfd_report_templates t),
   'people',case when 'members.view'=any(perms) then (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select p.id,p.name,p.email,
      array_remove(array[case when exists(select 1 from public.pfd_club_admins a where a.club_id=club and a.user_id=p.id) then 'club_admin' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and m.user_id=p.id and m.role_key='coach') then 'coach' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and m.user_id=p.id and m.role_key='player') then 'player' end],null) as roles
    from public.pfd_profiles p join public.pfd_club_memberships cm on cm.user_id=p.id and cm.club_id=club where not exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) order by p.name limit 2000)x) else '[]'::jsonb end,
   'permissions',to_jsonb(perms));end if;
  if action='stats' then return jsonb_build_object(
   'reports',case when 'reports.view_team'=any(perms) then (select count(*) from public.pfd_reports where club_id=club and status='submitted') else null end,
   'requests',case when 'members.approve'=any(perms) or 'coaches.approve'=any(perms) or 'players.approve'=any(perms) then (select count(*) from public.pfd_access_requests where club_id=club and status='pending' and role_key<>'club_admin') else null end,
   'sessions',case when 'events.view'=any(perms) then (select count(*) from public.pfd_club_events where club_id=club and status='scheduled' and starts_at>=now()) else null end,
   'homework',case when 'homework.view'=any(perms) then (select count(*) from public.pfd_homework where club_id=club and status='active') else null end);end if;
  if action='person_detail' then
   subject:=(payload->>'id')::uuid;
   if not exists(select 1 from public.pfd_club_memberships where club_id=club and user_id=subject) then raise exception 'Person not found in this club.' using errcode='P0002';end if;
   return jsonb_build_object('profile',(select jsonb_build_object('id',p.id,'name',p.name,'email',p.email,'created_at',p.created_at) from public.pfd_profiles p where p.id=subject),
    'teams',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select t.id,t.name,t.season,t.status,m.role_key from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and m.user_id=subject)x),
    'reports',case when 'reports.view_team'=any(perms) then (select coalesce(jsonb_agg(to_jsonb(x) order by x.report_date),'[]') from (select id,template_key,report_date,status,data from public.pfd_reports where club_id=club and status='submitted' and (subject_id=subject or coalesce(data->'team_ratings','{}') ? subject::text) order by report_date desc,created_at desc limit 100)x) else '[]'::jsonb end);
  end if;
  with people_rows as(select p.id,p.name,p.email,p.created_at,null::timestamptz as last_sign_in_at,
    array_remove(array[case when exists(select 1 from public.pfd_club_admins a where a.club_id=club and a.user_id=p.id) then 'club_admin' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and m.user_id=p.id and m.role_key='coach') then 'coach' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and m.user_id=p.id and m.role_key='player') then 'player' end],null) as roles
   from public.pfd_profiles p join public.pfd_club_memberships cm on cm.user_id=p.id and cm.club_id=club where not exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) and(q='' or strpos(lower(p.name||' '||p.email),lower(q))>0)),
  filtered as(select pr.* from people_rows pr where coalesce(payload->>'role','')='' or (payload->>'role'='member' and cardinality(pr.roles)=0) or payload->>'role'=any(pr.roles))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from filtered order by name,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
 elsif action='team_roster' then
  if not ('reports.create'=any(perms) or 'reports.view_team'=any(perms)) or not('members.view'=any(perms)) then raise exception 'Report and member permissions are required.' using errcode='42501';end if;
  return(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select p.id,p.name,p.email from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_profiles p on p.id=m.user_id where t.id=(payload->>'team_id')::uuid and t.club_id=club and t.status='active' and m.role_key='player')x);
 elsif action='drill_catalog' then
  return(select coalesce(jsonb_agg(to_jsonb(x) order by x.title),'[]') from(select id,title,kind,duration_minutes,status,category from public.pfd_resources r where r.kind in ('individual_drill','team_drill') and r.status<>'archived' and(r.club_id=club or(r.club_id is null and r.status='published' and(r.audience='all_clubs' or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=club)))))x);
 elsif action='reports_list' then
  with filtered as (
   select r.id,r.subject_id,r.club_id,r.team_id,r.template_key,r.report_date,r.status,r.created_at,r.updated_at,coalesce(p.name,t.name,'Team match review') as subject_name,coalesce(p.email,'') as subject_email,c.name as club_name,t.name as team_name,a.name as author_name
   from public.pfd_reports r left join public.pfd_profiles p on p.id=r.subject_id left join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles a on a.id=r.created_by
   where r.club_id=target_club and (q='' or strpos(lower(coalesce(p.name,'')||' '||coalesce(p.email,'')||' '||coalesce(t.name,'')||' '||coalesce(c.name,'')),lower(q))>0)
    and (coalesce(payload->>'template_key','')='' or r.template_key=payload->>'template_key')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
    and (coalesce(payload->>'team_id','')='' or r.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or r.report_date>=(payload->>'from_date')::date)
    and (coalesce(payload->>'to_date','')='' or r.report_date<=(payload->>'to_date')::date)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by report_date desc,created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'submitted',(select count(*) from public.pfd_reports where status='submitted'),'page',page_no) into result;
  return result;
 elsif action='report_get' then
  select to_jsonb(r) into result from public.pfd_reports r where id=(payload->>'id')::uuid and club_id=target_club;
  if result is null then raise exception 'Report not found.' using errcode='P0002'; end if;
  return result;
 elsif action='report_save' then
  record_id:=(payload->>'id')::uuid;subject:=nullif(payload->>'subject_id','')::uuid;
  club:=target_club;team:=nullif(payload->>'team_id','')::uuid;
  template:=payload->>'template_key';state:=payload->>'status';report_data:=payload->'data';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,42));
  select * into old_report from public.pfd_reports where id=record_id for update;
  if old_report.id is not null and old_report.club_id is distinct from target_club then raise exception 'Report not found in this club.' using errcode='42501';end if;
  if found and (old_report.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'This report changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if old_report.id is not null and old_report.status<>'draft' then raise exception 'Submitted reports are read-only. Create a new report for the next assessment.' using errcode='22023'; end if;
  select t.definition into definition from public.pfd_report_templates t where t.key=template;
  if definition is null or state not in ('draft','submitted') or state is null or jsonb_typeof(report_data) is distinct from 'object' then raise exception 'Invalid report template or status.' using errcode='22023'; end if;
  is_team:=coalesce((definition->>'team_report')::boolean,false);
  if is_team then
   subject:=null;
   if state='submitted' and team is null then raise exception 'Select a team before submitting a match review.' using errcode='22023'; end if;
  elsif not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Choose an existing account for this report.' using errcode='22023'; end if;
  if club is not null and not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an active club.' using errcode='22023'; end if;
  if team is not null and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active') then raise exception 'Choose a team in this club.' using errcode='22023'; end if;
  if not is_team then
   role_name:=case when template='coaches' then coalesce(report_data->>'subject_kind','coach') else 'player' end;
   if role_name not in ('player','coach') or not exists(select 1 from public.pfd_team_memberships m join public.pfd_teams st on st.id=m.team_id join public.pfd_club_memberships cm on cm.club_id=st.club_id and cm.user_id=m.user_id where st.club_id=target_club and st.status='active' and m.user_id=subject and m.role_key=role_name and(team is null or m.team_id=team)) then raise exception 'Choose a player or coach account assigned to this club and team.' using errcode='22023';end if;
   report_data:=jsonb_set(report_data,'{subject_kind}',to_jsonb(role_name));
  else report_data:=jsonb_set(report_data,'{subject_kind}','"team"'::jsonb);end if;
  info:=report_data->'info';
  if jsonb_typeof(info) is distinct from 'object' or jsonb_typeof(report_data->'ratings') is distinct from 'object' or jsonb_typeof(report_data->'notes') is distinct from 'array' or jsonb_array_length(report_data->'notes')<>4 then raise exception 'Report sections are missing.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(info) loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid report detail.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'ratings') loop
   if jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (1,2,3,4,5) or not exists(
    select 1 from jsonb_each(definition->'categories') c cross join lateral jsonb_array_elements(c.value) with ordinality question where c.key||'-'||(question.ordinality-1)::text=entry.key
   ) then raise exception 'Ratings must match the original questions and use 1–5.' using errcode='22023'; end if;
  end loop;
  for item in select value from jsonb_array_elements(report_data->'notes') loop
   if jsonb_typeof(item)<>'string' or length(item#>>'{}')>6000 then raise exception 'Report notes must be text of at most 6000 characters.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(report_data->'extra') is distinct from 'object' or jsonb_typeof(report_data->'values') is distinct from 'object' or jsonb_typeof(report_data->'progress') is distinct from 'object' then raise exception 'Invalid report detail sections.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(report_data->'extra') loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid fitness test value.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'progress') loop
   if entry.key !~ '^[0-2]-[0-2]-[0-2]$' or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (0,1,2,3) then raise exception 'Invalid exercise progress marker.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'values') loop
   if jsonb_typeof(entry.value)<>'boolean' or not exists(select 1 from jsonb_each(definition->'behaviours') b cross join lateral jsonb_array_elements_text(b.value) v where v.value=entry.key) then raise exception 'Invalid player behaviour value.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(coalesce(report_data->'metrics','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(report_data->'team_ratings','{}'::jsonb))<>'object' then raise exception 'Invalid structured report data.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'metrics','{}'::jsonb)) loop
   select value into field_config from jsonb_array_elements(coalesce(definition->'fields','[]')) where value->>'key'=entry.key and value->>'type'='number';
   if field_config is null or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric < (field_config->>'min')::numeric or (entry.value#>>'{}')::numeric > (field_config->>'max')::numeric then raise exception 'A numeric report field is outside its allowed range.' using errcode='22023'; end if;
   if (field_config->>'step')::numeric=1 and mod((entry.value#>>'{}')::numeric,1)<>0 then raise exception 'Counts must be whole numbers.' using errcode='22023'; end if;
  end loop;
  if report_data->'metrics' ? 'shots' and report_data->'metrics' ? 'shots_on_target' and (report_data->'metrics'->>'shots_on_target')::numeric>(report_data->'metrics'->>'shots')::numeric then raise exception 'Shots on target cannot exceed shots.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'total_distance_m' and report_data->'metrics' ? 'high_speed_distance_m' and (report_data->'metrics'->>'high_speed_distance_m')::numeric>(report_data->'metrics'->>'total_distance_m')::numeric then raise exception 'High-speed distance cannot exceed total distance.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'top_speed_kmh' and report_data->'metrics' ? 'average_speed_kmh' and (report_data->'metrics'->>'average_speed_kmh')::numeric>(report_data->'metrics'->>'top_speed_kmh')::numeric then raise exception 'Average speed cannot exceed top speed.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'team_ratings','{}'::jsonb)) loop
   if not is_team or jsonb_typeof(entry.value->'rating') is distinct from 'number' or (entry.value->>'rating')::numeric not in (1,2,3,4,5) or not exists(select 1 from public.pfd_team_memberships m where m.team_id=team and m.user_id=entry.key::uuid and m.role_key='player') then raise exception 'Player ratings must be 1–5 and belong to this team roster.' using errcode='22023'; end if;
   report_data:=jsonb_set(report_data,array['team_ratings',entry.key,'name'],to_jsonb((select name from public.pfd_profiles where id=entry.key::uuid)));
  end loop;
  if length(coalesce(report_data->>'prepared_by',''))>250 or length(coalesce(report_data->>'reviewer',''))>250 then raise exception 'Report author details are too long.' using errcode='22023'; end if;
  if state='submitted' and (length(btrim(coalesce(info->>'name','')))=0 or length(btrim(coalesce(report_data->>'prepared_by','')))=0 or report_data->'consent' is distinct from 'true'::jsonb) then raise exception 'Complete the name, prepared-by field and submission consent.' using errcode='22023'; end if;
  insert into public.pfd_reports(id,subject_id,club_id,team_id,template_key,template_snapshot,report_date,status,data,created_by)
   values(record_id,subject,club,team,template,definition,(payload->>'report_date')::date,state,report_data,actor)
   on conflict(id) do update set subject_id=excluded.subject_id,club_id=excluded.club_id,team_id=excluded.team_id,template_key=excluded.template_key,template_snapshot=excluded.template_snapshot,report_date=excluded.report_date,status=excluded.status,data=excluded.data,updated_at=clock_timestamp()
   returning to_jsonb(pfd_reports) into result;
  return result;
 elsif action='resources_list' then
  with filtered as (
   select r.*, (r.club_id is null) as read_only,(select coalesce(jsonb_agg(c.club_id),'[]') from public.pfd_resource_clubs c where c.resource_id=r.id) as club_ids from public.pfd_resources r
   where (r.club_id=target_club or (r.club_id is null and r.status='published' and(r.audience='all_clubs' or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=target_club)))) and (q='' or strpos(lower(r.title||' '||r.category||' '||r.instructions),lower(q))>0)
    and (coalesce(payload->>'kind','')='' or r.kind=payload->>'kind')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'difficulty','')='' or r.difficulty=payload->>'difficulty')
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by updated_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'published',(select count(*) from public.pfd_resources where club_id=target_club and status='published'),'page',page_no) into result;
  return result;
 elsif action='resource_save' then
  record_id:=(payload->>'id')::uuid;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,43));
  select * into old_resource from public.pfd_resources where id=record_id for update;
  if old_resource.id is not null and old_resource.club_id is distinct from target_club then raise exception 'Shared PFD resources are read-only.' using errcode='42501';end if;
  payload:=payload||jsonb_build_object('audience','selected_clubs','club_ids',jsonb_build_array(target_club));
  if found and old_resource.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This resource changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if coalesce(payload->>'video_url','')<>'' and payload->>'video_url' !~ '^https?://[^[:space:]]+$' then raise exception 'Use a valid http or https video link.' using errcode='22023'; end if;
  if jsonb_typeof(payload->'attachments') is distinct from 'array' or jsonb_array_length(payload->'attachments')>5 then raise exception 'A resource can have up to five files.' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(payload->'attachments') loop
   if jsonb_typeof(item) is distinct from 'object' or length(coalesce(item->>'name','')) not between 1 and 250 or length(coalesce(item->>'path','')) not between 1 and 350
    or not exists(select 1 from storage.objects o where o.bucket_id='pfd-club-files' and o.name=item->>'path' and o.name like target_club::text||'/resources/%') then raise exception 'An attached file is missing. Upload it again.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(payload->'club_ids') is distinct from 'array' then raise exception 'Invalid club selection.' using errcode='22023'; end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into selected_clubs from jsonb_array_elements_text(payload->'club_ids');
  if payload->>'audience'='selected_clubs' and (cardinality(selected_clubs)=0 or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_clubs c where c.id=id and c.status='active'))) then raise exception 'Select at least one active club.' using errcode='22023'; end if;
  if payload->>'status'='published' and length(btrim(coalesce(payload->>'instructions','')))=0 then raise exception 'Add instructions before publishing.' using errcode='22023'; end if;
  plan_minutes:=0;
  if payload->>'kind' in ('individual_drill','team_drill') and (nullif(payload->>'duration_minutes','') is null or (payload->>'duration_minutes')::numeric not between 0.1 and 240) then raise exception 'Add an estimated drill duration between 0.1 and 240 minutes.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(payload->'plan_blocks','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(payload->'plan_blocks','[]'::jsonb))>100 then raise exception 'A plan can contain up to 100 drills.' using errcode='22023'; end if;
  if payload->>'kind'='training_plan' then
   if payload->>'status'='published' and coalesce(jsonb_array_length(payload->'plan_blocks'),0)=0 then raise exception 'Add at least one drill before publishing a training plan.' using errcode='22023'; end if;
   for block in select value from jsonb_array_elements(coalesce(payload->'plan_blocks','[]'::jsonb)) loop
    select * into drill from public.pfd_resources where id=(block->>'resource_id')::uuid and kind in ('individual_drill','team_drill') and (club_id=target_club or(club_id is null and status='published' and(audience='all_clubs' or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=public.pfd_resources.id and rc.club_id=target_club))));
    if not found or (payload->>'status'='published' and drill.status<>'published') then raise exception 'Use available drills; published plans require published drills.' using errcode='22023'; end if;
    if jsonb_typeof(block->'minutes') is distinct from 'number' or (block->>'minutes')::numeric not between 0.1 and 240 then raise exception 'Set a valid duration for each plan drill.' using errcode='22023'; end if;
    if payload->>'status'='published' and drill.audience='selected_clubs' and (payload->>'audience'='all_clubs' or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=drill.id and rc.club_id=id))) then raise exception 'A plan cannot be shared more widely than its included drills.' using errcode='22023'; end if;
    normalized_blocks:=normalized_blocks||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'resource_id',drill.id,'title',drill.title,'kind',drill.kind,'minutes',(block->>'minutes')::numeric,'instructions',drill.instructions,'video_url',drill.video_url,'attachments',drill.attachments));
    plan_minutes:=plan_minutes+(block->>'minutes')::numeric;
   end loop;
  end if;
  insert into public.pfd_resources(id,title,kind,category,difficulty,instructions,video_url,attachments,audience,status,created_by,duration_minutes,plan_blocks,club_id)
   values(record_id,btrim(payload->>'title'),payload->>'kind',btrim(coalesce(payload->>'category','')),payload->>'difficulty',coalesce(payload->>'instructions',''),coalesce(payload->>'video_url',''),payload->'attachments',payload->>'audience',payload->>'status',actor,case when payload->>'kind'='training_plan' then null else nullif(payload->>'duration_minutes','')::numeric end,case when payload->>'kind'='training_plan' then normalized_blocks else '[]'::jsonb end,target_club)
   on conflict(id) do update set title=excluded.title,kind=excluded.kind,category=excluded.category,difficulty=excluded.difficulty,instructions=excluded.instructions,video_url=excluded.video_url,attachments=excluded.attachments,audience=excluded.audience,status=excluded.status,duration_minutes=excluded.duration_minutes,plan_blocks=excluded.plan_blocks,updated_at=clock_timestamp()
   returning to_jsonb(pfd_resources) into result;
  delete from public.pfd_resource_clubs where resource_id=record_id;
  if payload->>'audience'='selected_clubs' then insert into public.pfd_resource_clubs(resource_id,club_id) select record_id,id from (select distinct unnest(selected_clubs) id)x; end if;
  return result;

 elsif action in ('events_list','my_calendar') then
  if action='my_calendar' and not('events.view'=any(perms)) then raise exception 'Calendar permission is required.' using errcode='42501';end if;
  with filtered as(select e.*,(select count(*) from public.pfd_event_recipients er where er.event_id=e.id) as recipient_count,t.name as team_name from public.pfd_club_events e left join public.pfd_teams t on t.id=e.team_id
   where e.club_id=club and (coalesce(payload->>'sessions_only','false')<>'true' or e.kind in ('training','game')) and (action='events_list' or exists(select 1 from public.pfd_event_recipients er where er.event_id=e.id and er.user_id=actor))
    and (coalesce(payload->>'kind','')='' or e.kind=payload->>'kind') and (coalesce(payload->>'team_id','')='' or e.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or e.starts_at>=(payload->>'from_date')::timestamptz)
    and(q='' or strpos(lower(e.title||' '||e.location),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from filtered order by starts_at,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
 elsif action in ('event_save','announcement_save','homework_save') then
  record_id:=(payload->>'id')::uuid;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,71));
  select coalesce(array_agg(value::uuid),'{}') into teams from jsonb_array_elements_text(coalesce(payload->'team_ids','[]'));
  select coalesce(array_agg(value),'{}') into roles from jsonb_array_elements_text(coalesce(payload->'role_keys','[]'));
  select coalesce(array_agg(value::uuid),'{}') into people from jsonb_array_elements_text(coalesce(payload->'user_ids','[]'));
  if exists(select 1 from unnest(teams) selected_id where not exists(select 1 from public.pfd_teams st where st.id=selected_id and st.club_id=club and st.status='active')) or exists(select 1 from unnest(roles) rk where rk not in ('member','club_admin','coach','player')) or exists(select 1 from unnest(people) selected_user where not exists(select 1 from public.pfd_club_memberships cm where cm.club_id=club and cm.user_id=selected_user)) then raise exception 'Choose teams, roles and people in this club.' using errcode='22023';end if;
  if action='event_save' and payload->>'kind'<>'event' then
   team:=(payload->>'team_id')::uuid;
   if team is null or not exists(select 1 from public.pfd_teams st where st.id=team and st.club_id=club and st.status='active') then raise exception 'Training and games require a team in this club.' using errcode='22023';end if;
   teams:=array[team];roles:='{}';people:='{}';
  end if;
  if action='homework_save' then roles:=array['player'];end if;
  select coalesce(array_agg(user_id),'{}') into recipients from pfd_private.club_audience(club,teams,roles,people);
  if action='event_save' then
   select * into event_row from public.pfd_club_events where id=record_id for update;
   if found and (event_row.club_id<>club or event_row.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'Event changed or is outside this club. Reopen it.' using errcode='40001';end if;
   if not exists(select 1 from pg_catalog.pg_timezone_names where name=payload->>'timezone') then raise exception 'Choose a valid IANA timezone.' using errcode='22023';end if;
   select to_jsonb(r) into result from public.pfd_resources r where r.id=nullif(payload->>'plan_id','')::uuid and r.kind='training_plan' and r.status='published' and(r.club_id=club or(r.club_id is null and(r.audience='all_clubs' or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=club))));
   if nullif(payload->>'plan_id','') is not null and result is null then raise exception 'Choose a published training plan available to this club.' using errcode='22023';end if;
   if cardinality(recipients)=0 and payload->>'kind'='event' then raise exception 'Select at least one current event attendee.' using errcode='22023';end if;
   insert into public.pfd_club_events(id,club_id,team_id,kind,title,starts_at,ends_at,timezone,location,notes,plan_id,plan_snapshot,team_ids,role_keys,user_ids,status,created_by)
   values(record_id,club,team,payload->>'kind',btrim(payload->>'title'),(payload->>'starts_at')::timestamptz,(payload->>'ends_at')::timestamptz,payload->>'timezone',coalesce(payload->>'location',''),coalesce(payload->>'notes',''),nullif(payload->>'plan_id','')::uuid,result,teams,roles,people,coalesce(payload->>'status','scheduled'),actor)
   on conflict(id) do update set team_id=excluded.team_id,title=excluded.title,kind=excluded.kind,starts_at=excluded.starts_at,ends_at=excluded.ends_at,timezone=excluded.timezone,location=excluded.location,notes=excluded.notes,plan_id=excluded.plan_id,plan_snapshot=excluded.plan_snapshot,team_ids=excluded.team_ids,role_keys=excluded.role_keys,user_ids=excluded.user_ids,status=excluded.status,updated_at=clock_timestamp() returning to_jsonb(pfd_club_events) into result;
   delete from public.pfd_event_recipients where event_id=record_id and not(user_id=any(recipients));
   insert into public.pfd_event_recipients(event_id,user_id) select record_id,unnest(recipients) on conflict do nothing;
   return result;
  elsif action='announcement_save' then
   select * into post_row from public.pfd_announcements where id=record_id for update;
   if found and (post_row.club_id<>club or post_row.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'Announcement changed or is outside this club. Reopen it.' using errcode='40001';end if;
   if payload->>'status'='published' and cardinality(recipients)=0 then raise exception 'Select at least one current recipient.' using errcode='22023';end if;
   insert into public.pfd_announcements(id,club_id,title,body,team_ids,role_keys,user_ids,status,created_by) values(record_id,club,btrim(payload->>'title'),payload->>'body',teams,roles,people,payload->>'status',actor)
   on conflict(id) do update set title=excluded.title,body=excluded.body,team_ids=excluded.team_ids,role_keys=excluded.role_keys,user_ids=excluded.user_ids,status=excluded.status,updated_at=clock_timestamp() returning to_jsonb(pfd_announcements) into result;
   delete from public.pfd_announcement_recipients where announcement_id=record_id;
   if payload->>'status'='published' then insert into public.pfd_announcement_recipients(announcement_id,user_id) select record_id,unnest(recipients);end if;
   return result;
  else
   select * into hw from public.pfd_homework where id=record_id for update;
   if found and (hw.club_id<>club or hw.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'Homework changed or is outside this club. Reopen it.' using errcode='40001';end if;
   if cardinality(recipients)=0 then raise exception 'Choose at least one player or a team with players.' using errcode='22023';end if;
   select to_jsonb(r) into result from public.pfd_resources r where r.id=nullif(payload->>'resource_id','')::uuid and r.kind='individual_drill' and r.status='published' and(r.club_id=club or(r.club_id is null and(r.audience='all_clubs' or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=club))));
   if nullif(payload->>'resource_id','') is not null and result is null then raise exception 'Choose a published individual drill available to this club.' using errcode='22023';end if;
   if exists(select 1 from public.pfd_homework_submissions sub where sub.homework_id=record_id and not(sub.user_id=any(recipients))) then raise exception 'Keep players who have already submitted in this assignment.' using errcode='22023';end if;
   insert into public.pfd_homework(id,club_id,title,instructions,resource_id,resource_snapshot,due_at,team_ids,user_ids,status,created_by) values(record_id,club,btrim(payload->>'title'),coalesce(payload->>'instructions',''),nullif(payload->>'resource_id','')::uuid,result,(payload->>'due_at')::timestamptz,teams,people,coalesce(payload->>'status','active'),actor)
   on conflict(id) do update set title=excluded.title,instructions=excluded.instructions,resource_id=excluded.resource_id,resource_snapshot=excluded.resource_snapshot,due_at=excluded.due_at,team_ids=excluded.team_ids,user_ids=excluded.user_ids,status=excluded.status,updated_at=clock_timestamp() returning to_jsonb(pfd_homework) into result;
   delete from public.pfd_homework_recipients where homework_id=record_id and not(user_id=any(recipients));
   insert into public.pfd_homework_recipients(homework_id,user_id)select record_id,unnest(recipients) on conflict do nothing;return result;
  end if;
 elsif action='event_detail' then
  select * into event_row from public.pfd_club_events where id=(payload->>'id')::uuid and club_id=club;
  if not found then raise exception 'Event not found.' using errcode='P0002';end if;
  return to_jsonb(event_row)||jsonb_build_object('attendees',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from(select p.id,p.name,p.email,er.response,a.status as attendance,a.notes from public.pfd_event_recipients er join public.pfd_profiles p on p.id=er.user_id left join public.pfd_attendance a on a.event_id=er.event_id and a.user_id=er.user_id where er.event_id=event_row.id)x));
 elsif action='attendance_save' then
  record_id:=(payload->>'event_id')::uuid;subject:=(payload->>'user_id')::uuid;
  if not exists(select 1 from public.pfd_club_events e join public.pfd_event_recipients er on er.event_id=e.id where e.id=record_id and e.club_id=club and er.user_id=subject) then raise exception 'Choose an attendee in this club event.' using errcode='22023';end if;
  insert into public.pfd_attendance(event_id,user_id,status,notes,marked_by)values(record_id,subject,payload->>'status',coalesce(payload->>'notes',''),actor)on conflict(event_id,user_id)do update set status=excluded.status,notes=excluded.notes,marked_by=actor,updated_at=clock_timestamp();return jsonb_build_object('ok',true);
 elsif action in ('announcements_list','my_announcements') then
  if action='my_announcements' and not('announcements.view'=any(perms)) then raise exception 'Announcement permission is required.' using errcode='42501';end if;
  with filtered as(select a.*,(select count(*) from public.pfd_announcement_recipients ar where ar.announcement_id=a.id) as recipient_count from public.pfd_announcements a where a.club_id=club and(action='announcements_list' or(a.status='published' and exists(select 1 from public.pfd_announcement_recipients ar where ar.announcement_id=a.id and ar.user_id=actor))) and(q='' or strpos(lower(a.title||' '||a.body),lower(q))>0) and(coalesce(payload->>'status','')='' or a.status=payload->>'status'))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select * from filtered order by created_at desc,id limit 20 offset offset_no)x),'total',(select count(*)from filtered),'page',page_no)into result;return result;
 elsif action in ('homework_list','my_homework') then
  if action='my_homework' and not('homework.view'=any(perms))then raise exception 'Homework permission is required.' using errcode='42501';end if;
  with filtered as(select h.*,(select count(*)from public.pfd_homework_recipients hr where hr.homework_id=h.id)as recipient_count,(select count(*)from public.pfd_homework_submissions hs where hs.homework_id=h.id)as submission_count,
    case when action='my_homework' then(select to_jsonb(hs)from public.pfd_homework_submissions hs where hs.homework_id=h.id and hs.user_id=actor)else null end as my_submission
   from public.pfd_homework h where h.club_id=club and(action='homework_list' or exists(select 1 from public.pfd_homework_recipients hr where hr.homework_id=h.id and hr.user_id=actor))and(q='' or strpos(lower(h.title),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select * from filtered order by due_at desc,id limit 20 offset offset_no)x),'total',(select count(*)from filtered),'page',page_no)into result;return result;
 elsif action='homework_detail' then
  select * into hw from public.pfd_homework where id=(payload->>'id')::uuid and club_id=club;
  if not found then raise exception 'Homework not found.' using errcode='P0002';end if;
  return to_jsonb(hw)||jsonb_build_object('players',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]')from(select p.id,p.name,p.email,s.id as submission_id,s.notes,s.attachments,s.feedback,s.review_status,s.created_at as submitted_at,s.updated_at from public.pfd_homework_recipients hr join public.pfd_profiles p on p.id=hr.user_id left join public.pfd_homework_submissions s on s.homework_id=hr.homework_id and s.user_id=hr.user_id where hr.homework_id=hw.id)x));
 elsif action='homework_review' then
  select s.* into submission from public.pfd_homework_submissions s join public.pfd_homework h on h.id=s.homework_id where s.id=(payload->>'id')::uuid and h.club_id=club for update of s;
  if not found then raise exception 'Submission not found.'using errcode='P0002';end if;
  if submission.updated_at is distinct from(payload->>'updated_at')::timestamptz then raise exception 'Submission changed. Reopen it.'using errcode='40001';end if;
  update public.pfd_homework_submissions set feedback=coalesce(payload->>'feedback',''),review_status=payload->>'review_status',reviewed_by=actor,updated_at=clock_timestamp()where id=submission.id;return jsonb_build_object('ok',true);
 elsif action in ('homework_upload_access','submit_homework') then
  select h.*into hw from public.pfd_homework h join public.pfd_homework_recipients hr on hr.homework_id=h.id where h.id=(payload->>'homework_id')::uuid and h.club_id=club and h.status='active' and hr.user_id=actor for share of h;
  if not found then raise exception 'This active homework is not assigned to you.'using errcode='42501';end if;
  if action='homework_upload_access' then return jsonb_build_object('bucket','pfd-club-files','prefix',club::text||'/homework/'||hw.id::text||'/'||actor::text||'/');end if;
  if jsonb_typeof(payload->'attachments')is distinct from'array' or jsonb_array_length(payload->'attachments')>3 then raise exception 'Choose up to three videos or supporting files.'using errcode='22023';end if;
  for item in select value from jsonb_array_elements(payload->'attachments')loop
   if not exists(select 1 from storage.objects o where o.bucket_id='pfd-club-files' and o.name=item->>'path' and o.name like club::text||'/homework/'||hw.id::text||'/'||actor::text||'/%')then raise exception 'An uploaded file is missing or not yours.'using errcode='22023';end if;
  end loop;
  select *into submission from public.pfd_homework_submissions where homework_id=hw.id and user_id=actor for update;
  if found and submission.updated_at is distinct from(payload->>'updated_at')::timestamptz then raise exception 'Submission changed. Refresh before editing.'using errcode='40001';end if;
  insert into public.pfd_homework_submissions(id,homework_id,user_id,notes,attachments)values((payload->>'id')::uuid,hw.id,actor,coalesce(payload->>'notes',''),payload->'attachments')on conflict(homework_id,user_id)do update set notes=excluded.notes,attachments=excluded.attachments,feedback='',review_status='submitted',reviewed_by=null,updated_at=clock_timestamp()returning to_jsonb(pfd_homework_submissions)into result;return result;
 elsif action in ('rooms_list','room_messages','send_message','room_save','team_chat') then
  if action='rooms_list' then
   return(select coalesce(jsonb_agg(to_jsonb(x)order by x.updated_at desc),'[]')from(select r.*,(select count(*)from public.pfd_chat_messages m where m.room_id=r.id)as message_count from public.pfd_chat_rooms r where r.club_id=club and r.status='active' and((r.team_id is null and exists(select 1 from public.pfd_chat_members cm where cm.room_id=r.id and cm.user_id=actor))or(r.team_id is not null and(is_admin or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.team_id=r.team_id and t.status='active' and m.user_id=actor)))))x);
  end if;
  if action='team_chat' then
   team:=(payload->>'team_id')::uuid;
   if not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active')then raise exception 'Choose an active team.'using errcode='22023';end if;
   insert into public.pfd_chat_rooms(id,club_id,team_id,title,created_by)select gen_random_uuid(),club,t.id,t.name||' · Team chat',actor from public.pfd_teams t where t.id=team on conflict(team_id)where team_id is not null do update set title=excluded.title returning to_jsonb(pfd_chat_rooms)into result;return result;
  end if;
  if action='room_save' then
   record_id:=(payload->>'id')::uuid;
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,72));
   select *into room from public.pfd_chat_rooms where id=record_id for update;
   if found and(room.club_id<>club or room.team_id is not null or not exists(select 1 from public.pfd_chat_members where room_id=room.id and user_id=actor)or room.updated_at is distinct from(payload->>'updated_at')::timestamptz)then raise exception 'Group changed or is not available to you.'using errcode='40001';end if;
   select coalesce(array_agg(distinct id),'{}')into people from(select value::uuid id from jsonb_array_elements_text(coalesce(payload->'user_ids','[]'))union select actor)x;
   if exists(select 1 from unnest(people) selected_user where not exists(select 1 from public.pfd_club_memberships cm where cm.club_id=club and cm.user_id=selected_user))then raise exception 'Choose approved club members only.'using errcode='22023';end if;
   insert into public.pfd_chat_rooms(id,club_id,title,created_by,status)values(record_id,club,btrim(payload->>'title'),actor,coalesce(payload->>'status','active'))on conflict(id)do update set title=excluded.title,status=excluded.status,updated_at=clock_timestamp()returning to_jsonb(pfd_chat_rooms)into result;
   delete from public.pfd_chat_members where room_id=record_id;
   insert into public.pfd_chat_members(room_id,user_id)select record_id,unnest(people);return result;
  end if;
  select *into room from public.pfd_chat_rooms where id=(payload->>'room_id')::uuid and club_id=club and status='active';
  if not found or not((room.team_id is null and exists(select 1 from public.pfd_chat_members where room_id=room.id and user_id=actor))or(room.team_id is not null and exists(select 1 from public.pfd_teams t where t.id=room.team_id and t.status='active')and(is_admin or exists(select 1 from public.pfd_team_memberships where team_id=room.team_id and user_id=actor))))then raise exception 'You are not a member of this conversation.'using errcode='42501';end if;
  if action='room_messages' then
   return jsonb_build_object('room',to_jsonb(room),'members',(select coalesce(jsonb_agg(user_id),'[]')from public.pfd_chat_members where room_id=room.id),
    'items',(select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at,x.id),'[]')from(select m.id,m.user_id,m.body,m.created_at,p.name from public.pfd_chat_messages m join public.pfd_profiles p on p.id=m.user_id where m.room_id=room.id order by m.created_at desc,m.id desc limit 50 offset ((page_no-1)*50))x),
    'has_more',(select count(*)>page_no*50 from public.pfd_chat_messages where room_id=room.id));
  end if;
  insert into public.pfd_chat_messages(id,room_id,user_id,body)values((payload->>'id')::uuid,room.id,actor,btrim(payload->>'body'));
  update public.pfd_chat_rooms set updated_at=clock_timestamp()where id=room.id;return jsonb_build_object('ok',true);
 elsif action in ('settings_get','settings_save') then
  if action='settings_get'then return(select to_jsonb(c)from public.pfd_clubs c where c.id=club);end if;
  update public.pfd_clubs set name=btrim(payload->>'name'),city=btrim(payload->>'city'),state=btrim(payload->>'state'),country=btrim(payload->>'country'),contact_email=lower(btrim(payload->>'contact_email')),contact_number=btrim(payload->>'contact_number'),league=btrim(payload->>'league'),sport=btrim(payload->>'sport'),description=coalesce(payload->>'description',''),location=concat_ws(', ',btrim(payload->>'city'),btrim(payload->>'state'),btrim(payload->>'country')),updated_at=clock_timestamp()
  where id=club and updated_at=(payload->>'updated_at')::timestamptz returning to_jsonb(pfd_clubs)into result;
  if result is null then raise exception 'Club details changed. Reload before saving.'using errcode='40001';end if;return result;
 elsif action in ('resource_file_access','file_access') then
  if action='resource_file_access' then
   select *into old_resource from public.pfd_resources r where r.id=(payload->>'resource_id')::uuid and(r.club_id=club or(r.club_id is null and r.status='published'and(r.audience='all_clubs'or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=club))));
   if not found or not exists(select 1 from jsonb_array_elements(old_resource.attachments)a where a->>'path'=payload->>'path')then raise exception 'File is not available in this club resource.'using errcode='42501';end if;
   return jsonb_build_object('bucket',case when old_resource.club_id is null then 'pfd-development-resources'else'pfd-club-files'end,'path',payload->>'path');
  end if;
  select s.*into submission from public.pfd_homework_submissions s join public.pfd_homework h on h.id=s.homework_id where s.id=(payload->>'submission_id')::uuid and h.club_id=club;
  if not found or not(submission.user_id=actor or(is_admin and 'homework.review'=any(perms)))or not exists(select 1 from jsonb_array_elements(submission.attachments)a where a->>'path'=payload->>'path')then raise exception 'This submission file is not available to your account.'using errcode='42501';end if;
  return jsonb_build_object('bucket','pfd-club-files','path',payload->>'path');
 end if;
 raise exception 'Unknown club workspace action.'using errcode='22023';
end $$;
revoke all on function public.pfd_club_workspace(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pfd_club_workspace(uuid,uuid,text,jsonb)to service_role;
update public.pfd_permission_catalog set available=true where key in ('reports.view_team','reports.create','events.manage','events.view','homework.assign','homework.review','homework.view','homework.submit','library.view','library.manage_club','announcements.view','announcements.publish');


-- SOURCE: supabase/migrations/20261113054614_coach_workspace_library_levels.sql
-- Existing resources keep their global/club scope. New team resources require an actual club/team FK.
alter table public.pfd_resources add column team_id uuid,add column source_resource_id uuid references public.pfd_resources(id),add column source_updated_at timestamptz;
alter table public.pfd_resources add constraint pfd_resource_team_club_fk foreign key(team_id,club_id)references public.pfd_teams(id,club_id),add constraint pfd_resource_team_requires_club check(team_id is null or club_id is not null);
create index pfd_resource_team_idx on public.pfd_resources(team_id,club_id);
create index pfd_resource_source_idx on public.pfd_resources(source_resource_id);
create unique index pfd_resource_global_source_unique on public.pfd_resources(source_resource_id)where club_id is null and source_resource_id is not null;
create unique index pfd_resource_club_source_unique on public.pfd_resources(club_id,source_resource_id)where club_id is not null and team_id is null and source_resource_id is not null;
-- Title/kind duplicates are blocked in the curated global library. Preflight checks existing titles first.
create unique index pfd_resource_global_title_unique on public.pfd_resources(kind,lower(regexp_replace(btrim(title),'\s+',' ','g')))where club_id is null and status<>'archived';
insert into public.pfd_permission_catalog(key,category,label,description,available,owner_only,sort_order)values('library.manage_team','Development Library','Create team resources','Create and edit resources within approved coaching teams. Club sharing requires Club Admin; global publishing requires Owner.',true,false,33);
insert into public.pfd_role_permissions(role_key,permission_key,enabled)values('club_admin','library.manage_team',true),('coach','library.manage_team',true),('player','library.manage_team',false);
-- Club/team files are immutable signed uploads, so a source edit cannot overwrite an approved copy's files.
drop policy pfd_club_resource_files on storage.objects;
create policy pfd_owner_club_file_read on storage.objects for select to authenticated using(bucket_id='pfd-club-files' and exists(select 1 from public.pfd_platform_owners where user_id=(select auth.uid())));
create function pfd_private.resource_visible(r public.pfd_resources,c uuid,teams uuid[],admin boolean)returns boolean language sql stable security invoker set search_path=''as $$
 select (r.club_id is null and r.status='published' and(r.audience='all_clubs' or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=c))) or (r.club_id=c and(admin or(r.team_id is null and r.status='published')or r.team_id=any(teams)))
$$;
revoke all on function pfd_private.resource_visible(public.pfd_resources,uuid,uuid[],boolean)from public,anon,authenticated;
grant execute on function pfd_private.resource_visible(public.pfd_resources,uuid,uuid[],boolean)to service_role;
create function pfd_private.promote_resource(actor uuid,source_id uuid,destination_club uuid,expected_version text)returns jsonb language plpgsql security invoker set search_path=''as $$
declare src public.pfd_resources;approved public.pfd_resources;d public.pfd_resources;block jsonb;blocks jsonb:='[]';files jsonb;answer jsonb;
begin
 if current_user<>'service_role' and actor is distinct from auth.uid()then raise exception 'Verified actor required.'using errcode='42501';end if;
 if destination_club is null then
  if not exists(select 1 from public.pfd_platform_owners where user_id=actor)then raise exception 'Only the PFD Owner can publish globally.'using errcode='42501';end if;
 else
  if not exists(select 1 from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id where a.user_id=actor and a.club_id=destination_club and c.status='active')or not exists(select 1 from public.pfd_role_permissions where role_key='club_admin' and permission_key='library.manage_club' and enabled)then raise exception 'Club sharing requires its Club Administrator.'using errcode='42501';end if;
 end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(source_id::text||coalesce(destination_club::text,'global'),83));
 select *into src from public.pfd_resources where id=source_id for share;
 if not found or src.club_id is null or(destination_club is not null and(src.club_id<>destination_club or src.team_id is null))then raise exception 'Choose a local resource eligible for this destination.'using errcode='22023';end if;
 if src.updated_at is distinct from expected_version::timestamptz then raise exception 'Resource changed. Review it again before sharing.'using errcode='40001';end if;
 if src.status<>'published' then raise exception 'Review and publish the source locally before sharing it.'using errcode='22023';end if;
 if exists(select 1 from public.pfd_resources r where r.source_resource_id=source_id and r.club_id is not distinct from destination_club and r.team_id is null)then raise exception 'An approved copy already exists. Review that copy rather than duplicating it.'using errcode='23505';end if;
 if src.kind='training_plan'then
  for block in select value from jsonb_array_elements(src.plan_blocks)loop
   select *into d from public.pfd_resources where id=(block->>'resource_id')::uuid;
   if not found then raise exception 'An included drill is missing.'using errcode='22023';end if;
   if d.club_id is null and d.status='published' and d.audience='all_clubs'then approved:=d;
   elsif destination_club is not null and d.club_id=destination_club and d.team_id is null and d.status='published'then approved:=d;
   else
    select r.*into approved from public.pfd_resources r where r.status='published' and r.club_id is not distinct from destination_club and r.team_id is null and(r.source_resource_id=d.id or(destination_club is null and r.source_resource_id in(select id from public.pfd_resources where source_resource_id=d.id and team_id is null)))order by r.created_at limit 1;
    if not found then raise exception 'Approve each included drill at the destination level first, then share the training plan.'using errcode='22023';end if;
   end if;
   if destination_club is null and approved.audience<>'all_clubs'then raise exception 'Global plans require globally available drills.'using errcode='22023';end if;
   blocks:=blocks||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'resource_id',approved.id,'title',approved.title,'kind',approved.kind,'minutes',block->'minutes','instructions',approved.instructions,'video_url',approved.video_url,'attachments',approved.attachments));
  end loop;
 end if;
 select coalesce(jsonb_agg(a||jsonb_build_object('bucket',coalesce(a->>'bucket','pfd-club-files'))),'[]')into files from jsonb_array_elements(src.attachments)a;
 insert into public.pfd_resources(id,title,kind,category,difficulty,instructions,video_url,attachments,audience,status,created_by,duration_minutes,plan_blocks,club_id,team_id,source_resource_id,source_updated_at)
 values(gen_random_uuid(),src.title,src.kind,src.category,src.difficulty,src.instructions,src.video_url,files,case when destination_club is null then 'all_clubs'else'selected_clubs'end,'published',actor,src.duration_minutes,blocks,destination_club,null,src.id,src.updated_at)returning to_jsonb(pfd_resources)into answer;
 if destination_club is not null then insert into public.pfd_resource_clubs(resource_id,club_id)values((answer->>'id')::uuid,destination_club);end if;
 return answer;
end $$;
revoke all on function pfd_private.promote_resource(uuid,uuid,uuid,text)from public,anon;
grant usage on schema pfd_private to authenticated;
grant execute on function pfd_private.promote_resource(uuid,uuid,uuid,text)to authenticated,service_role;

create or replace function public.pfd_club_workspace(actor_id uuid,target_club uuid,action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor uuid:=actor_id;club uuid:=target_club;team uuid;subject uuid;record_id uuid;role_name text;state text;template text;
 result jsonb;definition jsonb;report_data jsonb;info jsonb;field_config jsonb;item jsonb;entry record;block jsonb;
 old_report public.pfd_reports;old_resource public.pfd_resources;drill public.pfd_resources;
 plan_minutes numeric;normalized_blocks jsonb:='[]';is_team boolean;selected_clubs uuid[];
 page_no integer:=coalesce((payload->>'page')::integer,1);page_size integer:=20;offset_no integer; q text:=btrim(coalesce(payload->>'query',''));
 is_admin boolean;is_coach boolean;coach_teams uuid[];resource_team uuid;perms text[];required_key text;teams uuid[];roles text[];people uuid[];recipients uuid[];
 event_row public.pfd_club_events;post_row public.pfd_announcements;hw public.pfd_homework;submission public.pfd_homework_submissions;room public.pfd_chat_rooms;
begin
 if actor is null or exists(select 1 from public.pfd_platform_owners where user_id=actor) then raise exception 'Use your separate club account.' using errcode='42501';end if;
 perform 1 from public.pfd_clubs where id=club and status='active' for share;
 if not found or not exists(select 1 from public.pfd_club_memberships where club_id=club and user_id=actor) then raise exception 'Approved access to this active club is required.' using errcode='42501';end if;
 select exists(select 1 from public.pfd_club_admins where club_id=club and user_id=actor) into is_admin;
 select coalesce(array_agg(t.id),'{}')into coach_teams from public.pfd_teams t join public.pfd_team_memberships m on m.team_id=t.id where t.club_id=club and t.status='active' and m.user_id=actor and m.role_key='coach';
 is_coach:=not is_admin and cardinality(coach_teams)>0;
 select coalesce(array_agg(distinct p.permission_key),'{}') into perms from public.pfd_role_permissions p where p.enabled and (
  (is_admin and p.role_key='club_admin') or (not is_admin and (not is_coach or p.role_key='coach') and exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=actor and m.role_key=p.role_key and t.club_id=club and t.status='active')));
 if not is_admin and not is_coach and action not in ('my_context','my_calendar','my_homework','my_announcements','homework_upload_access','submit_homework','rooms_list','room_messages','send_message','file_access') then raise exception 'Club Administrator access is required.' using errcode='42501';end if;
 if is_coach and action in ('settings_get','settings_save')then raise exception 'Club settings require a Club Administrator.'using errcode='42501';end if;
 if is_admin and not ('clubs.view'=any(perms)) then raise exception 'View club permission is required.' using errcode='42501';end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>180000 or page_no not between 1 and 100000 or length(q)>160 then raise exception 'Invalid workspace request.' using errcode='22023';end if;
 offset_no:=(page_no-1)*20;
 required_key:=case
 when action in ('users_list','people_list','person_detail') then 'members.view'
 when action in ('reports_list','report_get') then 'reports.view_team'
 when action='report_save' then 'reports.create'
 when action in ('resources_list','drill_catalog','resource_file_access') then 'library.view'
 when action in ('resource_save','resource_upload_access') then case when is_coach then 'library.manage_team' else 'library.manage_club' end
 when action='resource_share_club' then 'library.manage_club'
 when action in ('events_list','event_detail') then 'events.view'
 when action in ('event_save','attendance_save') then 'events.manage'
 when action='homework_list' then 'homework.view'
 when action='homework_save' then 'homework.assign'
 when action in ('homework_detail','homework_review') then 'homework.review'
 when action in ('homework_upload_access','submit_homework') then 'homework.submit'
 when action='announcements_list' then 'announcements.view'
 when action='announcement_save' then 'announcements.publish'
 when action in ('rooms_list','room_messages','send_message') then 'chats.view'
 when action='room_save' then 'chats.manage' when action='team_chat' then 'chats.view'
 when action='settings_get' then 'clubs.view'
 when action='settings_save' then 'clubs.edit' else null end;
 if required_key is not null and not(required_key=any(perms)) then raise exception 'Your role does not have permission for this action.' using errcode='42501';end if;
 if action='my_context' then return jsonb_build_object('workspace_role',case when is_admin then 'club_admin'else'coach'end,'permissions',to_jsonb(perms));end if;
 if action in ('options','users_list','people_list','person_detail','stats') then
  if action='options' then return jsonb_build_object(
   'clubs',(select jsonb_build_array(jsonb_build_object('id',c.id,'name',c.name,'status',c.status)) from public.pfd_clubs c where c.id=club),
   'teams',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name),'[]') from (select id,name,club_id,age_group,season,status from public.pfd_teams where club_id=club and status='active' and(not is_coach or id=any(coach_teams)))t),
   'templates',(select jsonb_agg(to_jsonb(t) order by t.key) from public.pfd_report_templates t),
   'people',case when 'members.view'=any(perms) then (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select p.id,p.name,p.email,
      array_remove(array[case when exists(select 1 from public.pfd_club_admins a where a.club_id=club and a.user_id=p.id) then 'club_admin' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and(not is_coach or t.id=any(coach_teams)) and m.user_id=p.id and m.role_key='coach') then 'coach' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and(not is_coach or t.id=any(coach_teams)) and m.user_id=p.id and m.role_key='player') then 'player' end],null) as roles
    from public.pfd_profiles p join public.pfd_club_memberships cm on cm.user_id=p.id and cm.club_id=club where (coalesce(payload->>'team_id','')='' or exists(select 1 from public.pfd_team_memberships filter_member where filter_member.user_id=p.id and filter_member.team_id=(payload->>'team_id')::uuid)) and (not is_coach or exists(select 1 from public.pfd_team_memberships sm where sm.user_id=p.id and sm.team_id=any(coach_teams))) and not exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) order by p.name limit 2000)x) else '[]'::jsonb end,
   'permissions',to_jsonb(perms));end if;
  if action='stats' then return jsonb_build_object(
   'awaiting_review',case when 'homework.review'=any(perms) then(select count(*)from public.pfd_homework_submissions hs join public.pfd_homework h on h.id=hs.homework_id where h.club_id=club and h.status='active' and hs.review_status='submitted' and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams)))else null end,
   'reports',case when 'reports.view_team'=any(perms) then (select count(*) from public.pfd_reports where club_id=club and(not is_coach or team_id=any(coach_teams)) and status='submitted') else null end,
   'requests',case when 'members.approve'=any(perms) or 'coaches.approve'=any(perms) or 'players.approve'=any(perms) then (select count(*) from public.pfd_access_requests where club_id=club and status='pending' and role_key<>'club_admin' and(not is_coach or (team_id=any(coach_teams) and role_key='player'))) else null end,
   'sessions',case when 'events.view'=any(perms) then (select count(*) from public.pfd_club_events where club_id=club and(not is_coach or team_id=any(coach_teams)) and status='scheduled' and starts_at>=now()) else null end,
   'homework',case when 'homework.view'=any(perms) then (select count(*) from public.pfd_homework where club_id=club and(not is_coach or (cardinality(team_ids)>0 and team_ids<@coach_teams)) and status='active') else null end);end if;
  if action='person_detail' then
   subject:=(payload->>'id')::uuid;
   if not exists(select 1 from public.pfd_club_memberships where club_id=club and user_id=subject) or (is_coach and not exists(select 1 from public.pfd_team_memberships sm where sm.user_id=subject and sm.team_id=any(coach_teams))) then raise exception 'Person not found in this club.' using errcode='P0002';end if;
   return jsonb_build_object('profile',(select jsonb_build_object('id',p.id,'name',p.name,'email',p.email,'created_at',p.created_at) from public.pfd_profiles p where p.id=subject),
    'teams',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select t.id,t.name,t.season,t.status,m.role_key from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and(not is_coach or t.id=any(coach_teams)) and m.user_id=subject)x),
    'reports',case when 'reports.view_team'=any(perms) then (select coalesce(jsonb_agg(to_jsonb(x) order by x.report_date),'[]') from (select id,template_key,report_date,status,data from public.pfd_reports where club_id=club and(not is_coach or team_id=any(coach_teams)) and status='submitted' and (subject_id=subject or coalesce(data->'team_ratings','{}') ? subject::text) order by report_date desc,created_at desc limit 100)x) else '[]'::jsonb end);
  end if;
  with people_rows as(select p.id,p.name,p.email,p.created_at,null::timestamptz as last_sign_in_at,
    array_remove(array[case when exists(select 1 from public.pfd_club_admins a where a.club_id=club and a.user_id=p.id) then 'club_admin' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and(not is_coach or t.id=any(coach_teams)) and m.user_id=p.id and m.role_key='coach') then 'coach' end,case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where t.club_id=club and t.status='active' and(not is_coach or t.id=any(coach_teams)) and m.user_id=p.id and m.role_key='player') then 'player' end],null) as roles
   from public.pfd_profiles p join public.pfd_club_memberships cm on cm.user_id=p.id and cm.club_id=club where (coalesce(payload->>'team_id','')='' or exists(select 1 from public.pfd_team_memberships filter_member where filter_member.user_id=p.id and filter_member.team_id=(payload->>'team_id')::uuid)) and (not is_coach or exists(select 1 from public.pfd_team_memberships sm where sm.user_id=p.id and sm.team_id=any(coach_teams))) and not exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) and(q='' or strpos(lower(p.name||' '||p.email),lower(q))>0)),
  filtered as(select pr.* from people_rows pr where coalesce(payload->>'role','')='' or (payload->>'role'='member' and cardinality(pr.roles)=0) or payload->>'role'=any(pr.roles))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from filtered order by name,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
 elsif action='team_roster' then
  if not ('reports.create'=any(perms) or 'reports.view_team'=any(perms)) or not('members.view'=any(perms)) then raise exception 'Report and member permissions are required.' using errcode='42501';end if;
  return(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select p.id,p.name,p.email from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_profiles p on p.id=m.user_id where t.id=(payload->>'team_id')::uuid and t.club_id=club and t.status='active' and(not is_coach or t.id=any(coach_teams)) and m.role_key='player')x);
 elsif action='drill_catalog' then
  return(select coalesce(jsonb_agg(to_jsonb(x) order by x.title),'[]') from(select id,title,kind,duration_minutes,status,category from public.pfd_resources r where r.kind in ('individual_drill','team_drill') and r.status<>'archived' and(not(payload?'team_id') or r.team_id is null or r.team_id=nullif(payload->>'team_id','')::uuid) and pfd_private.resource_visible(r,club,coach_teams,is_admin))x);
 elsif action='reports_list' then
  with filtered as (
   select r.id,r.subject_id,r.club_id,r.team_id,r.template_key,r.report_date,r.status,r.created_at,r.updated_at,coalesce(p.name,t.name,'Team match review') as subject_name,coalesce(p.email,'') as subject_email,c.name as club_name,t.name as team_name,a.name as author_name
   from public.pfd_reports r left join public.pfd_profiles p on p.id=r.subject_id left join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles a on a.id=r.created_by
   where r.club_id=target_club and(not is_coach or r.team_id=any(coach_teams)) and (q='' or strpos(lower(coalesce(p.name,'')||' '||coalesce(p.email,'')||' '||coalesce(t.name,'')||' '||coalesce(c.name,'')),lower(q))>0)
    and (coalesce(payload->>'template_key','')='' or r.template_key=payload->>'template_key')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
    and (coalesce(payload->>'team_id','')='' or r.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or r.report_date>=(payload->>'from_date')::date)
    and (coalesce(payload->>'to_date','')='' or r.report_date<=(payload->>'to_date')::date)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by report_date desc,created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'submitted',(select count(*) from public.pfd_reports where club_id=club and status='submitted' and(not is_coach or team_id=any(coach_teams))),'page',page_no) into result;
  return result;
 elsif action='report_get' then
  select to_jsonb(r) into result from public.pfd_reports r where id=(payload->>'id')::uuid and club_id=target_club and(not is_coach or team_id=any(coach_teams));
  if result is null then raise exception 'Report not found.' using errcode='P0002'; end if;
  return result;
 elsif action='report_save' then
  record_id:=(payload->>'id')::uuid;subject:=nullif(payload->>'subject_id','')::uuid;
  club:=target_club;team:=nullif(payload->>'team_id','')::uuid;
  if is_coach and (team is null or not(team=any(coach_teams)))then raise exception 'Choose one of your approved coaching teams.'using errcode='42501';end if;
  template:=payload->>'template_key';state:=payload->>'status';report_data:=payload->'data';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,42));
  select * into old_report from public.pfd_reports where id=record_id for update;
  if old_report.id is not null and (old_report.club_id is distinct from target_club or(is_coach and not coalesce(old_report.team_id=any(coach_teams),false))) then raise exception 'Report not found in this club.' using errcode='42501';end if;
  if found and (old_report.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'This report changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if old_report.id is not null and old_report.status<>'draft' then raise exception 'Submitted reports are read-only. Create a new report for the next assessment.' using errcode='22023'; end if;
  select t.definition into definition from public.pfd_report_templates t where t.key=template;
  if definition is null or state not in ('draft','submitted') or state is null or jsonb_typeof(report_data) is distinct from 'object' then raise exception 'Invalid report template or status.' using errcode='22023'; end if;
  is_team:=coalesce((definition->>'team_report')::boolean,false);
  if is_team then
   subject:=null;
   if state='submitted' and team is null then raise exception 'Select a team before submitting a match review.' using errcode='22023'; end if;
  elsif not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Choose an existing account for this report.' using errcode='22023'; end if;
  if club is not null and not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an active club.' using errcode='22023'; end if;
  if team is not null and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active') then raise exception 'Choose a team in this club.' using errcode='22023'; end if;
  if not is_team then
   role_name:=case when template='coaches' then coalesce(report_data->>'subject_kind','coach') else 'player' end;
   if role_name not in ('player','coach') or not exists(select 1 from public.pfd_team_memberships m join public.pfd_teams st on st.id=m.team_id join public.pfd_club_memberships cm on cm.club_id=st.club_id and cm.user_id=m.user_id where st.club_id=target_club and st.status='active' and m.user_id=subject and m.role_key=role_name and(team is null or m.team_id=team)) then raise exception 'Choose a player or coach account assigned to this club and team.' using errcode='22023';end if;
   report_data:=jsonb_set(report_data,'{subject_kind}',to_jsonb(role_name));
  else report_data:=jsonb_set(report_data,'{subject_kind}','"team"'::jsonb);end if;
  info:=report_data->'info';
  if jsonb_typeof(info) is distinct from 'object' or jsonb_typeof(report_data->'ratings') is distinct from 'object' or jsonb_typeof(report_data->'notes') is distinct from 'array' or jsonb_array_length(report_data->'notes')<>4 then raise exception 'Report sections are missing.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(info) loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid report detail.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'ratings') loop
   if jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (1,2,3,4,5) or not exists(
    select 1 from jsonb_each(definition->'categories') c cross join lateral jsonb_array_elements(c.value) with ordinality question where c.key||'-'||(question.ordinality-1)::text=entry.key
   ) then raise exception 'Ratings must match the original questions and use 1–5.' using errcode='22023'; end if;
  end loop;
  for item in select value from jsonb_array_elements(report_data->'notes') loop
   if jsonb_typeof(item)<>'string' or length(item#>>'{}')>6000 then raise exception 'Report notes must be text of at most 6000 characters.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(report_data->'extra') is distinct from 'object' or jsonb_typeof(report_data->'values') is distinct from 'object' or jsonb_typeof(report_data->'progress') is distinct from 'object' then raise exception 'Invalid report detail sections.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(report_data->'extra') loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid fitness test value.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'progress') loop
   if entry.key !~ '^[0-2]-[0-2]-[0-2]$' or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (0,1,2,3) then raise exception 'Invalid exercise progress marker.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'values') loop
   if jsonb_typeof(entry.value)<>'boolean' or not exists(select 1 from jsonb_each(definition->'behaviours') b cross join lateral jsonb_array_elements_text(b.value) v where v.value=entry.key) then raise exception 'Invalid player behaviour value.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(coalesce(report_data->'metrics','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(report_data->'team_ratings','{}'::jsonb))<>'object' then raise exception 'Invalid structured report data.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'metrics','{}'::jsonb)) loop
   select value into field_config from jsonb_array_elements(coalesce(definition->'fields','[]')) where value->>'key'=entry.key and value->>'type'='number';
   if field_config is null or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric < (field_config->>'min')::numeric or (entry.value#>>'{}')::numeric > (field_config->>'max')::numeric then raise exception 'A numeric report field is outside its allowed range.' using errcode='22023'; end if;
   if (field_config->>'step')::numeric=1 and mod((entry.value#>>'{}')::numeric,1)<>0 then raise exception 'Counts must be whole numbers.' using errcode='22023'; end if;
  end loop;
  if report_data->'metrics' ? 'shots' and report_data->'metrics' ? 'shots_on_target' and (report_data->'metrics'->>'shots_on_target')::numeric>(report_data->'metrics'->>'shots')::numeric then raise exception 'Shots on target cannot exceed shots.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'total_distance_m' and report_data->'metrics' ? 'high_speed_distance_m' and (report_data->'metrics'->>'high_speed_distance_m')::numeric>(report_data->'metrics'->>'total_distance_m')::numeric then raise exception 'High-speed distance cannot exceed total distance.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'top_speed_kmh' and report_data->'metrics' ? 'average_speed_kmh' and (report_data->'metrics'->>'average_speed_kmh')::numeric>(report_data->'metrics'->>'top_speed_kmh')::numeric then raise exception 'Average speed cannot exceed top speed.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'team_ratings','{}'::jsonb)) loop
   if not is_team or jsonb_typeof(entry.value->'rating') is distinct from 'number' or (entry.value->>'rating')::numeric not in (1,2,3,4,5) or not exists(select 1 from public.pfd_team_memberships m where m.team_id=team and m.user_id=entry.key::uuid and m.role_key='player') then raise exception 'Player ratings must be 1–5 and belong to this team roster.' using errcode='22023'; end if;
   report_data:=jsonb_set(report_data,array['team_ratings',entry.key,'name'],to_jsonb((select name from public.pfd_profiles where id=entry.key::uuid)));
  end loop;
  if length(coalesce(report_data->>'prepared_by',''))>250 or length(coalesce(report_data->>'reviewer',''))>250 then raise exception 'Report author details are too long.' using errcode='22023'; end if;
  if state='submitted' and (length(btrim(coalesce(info->>'name','')))=0 or length(btrim(coalesce(report_data->>'prepared_by','')))=0 or report_data->'consent' is distinct from 'true'::jsonb) then raise exception 'Complete the name, prepared-by field and submission consent.' using errcode='22023'; end if;
  insert into public.pfd_reports(id,subject_id,club_id,team_id,template_key,template_snapshot,report_date,status,data,created_by)
   values(record_id,subject,club,team,template,definition,(payload->>'report_date')::date,state,report_data,actor)
   on conflict(id) do update set subject_id=excluded.subject_id,club_id=excluded.club_id,team_id=excluded.team_id,template_key=excluded.template_key,template_snapshot=excluded.template_snapshot,report_date=excluded.report_date,status=excluded.status,data=excluded.data,updated_at=clock_timestamp()
   returning to_jsonb(pfd_reports) into result;
  return result;
 elsif action='resources_list' then
  with filtered as (
   select r.*, (r.club_id is null or(is_coach and r.team_id is null)) as read_only,(select coalesce(jsonb_agg(c.club_id),'[]') from public.pfd_resource_clubs c where c.resource_id=r.id) as club_ids from public.pfd_resources r
   where pfd_private.resource_visible(r,club,coach_teams,is_admin) and(coalesce(payload->>'scope','')='' or (payload->>'scope'='global' and r.club_id is null) or(payload->>'scope'='club' and r.club_id is not null and r.team_id is null)or(payload->>'scope'='team' and r.team_id is not null)) and (q='' or strpos(lower(r.title||' '||r.category||' '||r.instructions),lower(q))>0)
    and (coalesce(payload->>'kind','')='' or r.kind=payload->>'kind')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'difficulty','')='' or r.difficulty=payload->>'difficulty')
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by updated_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'published',(select count(*) from public.pfd_resources where club_id=target_club and status='published'),'page',page_no) into result;
  return result;
 elsif action='resource_share_club' then
  if not is_admin then raise exception 'Only Club Admin can share across a club.'using errcode='42501';end if;
  return pfd_private.promote_resource(actor,(payload->>'id')::uuid,club,payload->>'updated_at');
 elsif action='resource_upload_access' then
  resource_team:=nullif(payload->>'team_id','')::uuid;
  if resource_team is not null and not exists(select 1 from public.pfd_teams where id=resource_team and club_id=club and status='active')then raise exception 'Choose an active team.'using errcode='22023';end if;
  if is_coach and (resource_team is null or not(resource_team=any(coach_teams)))then raise exception 'Choose your coaching team.'using errcode='42501';end if;
  return jsonb_build_object('bucket','pfd-club-files','prefix',club::text||'/resources/'||coalesce(resource_team::text,'club')||'/');
 elsif action='resource_save' then
  record_id:=(payload->>'id')::uuid;resource_team:=nullif(payload->>'team_id','')::uuid;
  if resource_team is not null and not exists(select 1 from public.pfd_teams where id=resource_team and club_id=club and status='active')then raise exception 'Choose an active team.'using errcode='22023';end if;
  if is_coach and (resource_team is null or not(resource_team=any(coach_teams)))then raise exception 'Coaches create resources for their own teams only.'using errcode='42501';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,43));
  select * into old_resource from public.pfd_resources where id=record_id for update;
  if old_resource.id is not null and (old_resource.club_id is distinct from target_club or old_resource.team_id is distinct from resource_team) then raise exception 'Shared PFD resources are read-only.' using errcode='42501';end if;
  payload:=payload||jsonb_build_object('audience','selected_clubs','club_ids',jsonb_build_array(target_club));
  if found and old_resource.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This resource changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if coalesce(payload->>'video_url','')<>'' and payload->>'video_url' !~ '^https?://[^[:space:]]+$' then raise exception 'Use a valid http or https video link.' using errcode='22023'; end if;
  if jsonb_typeof(payload->'attachments') is distinct from 'array' or jsonb_array_length(payload->'attachments')>5 then raise exception 'A resource can have up to five files.' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(payload->'attachments') loop
   if jsonb_typeof(item) is distinct from 'object' or length(coalesce(item->>'name','')) not between 1 and 250 or length(coalesce(item->>'path','')) not between 1 and 350
    or not exists(select 1 from storage.objects o where o.bucket_id='pfd-club-files' and o.name=item->>'path' and (o.name like target_club::text||'/resources/'||coalesce(resource_team::text,'club')||'/%' or exists(select 1 from jsonb_array_elements(coalesce(old_resource.attachments,'[]')) kept where kept->>'path'=o.name))) then raise exception 'An attached file is missing. Upload it again.' using errcode='22023'; end if;
  end loop;
  payload:=jsonb_set(payload,'{attachments}',(select coalesce(jsonb_agg(a||jsonb_build_object('bucket','pfd-club-files')),'[]')from jsonb_array_elements(payload->'attachments')a));
  if jsonb_typeof(payload->'club_ids') is distinct from 'array' then raise exception 'Invalid club selection.' using errcode='22023'; end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into selected_clubs from jsonb_array_elements_text(payload->'club_ids');
  if payload->>'audience'='selected_clubs' and (cardinality(selected_clubs)=0 or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_clubs c where c.id=id and c.status='active'))) then raise exception 'Select at least one active club.' using errcode='22023'; end if;
  if payload->>'status'='published' and length(btrim(coalesce(payload->>'instructions','')))=0 then raise exception 'Add instructions before publishing.' using errcode='22023'; end if;
  plan_minutes:=0;
  if payload->>'kind' in ('individual_drill','team_drill') and (nullif(payload->>'duration_minutes','') is null or (payload->>'duration_minutes')::numeric not between 0.1 and 240) then raise exception 'Add an estimated drill duration between 0.1 and 240 minutes.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(payload->'plan_blocks','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(payload->'plan_blocks','[]'::jsonb))>100 then raise exception 'A plan can contain up to 100 drills.' using errcode='22023'; end if;
  if payload->>'kind'='training_plan' then
   if payload->>'status'='published' and coalesce(jsonb_array_length(payload->'plan_blocks'),0)=0 then raise exception 'Add at least one drill before publishing a training plan.' using errcode='22023'; end if;
   for block in select value from jsonb_array_elements(coalesce(payload->'plan_blocks','[]'::jsonb)) loop
    select r.* into drill from public.pfd_resources r where r.id=(block->>'resource_id')::uuid and r.kind in ('individual_drill','team_drill') and pfd_private.resource_visible(r,club,coach_teams,is_admin) and (r.team_id is null or r.team_id=resource_team);
    if not found or (payload->>'status'='published' and drill.status<>'published') then raise exception 'Use available drills; published plans require published drills.' using errcode='22023'; end if;
    if jsonb_typeof(block->'minutes') is distinct from 'number' or (block->>'minutes')::numeric not between 0.1 and 240 then raise exception 'Set a valid duration for each plan drill.' using errcode='22023'; end if;
    if payload->>'status'='published' and drill.audience='selected_clubs' and (payload->>'audience'='all_clubs' or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=drill.id and rc.club_id=id))) then raise exception 'A plan cannot be shared more widely than its included drills.' using errcode='22023'; end if;
    normalized_blocks:=normalized_blocks||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'resource_id',drill.id,'title',drill.title,'kind',drill.kind,'minutes',(block->>'minutes')::numeric,'instructions',drill.instructions,'video_url',drill.video_url,'attachments',drill.attachments));
    plan_minutes:=plan_minutes+(block->>'minutes')::numeric;
   end loop;
  end if;
  insert into public.pfd_resources(id,title,kind,category,difficulty,instructions,video_url,attachments,audience,status,created_by,duration_minutes,plan_blocks,club_id,team_id)
   values(record_id,btrim(payload->>'title'),payload->>'kind',btrim(coalesce(payload->>'category','')),payload->>'difficulty',coalesce(payload->>'instructions',''),coalesce(payload->>'video_url',''),payload->'attachments',payload->>'audience',payload->>'status',actor,case when payload->>'kind'='training_plan' then null else nullif(payload->>'duration_minutes','')::numeric end,case when payload->>'kind'='training_plan' then normalized_blocks else '[]'::jsonb end,target_club,resource_team)
   on conflict(id) do update set title=excluded.title,kind=excluded.kind,category=excluded.category,difficulty=excluded.difficulty,instructions=excluded.instructions,video_url=excluded.video_url,attachments=excluded.attachments,audience=excluded.audience,status=excluded.status,duration_minutes=excluded.duration_minutes,plan_blocks=excluded.plan_blocks,updated_at=clock_timestamp()
   returning to_jsonb(pfd_resources) into result;
  delete from public.pfd_resource_clubs where resource_id=record_id;
  if payload->>'audience'='selected_clubs' then insert into public.pfd_resource_clubs(resource_id,club_id) select record_id,id from (select distinct unnest(selected_clubs) id)x; end if;
  return result;

 elsif action in ('events_list','my_calendar') then
  if action='my_calendar' and not('events.view'=any(perms)) then raise exception 'Calendar permission is required.' using errcode='42501';end if;
  with filtered as(select e.*,(select count(*) from public.pfd_event_recipients er where er.event_id=e.id) as recipient_count,t.name as team_name from public.pfd_club_events e left join public.pfd_teams t on t.id=e.team_id
   where e.club_id=club and(action='my_calendar' or not is_coach or e.team_id=any(coach_teams)) and (coalesce(payload->>'sessions_only','false')<>'true' or e.kind in ('training','game')) and (action='events_list' or exists(select 1 from public.pfd_event_recipients er where er.event_id=e.id and er.user_id=actor))
    and (coalesce(payload->>'kind','')='' or e.kind=payload->>'kind') and (coalesce(payload->>'team_id','')='' or e.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or e.starts_at>=(payload->>'from_date')::timestamptz)
    and(q='' or strpos(lower(e.title||' '||e.location),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from filtered order by starts_at,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
 elsif action in ('event_save','announcement_save','homework_save') then
  record_id:=(payload->>'id')::uuid;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,71));
  select coalesce(array_agg(value::uuid),'{}') into teams from jsonb_array_elements_text(coalesce(payload->'team_ids','[]'));
  select coalesce(array_agg(value),'{}') into roles from jsonb_array_elements_text(coalesce(payload->'role_keys','[]'));
  select coalesce(array_agg(value::uuid),'{}') into people from jsonb_array_elements_text(coalesce(payload->'user_ids','[]'));
  if exists(select 1 from unnest(teams) selected_id where not exists(select 1 from public.pfd_teams st where st.id=selected_id and st.club_id=club and st.status='active')) or exists(select 1 from unnest(roles) rk where rk not in ('member','club_admin','coach','player')) or exists(select 1 from unnest(people) selected_user where not exists(select 1 from public.pfd_club_memberships cm where cm.club_id=club and cm.user_id=selected_user)) then raise exception 'Choose teams, roles and people in this club.' using errcode='22023';end if;
  if is_coach then
   if action='event_save' and (payload->>'kind'='event' or not coalesce((payload->>'team_id')::uuid=any(coach_teams),false))then raise exception 'Coaches schedule training and games for their teams.'using errcode='42501';end if;
   if action<>'event_save' and (cardinality(teams)=0 or not(teams<@coach_teams))then raise exception 'Select only your approved coaching teams.'using errcode='42501';end if;
   if action='announcement_save' and (cardinality(roles)>0 or cardinality(people)>0)then raise exception 'Coach announcements target their teams only.'using errcode='42501';end if;
   if exists(select 1 from unnest(people) p where not exists(select 1 from public.pfd_team_memberships m where m.user_id=p and m.team_id=any(teams)))then raise exception 'Choose players in the selected teams.'using errcode='42501';end if;
  end if;
  if action='event_save' and payload->>'kind'<>'event' then
   team:=(payload->>'team_id')::uuid;
   if team is null or not exists(select 1 from public.pfd_teams st where st.id=team and st.club_id=club and st.status='active') then raise exception 'Training and games require a team in this club.' using errcode='22023';end if;
   teams:=array[team];roles:='{}';people:='{}';
  end if;
  if action='homework_save' then roles:=array['player'];end if;
  select coalesce(array_agg(user_id),'{}') into recipients from pfd_private.club_audience(club,teams,roles,people);
  if action='event_save' then
   select * into event_row from public.pfd_club_events where id=record_id for update;
   if found and (event_row.club_id<>club or(is_coach and not coalesce(event_row.team_id=any(coach_teams),false)) or event_row.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'Event changed or is outside this club. Reopen it.' using errcode='40001';end if;
   if not exists(select 1 from pg_catalog.pg_timezone_names where name=payload->>'timezone') then raise exception 'Choose a valid IANA timezone.' using errcode='22023';end if;
   select to_jsonb(r) into result from public.pfd_resources r where r.id=nullif(payload->>'plan_id','')::uuid and r.kind='training_plan' and r.status='published' and pfd_private.resource_visible(r,club,coach_teams,is_admin) and(r.team_id is null or(cardinality(teams)=1 and r.team_id=teams[1]));
   if nullif(payload->>'plan_id','') is not null and result is null then raise exception 'Choose a published training plan available to this club.' using errcode='22023';end if;
   if cardinality(recipients)=0 and payload->>'kind'='event' then raise exception 'Select at least one current event attendee.' using errcode='22023';end if;
   insert into public.pfd_club_events(id,club_id,team_id,kind,title,starts_at,ends_at,timezone,location,notes,plan_id,plan_snapshot,team_ids,role_keys,user_ids,status,created_by)
   values(record_id,club,team,payload->>'kind',btrim(payload->>'title'),(payload->>'starts_at')::timestamptz,(payload->>'ends_at')::timestamptz,payload->>'timezone',coalesce(payload->>'location',''),coalesce(payload->>'notes',''),nullif(payload->>'plan_id','')::uuid,result,teams,roles,people,coalesce(payload->>'status','scheduled'),actor)
   on conflict(id) do update set team_id=excluded.team_id,title=excluded.title,kind=excluded.kind,starts_at=excluded.starts_at,ends_at=excluded.ends_at,timezone=excluded.timezone,location=excluded.location,notes=excluded.notes,plan_id=excluded.plan_id,plan_snapshot=excluded.plan_snapshot,team_ids=excluded.team_ids,role_keys=excluded.role_keys,user_ids=excluded.user_ids,status=excluded.status,updated_at=clock_timestamp() returning to_jsonb(pfd_club_events) into result;
   delete from public.pfd_event_recipients where event_id=record_id and not(user_id=any(recipients));
   insert into public.pfd_event_recipients(event_id,user_id) select record_id,unnest(recipients) on conflict do nothing;
   return result;
  elsif action='announcement_save' then
   select * into post_row from public.pfd_announcements where id=record_id for update;
   if found and (post_row.club_id<>club or(is_coach and (cardinality(post_row.team_ids)=0 or not(post_row.team_ids<@coach_teams) or cardinality(post_row.role_keys)>0 or cardinality(post_row.user_ids)>0)) or post_row.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'Announcement changed or is outside this club. Reopen it.' using errcode='40001';end if;
   if payload->>'status'='published' and cardinality(recipients)=0 then raise exception 'Select at least one current recipient.' using errcode='22023';end if;
   insert into public.pfd_announcements(id,club_id,title,body,team_ids,role_keys,user_ids,status,created_by) values(record_id,club,btrim(payload->>'title'),payload->>'body',teams,roles,people,payload->>'status',actor)
   on conflict(id) do update set title=excluded.title,body=excluded.body,team_ids=excluded.team_ids,role_keys=excluded.role_keys,user_ids=excluded.user_ids,status=excluded.status,updated_at=clock_timestamp() returning to_jsonb(pfd_announcements) into result;
   delete from public.pfd_announcement_recipients where announcement_id=record_id;
   if payload->>'status'='published' then insert into public.pfd_announcement_recipients(announcement_id,user_id) select record_id,unnest(recipients);end if;
   return result;
  else
   select * into hw from public.pfd_homework where id=record_id for update;
   if found and (hw.club_id<>club or(is_coach and(cardinality(hw.team_ids)=0 or not(hw.team_ids<@coach_teams))) or hw.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'Homework changed or is outside this club. Reopen it.' using errcode='40001';end if;
   if cardinality(recipients)=0 then raise exception 'Choose at least one player or a team with players.' using errcode='22023';end if;
   select to_jsonb(r) into result from public.pfd_resources r where r.id=nullif(payload->>'resource_id','')::uuid and r.kind='individual_drill' and r.status='published' and pfd_private.resource_visible(r,club,coach_teams,is_admin) and(r.team_id is null or(cardinality(teams)=1 and r.team_id=teams[1]));
   if nullif(payload->>'resource_id','') is not null and result is null then raise exception 'Choose a published individual drill available to this club.' using errcode='22023';end if;
   if exists(select 1 from public.pfd_homework_submissions sub where sub.homework_id=record_id and not(sub.user_id=any(recipients))) then raise exception 'Keep players who have already submitted in this assignment.' using errcode='22023';end if;
   insert into public.pfd_homework(id,club_id,title,instructions,resource_id,resource_snapshot,due_at,team_ids,user_ids,status,created_by) values(record_id,club,btrim(payload->>'title'),coalesce(payload->>'instructions',''),nullif(payload->>'resource_id','')::uuid,result,(payload->>'due_at')::timestamptz,teams,people,coalesce(payload->>'status','active'),actor)
   on conflict(id) do update set title=excluded.title,instructions=excluded.instructions,resource_id=excluded.resource_id,resource_snapshot=excluded.resource_snapshot,due_at=excluded.due_at,team_ids=excluded.team_ids,user_ids=excluded.user_ids,status=excluded.status,updated_at=clock_timestamp() returning to_jsonb(pfd_homework) into result;
   delete from public.pfd_homework_recipients where homework_id=record_id and not(user_id=any(recipients));
   insert into public.pfd_homework_recipients(homework_id,user_id)select record_id,unnest(recipients) on conflict do nothing;return result;
  end if;
 elsif action='event_detail' then
  select * into event_row from public.pfd_club_events where id=(payload->>'id')::uuid and club_id=club and(not is_coach or team_id=any(coach_teams));
  if not found then raise exception 'Event not found.' using errcode='P0002';end if;
  return to_jsonb(event_row)||jsonb_build_object('attendees',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from(select p.id,p.name,p.email,er.response,a.status as attendance,a.notes from public.pfd_event_recipients er join public.pfd_profiles p on p.id=er.user_id left join public.pfd_attendance a on a.event_id=er.event_id and a.user_id=er.user_id where er.event_id=event_row.id)x));
 elsif action='attendance_save' then
  record_id:=(payload->>'event_id')::uuid;subject:=(payload->>'user_id')::uuid;
  if not exists(select 1 from public.pfd_club_events e join public.pfd_event_recipients er on er.event_id=e.id where e.id=record_id and e.club_id=club and(not is_coach or e.team_id=any(coach_teams)) and er.user_id=subject) then raise exception 'Choose an attendee in this club event.' using errcode='22023';end if;
  insert into public.pfd_attendance(event_id,user_id,status,notes,marked_by)values(record_id,subject,payload->>'status',coalesce(payload->>'notes',''),actor)on conflict(event_id,user_id)do update set status=excluded.status,notes=excluded.notes,marked_by=actor,updated_at=clock_timestamp();return jsonb_build_object('ok',true);
 elsif action in ('announcements_list','my_announcements') then
  if action='my_announcements' and not('announcements.view'=any(perms)) then raise exception 'Announcement permission is required.' using errcode='42501';end if;
  with filtered as(select a.*,(select count(*) from public.pfd_announcement_recipients ar where ar.announcement_id=a.id) as recipient_count from public.pfd_announcements a where a.club_id=club and((action='announcements_list' and(not is_coach or(cardinality(a.team_ids)>0 and a.team_ids<@coach_teams))) or(a.status='published' and exists(select 1 from public.pfd_announcement_recipients ar where ar.announcement_id=a.id and ar.user_id=actor))) and(q='' or strpos(lower(a.title||' '||a.body),lower(q))>0) and(coalesce(payload->>'status','')='' or a.status=payload->>'status'))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select * from filtered order by created_at desc,id limit 20 offset offset_no)x),'total',(select count(*)from filtered),'page',page_no)into result;return result;
 elsif action in ('homework_list','my_homework') then
  if action='my_homework' and not('homework.view'=any(perms))then raise exception 'Homework permission is required.' using errcode='42501';end if;
  with filtered as(select h.*,(select count(*)from public.pfd_homework_recipients hr where hr.homework_id=h.id)as recipient_count,(select count(*)from public.pfd_homework_submissions hs where hs.homework_id=h.id)as submission_count,
    case when action='my_homework' then(select to_jsonb(hs)from public.pfd_homework_submissions hs where hs.homework_id=h.id and hs.user_id=actor)else null end as my_submission
   from public.pfd_homework h where h.club_id=club and((action='homework_list' and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams))) or (action='my_homework' and exists(select 1 from public.pfd_homework_recipients hr where hr.homework_id=h.id and hr.user_id=actor)))and(q='' or strpos(lower(h.title),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select * from filtered order by due_at desc,id limit 20 offset offset_no)x),'total',(select count(*)from filtered),'page',page_no)into result;return result;
 elsif action='homework_detail' then
  select * into hw from public.pfd_homework where id=(payload->>'id')::uuid and club_id=club and(not is_coach or(cardinality(team_ids)>0 and team_ids<@coach_teams));
  if not found then raise exception 'Homework not found.' using errcode='P0002';end if;
  return to_jsonb(hw)||jsonb_build_object('players',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]')from(select p.id,p.name,p.email,s.id as submission_id,s.notes,s.attachments,s.feedback,s.review_status,s.created_at as submitted_at,s.updated_at from public.pfd_homework_recipients hr join public.pfd_profiles p on p.id=hr.user_id left join public.pfd_homework_submissions s on s.homework_id=hr.homework_id and s.user_id=hr.user_id where hr.homework_id=hw.id)x));
 elsif action='homework_review' then
  select s.* into submission from public.pfd_homework_submissions s join public.pfd_homework h on h.id=s.homework_id where s.id=(payload->>'id')::uuid and h.club_id=club and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams)) for update of s;
  if not found then raise exception 'Submission not found.'using errcode='P0002';end if;
  if submission.updated_at is distinct from(payload->>'updated_at')::timestamptz then raise exception 'Submission changed. Reopen it.'using errcode='40001';end if;
  update public.pfd_homework_submissions set feedback=coalesce(payload->>'feedback',''),review_status=payload->>'review_status',reviewed_by=actor,updated_at=clock_timestamp()where id=submission.id;return jsonb_build_object('ok',true);
 elsif action in ('homework_upload_access','submit_homework') then
  select h.*into hw from public.pfd_homework h join public.pfd_homework_recipients hr on hr.homework_id=h.id where h.id=(payload->>'homework_id')::uuid and h.club_id=club and h.status='active' and hr.user_id=actor for share of h;
  if not found then raise exception 'This active homework is not assigned to you.'using errcode='42501';end if;
  if action='homework_upload_access' then return jsonb_build_object('bucket','pfd-club-files','prefix',club::text||'/homework/'||hw.id::text||'/'||actor::text||'/');end if;
  if jsonb_typeof(payload->'attachments')is distinct from'array' or jsonb_array_length(payload->'attachments')>3 then raise exception 'Choose up to three videos or supporting files.'using errcode='22023';end if;
  for item in select value from jsonb_array_elements(payload->'attachments')loop
   if not exists(select 1 from storage.objects o where o.bucket_id='pfd-club-files' and o.name=item->>'path' and o.name like club::text||'/homework/'||hw.id::text||'/'||actor::text||'/%')then raise exception 'An uploaded file is missing or not yours.'using errcode='22023';end if;
  end loop;
  select *into submission from public.pfd_homework_submissions where homework_id=hw.id and user_id=actor for update;
  if found and submission.updated_at is distinct from(payload->>'updated_at')::timestamptz then raise exception 'Submission changed. Refresh before editing.'using errcode='40001';end if;
  insert into public.pfd_homework_submissions(id,homework_id,user_id,notes,attachments)values((payload->>'id')::uuid,hw.id,actor,coalesce(payload->>'notes',''),payload->'attachments')on conflict(homework_id,user_id)do update set notes=excluded.notes,attachments=excluded.attachments,feedback='',review_status='submitted',reviewed_by=null,updated_at=clock_timestamp()returning to_jsonb(pfd_homework_submissions)into result;return result;
 elsif action in ('rooms_list','room_messages','send_message','room_save','team_chat') then
  if action='rooms_list' then
   return(select coalesce(jsonb_agg(to_jsonb(x)order by x.updated_at desc),'[]')from(select r.*,(select count(*)from public.pfd_chat_messages m where m.room_id=r.id)as message_count from public.pfd_chat_rooms r where r.club_id=club and r.status='active' and((r.team_id is null and exists(select 1 from public.pfd_chat_members cm where cm.room_id=r.id and cm.user_id=actor))or(r.team_id is not null and(is_admin or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.team_id=r.team_id and t.status='active' and m.user_id=actor)))))x);
  end if;
  if action='team_chat' then
   team:=(payload->>'team_id')::uuid;
   if not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active' and(not is_coach or id=any(coach_teams)))then raise exception 'Choose an active team.'using errcode='22023';end if;
   insert into public.pfd_chat_rooms(id,club_id,team_id,title,created_by)select gen_random_uuid(),club,t.id,t.name||' · Team chat',actor from public.pfd_teams t where t.id=team on conflict(team_id)where team_id is not null do update set title=excluded.title returning to_jsonb(pfd_chat_rooms)into result;return result;
  end if;
  if action='room_save' then
   record_id:=(payload->>'id')::uuid;
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,72));
   select *into room from public.pfd_chat_rooms where id=record_id for update;
   if found and(room.club_id<>club or room.team_id is not null or not exists(select 1 from public.pfd_chat_members where room_id=room.id and user_id=actor)or room.updated_at is distinct from(payload->>'updated_at')::timestamptz)then raise exception 'Group changed or is not available to you.'using errcode='40001';end if;
   select coalesce(array_agg(distinct id),'{}')into people from(select value::uuid id from jsonb_array_elements_text(coalesce(payload->'user_ids','[]'))union select actor)x;
   if exists(select 1 from unnest(people) selected_user where not exists(select 1 from public.pfd_club_memberships cm where cm.club_id=club and cm.user_id=selected_user and(not is_coach or exists(select 1 from public.pfd_team_memberships sm where sm.user_id=selected_user and sm.team_id=any(coach_teams)))))then raise exception 'Choose approved club members only.'using errcode='22023';end if;
   insert into public.pfd_chat_rooms(id,club_id,title,created_by,status)values(record_id,club,btrim(payload->>'title'),actor,coalesce(payload->>'status','active'))on conflict(id)do update set title=excluded.title,status=excluded.status,updated_at=clock_timestamp()returning to_jsonb(pfd_chat_rooms)into result;
   delete from public.pfd_chat_members where room_id=record_id;
   insert into public.pfd_chat_members(room_id,user_id)select record_id,unnest(people);return result;
  end if;
  select *into room from public.pfd_chat_rooms where id=(payload->>'room_id')::uuid and club_id=club and status='active';
  if not found or not((room.team_id is null and exists(select 1 from public.pfd_chat_members where room_id=room.id and user_id=actor))or(room.team_id is not null and exists(select 1 from public.pfd_teams t where t.id=room.team_id and t.status='active')and(is_admin or exists(select 1 from public.pfd_team_memberships where team_id=room.team_id and user_id=actor))))then raise exception 'You are not a member of this conversation.'using errcode='42501';end if;
  if action='room_messages' then
   return jsonb_build_object('room',to_jsonb(room),'members',(select coalesce(jsonb_agg(user_id),'[]')from public.pfd_chat_members where room_id=room.id),
    'items',(select coalesce(jsonb_agg(to_jsonb(x)order by x.created_at,x.id),'[]')from(select m.id,m.user_id,m.body,m.created_at,p.name from public.pfd_chat_messages m join public.pfd_profiles p on p.id=m.user_id where m.room_id=room.id order by m.created_at desc,m.id desc limit 50 offset ((page_no-1)*50))x),
    'has_more',(select count(*)>page_no*50 from public.pfd_chat_messages where room_id=room.id));
  end if;
  insert into public.pfd_chat_messages(id,room_id,user_id,body)values((payload->>'id')::uuid,room.id,actor,btrim(payload->>'body'));
  update public.pfd_chat_rooms set updated_at=clock_timestamp()where id=room.id;return jsonb_build_object('ok',true);
 elsif action in ('settings_get','settings_save') then
  if action='settings_get'then return(select to_jsonb(c)from public.pfd_clubs c where c.id=club);end if;
  update public.pfd_clubs set name=btrim(payload->>'name'),city=btrim(payload->>'city'),state=btrim(payload->>'state'),country=btrim(payload->>'country'),contact_email=lower(btrim(payload->>'contact_email')),contact_number=btrim(payload->>'contact_number'),league=btrim(payload->>'league'),sport=btrim(payload->>'sport'),description=coalesce(payload->>'description',''),location=concat_ws(', ',btrim(payload->>'city'),btrim(payload->>'state'),btrim(payload->>'country')),updated_at=clock_timestamp()
  where id=club and updated_at=(payload->>'updated_at')::timestamptz returning to_jsonb(pfd_clubs)into result;
  if result is null then raise exception 'Club details changed. Reload before saving.'using errcode='40001';end if;return result;
 elsif action in ('resource_file_access','file_access') then
  if action='resource_file_access' then
   select *into old_resource from public.pfd_resources r where r.id=(payload->>'resource_id')::uuid and pfd_private.resource_visible(r,club,coach_teams,is_admin);
   if not found or not exists(select 1 from jsonb_array_elements(old_resource.attachments)a where a->>'path'=payload->>'path')then raise exception 'File is not available in this club resource.'using errcode='42501';end if;
   return jsonb_build_object('bucket',coalesce((select a->>'bucket'from jsonb_array_elements(old_resource.attachments)a where a->>'path'=payload->>'path'),case when old_resource.club_id is null then 'pfd-development-resources'else'pfd-club-files'end),'path',payload->>'path');
  end if;
  select s.*into submission from public.pfd_homework_submissions s join public.pfd_homework h on h.id=s.homework_id where s.id=(payload->>'submission_id')::uuid and h.club_id=club;
  if not found or not(submission.user_id=actor or((is_admin or(is_coach and exists(select 1 from public.pfd_homework sh where sh.id=submission.homework_id and cardinality(sh.team_ids)>0 and sh.team_ids<@coach_teams))) and 'homework.review'=any(perms)))or not exists(select 1 from jsonb_array_elements(submission.attachments)a where a->>'path'=payload->>'path')then raise exception 'This submission file is not available to your account.'using errcode='42501';end if;
  return jsonb_build_object('bucket','pfd-club-files','path',payload->>'path');
 end if;
 raise exception 'Unknown club workspace action.'using errcode='22023';
end $$;
revoke all on function public.pfd_club_workspace(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pfd_club_workspace(uuid,uuid,text,jsonb)to service_role;

create or replace function public.pfd_owner_workspace(action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 actor uuid:=auth.uid(); q text:=left(coalesce(payload->>'query',''),160);
 page_no integer:=coalesce((payload->>'page')::integer,1); page_size integer:=20;
 offset_no integer; result jsonb; item jsonb; definition jsonb; entry record;
 req public.pfd_access_requests; old_report public.pfd_reports; old_resource public.pfd_resources;
 record_id uuid; subject uuid; club uuid; team uuid; role_name text; state text; template text;
 info jsonb; report_data jsonb; field_config jsonb; block jsonb; drill public.pfd_resources; plan_minutes numeric; normalized_blocks jsonb:='[]'::jsonb; is_team boolean; revision_time timestamptz; selected_clubs uuid[];
begin
 if not exists(select 1 from public.pfd_platform_owners o where o.user_id=actor) then
  raise exception 'PFD Owner access is required.' using errcode='42501';
 end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>150000 or page_no not between 1 and 100000 then
  raise exception 'Invalid request.' using errcode='22023';
 end if;
 offset_no:=(page_no-1)*page_size;
 if action='options' then
  return jsonb_build_object(
   'clubs',(select coalesce(jsonb_agg(to_jsonb(c) order by c.name),'[]') from (select id,name,status from public.pfd_clubs order by name limit 1000)c),
   'teams',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name),'[]') from (select id,club_id,name,age_group,season,status from public.pfd_teams order by name limit 2000)t),
   'templates',(select jsonb_agg(to_jsonb(t) order by t.key) from public.pfd_report_templates t)
  );
 elsif action='team_roster' then
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (
   select p.id,p.name,p.email from public.pfd_team_memberships m join public.pfd_profiles p on p.id=m.user_id join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id
   where m.team_id=(payload->>'team_id')::uuid and m.role_key='player' and t.status='active' and c.status='active'
  )x);
 elsif action='drill_catalog' then
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.title),'[]') from (select id,title,kind,duration_minutes,status,category from public.pfd_resources where club_id is null and kind in ('individual_drill','team_drill') and status<>'archived' order by title limit 1000)x);
 elsif action='users_list' then
  with accounts as (
   select p.*,
    array_remove(array[
     case when exists(select 1 from public.pfd_platform_owners o where o.user_id=p.id) then 'owner' end,
     case when exists(select 1 from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id and c.status='active' where a.user_id=p.id) then 'club_admin' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='coach') then 'coach' end,
     case when exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id and t.status='active' join public.pfd_clubs c on c.id=t.club_id and c.status='active' where m.user_id=p.id and m.role_key='player') then 'player' end
    ],null) as roles,
    (select count(*) from public.pfd_reports r where (r.subject_id=p.id or coalesce(r.data->'team_ratings','{}'::jsonb) ? p.id::text) and r.status='submitted') as report_count
   from public.pfd_profiles p
   where (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0)
    and (coalesce(payload->>'club_id','')='' or exists(select 1 from public.pfd_club_memberships cm where cm.user_id=p.id and cm.club_id=(payload->>'club_id')::uuid) or exists(select 1 from public.pfd_club_admins a where a.user_id=p.id and a.club_id=(payload->>'club_id')::uuid)
      or exists(select 1 from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id where m.user_id=p.id and t.club_id=(payload->>'club_id')::uuid))
  ), filtered as(select * from accounts where coalesce(payload->>'role','')='' or (payload->>'role'='member' and cardinality(roles)=0) or payload->>'role'=any(roles))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),
   'total',(select count(*) from filtered),'total_accounts',(select count(*) from public.pfd_profiles),'page',page_no) into result;
  return result;
 elsif action='user_detail' then
  subject:=(payload->>'id')::uuid;
  if not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Account not found.' using errcode='P0002'; end if;
  return jsonb_build_object('profile',(select to_jsonb(p) from public.pfd_profiles p where p.id=subject),
   'is_owner',exists(select 1 from public.pfd_platform_owners o where o.user_id=subject),
   'memberships',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from (
    select a.club_id,c.name as club_name,null::uuid as team_id,null::text as team_name,'club_admin'::text as role_key,c.status,a.created_at from public.pfd_club_admins a join public.pfd_clubs c on c.id=a.club_id where a.user_id=subject
    union all select t.club_id,c.name,m.team_id,t.name,m.role_key,case when c.status='archived' then 'archived' else t.status end,m.created_at from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.user_id=subject
    union all select cm.club_id,c.name,null::uuid,null::text,'member',c.status,cm.created_at from public.pfd_club_memberships cm join public.pfd_clubs c on c.id=cm.club_id where cm.user_id=subject and not exists(select 1 from public.pfd_club_admins ca where ca.club_id=cm.club_id and ca.user_id=subject)
   )m),
   'report_count',(select count(*) from public.pfd_reports where (subject_id=subject or coalesce(data->'team_ratings','{}'::jsonb) ? subject::text) and status='submitted'),
   'created_reports',(select count(*) from public.pfd_reports where created_by=subject and status='submitted'),
   'pending_requests',(select count(*) from public.pfd_access_requests where user_id=subject and status='pending'),
   'recent_reports',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (select id,template_key,report_date,status from public.pfd_reports where (subject_id=subject or coalesce(data->'team_ratings','{}'::jsonb) ? subject::text) order by report_date desc,created_at desc limit 10)r)
  );
 elsif action='requests_list' then
  with filtered as (
   select r.*,p.name,p.email,c.name as club_name,t.name as team_name,reviewer.name as reviewer_name from public.pfd_access_requests r
   join public.pfd_profiles p on p.id=r.user_id join public.pfd_clubs c on c.id=r.club_id
   left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles reviewer on reviewer.id=r.reviewed_by
   where (coalesce(payload->>'status','')='' or r.status=payload->>'status')
   and (coalesce(payload->>'role','')='' or r.role_key=payload->>'role')
   and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
   and (q='' or strpos(lower(p.name||' '||p.email||' '||c.name),lower(q))>0)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'pending',(select count(*) from public.pfd_access_requests where status='pending'),'page',page_no) into result;
  return result;
 elsif action='request_create' then
  subject:=(payload->>'user_id')::uuid;club:=(payload->>'club_id')::uuid;team:=nullif(payload->>'team_id','')::uuid;role_name:=payload->>'role_key';
  if not exists(select 1 from public.pfd_profiles where id=subject) or not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an existing account and active club.' using errcode='22023'; end if;
  if role_name not in ('member','club_admin','coach','player') or role_name is null or (role_name in ('member','club_admin') and team is not null) or (role_name in ('coach','player') and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active')) then raise exception 'Choose a valid role and team for this club.' using errcode='22023'; end if;
  if exists(select 1 from public.pfd_club_admins where user_id=subject and club_id=club and role_name='club_admin') or exists(select 1 from public.pfd_team_memberships where user_id=subject and team_id=team and role_key=role_name) then raise exception 'This account already has the requested membership.' using errcode='22023'; end if;
  if role_name='member' and exists(select 1 from public.pfd_club_memberships where user_id=subject and club_id=club) then raise exception 'This account already belongs to the club.' using errcode='22023';end if;
  if role_name in ('coach','player') and not exists(select 1 from public.pfd_club_memberships where user_id=subject and club_id=club) then raise exception 'Approve club membership before requesting a team.' using errcode='22023';end if;
  insert into public.pfd_access_requests(user_id,club_id,team_id,role_key,message,created_by) values(subject,club,team,role_name,coalesce(payload->>'message',''),actor) returning id into record_id;
  return jsonb_build_object('id',record_id);
 elsif action='request_review' then
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid;
  if not found then raise exception 'Request not found.' using errcode='P0002';end if;
  -- Match direct team assignment's lock order: club, team, then request.
  if req.team_id is not null then perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id for update;end if;
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid for update;
  if not found then raise exception 'Request not found.' using errcode='P0002'; end if;
  if req.status<>'pending' then raise exception 'This request has already been reviewed. Refresh the list.' using errcode='40001'; end if;
  state:=payload->>'decision';
  if state not in ('approved','rejected') or state is null then raise exception 'Choose approve or reject.' using errcode='22023'; end if;
  if state='rejected' and length(btrim(coalesce(payload->>'reason','')))=0 then raise exception 'Add a reason for rejecting this request.' using errcode='22023'; end if;
  if state='approved' then
   -- Lock the parent status while granting membership to avoid archive/approval races.
   perform 1 from public.pfd_clubs where id=req.club_id and status='active' for share;
   if not found then raise exception 'Restore the club before approving access.' using errcode='22023'; end if;
   if not exists(select 1 from public.pfd_clubs c where c.id=req.club_id and length(btrim(c.city))>0 and length(btrim(c.state))>0 and length(btrim(c.country))>0 and length(btrim(c.contact_email))>0 and length(btrim(c.contact_number))>0 and length(btrim(c.league))>0 and length(btrim(c.sport))>0) then raise exception 'Complete the club details before approving access.' using errcode='22023'; end if;
   if req.role_key='member' then
    insert into public.pfd_club_memberships(club_id,user_id,approved_by) values(req.club_id,req.user_id,actor) on conflict do nothing;
   elsif req.role_key='club_admin' then
    insert into public.pfd_club_admins(club_id,user_id,granted_by) values(req.club_id,req.user_id,actor) on conflict do nothing;
   else
    if not exists(select 1 from public.pfd_club_memberships where club_id=req.club_id and user_id=req.user_id) then raise exception 'Approve club membership before team access.' using errcode='22023';end if;
    perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id and status='active' for share;
    if not found then raise exception 'Restore the team before approving access.' using errcode='22023'; end if;
    insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(req.team_id,req.user_id,req.role_key,actor) on conflict do nothing;
   end if;
  end if;
  update public.pfd_access_requests set status=state,reason=coalesce(payload->>'reason',''),reviewed_by=actor,reviewed_at=now() where id=req.id;
  return jsonb_build_object('ok',true);
 elsif action='reports_list' then
  with filtered as (
   select r.id,r.subject_id,r.club_id,r.team_id,r.template_key,r.report_date,r.status,r.created_at,r.updated_at,coalesce(p.name,t.name,'Team match review') as subject_name,coalesce(p.email,'') as subject_email,c.name as club_name,t.name as team_name,a.name as author_name
   from public.pfd_reports r left join public.pfd_profiles p on p.id=r.subject_id left join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles a on a.id=r.created_by
   where (q='' or strpos(lower(coalesce(p.name,'')||' '||coalesce(p.email,'')||' '||coalesce(t.name,'')||' '||coalesce(c.name,'')),lower(q))>0)
    and (coalesce(payload->>'template_key','')='' or r.template_key=payload->>'template_key')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'club_id','')='' or r.club_id=(payload->>'club_id')::uuid)
    and (coalesce(payload->>'team_id','')='' or r.team_id=(payload->>'team_id')::uuid)
    and (coalesce(payload->>'from_date','')='' or r.report_date>=(payload->>'from_date')::date)
    and (coalesce(payload->>'to_date','')='' or r.report_date<=(payload->>'to_date')::date)
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by report_date desc,created_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'submitted',(select count(*) from public.pfd_reports where status='submitted'),'page',page_no) into result;
  return result;
 elsif action='report_get' then
  select to_jsonb(r) into result from public.pfd_reports r where id=(payload->>'id')::uuid;
  if result is null then raise exception 'Report not found.' using errcode='P0002'; end if;
  return result;
 elsif action='report_save' then
  record_id:=(payload->>'id')::uuid;subject:=nullif(payload->>'subject_id','')::uuid;
  club:=nullif(payload->>'club_id','')::uuid;team:=nullif(payload->>'team_id','')::uuid;
  template:=payload->>'template_key';state:=payload->>'status';report_data:=payload->'data';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,42));
  select * into old_report from public.pfd_reports where id=record_id for update;
  if found and (old_report.updated_at is distinct from (payload->>'updated_at')::timestamptz) then raise exception 'This report changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if old_report.id is not null and old_report.status<>'draft' then raise exception 'Submitted reports are read-only. Create a new report for the next assessment.' using errcode='22023'; end if;
  select t.definition into definition from public.pfd_report_templates t where t.key=template;
  if definition is null or state not in ('draft','submitted') or state is null or jsonb_typeof(report_data) is distinct from 'object' then raise exception 'Invalid report template or status.' using errcode='22023'; end if;
  is_team:=coalesce((definition->>'team_report')::boolean,false);
  if is_team then
   subject:=null;
   if state='submitted' and team is null then raise exception 'Select a team before submitting a match review.' using errcode='22023'; end if;
  elsif not exists(select 1 from public.pfd_profiles where id=subject) then raise exception 'Choose an existing account for this report.' using errcode='22023'; end if;
  if club is not null and not exists(select 1 from public.pfd_clubs where id=club and status='active') then raise exception 'Choose an active club.' using errcode='22023'; end if;
  if team is not null and not exists(select 1 from public.pfd_teams where id=team and club_id=club and status='active') then raise exception 'Choose a team in this club.' using errcode='22023'; end if;
  info:=report_data->'info';
  if jsonb_typeof(info) is distinct from 'object' or jsonb_typeof(report_data->'ratings') is distinct from 'object' or jsonb_typeof(report_data->'notes') is distinct from 'array' or jsonb_array_length(report_data->'notes')<>4 then raise exception 'Report sections are missing.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(info) loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid report detail.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'ratings') loop
   if jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (1,2,3,4,5) or not exists(
    select 1 from jsonb_each(definition->'categories') c cross join lateral jsonb_array_elements(c.value) with ordinality question where c.key||'-'||(question.ordinality-1)::text=entry.key
   ) then raise exception 'Ratings must match the original questions and use 1–5.' using errcode='22023'; end if;
  end loop;
  for item in select value from jsonb_array_elements(report_data->'notes') loop
   if jsonb_typeof(item)<>'string' or length(item#>>'{}')>6000 then raise exception 'Report notes must be text of at most 6000 characters.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(report_data->'extra') is distinct from 'object' or jsonb_typeof(report_data->'values') is distinct from 'object' or jsonb_typeof(report_data->'progress') is distinct from 'object' then raise exception 'Invalid report detail sections.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(report_data->'extra') loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid fitness test value.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'progress') loop
   if entry.key !~ '^[0-2]-[0-2]-[0-2]$' or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (0,1,2,3) then raise exception 'Invalid exercise progress marker.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'values') loop
   if jsonb_typeof(entry.value)<>'boolean' or not exists(select 1 from jsonb_each(definition->'behaviours') b cross join lateral jsonb_array_elements_text(b.value) v where v.value=entry.key) then raise exception 'Invalid player behaviour value.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(coalesce(report_data->'metrics','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(report_data->'team_ratings','{}'::jsonb))<>'object' then raise exception 'Invalid structured report data.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'metrics','{}'::jsonb)) loop
   select value into field_config from jsonb_array_elements(coalesce(definition->'fields','[]')) where value->>'key'=entry.key and value->>'type'='number';
   if field_config is null or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric < (field_config->>'min')::numeric or (entry.value#>>'{}')::numeric > (field_config->>'max')::numeric then raise exception 'A numeric report field is outside its allowed range.' using errcode='22023'; end if;
   if (field_config->>'step')::numeric=1 and mod((entry.value#>>'{}')::numeric,1)<>0 then raise exception 'Counts must be whole numbers.' using errcode='22023'; end if;
  end loop;
  if report_data->'metrics' ? 'shots' and report_data->'metrics' ? 'shots_on_target' and (report_data->'metrics'->>'shots_on_target')::numeric>(report_data->'metrics'->>'shots')::numeric then raise exception 'Shots on target cannot exceed shots.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'total_distance_m' and report_data->'metrics' ? 'high_speed_distance_m' and (report_data->'metrics'->>'high_speed_distance_m')::numeric>(report_data->'metrics'->>'total_distance_m')::numeric then raise exception 'High-speed distance cannot exceed total distance.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'top_speed_kmh' and report_data->'metrics' ? 'average_speed_kmh' and (report_data->'metrics'->>'average_speed_kmh')::numeric>(report_data->'metrics'->>'top_speed_kmh')::numeric then raise exception 'Average speed cannot exceed top speed.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'team_ratings','{}'::jsonb)) loop
   if not is_team or jsonb_typeof(entry.value->'rating') is distinct from 'number' or (entry.value->>'rating')::numeric not in (1,2,3,4,5) or not exists(select 1 from public.pfd_team_memberships m where m.team_id=team and m.user_id=entry.key::uuid and m.role_key='player') then raise exception 'Player ratings must be 1–5 and belong to this team roster.' using errcode='22023'; end if;
   report_data:=jsonb_set(report_data,array['team_ratings',entry.key,'name'],to_jsonb((select name from public.pfd_profiles where id=entry.key::uuid)));
  end loop;
  if length(coalesce(report_data->>'prepared_by',''))>250 or length(coalesce(report_data->>'reviewer',''))>250 then raise exception 'Report author details are too long.' using errcode='22023'; end if;
  if state='submitted' and (length(btrim(coalesce(info->>'name','')))=0 or length(btrim(coalesce(report_data->>'prepared_by','')))=0 or report_data->'consent' is distinct from 'true'::jsonb) then raise exception 'Complete the name, prepared-by field and submission consent.' using errcode='22023'; end if;
  insert into public.pfd_reports(id,subject_id,club_id,team_id,template_key,template_snapshot,report_date,status,data,created_by)
   values(record_id,subject,club,team,template,definition,(payload->>'report_date')::date,state,report_data,actor)
   on conflict(id) do update set subject_id=excluded.subject_id,club_id=excluded.club_id,team_id=excluded.team_id,template_key=excluded.template_key,template_snapshot=excluded.template_snapshot,report_date=excluded.report_date,status=excluded.status,data=excluded.data,updated_at=clock_timestamp()
   returning to_jsonb(pfd_reports) into result;
  return result;
 elsif action='resources_list' then
  with filtered as (
   select r.*,(r.club_id is not null)as read_only,(select name from public.pfd_clubs c where c.id=r.club_id)as club_name,(select name from public.pfd_teams t where t.id=r.team_id)as team_name,(select name from public.pfd_profiles p where p.id=r.created_by)as author_name,(select coalesce(jsonb_agg(c.club_id),'[]') from public.pfd_resource_clubs c where c.resource_id=r.id) as club_ids from public.pfd_resources r
   where (coalesce(payload->>'scope','')='' or(payload->>'scope'='global'and r.club_id is null)or(payload->>'scope'='club'and r.club_id is not null and r.team_id is null)or(payload->>'scope'='team'and r.team_id is not null)or(payload->>'scope'='local'and r.club_id is not null)) and (q='' or strpos(lower(r.title||' '||r.category||' '||r.instructions),lower(q))>0)
    and (coalesce(payload->>'kind','')='' or r.kind=payload->>'kind')
    and (coalesce(payload->>'status','')='' or r.status=payload->>'status')
    and (coalesce(payload->>'difficulty','')='' or r.difficulty=payload->>'difficulty')
  ) select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by updated_at desc,id limit page_size offset offset_no)x),'total',(select count(*) from filtered),'published',(select count(*) from public.pfd_resources where status='published'),'page',page_no) into result;
  return result;
 elsif action='resource_promote' then
  return pfd_private.promote_resource(actor,(payload->>'id')::uuid,null,payload->>'updated_at');
 elsif action='resource_save' then
  record_id:=(payload->>'id')::uuid;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,43));
  select * into old_resource from public.pfd_resources where id=record_id for update;
  if old_resource.club_id is not null then raise exception 'Review local resources and approve a global copy. Edit the source from its club workspace.'using errcode='42501';end if;
  if found and old_resource.updated_at is distinct from (payload->>'updated_at')::timestamptz then raise exception 'This resource changed elsewhere. Reopen it before saving.' using errcode='40001'; end if;
  if coalesce(payload->>'video_url','')<>'' and payload->>'video_url' !~ '^https?://[^[:space:]]+$' then raise exception 'Use a valid http or https video link.' using errcode='22023'; end if;
  if jsonb_typeof(payload->'attachments') is distinct from 'array' or jsonb_array_length(payload->'attachments')>5 then raise exception 'A resource can have up to five files.' using errcode='22023'; end if;
  for item in select value from jsonb_array_elements(payload->'attachments') loop
   if jsonb_typeof(item) is distinct from 'object' or length(coalesce(item->>'name','')) not between 1 and 250 or length(coalesce(item->>'path','')) not between 1 and 350
    or not exists(select 1 from storage.objects o where o.name=item->>'path' and(o.bucket_id='pfd-development-resources' or(o.bucket_id='pfd-club-files' and exists(select 1 from jsonb_array_elements(coalesce(old_resource.attachments,'[]'))kept where kept->>'path'=o.name and kept->>'bucket'='pfd-club-files')))) then raise exception 'An attached file is missing. Upload it again.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(payload->'club_ids') is distinct from 'array' then raise exception 'Invalid club selection.' using errcode='22023'; end if;
  select coalesce(array_agg(value::uuid),'{}'::uuid[]) into selected_clubs from jsonb_array_elements_text(payload->'club_ids');
  if payload->>'audience'='selected_clubs' and (cardinality(selected_clubs)=0 or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_clubs c where c.id=id and c.status='active'))) then raise exception 'Select at least one active club.' using errcode='22023'; end if;
  if payload->>'status'='published' and length(btrim(coalesce(payload->>'instructions','')))=0 then raise exception 'Add instructions before publishing.' using errcode='22023'; end if;
  plan_minutes:=0;
  if payload->>'kind' in ('individual_drill','team_drill') and (nullif(payload->>'duration_minutes','') is null or (payload->>'duration_minutes')::numeric not between 0.1 and 240) then raise exception 'Add an estimated drill duration between 0.1 and 240 minutes.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(payload->'plan_blocks','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(payload->'plan_blocks','[]'::jsonb))>100 then raise exception 'A plan can contain up to 100 drills.' using errcode='22023'; end if;
  if payload->>'kind'='training_plan' then
   if payload->>'status'='published' and coalesce(jsonb_array_length(payload->'plan_blocks'),0)=0 then raise exception 'Add at least one drill before publishing a training plan.' using errcode='22023'; end if;
   for block in select value from jsonb_array_elements(coalesce(payload->'plan_blocks','[]'::jsonb)) loop
    select * into drill from public.pfd_resources where club_id is null and id=(block->>'resource_id')::uuid and kind in ('individual_drill','team_drill');
    if not found or (payload->>'status'='published' and drill.status<>'published') then raise exception 'Use available drills; published plans require published drills.' using errcode='22023'; end if;
    if jsonb_typeof(block->'minutes') is distinct from 'number' or (block->>'minutes')::numeric not between 0.1 and 240 then raise exception 'Set a valid duration for each plan drill.' using errcode='22023'; end if;
    if payload->>'status'='published' and drill.audience='selected_clubs' and (payload->>'audience'='all_clubs' or exists(select 1 from unnest(selected_clubs) id where not exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=drill.id and rc.club_id=id))) then raise exception 'A plan cannot be shared more widely than its included drills.' using errcode='22023'; end if;
    normalized_blocks:=normalized_blocks||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'resource_id',drill.id,'title',drill.title,'kind',drill.kind,'minutes',(block->>'minutes')::numeric,'instructions',drill.instructions,'video_url',drill.video_url,'attachments',drill.attachments));
    plan_minutes:=plan_minutes+(block->>'minutes')::numeric;
   end loop;
  end if;
  insert into public.pfd_resources(id,title,kind,category,difficulty,instructions,video_url,attachments,audience,status,created_by,duration_minutes,plan_blocks)
   values(record_id,btrim(payload->>'title'),payload->>'kind',btrim(coalesce(payload->>'category','')),payload->>'difficulty',coalesce(payload->>'instructions',''),coalesce(payload->>'video_url',''),payload->'attachments',payload->>'audience',payload->>'status',actor,case when payload->>'kind'='training_plan' then null else nullif(payload->>'duration_minutes','')::numeric end,case when payload->>'kind'='training_plan' then normalized_blocks else '[]'::jsonb end)
   on conflict(id) do update set title=excluded.title,kind=excluded.kind,category=excluded.category,difficulty=excluded.difficulty,instructions=excluded.instructions,video_url=excluded.video_url,attachments=excluded.attachments,audience=excluded.audience,status=excluded.status,duration_minutes=excluded.duration_minutes,plan_blocks=excluded.plan_blocks,updated_at=clock_timestamp()
   returning to_jsonb(pfd_resources) into result;
  delete from public.pfd_resource_clubs where resource_id=record_id;
  if payload->>'audience'='selected_clubs' then insert into public.pfd_resource_clubs(resource_id,club_id) select record_id,id from (select distinct unnest(selected_clubs) id)x; end if;
  return result;
 elsif action='stats' then
  return jsonb_build_object('coaches',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='coach' and t.status='active' and c.status='active'),
   'players',(select count(distinct m.user_id) from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_clubs c on c.id=t.club_id where m.role_key='player' and t.status='active' and c.status='active'),
   'reports',(select count(*) from public.pfd_reports where status='submitted'),'requests',(select count(*) from public.pfd_access_requests where status='pending'));
 end if;
 raise exception 'Unknown workspace action.' using errcode='22023';
end $$;


create or replace function public.pfd_membership_flow(actor_id uuid,action text,payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare club uuid:=nullif(payload->>'club_id','')::uuid;team uuid:=nullif(payload->>'team_id','')::uuid;
 req public.pfd_access_requests;role_name text:=payload->>'role_key';decision text:=payload->>'decision';result jsonb;
 page_no integer:=coalesce((payload->>'page')::integer,1);offset_no integer;q text:=btrim(coalesce(payload->>'query',''));
 coach_scope uuid[];is_coach boolean;permission_role text;members_allowed boolean;coaches_allowed boolean;players_allowed boolean;state text:=coalesce(payload->>'status','pending');
begin
 if actor_id is null or not exists(select 1 from public.pfd_profiles where id=actor_id) or exists(select 1 from public.pfd_platform_owners where user_id=actor_id) then raise exception 'Use your separate club account.' using errcode='42501';end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>10000 or page_no not between 1 and 100000 or length(q)>160 then raise exception 'Invalid membership request.' using errcode='22023';end if;
 offset_no:=(page_no-1)*20;
 if action='my_access' then
  return jsonb_build_object(
   'clubs',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select c.id,c.name,c.status,c.city,c.state,c.country,c.sport,c.league,cm.created_at as joined_at from public.pfd_club_memberships cm join public.pfd_clubs c on c.id=cm.club_id where cm.user_id=actor_id)x),
   'teams',(select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select t.id,t.name,t.club_id,t.age_group,t.season,t.status,m.role_key from public.pfd_team_memberships m join public.pfd_teams t on t.id=m.team_id join public.pfd_club_memberships cm on cm.club_id=t.club_id and cm.user_id=m.user_id where m.user_id=actor_id)x),
   'requests',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') from (select r.id,r.club_id,c.name as club_name,r.team_id,t.name as team_name,r.role_key,r.status,r.message,r.reason,r.created_at,r.reviewed_at from public.pfd_access_requests r join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id where r.user_id=actor_id order by r.created_at desc limit 100)x)
  );
 elsif action='browse_clubs' then
  with filtered as(select c.id,c.name,c.city,c.state,c.country,c.sport,c.league,
    exists(select 1 from public.pfd_club_memberships cm where cm.club_id=c.id and cm.user_id=actor_id) as joined,
    exists(select 1 from public.pfd_access_requests r where r.user_id=actor_id and r.club_id=c.id and r.role_key='member' and r.status='pending') as pending
   from public.pfd_clubs c where c.status='active' and (q='' or strpos(lower(c.name||' '||c.city||' '||c.sport),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by name,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
 end if;
 perform 1 from public.pfd_clubs where id=club and status='active' for share;
 if not found then raise exception 'Choose an active club.' using errcode='22023';end if;
 if action in ('admin_requests','review_request') then
  is_coach:=not exists(select 1 from public.pfd_club_admins where club_id=club and user_id=actor_id);
  select coalesce(array_agg(t.id),'{}')into coach_scope from public.pfd_team_memberships tm join public.pfd_teams t on t.id=tm.team_id join public.pfd_club_memberships cm on cm.club_id=t.club_id and cm.user_id=tm.user_id where tm.user_id=actor_id and tm.role_key='coach' and t.club_id=club and t.status='active';
  if is_coach and cardinality(coach_scope)=0 then raise exception 'Approved staff access required.'using errcode='42501';end if;
  permission_role:=case when is_coach then 'coach'else'club_admin'end;
  if not exists(select 1 from public.pfd_role_permissions where role_key=permission_role and permission_key=case when is_coach then 'teams.view'else'clubs.view'end and enabled)then raise exception 'Staff view permission required.'using errcode='42501';end if;
  perform 1 from public.pfd_role_permissions where role_key=permission_role for share;
  select enabled and not is_coach into members_allowed from public.pfd_role_permissions where role_key=permission_role and permission_key='members.approve';
  select enabled and not is_coach into coaches_allowed from public.pfd_role_permissions where role_key=permission_role and permission_key='coaches.approve';
  select enabled into players_allowed from public.pfd_role_permissions where role_key=permission_role and permission_key='players.approve';
  if action='admin_requests' then
   if not coalesce(members_allowed,false) and not coalesce(coaches_allowed,false) and not coalesce(players_allowed,false) then raise exception 'Request approval permission is required.' using errcode='42501';end if;
   if state not in ('pending','approved','rejected','all') then raise exception 'Invalid request status.' using errcode='22023';end if;
   with filtered as(select r.id,r.user_id,r.role_key,r.club_id,r.team_id,r.status,r.message,r.reason,r.created_at,r.reviewed_at,p.name,p.email,t.name as team_name,
      reviewer.name as reviewer_name
    from public.pfd_access_requests r join public.pfd_profiles p on p.id=r.user_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles reviewer on reviewer.id=r.reviewed_by
    where r.club_id=club and(coalesce(payload->>'team_id','')='' or r.team_id=(payload->>'team_id')::uuid) and(not is_coach or(r.team_id=any(coach_scope) and r.role_key='player')) and (state='all' or r.status=state)
     and ((r.role_key='member' and coalesce(members_allowed,false)) or (r.role_key='coach' and coalesce(coaches_allowed,false)) or (r.role_key='player' and coalesce(players_allowed,false)))
     and (coalesce(payload->>'role_key','')='' or r.role_key=payload->>'role_key')
     and (q='' or strpos(lower(p.name||' '||p.email),lower(q))>0))
   select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from filtered order by created_at desc,id limit 20 offset offset_no)x),'total',(select count(*) from filtered),'page',page_no) into result;return result;
  end if;
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid and club_id=club;
  if not found then raise exception 'Request not found.' using errcode='P0002';end if;
  -- Match direct team assignment's lock order: club, team, then request.
  if req.team_id is not null then perform 1 from public.pfd_teams where id=req.team_id and club_id=req.club_id for update;end if;
  select * into req from public.pfd_access_requests where id=(payload->>'id')::uuid and club_id=club for update;
  if not found then raise exception 'Request not found in this club.' using errcode='P0002';end if;
  if not ((req.role_key='member' and coalesce(members_allowed,false)) or (req.role_key='coach' and coalesce(coaches_allowed,false)) or (req.role_key='player' and coalesce(players_allowed,false))) then raise exception 'You cannot approve this role.' using errcode='42501';end if;
  if is_coach and(req.role_key<>'player' or not coalesce(req.team_id=any(coach_scope),false))then raise exception 'Coaches approve players in their teams only.'using errcode='42501';end if;
  if req.status<>'pending' then raise exception 'This request has already been reviewed. Refresh the list.' using errcode='40001';end if;
  if decision is null or decision not in ('approved','rejected') then raise exception 'Choose approve or reject.' using errcode='22023';end if;
  if decision='rejected' and length(btrim(coalesce(payload->>'reason','')))=0 then raise exception 'Add a rejection reason.' using errcode='22023';end if;
  if decision='approved' then
   if req.role_key='member' then
    insert into public.pfd_club_memberships(club_id,user_id,approved_by) values(club,req.user_id,actor_id) on conflict do nothing;
   else
    perform 1 from public.pfd_club_memberships where club_id=club and user_id=req.user_id for share;
    if not found then raise exception 'Approve this account into the club first.' using errcode='22023';end if;
    perform 1 from public.pfd_teams where id=req.team_id and club_id=club and status='active' for share;
    if not found then raise exception 'Choose an active team in this club.' using errcode='22023';end if;
    insert into public.pfd_team_memberships(team_id,user_id,role_key,granted_by) values(req.team_id,req.user_id,req.role_key,actor_id) on conflict do nothing;
    update public.pfd_teams set updated_at=clock_timestamp() where id=req.team_id;
   end if;
  end if;
  update public.pfd_access_requests set status=decision,reason=coalesce(payload->>'reason',''),reviewed_at=clock_timestamp(),reviewed_by=actor_id where id=req.id;
  return jsonb_build_object('ok',true);
 elsif action='request_club' then
  if exists(select 1 from public.pfd_club_memberships where club_id=club and user_id=actor_id) then raise exception 'You already belong to this club.' using errcode='22023';end if;
  insert into public.pfd_access_requests(user_id,club_id,role_key,message,created_by) values(actor_id,club,'member',coalesce(payload->>'message',''),actor_id) returning id into team;
  return jsonb_build_object('id',team);
 elsif action in ('club_teams','request_team') then
  perform 1 from public.pfd_club_memberships where club_id=club and user_id=actor_id for share;
  if not found then raise exception 'Your club request must be approved before you can join a team.' using errcode='42501';end if;
  if action='club_teams' then
   return (select coalesce(jsonb_agg(to_jsonb(x) order by x.name),'[]') from (select t.id,t.name,t.age_group,t.season,
     (select coalesce(jsonb_agg(m.role_key),'[]') from public.pfd_team_memberships m where m.team_id=t.id and m.user_id=actor_id) as roles,
     (select coalesce(jsonb_agg(r.role_key),'[]') from public.pfd_access_requests r where r.team_id=t.id and r.user_id=actor_id and r.status='pending') as pending_roles
    from public.pfd_teams t where t.club_id=club and t.status='active' order by name limit 1000)x);
  end if;
  if role_name is null or role_name not in ('coach','player') then raise exception 'Choose coach or player access.' using errcode='22023';end if;
  perform 1 from public.pfd_teams where id=team and club_id=club and status='active' for share;
  if not found then raise exception 'Choose an active team in this club.' using errcode='22023';end if;
  if exists(select 1 from public.pfd_team_memberships where team_id=team and user_id=actor_id and role_key=role_name) then raise exception 'You already have this team membership.' using errcode='22023';end if;
  insert into public.pfd_access_requests(user_id,club_id,team_id,role_key,message,created_by) values(actor_id,club,team,role_name,coalesce(payload->>'message',''),actor_id) returning id into team;
  return jsonb_build_object('id',team);
 end if;
 raise exception 'Unknown membership action.' using errcode='22023';
end $$;
revoke all on function public.pfd_membership_flow(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.pfd_membership_flow(uuid,text,jsonb) to service_role;


-- SOURCE: supabase/migrations/20261113063733_coach_options_role_fix.sql
-- Add the canonical role to the exact options response the dashboards consume.
-- Preserve all existing membership, permission and team-scope checks.
do $patch$
declare definition text:=pg_get_functiondef('public.pfd_club_workspace(uuid,uuid,text,jsonb)'::regprocedure);
 old_fragment text:=$old$   'permissions',to_jsonb(perms));end if;
  if action='stats'$old$;
 new_fragment text:=$new$   'workspace_role',case when is_admin then 'club_admin' when is_coach then 'coach' else 'member' end,
   'permissions',to_jsonb(perms));end if;
  if action='stats'$new$;
begin
 if strpos(definition,old_fragment)=0 then raise exception 'Expected workspace options response not found. No changes applied.';end if;
 execute replace(definition,old_fragment,new_fragment);
end $patch$;


-- SOURCE: supabase/migrations/20261113070015_coach_shared_homework_review.sql
-- Review follows actual assigned players in current coaching teams, regardless of author.
create function pfd_private.coach_has_player(actor uuid,c uuid,player uuid,target_teams uuid[])returns boolean
language sql stable security invoker set search_path=''as $$
 select exists(select 1 from public.pfd_teams t
 join public.pfd_clubs club on club.id=t.club_id and club.status='active'
 join public.pfd_team_memberships coach on coach.team_id=t.id and coach.user_id=actor and coach.role_key='coach'
 join public.pfd_team_memberships pupil on pupil.team_id=t.id and pupil.user_id=player and pupil.role_key='player'
 join public.pfd_club_memberships cm on cm.club_id=t.club_id and cm.user_id=actor
 join public.pfd_club_memberships pm on pm.club_id=t.club_id and pm.user_id=player
 where t.club_id=c and t.status='active' and(cardinality(target_teams)=0 or t.id=any(target_teams)))
$$;
create function pfd_private.coach_homework_visible(actor uuid,h public.pfd_homework)returns boolean
language sql stable security invoker set search_path=''as $$
 select exists(select 1 from public.pfd_homework_recipients hr where hr.homework_id=h.id and pfd_private.coach_has_player(actor,h.club_id,hr.user_id,h.team_ids))
$$;
revoke all on function pfd_private.coach_has_player(uuid,uuid,uuid,uuid[]),pfd_private.coach_homework_visible(uuid,public.pfd_homework)from public,anon,authenticated;
grant execute on function pfd_private.coach_has_player(uuid,uuid,uuid,uuid[]),pfd_private.coach_homework_visible(uuid,public.pfd_homework)to service_role;
do $patch$
declare definition text:=pg_get_functiondef('public.pfd_club_workspace(uuid,uuid,text,jsonb)'::regprocedure);previous text;replacement text;
begin
 for previous,replacement in select *from(values
 ($old$hs.review_status='submitted' and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams))$old$,
  $new$hs.review_status='submitted' and(not is_coach or pfd_private.coach_has_player(actor,club,hs.user_id,h.team_ids))$new$),
 ($old$(select count(*) from public.pfd_homework where club_id=club and(not is_coach or (cardinality(team_ids)>0 and team_ids<@coach_teams)) and status='active')$old$,
  $new$(select count(*) from public.pfd_homework h where h.club_id=club and(not is_coach or pfd_private.coach_homework_visible(actor,h)) and h.status='active')$new$),
 ($old$with filtered as(select h.*,(select count(*)from public.pfd_homework_recipients hr where hr.homework_id=h.id)as recipient_count,(select count(*)from public.pfd_homework_submissions hs where hs.homework_id=h.id)as submission_count,$old$,
  $new$with filtered as(select h.*,(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams))as can_edit,(select count(*)from public.pfd_homework_recipients hr where hr.homework_id=h.id and(not is_coach or pfd_private.coach_has_player(actor,club,hr.user_id,h.team_ids)))as recipient_count,(select count(*)from public.pfd_homework_submissions hs where hs.homework_id=h.id and(not is_coach or pfd_private.coach_has_player(actor,club,hs.user_id,h.team_ids)))as submission_count,$new$),
 ($old$(action='homework_list' and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams)))$old$,
  $new$(action='homework_list' and(not is_coach or pfd_private.coach_homework_visible(actor,h)))$new$),
 ($old$select * into hw from public.pfd_homework where id=(payload->>'id')::uuid and club_id=club and(not is_coach or(cardinality(team_ids)>0 and team_ids<@coach_teams));$old$,
  $new$select h.* into hw from public.pfd_homework h where h.id=(payload->>'id')::uuid and h.club_id=club and(not is_coach or pfd_private.coach_homework_visible(actor,h));$new$),
 ($old$where hr.homework_id=hw.id)x));$old$,
  $new$where hr.homework_id=hw.id and(not is_coach or pfd_private.coach_has_player(actor,club,hr.user_id,hw.team_ids)))x));$new$),
 ($old$and h.club_id=club and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams)) for update of s;$old$,
  $new$and h.club_id=club and(not is_coach or pfd_private.coach_has_player(actor,club,s.user_id,h.team_ids)) for update of s;$new$),
 ($old$(is_coach and exists(select 1 from public.pfd_homework sh where sh.id=submission.homework_id and cardinality(sh.team_ids)>0 and sh.team_ids<@coach_teams))$old$,
  $new$(is_coach and exists(select 1 from public.pfd_homework sh where sh.id=submission.homework_id and pfd_private.coach_has_player(actor,club,submission.user_id,sh.team_ids)))$new$)
 )as patches(before_text,after_text)loop
  if strpos(definition,previous)=0 then raise exception 'Expected homework scope fragment missing. No changes applied: %',left(previous,100);end if;
  definition:=replace(definition,previous,replacement);
 end loop;
 execute definition;
end $patch$;


-- SOURCE: supabase/migrations/20261113071246_player_dashboard.sql
-- Player endpoints are service-only and always derive identity from the verified Edge actor.
update public.pfd_permission_catalog set available=true where key in ('reports.view_own','reports.self_assess');
update storage.buckets set allowed_mime_types=array_append(allowed_mime_types,'video/quicktime')where id='pfd-club-files'and not('video/quicktime'=any(allowed_mime_types));
create function public.pfd_player_workspace(actor_id uuid,target_club uuid,action text,payload jsonb default '{}')returns jsonb
language plpgsql security invoker set search_path=''as $$
declare actor uuid:=actor_id;club uuid:=target_club;player_teams uuid[];perms text[];required_key text;
 page_no integer:=coalesce((payload->>'page')::integer,1);offset_no integer;q text:=btrim(coalesce(payload->>'query',''));
 subject uuid;team uuid;record_id uuid;template text;state text;report_data jsonb;definition jsonb;info jsonb;entry record;item jsonb;field_config jsonb;is_team boolean:=false;
 old_report public.pfd_reports;resource public.pfd_resources;event_row public.pfd_club_events;hw public.pfd_homework;result jsonb;own_name text;
begin
 if actor is null or exists(select 1 from public.pfd_platform_owners where user_id=actor)then raise exception 'Use your separate Player account.'using errcode='42501';end if;
 perform 1 from public.pfd_clubs c join public.pfd_club_memberships cm on cm.club_id=c.id where c.id=club and c.status='active'and cm.user_id=actor for share of c;
 if not found then raise exception 'Approved access to an active club is required.'using errcode='42501';end if;
 select coalesce(array_agg(t.id),'{}')into player_teams from public.pfd_teams t join public.pfd_team_memberships m on m.team_id=t.id where t.club_id=club and t.status='active'and m.user_id=actor and m.role_key='player';
 if cardinality(player_teams)=0 then raise exception 'An approved player team is required.'using errcode='42501';end if;
 if jsonb_typeof(payload)is distinct from'object'or octet_length(payload::text)>180000 or page_no not between 1 and 100000 or length(q)>160 then raise exception 'Invalid player request.'using errcode='22023';end if;
 offset_no:=(page_no-1)*20;
 select coalesce(array_agg(permission_key),'{}')into perms from public.pfd_role_permissions where role_key='player'and enabled;
 select name into own_name from public.pfd_profiles where id=actor;
 required_key:=case when action in('player_reports_list','player_report_get','player_progress')then'reports.view_own'when action='player_report_save'then'reports.self_assess'when action in('player_resources_list','player_resource_file_access')then'library.view'when action in('player_calendar','player_event_response')then'events.view'when action='player_team_chat'then'chats.view'when action='player_homework_file_access'then'homework.view'else null end;
 if required_key is not null and not(required_key=any(perms))then raise exception 'Your role does not have permission for this action.'using errcode='42501';end if;
 if action='player_options'then
  return jsonb_build_object('workspace_role','player','self',jsonb_build_object('id',actor,'name',own_name),'permissions',to_jsonb(perms),
   'clubs',(select jsonb_build_array(jsonb_build_object('id',id,'name',name,'status',status))from public.pfd_clubs where id=club),
   'teams',(select coalesce(jsonb_agg(to_jsonb(t)order by t.name),'[]')from(select id,club_id,name,age_group,season,status,description from public.pfd_teams where id=any(player_teams))t),
   'templates',(select jsonb_agg(to_jsonb(t)order by key)from public.pfd_report_templates t where key<>'match_review'),
   'self_templates',jsonb_build_array('player','fitness','tactical','performance'));
 elsif action='player_stats'then
  return jsonb_build_object('reports',case when'reports.view_own'=any(perms)then(select count(*)from public.pfd_reports where club_id=club and subject_id=actor and status='submitted')else null end,
   'homework_due',case when'homework.view'=any(perms)then(select count(*)from public.pfd_homework h join public.pfd_homework_recipients hr on hr.homework_id=h.id left join public.pfd_homework_submissions s on s.homework_id=h.id and s.user_id=actor where h.club_id=club and hr.user_id=actor and h.status='active'and(s.id is null or s.review_status='resubmit'))else null end,
   'upcoming',case when'events.view'=any(perms)then(select count(*)from public.pfd_club_events e where e.club_id=club and e.status='scheduled'and e.starts_at>=now()and((e.kind in('training','game')and e.team_id=any(player_teams))or(e.kind='event'and exists(select 1 from public.pfd_event_recipients er where er.event_id=e.id and er.user_id=actor))))else null end,
   'feedback',case when'homework.view'=any(perms)then(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select h.title,s.feedback,s.review_status,s.updated_at from public.pfd_homework_submissions s join public.pfd_homework h on h.id=s.homework_id where h.club_id=club and s.user_id=actor and length(s.feedback)>0 order by s.updated_at desc limit 3)x)else'[]'::jsonb end);
 elsif action='player_reports_list'then
  with filtered as(select r.id,r.subject_id,r.club_id,r.team_id,r.template_key,r.report_date,r.status,r.updated_at,r.created_by,r.data->>'entry_kind' as entry_kind,own_name as subject_name,author.name as author_name,c.name as club_name,t.name as team_name,
    not(r.created_by=actor and r.status='draft'and r.data->>'entry_kind'='self_assessment')as read_only
   from public.pfd_reports r join public.pfd_clubs c on c.id=r.club_id left join public.pfd_teams t on t.id=r.team_id left join public.pfd_profiles author on author.id=r.created_by
   where r.club_id=club and r.subject_id=actor and(r.status='submitted'or(r.status='draft'and r.created_by=actor and r.data->>'entry_kind'='self_assessment'))
   and(coalesce(payload->>'template_key','')=''or r.template_key=payload->>'template_key')and(coalesce(payload->>'status','')=''or r.status=payload->>'status')
   and(coalesce(payload->>'team_id','')=''or r.team_id=(payload->>'team_id')::uuid)and(coalesce(payload->>'from_date','')=''or r.report_date>=(payload->>'from_date')::date)and(coalesce(payload->>'to_date','')=''or r.report_date<=(payload->>'to_date')::date)
   and(q=''or strpos(lower(coalesce(t.name,'')||' '||coalesce(author.name,'')||' '||r.template_key),lower(q))>0))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select *from filtered order by report_date desc,id limit 20 offset offset_no)x),'total',(select count(*)from filtered),'page',page_no)into result;return result;
 elsif action='player_report_get'then
  select to_jsonb(r)||jsonb_build_object('read_only',not(r.created_by=actor and r.status='draft'and r.data->>'entry_kind'='self_assessment'))into result from public.pfd_reports r where r.id=(payload->>'id')::uuid and r.club_id=club and r.subject_id=actor and(r.status='submitted'or(r.status='draft'and r.created_by=actor and r.data->>'entry_kind'='self_assessment'));
  if result is null then raise exception 'Your report was not found.'using errcode='P0002';end if;return result;
 elsif action='player_progress'then
  return(select coalesce(jsonb_agg(to_jsonb(x)order by x.report_date),'[]')from(
   select r.id,r.template_key,r.report_date,r.status,case when r.subject_id=actor then r.data else jsonb_build_object('ratings','{}'::jsonb,'metrics','{}'::jsonb,'team_ratings',jsonb_build_object(actor::text,jsonb_build_object('name',own_name,'rating',r.data->'team_ratings'->actor::text->'rating')))end as data
   from public.pfd_reports r where r.club_id=club and r.status='submitted'and(r.subject_id=actor or(r.template_key='match_review'and r.data->'team_ratings'?actor::text))order by r.report_date desc,r.created_at desc limit 100)x);
 elsif action='player_report_save'then
  record_id:=(payload->>'id')::uuid;subject:=actor;team:=nullif(payload->>'team_id','')::uuid;template:=payload->>'template_key';state:=payload->>'status';report_data:=payload->'data';
  if nullif(payload->>'subject_id','')is not null and(payload->>'subject_id')::uuid<>actor then raise exception 'Self-assessments must belong to your own account.'using errcode='42501';end if;
  if team is null or not(team=any(player_teams))then raise exception 'Choose one of your approved player teams.'using errcode='42501';end if;
  if template not in('player','fitness','tactical','performance')or template is null then raise exception 'This template is not available for player self-assessment.'using errcode='42501';end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(record_id::text,42));
  select *into old_report from public.pfd_reports where id=record_id for update;
  if old_report.id is not null and(old_report.club_id is distinct from club or old_report.subject_id is distinct from actor or old_report.created_by is distinct from actor or old_report.data->>'entry_kind'is distinct from'self_assessment')then raise exception 'You can edit only your own self-assessment drafts.'using errcode='42501';end if;
  if old_report.id is not null and old_report.updated_at is distinct from(payload->>'updated_at')::timestamptz then raise exception 'This draft changed. Reopen it before saving.'using errcode='40001';end if;
  if old_report.id is not null and old_report.status<>'draft'then raise exception 'Submitted assessments are read-only.'using errcode='22023';end if;
  select t.definition into definition from public.pfd_report_templates t where t.key=template;
  if state is null or state not in('draft','submitted')or jsonb_typeof(report_data)is distinct from'object'then raise exception 'Invalid assessment.'using errcode='22023';end if;
  report_data:=report_data||jsonb_build_object('subject_kind','player','entry_kind','self_assessment','prepared_by',own_name,'reviewer','');
  report_data:=jsonb_set(report_data,'{info}',coalesce(report_data->'info','{}')||jsonb_build_object('name',own_name,'team',(select name from public.pfd_teams where id=team),'date',payload->>'report_date'));
  info:=report_data->'info';
  if jsonb_typeof(info) is distinct from 'object' or jsonb_typeof(report_data->'ratings') is distinct from 'object' or jsonb_typeof(report_data->'notes') is distinct from 'array' or jsonb_array_length(report_data->'notes')<>4 then raise exception 'Report sections are missing.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(info) loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid report detail.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'ratings') loop
   if jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (1,2,3,4,5) or not exists(
    select 1 from jsonb_each(definition->'categories') c cross join lateral jsonb_array_elements(c.value) with ordinality question where c.key||'-'||(question.ordinality-1)::text=entry.key
   ) then raise exception 'Ratings must match the original questions and use 1–5.' using errcode='22023'; end if;
  end loop;
  for item in select value from jsonb_array_elements(report_data->'notes') loop
   if jsonb_typeof(item)<>'string' or length(item#>>'{}')>6000 then raise exception 'Report notes must be text of at most 6000 characters.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(report_data->'extra') is distinct from 'object' or jsonb_typeof(report_data->'values') is distinct from 'object' or jsonb_typeof(report_data->'progress') is distinct from 'object' then raise exception 'Invalid report detail sections.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(report_data->'extra') loop
   if jsonb_typeof(entry.value)<>'string' or length(entry.value#>>'{}')>250 then raise exception 'Invalid fitness test value.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'progress') loop
   if entry.key !~ '^[0-2]-[0-2]-[0-2]$' or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric not in (0,1,2,3) then raise exception 'Invalid exercise progress marker.' using errcode='22023'; end if;
  end loop;
  for entry in select * from jsonb_each(report_data->'values') loop
   if jsonb_typeof(entry.value)<>'boolean' or not exists(select 1 from jsonb_each(definition->'behaviours') b cross join lateral jsonb_array_elements_text(b.value) v where v.value=entry.key) then raise exception 'Invalid player behaviour value.' using errcode='22023'; end if;
  end loop;
  if jsonb_typeof(coalesce(report_data->'metrics','{}'::jsonb))<>'object' or jsonb_typeof(coalesce(report_data->'team_ratings','{}'::jsonb))<>'object' then raise exception 'Invalid structured report data.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'metrics','{}'::jsonb)) loop
   select value into field_config from jsonb_array_elements(coalesce(definition->'fields','[]')) where value->>'key'=entry.key and value->>'type'='number';
   if field_config is null or jsonb_typeof(entry.value)<>'number' or (entry.value#>>'{}')::numeric < (field_config->>'min')::numeric or (entry.value#>>'{}')::numeric > (field_config->>'max')::numeric then raise exception 'A numeric report field is outside its allowed range.' using errcode='22023'; end if;
   if (field_config->>'step')::numeric=1 and mod((entry.value#>>'{}')::numeric,1)<>0 then raise exception 'Counts must be whole numbers.' using errcode='22023'; end if;
  end loop;
  if report_data->'metrics' ? 'shots' and report_data->'metrics' ? 'shots_on_target' and (report_data->'metrics'->>'shots_on_target')::numeric>(report_data->'metrics'->>'shots')::numeric then raise exception 'Shots on target cannot exceed shots.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'total_distance_m' and report_data->'metrics' ? 'high_speed_distance_m' and (report_data->'metrics'->>'high_speed_distance_m')::numeric>(report_data->'metrics'->>'total_distance_m')::numeric then raise exception 'High-speed distance cannot exceed total distance.' using errcode='22023'; end if;
  if report_data->'metrics' ? 'top_speed_kmh' and report_data->'metrics' ? 'average_speed_kmh' and (report_data->'metrics'->>'average_speed_kmh')::numeric>(report_data->'metrics'->>'top_speed_kmh')::numeric then raise exception 'Average speed cannot exceed top speed.' using errcode='22023'; end if;
  for entry in select * from jsonb_each(coalesce(report_data->'team_ratings','{}'::jsonb)) loop
   if not is_team or jsonb_typeof(entry.value->'rating') is distinct from 'number' or (entry.value->>'rating')::numeric not in (1,2,3,4,5) or not exists(select 1 from public.pfd_team_memberships m where m.team_id=team and m.user_id=entry.key::uuid and m.role_key='player') then raise exception 'Player ratings must be 1–5 and belong to this team roster.' using errcode='22023'; end if;
   report_data:=jsonb_set(report_data,array['team_ratings',entry.key,'name'],to_jsonb((select name from public.pfd_profiles where id=entry.key::uuid)));
  end loop;
  if length(coalesce(report_data->>'prepared_by',''))>250 or length(coalesce(report_data->>'reviewer',''))>250 then raise exception 'Report author details are too long.' using errcode='22023'; end if;
  if state='submitted' and (length(btrim(coalesce(info->>'name','')))=0 or length(btrim(coalesce(report_data->>'prepared_by','')))=0 or report_data->'consent' is distinct from 'true'::jsonb) then raise exception 'Complete the name, prepared-by field and submission consent.' using errcode='22023'; end if;
  insert into public.pfd_reports(id,subject_id,club_id,team_id,template_key,template_snapshot,report_date,status,data,created_by)
   values(record_id,subject,club,team,template,definition,(payload->>'report_date')::date,state,report_data,actor)
   on conflict(id) do update set subject_id=excluded.subject_id,club_id=excluded.club_id,team_id=excluded.team_id,template_key=excluded.template_key,template_snapshot=excluded.template_snapshot,report_date=excluded.report_date,status=excluded.status,data=excluded.data,updated_at=clock_timestamp()
   returning to_jsonb(pfd_reports) into result;
  return result||jsonb_build_object('read_only',state<>'draft');
 elsif action='player_resources_list'then
  with filtered as(select r.*,(select coalesce(jsonb_agg(rc.club_id),'[]')from public.pfd_resource_clubs rc where rc.resource_id=r.id)as club_ids,true as read_only from public.pfd_resources r where r.kind='individual_drill'and r.status='published'
   and((r.club_id is null and(r.audience='all_clubs'or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=club)))or(r.club_id=club and(r.team_id is null or r.team_id=any(player_teams))))
   and(q=''or strpos(lower(r.title||' '||r.category||' '||r.instructions),lower(q))>0)and(coalesce(payload->>'difficulty','')=''or r.difficulty=payload->>'difficulty')
   and(coalesce(payload->>'scope','')=''or(payload->>'scope'='global'and r.club_id is null)or(payload->>'scope'='club'and r.club_id=club and r.team_id is null)or(payload->>'scope'='team'and r.team_id=any(player_teams))))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select *from filtered order by updated_at desc,id limit 20 offset offset_no)x),'total',(select count(*)from filtered),'page',page_no)into result;return result;
 elsif action in('player_resource_file_access','player_homework_file_access')then
  if action='player_resource_file_access'then
   select r.*into resource from public.pfd_resources r where r.id=(payload->>'resource_id')::uuid and r.kind='individual_drill'and r.status='published'and((r.club_id is null and(r.audience='all_clubs'or exists(select 1 from public.pfd_resource_clubs rc where rc.resource_id=r.id and rc.club_id=club)))or(r.club_id=club and(r.team_id is null or r.team_id=any(player_teams))));
   if not found then raise exception 'This drill is not available to your account.'using errcode='42501';end if;
   select a into item from jsonb_array_elements(resource.attachments)a where a->>'path'=payload->>'path';
   if item is null then raise exception 'This file is not attached to this drill.'using errcode='42501';end if;
   return jsonb_build_object('bucket',coalesce(item->>'bucket',case when resource.club_id is null then'pfd-development-resources'else'pfd-club-files'end),'path',item->>'path');
  end if;
  select h.*into hw from public.pfd_homework h join public.pfd_homework_recipients hr on hr.homework_id=h.id where h.id=(payload->>'homework_id')::uuid and h.club_id=club and hr.user_id=actor;
  if not found then raise exception 'This homework is not assigned to you.'using errcode='42501';end if;
  select a into item from jsonb_array_elements(coalesce(hw.resource_snapshot->'attachments','[]'))a where a->>'path'=payload->>'path';
  if item is null then raise exception 'This file is not attached to your assignment.'using errcode='42501';end if;
  return jsonb_build_object('bucket',coalesce(item->>'bucket',case when hw.resource_snapshot->>'club_id'is null then'pfd-development-resources'else'pfd-club-files'end),'path',item->>'path');
 elsif action='player_calendar'then
  if nullif(payload->>'team_id','')is not null and not((payload->>'team_id')::uuid=any(player_teams))then raise exception 'Choose one of your teams.'using errcode='42501';end if;
  with filtered as(select e.id,e.title,e.kind,e.team_id,t.name as team_name,e.starts_at,e.ends_at,e.timezone,e.location,e.notes,e.status,coalesce(er.response,'pending')as response
   from public.pfd_club_events e left join public.pfd_teams t on t.id=e.team_id left join public.pfd_event_recipients er on er.event_id=e.id and er.user_id=actor
   where e.club_id=club and((e.kind in('training','game')and e.team_id=any(player_teams))or(e.kind='event'and er.user_id=actor))
   and(coalesce(payload->>'kind','')=''or e.kind=payload->>'kind')and(coalesce(payload->>'sessions_only','false')<>'true'or e.kind in('training','game'))
   and(coalesce(payload->>'team_id','')=''or e.team_id=(payload->>'team_id')::uuid)and(coalesce(payload->>'from_date','')=''or e.starts_at>=(payload->>'from_date')::timestamptz))
  select jsonb_build_object('items',(select coalesce(jsonb_agg(to_jsonb(x)),'[]')from(select *from filtered order by starts_at,id limit 20 offset offset_no)x),'total',(select count(*)from filtered),'page',page_no)into result;return result;
 elsif action='player_event_response'then
  if payload->>'response'is null or payload->>'response'not in('pending','attending','declined')then raise exception 'Choose your availability.'using errcode='22023';end if;
  select e.*into event_row from public.pfd_club_events e where e.id=(payload->>'id')::uuid and e.club_id=club and e.status='scheduled'and e.ends_at>=now()and((e.kind in('training','game')and e.team_id=any(player_teams))or(e.kind='event'and exists(select 1 from public.pfd_event_recipients er where er.event_id=e.id and er.user_id=actor)))for share;
  if not found then raise exception 'This upcoming event is not available to your account.'using errcode='42501';end if;
  insert into public.pfd_event_recipients(event_id,user_id,response)values(event_row.id,actor,payload->>'response')on conflict(event_id,user_id)do update set response=excluded.response;
  return jsonb_build_object('ok',true);
 elsif action='player_team_chat'then
  team:=(payload->>'team_id')::uuid;if team is null or not(team=any(player_teams))then raise exception 'Choose one of your approved player teams.'using errcode='42501';end if;
  insert into public.pfd_chat_rooms(id,club_id,team_id,title,created_by)select gen_random_uuid(),club,t.id,t.name||' · Team chat',actor from public.pfd_teams t where t.id=team on conflict(team_id)where team_id is not null do update set title=excluded.title returning to_jsonb(pfd_chat_rooms)into result;return result;
 end if;
 raise exception 'Unknown player action.'using errcode='22023';
end $$;
revoke all on function public.pfd_player_workspace(uuid,uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.pfd_player_workspace(uuid,uuid,text,jsonb)to service_role;


-- SOURCE: supabase/migrations/20261113100954_verified_session_security.sql
-- Defense in depth for direct REST/RPC/storage requests and service-backed Edges.
create schema if not exists pfd_private;
revoke all on schema pfd_private from public;
grant usage on schema pfd_private to authenticated,service_role;

create function pfd_private.valid_session(actor uuid, session_key uuid, assurance text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
   select 1 from auth.users u join auth.sessions s on s.user_id=u.id
   where u.id=actor and s.id=session_key
     and u.email_confirmed_at is not null and u.deleted_at is null
     and (u.banned_until is null or u.banned_until<=now())
     and (s.not_after is null or s.not_after>now())
     and (not exists(select 1 from auth.mfa_factors f where f.user_id=u.id and f.status='verified')
          or (assurance='aal2' and s.aal::text='aal2'))
 );
$$;
revoke all on function pfd_private.valid_session(uuid,uuid,text) from public,anon,authenticated;
grant execute on function pfd_private.valid_session(uuid,uuid,text) to service_role;

-- No actor parameter: clients can only check their own JWT-backed session.
create function pfd_private.session_allowed()
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 return pfd_private.valid_session(auth.uid(),nullif(auth.jwt()->>'session_id','')::uuid,auth.jwt()->>'aal');
exception when invalid_text_representation then return false;
end;
$$;
revoke all on function pfd_private.session_allowed() from public,anon;
grant execute on function pfd_private.session_allowed() to authenticated,service_role;

-- Only service_role can call this with a previously Auth-verified actor/token.
create function public.pfd_check_session(actor_id uuid,session_id uuid,assurance text)
returns boolean language sql stable security invoker set search_path='' as $$
 select pfd_private.valid_session(actor_id,session_id,assurance);
$$;
revoke all on function public.pfd_check_session(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pfd_check_session(uuid,uuid,text) to service_role;

-- Restrictive policies AND with every existing scoped policy; they grant no rows.
do $$declare tab record;begin
 for tab in select tablename from pg_tables where schemaname='public' and tablename like 'pfd\_%' escape '\' loop
  execute format('create policy pfd_active_session on public.%I as restrictive for all to authenticated using ((select pfd_private.session_allowed())) with check ((select pfd_private.session_allowed()))',tab.tablename);
 end loop;
end$$;
create policy pfd_active_storage_session on storage.objects as restrictive for all to authenticated
 using (bucket_id not in ('pfd-development-resources','pfd-club-files') or (select pfd_private.session_allowed()))
 with check (bucket_id not in ('pfd-development-resources','pfd-club-files') or (select pfd_private.session_allowed()));

create function public.pfd_session_status()
returns boolean language sql stable security invoker set search_path='' as $$
 select pfd_private.session_allowed();
$$;
revoke all on function public.pfd_session_status() from public,anon;
grant execute on function public.pfd_session_status() to authenticated;


commit;
