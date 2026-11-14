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
