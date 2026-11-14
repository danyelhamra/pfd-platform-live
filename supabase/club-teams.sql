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
