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
