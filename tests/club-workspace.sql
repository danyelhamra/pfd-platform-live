-- Full club workflow regression. Every fixture and permission change rolls back.
begin;
insert into auth.users(id,email,raw_user_meta_data,created_at,updated_at) values
('61000000-0000-4000-8000-000000000001','admin-a@local.invalid','{"full_name":"Admin A"}',now(),now()),
('61000000-0000-4000-8000-000000000002','admin-b@local.invalid','{"full_name":"Admin B"}',now(),now()),
('61000000-0000-4000-8000-000000000003','coach@local.invalid','{"full_name":"Coach A"}',now(),now()),
('61000000-0000-4000-8000-000000000004','player@local.invalid','{"full_name":"Player A"}',now(),now()),
('61000000-0000-4000-8000-000000000005','outsider@local.invalid','{"full_name":"Outsider"}',now(),now());
insert into public.pfd_clubs(id,name,location,city,state,country,contact_email,contact_number,league,sport,status) values
('62000000-0000-4000-8000-000000000001','Workspace A','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@local.invalid','0412345678','League','Soccer','active'),
('62000000-0000-4000-8000-000000000002','Workspace B','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@local.invalid','0412345678','League','Soccer','active');
insert into public.pfd_club_admins(club_id,user_id) values
('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001'),
('62000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000002');
insert into public.pfd_club_memberships(club_id,user_id) values
('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000003'),
('62000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000004');
insert into public.pfd_teams(id,club_id,name,age_group,season) values
('63000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','U14','U14','2026'),
('63000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000002','U15','U15','2026');
insert into public.pfd_team_memberships(team_id,user_id,role_key) values
('63000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000003','coach'),
('63000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000004','player');
update public.pfd_role_permissions set enabled=true where role_key='club_admin';
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role service_role;
do $$ declare
 a uuid:='61000000-0000-4000-8000-000000000001';b uuid:='61000000-0000-4000-8000-000000000002';coach uuid:='61000000-0000-4000-8000-000000000003';player uuid:='61000000-0000-4000-8000-000000000004';outsider uuid:='61000000-0000-4000-8000-000000000005';
 c uuid:='62000000-0000-4000-8000-000000000001';t uuid:='63000000-0000-4000-8000-000000000001';r jsonb;record jsonb;post jsonb;hw jsonb;room jsonb;report jsonb;resource jsonb;sub jsonb;path text;id uuid;
 data jsonb:='{"info":{"name":"Player A"},"ratings":{},"notes":["","","",""],"extra":{},"values":{},"progress":{},"metrics":{},"team_ratings":{},"prepared_by":"Admin A","consent":true}';
 begin
 r:=public.pfd_club_workspace(a,c,'options');if jsonb_array_length(r->'people')<>3 or jsonb_array_length(r->'templates')<>8 then raise exception 'Options scope';end if;
 begin perform public.pfd_club_workspace(b,c,'options');raise exception 'Other admin entered club';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_workspace(outsider,c,'options');raise exception 'Unapproved account entered club';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_workspace(coach,c,'settings_get');raise exception 'Coach entered club settings';exception when insufficient_privilege then null;end;
 r:=public.pfd_club_workspace(a,c,'users_list','{"role":"player"}');if (r->>'total')::int<>1 then raise exception 'Role picker scope';end if;
 r:=public.pfd_club_workspace(a,c,'person_detail',jsonb_build_object('id',player));
 -- Schedules require a team; recipients are scoped, and attendance requires an actual attendee.
 begin perform public.pfd_club_workspace(a,c,'event_save',jsonb_build_object('id',gen_random_uuid(),'kind','training','title','Session','starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour','timezone','Australia/Adelaide'));raise exception 'Teamless training accepted';exception when invalid_parameter_value then null;end;
 record:=public.pfd_club_workspace(a,c,'event_save',jsonb_build_object('id',gen_random_uuid(),'kind','training','team_id',t,'title','Session','starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour','timezone','Australia/Adelaide'));
 r:=public.pfd_club_workspace(player,c,'my_calendar');if (r->>'total')::int<>1 then raise exception 'Player calendar missing session';end if;
 r:=public.pfd_club_workspace(a,c,'event_detail',jsonb_build_object('id',record->>'id'));if jsonb_array_length(r->'attendees')<>3 then raise exception 'Team recipients';end if;
 perform public.pfd_club_workspace(a,c,'attendance_save',jsonb_build_object('event_id',record->>'id','user_id',player,'status','present'));
 begin perform public.pfd_club_workspace(a,c,'attendance_save',jsonb_build_object('event_id',record->>'id','user_id',outsider,'status','present'));raise exception 'Marked outside attendee';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_club_workspace(a,c,'event_save',record||jsonb_build_object('updated_at',now()-interval '1 day'));raise exception 'Stale event save';exception when serialization_failure then null;end;
 -- Team+role is an intersection: only this team's coach receives the announcement.
 post:=public.pfd_club_workspace(a,c,'announcement_save',jsonb_build_object('id',gen_random_uuid(),'title','Coaches only','body','Meeting','status','published','team_ids',jsonb_build_array(t),'role_keys','["coach"]'::jsonb));
 if(select count(*)from public.pfd_announcement_recipients where announcement_id=(post->>'id')::uuid)<>1 then raise exception 'Audience union leak';end if;
 r:=public.pfd_club_workspace(player,c,'my_announcements');if(r->>'total')::int<>0 then raise exception 'Player saw coaches announcement';end if;
 r:=public.pfd_club_workspace(coach,c,'my_announcements');if(r->>'total')::int<>1 then raise exception 'Coach missed announcement';end if;
 -- Club-private library, and shared PFD content is immutable here.
 resource:=public.pfd_club_workspace(a,c,'resource_save',jsonb_build_object('id',gen_random_uuid(),'title','Passing drill','kind','individual_drill','category','Passing','difficulty','all','instructions','Practice','video_url','','attachments','[]'::jsonb,'audience','selected_clubs','club_ids',jsonb_build_array(c),'status','published','duration_minutes',10,'plan_blocks','[]'::jsonb));
 r:=public.pfd_club_workspace(b,'62000000-0000-4000-8000-000000000002','resources_list','{"scope":"club"}');if(r->>'total')::int<>0 then raise exception 'Private club drill leaked';end if;
 -- All individual reports use real approved player/coach accounts.
 report:=public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',player,'team_id',t,'template_key','fitness','report_date',current_date,'status','submitted','data',data));
 r:=public.pfd_club_workspace(a,c,'report_get',jsonb_build_object('id',report->>'id'));if r->>'subject_id'<>player::text then raise exception 'Report subject not stored';end if;
 perform public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',player,'team_id',t,'template_key','coaches','report_date',current_date,'status','draft','data',data||'{"subject_kind":"player"}'));
 perform public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',coach,'team_id',t,'template_key','coaches','report_date',current_date,'status','draft','data',data||'{"subject_kind":"coach"}'));
 begin perform public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',outsider,'template_key','fitness','report_date',current_date,'status','draft','data',data));raise exception 'Outside report subject';exception when invalid_parameter_value then null;end;
 -- Homework recipients are players; signed-upload scope and submission ownership.
 hw:=public.pfd_club_workspace(a,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Passing homework','instructions','Upload practice','due_at',now()+interval '2 days','resource_id',resource->>'id','team_ids',jsonb_build_array(t)));
 if(select count(*)from public.pfd_homework_recipients where homework_id=(hw->>'id')::uuid)<>1 then raise exception 'Homework nonplayers included';end if;
 r:=public.pfd_club_workspace(player,c,'homework_upload_access',jsonb_build_object('homework_id',hw->>'id'));path:=(r->>'prefix')||'practice.mp4';
 begin perform public.pfd_club_workspace(coach,c,'homework_upload_access',jsonb_build_object('homework_id',hw->>'id'));raise exception 'Coach uploads as player';exception when insufficient_privilege then null;end;
 insert into storage.objects(bucket_id,name)values('pfd-club-files',path);
 sub:=public.pfd_club_workspace(player,c,'submit_homework',jsonb_build_object('id',gen_random_uuid(),'homework_id',hw->>'id','notes','My practice','attachments',jsonb_build_array(jsonb_build_object('path',path,'name','practice.mp4','mime','video/mp4','size',100))));
 perform public.pfd_club_workspace(a,c,'homework_review',jsonb_build_object('id',sub->>'id','updated_at',sub->>'updated_at','feedback','Well done','review_status','reviewed'));
 r:=public.pfd_club_workspace(a,c,'file_access',jsonb_build_object('submission_id',sub->>'id','path',path));
 perform public.pfd_club_workspace(coach,c,'file_access',jsonb_build_object('submission_id',sub->>'id','path',path));
 -- Private chats are participant-only, team chats derive membership.
 room:=public.pfd_club_workspace(a,c,'room_save',jsonb_build_object('id',gen_random_uuid(),'title','Coach group','user_ids',jsonb_build_array(coach)));
 perform public.pfd_club_workspace(coach,c,'send_message',jsonb_build_object('id',gen_random_uuid(),'room_id',room->>'id','body','Hello'));
 r:=public.pfd_club_workspace(a,c,'room_messages',jsonb_build_object('room_id',room->>'id'));if jsonb_array_length(r->'items')<>1 then raise exception 'Missing chat message';end if;
 begin perform public.pfd_club_workspace(player,c,'room_messages',jsonb_build_object('room_id',room->>'id'));raise exception 'Private chat leaked';exception when insufficient_privilege then null;end;
 room:=public.pfd_club_workspace(a,c,'team_chat',jsonb_build_object('team_id',t));r:=public.pfd_club_workspace(player,c,'room_messages',jsonb_build_object('room_id',room->>'id'));
 -- Club settings retain all required details, with stale edit protection.
 r:=public.pfd_club_workspace(a,c,'settings_get');r:=public.pfd_club_workspace(a,c,'settings_save',r||'{"city":"New city"}');if r->>'city'<>'New city' then raise exception 'Settings not saved';end if;
 begin perform public.pfd_club_workspace(a,c,'settings_save',r||jsonb_build_object('updated_at',now()-interval '1 day'));raise exception 'Stale settings save';exception when serialization_failure then null;end;
 r:=public.pfd_club_workspace(a,c,'stats');if(r->>'reports')::int<>1 then raise exception 'Incorrect live report count';end if;
 end $$;
reset role;
update public.pfd_role_permissions set enabled=false where role_key='club_admin' and permission_key='announcements.publish';
set local role service_role;
do $$begin
 begin perform public.pfd_club_workspace('61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','announcement_save','{}');raise exception 'Disabled permission bypass';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','61000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$begin
 begin perform public.pfd_club_workspace(auth.uid(),'62000000-0000-4000-8000-000000000001','stats');raise exception 'Direct service RPC bypass';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pfd_chat_messages)then raise exception 'Direct chat SELECT leaked';end if;
end $$;
reset role;
select 'PASS: club workflow, audiences, schedules, attendance, reports, private resources, homework, uploads, feedback, chat, settings, permissions and direct-client denial' as result;
rollback;
