-- Rollback-only regression: coach review of Club Admin assignments.
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
set local role service_role;
do $$declare
 a uuid:='71000000-0000-4000-8000-000000000001';ca uuid:='71000000-0000-4000-8000-000000000002';cb uuid:='71000000-0000-4000-8000-000000000003';pa uuid:='71000000-0000-4000-8000-000000000004';pb uuid:='71000000-0000-4000-8000-000000000005';c uuid:='72000000-0000-4000-8000-000000000001';ta uuid:='73000000-0000-4000-8000-000000000001';tb uuid:='73000000-0000-4000-8000-000000000002';v jsonb;shared_hw jsonb;individual_hw jsonb;upload jsonb;sub_a jsonb;sub_b jsonb;
begin
 perform public.pfd_club_workspace(ca,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Coach own homework regression','due_at',now()+interval '2 days','team_ids',jsonb_build_array(ta)));
 -- Club Admin homework is visible to each assigned player's own coach.
 shared_hw:=public.pfd_club_workspace(a,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Admin shared homework regression','due_at',now()+interval '2 days','team_ids',jsonb_build_array(ta,tb)));
 upload:=public.pfd_club_workspace(pa,c,'homework_upload_access',jsonb_build_object('homework_id',shared_hw->>'id'));
 insert into storage.objects(bucket_id,name)values('pfd-club-files',(upload->>'prefix')||'player-a.mp4');
 sub_a:=public.pfd_club_workspace(pa,c,'submit_homework',jsonb_build_object('id',gen_random_uuid(),'homework_id',shared_hw->>'id','notes','Player A upload','attachments',jsonb_build_array(jsonb_build_object('path',(upload->>'prefix')||'player-a.mp4','name','player-a.mp4'))));
 v:=public.pfd_club_workspace(ca,c,'homework_list','{"query":"Admin shared homework regression"}');
 if (v->>'total')::int<>1 or (v->'items'->0->>'recipient_count')::int<>1 or(v->'items'->0->>'submission_count')::int<>1 or(v->'items'->0->>'can_edit')::boolean is distinct from false then raise exception 'Admin shared homework visibility or counts incorrect';end if;
 v:=public.pfd_club_workspace(cb,c,'homework_list','{"query":"Admin shared homework regression"}');if(v->'items'->0->>'submission_count')::int<>0 then raise exception 'Other team submission count leaked';end if;
 upload:=public.pfd_club_workspace(pb,c,'homework_upload_access',jsonb_build_object('homework_id',shared_hw->>'id'));
 insert into storage.objects(bucket_id,name)values('pfd-club-files',(upload->>'prefix')||'player-b.mp4');
 sub_b:=public.pfd_club_workspace(pb,c,'submit_homework',jsonb_build_object('id',gen_random_uuid(),'homework_id',shared_hw->>'id','notes','Player B upload','attachments',jsonb_build_array(jsonb_build_object('path',(upload->>'prefix')||'player-b.mp4','name','player-b.mp4'))));
 v:=public.pfd_club_workspace(ca,c,'homework_detail',shared_hw);if jsonb_array_length(v->'players')<>1 or(v->'players'->0->>'id')is distinct from pa::text then raise exception 'Shared detail leaked another team';end if;
 v:=public.pfd_club_workspace(cb,c,'homework_detail',shared_hw);if jsonb_array_length(v->'players')<>1 or(v->'players'->0->>'id')is distinct from pb::text then raise exception 'Second coach detail not scoped';end if;
 perform public.pfd_club_workspace(ca,c,'file_access',jsonb_build_object('submission_id',sub_a->>'id','path',sub_a->'attachments'->0->>'path'));
 begin perform public.pfd_club_workspace(ca,c,'file_access',jsonb_build_object('submission_id',sub_b->>'id','path',sub_b->'attachments'->0->>'path'));raise exception 'Other team shared upload exposed';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_workspace(ca,c,'homework_review',jsonb_build_object('id',sub_b->>'id','updated_at',sub_b->>'updated_at','feedback','Wrong coach','review_status','reviewed'));raise exception 'Other team review allowed';exception when no_data_found then null;end;
 perform public.pfd_club_workspace(ca,c,'homework_review',jsonb_build_object('id',sub_a->>'id','updated_at',sub_a->>'updated_at','feedback','Coach feedback on admin assignment','review_status','reviewed'));
 v:=public.pfd_club_workspace(ca,c,'stats');if(v->>'awaiting_review')::int<>0 then raise exception 'Other team awaiting-review count leaked';end if;
 v:=public.pfd_club_workspace(cb,c,'stats');if(v->>'awaiting_review')::int<>1 then raise exception 'Coach awaiting-review count incorrect';end if;
 individual_hw:=public.pfd_club_workspace(a,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Admin individual homework regression','due_at',now()+interval '2 days','user_ids',jsonb_build_array(pa)));
 sub_a:=public.pfd_club_workspace(pa,c,'submit_homework',jsonb_build_object('id',gen_random_uuid(),'homework_id',individual_hw->>'id','notes','Individual practice','attachments','[]'::jsonb));
 v:=public.pfd_club_workspace(ca,c,'homework_detail',individual_hw);if jsonb_array_length(v->'players')<>1 then raise exception 'Direct individual admin assignment missing';end if;
 perform public.pfd_club_workspace(ca,c,'homework_review',jsonb_build_object('id',sub_a->>'id','updated_at',sub_a->>'updated_at','feedback','Reviewed direct assignment','review_status','reviewed'));
 begin perform public.pfd_club_workspace(cb,c,'homework_detail',individual_hw);raise exception 'Individual assignment leaked to other coach';exception when no_data_found then null;end;
 v:=public.pfd_club_workspace(ca,c,'stats');if(v->>'homework')::int<>3 then raise exception 'Admin-assigned homework absent from overview';end if;
 -- A multi-team player does not expose an explicit Team B assignment to Team A's coach.
 insert into public.pfd_team_memberships(team_id,user_id,role_key)values(tb,pa,'player');
 individual_hw:=public.pfd_club_workspace(a,c,'homework_save',jsonb_build_object('id',gen_random_uuid(),'title','Team B only regression','due_at',now()+interval '2 days','team_ids',jsonb_build_array(tb),'user_ids',jsonb_build_array(pa)));
 begin perform public.pfd_club_workspace(ca,c,'homework_detail',individual_hw);raise exception 'Explicit other-team assignment leaked through multi-team player';exception when no_data_found then null;end;
 perform public.pfd_club_workspace(cb,c,'homework_detail',individual_hw);
 delete from public.pfd_team_memberships where team_id=tb and user_id=pa and role_key='player';
end $$;
reset role;
select 'PASS: Club Admin individual/shared homework visible to current team coaches; submissions, signed file access, feedback and counts scoped per player; explicit other-team isolation preserved' as result;
rollback;
