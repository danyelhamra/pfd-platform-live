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
