-- Full Player flow; all accounts, reports, uploads and role changes roll back.
-- Rollback-only regression for actual coach scopes and Team -> Club -> Global approval.
begin;
insert into auth.users(id,email,raw_user_meta_data,created_at,updated_at)values
('71000000-0000-4000-8000-000000000001','coach-admin@local.invalid','{"full_name":"Admin"}',now(),now()),
('71000000-0000-4000-8000-000000000002','coach-a@local.invalid','{"full_name":"Coach A"}',now(),now()),
('71000000-0000-4000-8000-000000000003','coach-b@local.invalid','{"full_name":"Coach B"}',now(),now()),
('71000000-0000-4000-8000-000000000004','player-a@local.invalid','{"full_name":"Player A"}',now(),now()),
('71000000-0000-4000-8000-000000000005','player-b@local.invalid','{"full_name":"Player B"}',now(),now()),
('71000000-0000-4000-8000-000000000006','applicant@local.invalid','{"full_name":"Applicant"}',now(),now());
insert into public.pfd_clubs(id,name,location,city,state,country,contact_email,contact_number,league,sport,status)values('72000000-0000-4000-8000-000000000001','Coach fixture','Adelaide','Adelaide','SA','Australia','club@local.invalid','0412345678','League','Soccer','active');
insert into public.pfd_club_admins(club_id,user_id)values('72000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001');
insert into public.pfd_club_memberships(club_id,user_id)select '72000000-0000-4000-8000-000000000001',id from auth.users where id in('71000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','71000000-0000-4000-8000-000000000004','71000000-0000-4000-8000-000000000005','71000000-0000-4000-8000-000000000006');
insert into public.pfd_teams(id,club_id,name,age_group,season)values('73000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','Team A','U14','2026'),('73000000-0000-4000-8000-000000000002','72000000-0000-4000-8000-000000000001','Team B','U15','2026');
insert into public.pfd_team_memberships(team_id,user_id,role_key)values
('73000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002','coach'),
('73000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000003','coach'),
('73000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000004','player'),
('73000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000005','player');
insert into public.pfd_team_memberships(team_id,user_id,role_key)values('73000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000006','player');
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role service_role;
do $$declare
 a uuid:='71000000-0000-4000-8000-000000000001';ca uuid:='71000000-0000-4000-8000-000000000002';pa uuid:='71000000-0000-4000-8000-000000000004';pb uuid:='71000000-0000-4000-8000-000000000005';other_player uuid:='71000000-0000-4000-8000-000000000006';c uuid:='72000000-0000-4000-8000-000000000001';ta uuid:='73000000-0000-4000-8000-000000000001';tb uuid:='73000000-0000-4000-8000-000000000002';owner_id uuid;
 v jsonb;r jsonb;mine jsonb;other jsonb;staff_draft jsonb;self_draft jsonb;match jsonb;global_drill uuid:=gen_random_uuid();private_drill jsonb;club_drill jsonb;hw jsonb;sub jsonb;upload jsonb;session jsonb;meeting jsonb;room jsonb;path text;
 data jsonb:='{"info":{"name":"Player A"},"ratings":{},"notes":["","","",""],"extra":{},"values":{},"progress":{},"metrics":{},"team_ratings":{},"prepared_by":"Admin","consent":true}';
 resource jsonb:='{"kind":"individual_drill","title":"Player library fixture club","category":"Passing","difficulty":"all","instructions":"Published practice","status":"published","duration_minutes":10,"attachments":[],"plan_blocks":[]}';
 begin
 select user_id into owner_id from public.pfd_platform_owners order by granted_at limit 1;
 v:=public.pfd_player_workspace(pa,c,'player_options');if(v->>'workspace_role')is distinct from'player'or(v->'self'->>'id')is distinct from pa::text or jsonb_array_length(v->'teams')<>1 then raise exception 'Canonical Player context invalid';end if;
 if not(v->'self_templates'?'fitness')or v->'self_templates'?'coaches'then raise exception 'Self template allowlist incorrect';end if;
 begin perform public.pfd_player_workspace(owner_id,c,'player_options');raise exception 'Owner entered Player view';exception when insufficient_privilege then null;end;
 begin perform public.pfd_player_workspace(ca,c,'player_options');raise exception 'Coach without player membership entered Player view';exception when insufficient_privilege then null;end;
 mine:=public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',pa,'team_id',ta,'template_key','fitness','report_date',current_date,'status','submitted','data',data));
 other:=public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',pb,'team_id',tb,'template_key','fitness','report_date',current_date,'status','submitted','data',data));
 staff_draft:=public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',pa,'team_id',ta,'template_key','fitness','report_date',current_date,'status','draft','data',data));
 v:=public.pfd_player_workspace(pa,c,'player_reports_list');if(v->>'total')::int<>1 then raise exception 'Player report list exposed another account or staff draft';end if;
 v:=public.pfd_player_workspace(pa,c,'player_report_get',mine);if(v->>'read_only')::boolean is distinct from true then raise exception 'Coach report writable';end if;
 begin perform public.pfd_player_workspace(pa,c,'player_report_get',other);raise exception 'Another player report exposed';exception when no_data_found then null;end;
 begin perform public.pfd_player_workspace(pa,c,'player_report_get',staff_draft);raise exception 'Staff draft exposed';exception when no_data_found then null;end;
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',mine||'{"status":"draft"}');raise exception 'Player edited staff report';exception when insufficient_privilege then null;end;
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',pb,'team_id',ta,'template_key','fitness','status','draft','report_date',current_date,'data',data));raise exception 'Forged self subject';exception when insufficient_privilege then null;end;
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',jsonb_build_object('id',gen_random_uuid(),'team_id',tb,'template_key','fitness','status','draft','report_date',current_date,'data',data));raise exception 'Self report in other team';exception when insufficient_privilege then null;end;
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',jsonb_build_object('id',gen_random_uuid(),'team_id',ta,'template_key','coaches','status','draft','report_date',current_date,'data',data));raise exception 'Player created coach template';exception when insufficient_privilege then null;end;
 self_draft:=public.pfd_player_workspace(pa,c,'player_report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',pa,'team_id',ta,'template_key','fitness','status','draft','report_date',current_date,'data',data||'{"prepared_by":"Fake coach","reviewer":"Forged review"}'));
 if(self_draft->>'subject_id')is distinct from pa::text or(self_draft->>'created_by')is distinct from pa::text or(self_draft->'data'->>'entry_kind')is distinct from'self_assessment'or(self_draft->'data'->>'prepared_by')is distinct from'Player A'or(self_draft->'data'->>'reviewer')is distinct from''then raise exception 'Self-assessment identity or origin spoofed';end if;
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',self_draft||jsonb_build_object('updated_at',now()-interval '1 day'));raise exception 'Stale self edit';exception when serialization_failure then null;end;
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',self_draft||jsonb_build_object('data',self_draft->'data'||'{"ratings":{"Movement-0":6}}'));raise exception 'Invalid original rating accepted';exception when invalid_parameter_value then null;end;
 self_draft:=public.pfd_player_workspace(pa,c,'player_report_save',self_draft||'{"status":"submitted"}');
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',self_draft);raise exception 'Submitted self edit';exception when invalid_parameter_value then null;end;
 match:=public.pfd_club_workspace(a,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'team_id',ta,'template_key','match_review','report_date',current_date,'status','submitted','data',data||jsonb_build_object('notes','["Private team notes","","",""]'::jsonb,'team_ratings',jsonb_build_object(pa::text,jsonb_build_object('rating',3),other_player::text,jsonb_build_object('rating',5)))));
 begin perform public.pfd_player_workspace(pa,c,'player_report_get',match);raise exception 'Full team review exposed';exception when no_data_found then null;end;
 v:=public.pfd_player_workspace(pa,c,'player_progress');select x into r from jsonb_array_elements(v)x where x->>'id'=match->>'id';
 if r is null or r->'data'?'notes'or r->'data'->'team_ratings'?other_player::text or(r->'data'->'team_ratings'->pa::text->>'rating')::int is distinct from 3 then raise exception 'Match progress exposed other ratings or notes';end if;
 -- Only published individual drills at Global, Club or joined Team level.
 insert into public.pfd_resources(id,title,kind,instructions,status,audience,duration_minutes,created_by)values(global_drill,'Player library fixture global','individual_drill','Global practice','published','all_clubs',10,owner_id),
 (gen_random_uuid(),'Player library fixture team drill','team_drill','Staff only','published','all_clubs',10,owner_id),
 (gen_random_uuid(),'Player library fixture draft','individual_drill','Unpublished','draft','all_clubs',10,owner_id);
 private_drill:=public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'title','Player library fixture team','team_id',ta));
 club_drill:=public.pfd_club_workspace(a,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid()));
 r:=public.pfd_club_workspace(a,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'title','Player library fixture other team','team_id',tb));
 v:=public.pfd_player_workspace(pa,c,'player_resources_list','{"query":"Player library fixture"}');if(v->>'total')::int<>3 then raise exception 'Library visibility wrong';end if;
 begin perform public.pfd_player_workspace(pa,c,'player_resource_file_access',jsonb_build_object('resource_id',r->>'id','path','forged'));raise exception 'Other team resource file exposed';exception when insufficient_privilege then null;end;
 -- Assignment snapshots retain supporting files; uploads and feedback remain personal.
 upload:=public.pfd_club_workspace(ca,c,'resource_upload_access',jsonb_build_object('team_id',ta));path:=(upload->>'prefix')||'drill.pdf';insert into storage.objects(bucket_id,name)values('pfd-club-files',path);
 private_drill:=public.pfd_club_workspace(ca,c,'resource_save',private_drill||jsonb_build_object('attachments',jsonb_build_array(jsonb_build_object('path',path,'name','drill.pdf'))));
 hw:=public.pfd_club_workspace(a,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Player homework fixture','due_at',now()+interval '1 day','team_ids',jsonb_build_array(ta),'user_ids',jsonb_build_array(pa),'resource_id',private_drill->>'id'));
 private_drill:=public.pfd_club_workspace(ca,c,'resource_save',private_drill||'{"status":"archived"}');
 v:=public.pfd_player_workspace(pa,c,'player_homework_file_access',jsonb_build_object('homework_id',hw->>'id','path',path));if(v->>'bucket')is distinct from'pfd-club-files'then raise exception 'Assigned supporting file missing';end if;
 begin perform public.pfd_player_workspace(pb,c,'player_homework_file_access',jsonb_build_object('homework_id',hw->>'id','path',path));raise exception 'Other homework drill file exposed';exception when insufficient_privilege then null;end;
 upload:=public.pfd_club_workspace(pa,c,'homework_upload_access',jsonb_build_object('homework_id',hw->>'id'));path:=(upload->>'prefix')||'practice.mov';insert into storage.objects(bucket_id,name)values('pfd-club-files',path);
 if not(select 'video/quicktime'=any(allowed_mime_types)from storage.buckets where id='pfd-club-files')then raise exception 'iPhone video format unavailable';end if;
 sub:=public.pfd_club_workspace(pa,c,'submit_homework',jsonb_build_object('id',gen_random_uuid(),'homework_id',hw->>'id','notes','My practice','attachments',jsonb_build_array(jsonb_build_object('path',path,'name','practice.mov','mime','video/quicktime','size',100))));
 perform public.pfd_club_workspace(ca,c,'homework_review',jsonb_build_object('id',sub->>'id','updated_at',sub->>'updated_at','feedback','Keep your head up','review_status','reviewed'));
 v:=public.pfd_club_workspace(pa,c,'my_homework');if(v->'items'->0->'my_submission'->>'feedback')is distinct from'Keep your head up'then raise exception 'Own coach feedback unavailable';end if;
 begin perform public.pfd_club_workspace(pb,c,'file_access',jsonb_build_object('submission_id',sub->>'id','path',path));raise exception 'Other player video exposed';exception when insufficient_privilege then null;end;
 -- Schedules follow current team membership, including a newly joined player.
 session:=public.pfd_club_workspace(a,c,'event_save',jsonb_build_object('id',gen_random_uuid(),'kind','training','team_id',ta,'title','Player session fixture','starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour','timezone','Australia/Adelaide'));
 delete from public.pfd_event_recipients where event_id=(session->>'id')::uuid and user_id=pa;
 meeting:=public.pfd_club_workspace(a,c,'event_save',jsonb_build_object('id',gen_random_uuid(),'kind','event','title','Staff-only meeting fixture','role_keys','["coach"]'::jsonb,'starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour','timezone','Australia/Adelaide'));
 v:=public.pfd_player_workspace(pa,c,'player_calendar');if(v->>'total')::int<>1 then raise exception 'Player schedule or invitation scope wrong';end if;
 perform public.pfd_player_workspace(pa,c,'player_event_response',jsonb_build_object('id',session->>'id','user_id',pb,'response','attending'));
 v:=public.pfd_club_workspace(a,c,'event_detail',session);if not exists(select 1 from jsonb_array_elements(v->'attendees')x where x->>'id'=pa::text and x->>'response'='attending')then raise exception 'Staff cannot see player availability';end if;
 begin perform public.pfd_player_workspace(pb,c,'player_event_response',jsonb_build_object('id',session->>'id','response','attending'));raise exception 'Other team RSVP allowed';exception when insufficient_privilege then null;end;
 begin perform public.pfd_player_workspace(pa,c,'player_event_response',jsonb_build_object('id',meeting->>'id','response','attending'));raise exception 'Uninvited event RSVP';exception when insufficient_privilege then null;end;
 room:=public.pfd_player_workspace(pa,c,'player_team_chat',jsonb_build_object('team_id',ta));
 perform public.pfd_club_workspace(pa,c,'send_message',jsonb_build_object('id',gen_random_uuid(),'room_id',room->>'id','body','Ready for practice'));
 begin perform public.pfd_club_workspace(pb,c,'room_messages',jsonb_build_object('room_id',room->>'id'));raise exception 'Other player team chat exposed';exception when insufficient_privilege then null;end;
 begin perform public.pfd_player_workspace(pb,c,'player_team_chat',jsonb_build_object('team_id',ta));raise exception 'Player opened other team chat';exception when insufficient_privilege then null;end;
 v:=public.pfd_player_workspace(pa,c,'player_stats');if(v->>'reports')::int is distinct from 2 or(v->>'upcoming')::int is distinct from 1 or(v->'feedback'->0->>'feedback')is distinct from'Keep your head up'then raise exception 'Player overview data wrong';end if;
 update public.pfd_role_permissions set enabled=false where role_key='player'and permission_key='reports.view_own';
 begin perform public.pfd_player_workspace(pa,c,'player_report_get',mine);raise exception 'Revoked own-report permission bypassed';exception when insufficient_privilege then null;end;
 update public.pfd_role_permissions set enabled=false where role_key='player'and permission_key='reports.self_assess';
 begin perform public.pfd_player_workspace(pa,c,'player_report_save',self_draft);raise exception 'Revoked self-assessment permission bypassed';exception when insufficient_privilege then null;end;
 delete from public.pfd_team_memberships where user_id=pa and role_key='player';
 begin perform public.pfd_player_workspace(pa,c,'player_options');raise exception 'Removed player kept workspace';exception when insufficient_privilege then null;end;
 end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$begin
 begin perform public.pfd_player_workspace(auth.uid(),'72000000-0000-4000-8000-000000000001','player_options');raise exception 'Client called service RPC';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pfd_reports)then raise exception 'Direct player report SELECT leaked';end if;
end $$;
reset role;
select 'PASS: Player context, own reports/self-assessments, staff-draft isolation, immutable submissions, redacted match progress, published individual-library levels, private assignment files/MOV uploads/feedback, team calendar/RSVP, team chat, overview and live permission/membership revocation' as result;
rollback;
