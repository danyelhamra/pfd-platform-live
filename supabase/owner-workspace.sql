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
