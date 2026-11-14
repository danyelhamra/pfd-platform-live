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
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role service_role;
do $$declare
 a uuid:='71000000-0000-4000-8000-000000000001';ca uuid:='71000000-0000-4000-8000-000000000002';cb uuid:='71000000-0000-4000-8000-000000000003';pa uuid:='71000000-0000-4000-8000-000000000004';pb uuid:='71000000-0000-4000-8000-000000000005';applicant uuid:='71000000-0000-4000-8000-000000000006';c uuid:='72000000-0000-4000-8000-000000000001';ta uuid:='73000000-0000-4000-8000-000000000001';tb uuid:='73000000-0000-4000-8000-000000000002';owner_id uuid;v jsonb;r jsonb;local_drill jsonb;club_drill jsonb;global_drill jsonb;plan jsonb;otherplan jsonb;hw jsonb;sub jsonb;ev jsonb;req jsonb;
 draft jsonb:='{"info":{"name":"Player A"},"ratings":{},"notes":["","","",""],"extra":{},"values":{},"progress":{},"prepared_by":"Coach A","consent":true}';
 resource jsonb:='{"kind":"individual_drill","title":"Unique coach drill fixture","category":"Passing","difficulty":"all","instructions":"Original practice","status":"published","duration_minutes":10,"attachments":[],"plan_blocks":[]}';
 begin
 select user_id into owner_id from public.pfd_platform_owners order by granted_at limit 1;
 v:=public.pfd_club_workspace(ca,c,'options');if (v->>'workspace_role')is distinct from'coach' or jsonb_array_length(v->'teams')<>1 or jsonb_array_length(v->'people')<>2 then raise exception 'Coach options leak';end if;
 v:=public.pfd_club_workspace(a,c,'options');if(v->>'workspace_role')is distinct from'club_admin'then raise exception 'Club Admin options role missing';end if;
 v:=public.pfd_club_workspace(ca,c,'people_list');if(v->>'total')::int<>2 then raise exception 'Coach directory leak';end if;
 begin perform public.pfd_club_workspace(ca,c,'person_detail',jsonb_build_object('id',pb));raise exception 'Other team player profile leaked';exception when no_data_found then null;end;
 begin perform public.pfd_club_workspace(ca,c,'settings_save','{}');raise exception 'Coach changed club';exception when insufficient_privilege then null;end;
 r:=public.pfd_club_workspace(ca,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',pa,'team_id',ta,'template_key','fitness','report_date',current_date,'status','submitted','data',draft));
 begin perform public.pfd_club_workspace(cb,c,'report_get',jsonb_build_object('id',r->>'id'));raise exception 'Other team report leaked';exception when no_data_found then null;end;
 begin perform public.pfd_club_workspace(ca,c,'report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id',pb,'team_id',tb,'template_key','fitness','report_date',current_date,'status','draft','data',draft));raise exception 'Cross team report';exception when insufficient_privilege then null;end;
 v:=public.pfd_club_workspace(ca,c,'resource_upload_access',jsonb_build_object('team_id',ta));
 insert into storage.objects(bucket_id,name)values('pfd-club-files',(v->>'prefix')||'fixture.mp4');
 local_drill:=public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'team_id',ta,'attachments',jsonb_build_array(jsonb_build_object('path',(v->>'prefix')||'fixture.mp4','name','fixture.mp4'))));
 v:=public.pfd_club_workspace(ca,c,'resource_file_access',jsonb_build_object('resource_id',local_drill->>'id','path',local_drill->'attachments'->0->>'path'));if v->>'bucket'<>'pfd-club-files'then raise exception 'Local bucket incorrect';end if;
 begin perform public.pfd_club_workspace(cb,c,'resource_file_access',jsonb_build_object('resource_id',local_drill->>'id','path',local_drill->'attachments'->0->>'path'));raise exception 'Other team private resource file leaked';exception when insufficient_privilege then null;end;
 v:=public.pfd_club_workspace(cb,c,'resources_list','{"scope":"team"}');if(v->>'total')::int<>0 then raise exception 'Team resource leaked';end if;
 begin perform public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid()));raise exception 'Coach created club/global drill';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'team_id',tb));raise exception 'Coach created in other team';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_workspace(ca,c,'resource_share_club',local_drill);raise exception 'Coach promoted to club';exception when insufficient_privilege then null;end;
 begin perform pfd_private.promote_resource(ca,(local_drill->>'id')::uuid,null,local_drill->>'updated_at');raise exception 'Coach promoted global';exception when insufficient_privilege then null;end;
 club_drill:=public.pfd_club_workspace(a,c,'resource_share_club',local_drill);
 v:=public.pfd_club_workspace(cb,c,'resources_list','{"scope":"club"}');if(v->>'total')::int<>1 then raise exception 'Club copy missing';end if;
 begin perform public.pfd_club_workspace(ca,c,'resource_save',club_drill||'{"instructions":"Tampered"}');raise exception 'Coach edited club copy';exception when insufficient_privilege then null;end;
 global_drill:=pfd_private.promote_resource(owner_id,(club_drill->>'id')::uuid,null,club_drill->>'updated_at');
 v:=public.pfd_club_workspace(cb,c,'resource_file_access',jsonb_build_object('resource_id',global_drill->>'id','path',global_drill->'attachments'->0->>'path'));if v->>'bucket'<>'pfd-club-files'then raise exception 'Approved copy lost immutable bucket metadata';end if;
 local_drill:=public.pfd_club_workspace(ca,c,'resource_save',local_drill||'{"instructions":"Edited local practice"}');
 if(select instructions from public.pfd_resources where id=(global_drill->>'id')::uuid)<>'Original practice'then raise exception 'Local edit mutated global snapshot';end if;
 begin perform pfd_private.promote_resource(owner_id,(club_drill->>'id')::uuid,null,club_drill->>'updated_at');raise exception 'Duplicate source promotion';exception when unique_violation then null;end;
 -- Same-name global duplicate is independently blocked, even from another source.
 r:=public.pfd_club_workspace(cb,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'team_id',tb));
 begin perform pfd_private.promote_resource(owner_id,(r->>'id')::uuid,null,r->>'updated_at');raise exception 'Duplicate global title';exception when unique_violation then null;end;
 -- Team plans cannot expose private drills by changing their visibility.
 plan:=public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'title','Fixture timed plan','kind','training_plan','team_id',ta,'plan_blocks',jsonb_build_array(jsonb_build_object('resource_id',local_drill->>'id','minutes',12))));
 otherplan:=pfd_private.promote_resource(owner_id,(plan->>'id')::uuid,null,plan->>'updated_at');
 if(otherplan->'plan_blocks'->0->>'resource_id')<>(global_drill->>'id')then raise exception 'Plan did not remap to approved global drill';end if;
 r:=public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'title','Unapproved drill fixture','team_id',ta));
 plan:=public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'title','Unapproved plan fixture','kind','training_plan','team_id',ta,'plan_blocks',jsonb_build_array(jsonb_build_object('resource_id',r->>'id','minutes',10))));
 begin perform pfd_private.promote_resource(owner_id,(plan->>'id')::uuid,null,plan->>'updated_at');raise exception 'Plan exposed unapproved drill';exception when invalid_parameter_value then null;end;
 -- Team schedules and homework are inaccessible to another coach in the same club.
 ev:=public.pfd_club_workspace(ca,c,'event_save',jsonb_build_object('id',gen_random_uuid(),'kind','training','team_id',ta,'title','Team A session','starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour','timezone','Australia/Adelaide'));
 begin perform public.pfd_club_workspace(cb,c,'event_detail',ev);raise exception 'Other team attendance exposed';exception when no_data_found then null;end;
 begin perform public.pfd_club_workspace(cb,c,'event_save',ev);raise exception 'Other coach edited session';exception when insufficient_privilege then null;end;
 hw:=public.pfd_club_workspace(ca,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Team homework','due_at',now()+interval '2 days','team_ids',jsonb_build_array(ta),'resource_id',local_drill->>'id'));
 begin perform public.pfd_club_workspace(cb,c,'homework_detail',hw);raise exception 'Other team homework exposed';exception when no_data_found then null;end;
 begin perform public.pfd_club_workspace(ca,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Other team homework','due_at',now()+interval '2 days','team_ids',jsonb_build_array(tb)));raise exception 'Other team homework assignment';exception when insufficient_privilege then null;end;
 -- Coach sees invited club events through personal calendar even without a team_id.
 ev:=public.pfd_club_workspace(a,c,'event_save',jsonb_build_object('id',gen_random_uuid(),'kind','event','title','Coaches meeting','role_keys','["coach"]'::jsonb,'starts_at',now()+interval '1 day','ends_at',now()+interval '1 day 1 hour','timezone','Australia/Adelaide'));
 v:=public.pfd_club_workspace(ca,c,'my_calendar');if(v->>'total')::int<>2 then raise exception 'Invited club meeting missing';end if;
 -- Requests: approved club members, player role, coach's own team only.
 req:=public.pfd_membership_flow(applicant,'request_team',jsonb_build_object('club_id',c,'team_id',ta,'role_key','player'));
 begin perform public.pfd_membership_flow(cb,'review_request',jsonb_build_object('club_id',c,'id',req->>'id','decision','approved'));raise exception 'Other coach approved player';exception when insufficient_privilege then null;end;
 perform public.pfd_membership_flow(ca,'review_request',jsonb_build_object('club_id',c,'id',req->>'id','decision','approved'));
 if not exists(select 1 from public.pfd_team_memberships where team_id=ta and user_id=applicant and role_key='player')then raise exception 'Coach approval missing';end if;
 -- Fresh role/permission revocation applies without trusting metadata or cached JWT claims.
 update public.pfd_role_permissions set enabled=false where role_key='coach'and permission_key='library.manage_team';
 begin perform public.pfd_club_workspace(ca,c,'resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'team_id',ta));raise exception 'Disabled team library permission bypassed';exception when insufficient_privilege then null;end;
 delete from public.pfd_team_memberships where user_id=ca and role_key='coach';
 begin perform public.pfd_club_workspace(ca,c,'options');raise exception 'Removed coach kept staff access';exception when insufficient_privilege then null;end;
 end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','71000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$declare owner_id uuid;begin
 begin insert into storage.objects(bucket_id,name)values('pfd-club-files','forged-resource-upload');raise exception 'Direct client storage upload allowed';exception when insufficient_privilege then null;end;
 select user_id into owner_id from public.pfd_platform_owners limit 1;
 begin perform pfd_private.promote_resource('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',null,null);raise exception 'Forged actor promotion';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select user_id::text from public.pfd_platform_owners order by granted_at limit 1),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
set local role authenticated;
do $$declare src public.pfd_resources;r jsonb;begin
 select *into src from public.pfd_resources where title='Unapproved drill fixture';
 r:=public.pfd_owner_workspace('resource_promote',jsonb_build_object('id',src.id,'updated_at',src.updated_at));
 if r->>'club_id' is not null or r->>'source_resource_id'<>src.id::text then raise exception 'Owner approval RPC failed';end if;
 if not exists(select 1 from storage.objects where bucket_id='pfd-club-files'and name like '%fixture.mp4')then raise exception 'Owner cannot review local source files';end if;
end $$;
reset role;
select 'PASS: actual coach team scope, directory/profiles/reports, resource ownership, Team/Club/Global approval, immutable copies, duplicate prevention, plan dependency approval, calendar/homework boundaries, invited meetings, player requests and live permission/membership revocation' as result;
rollback;
