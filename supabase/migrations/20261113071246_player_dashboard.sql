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
