-- Service RPC integration tests. All users, teams and permissions are rolled back.
begin;
insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at) values
 ('51000000-0000-4000-8000-000000000001','authenticated','authenticated','teams-admin-a@example.invalid','{"full_name":"Admin A","role":"owner"}','{}',now(),now()),
 ('51000000-0000-4000-8000-000000000002','authenticated','authenticated','teams-admin-b@example.invalid','{"full_name":"Admin B"}','{}',now(),now()),
 ('51000000-0000-4000-8000-000000000003','authenticated','authenticated','teams-coach@example.invalid','{"full_name":"Fixture Coach"}','{}',now(),now()),
 ('51000000-0000-4000-8000-000000000004','authenticated','authenticated','teams-player@example.invalid','{"full_name":"Fixture Player"}','{}',now(),now());
insert into public.pfd_clubs(id,name,location,city,state,country,contact_email,contact_number,league,sport,status) values
 ('52000000-0000-4000-8000-000000000001','Teams fixture A','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture league','Soccer','active'),
 ('52000000-0000-4000-8000-000000000002','Teams fixture B','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture league','Soccer','active'),
 ('52000000-0000-4000-8000-000000000003','Teams fixture archived','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture league','Soccer','archived');
insert into public.pfd_club_admins(club_id,user_id) values
 ('52000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000001'),
 ('52000000-0000-4000-8000-000000000003','51000000-0000-4000-8000-000000000001'),
 ('52000000-0000-4000-8000-000000000002','51000000-0000-4000-8000-000000000002');
update public.pfd_role_permissions set enabled=true where role_key='club_admin' and permission_key in ('clubs.view','teams.view','teams.create','members.view','coaches.approve','players.approve');
insert into public.pfd_teams(id,club_id,name,age_group,season) values('54000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000001','Join Fixture U14','U14','2026'),('54000000-0000-4000-8000-000000000002','52000000-0000-4000-8000-000000000002','Other Join U14','U14','2026');
update public.pfd_role_permissions set enabled=true where role_key='club_admin' and permission_key='members.approve';
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role service_role;
do $$ declare a uuid:='51000000-0000-4000-8000-000000000001';b uuid:='51000000-0000-4000-8000-000000000002';person uuid:='51000000-0000-4000-8000-000000000003';other_person uuid:='51000000-0000-4000-8000-000000000004';c uuid:='52000000-0000-4000-8000-000000000001';other_club uuid:='52000000-0000-4000-8000-000000000002';t uuid:='54000000-0000-4000-8000-000000000001';r jsonb;req uuid;begin
 if not exists(select 1 from public.pfd_club_memberships where club_id=c and user_id=a) then raise exception 'Owner-assigned admin was not admitted';end if;
 r:=public.pfd_membership_flow(person,'browse_clubs');if exists(select 1 from jsonb_array_elements(r->'items')x where x ? 'contact_email' or x ? 'contact_number') then raise exception 'Public directory leaked contact data';end if;
 begin perform public.pfd_membership_flow(person,'club_teams',jsonb_build_object('club_id',c));raise exception 'Unapproved account browsed teams';exception when insufficient_privilege then null;end;
 r:=public.pfd_membership_flow(person,'request_club',jsonb_build_object('club_id',c,'user_id',other_person,'role_key','club_admin','message','Please admit me'));req:=(r->>'id')::uuid;
 if not exists(select 1 from public.pfd_access_requests where id=req and user_id=person and role_key='member' and team_id is null) then raise exception 'Club request actor/type tampered';end if;
 begin perform public.pfd_membership_flow(person,'request_club',jsonb_build_object('club_id',c));raise exception 'Duplicate pending club request';exception when unique_violation then null;end;
 begin perform public.pfd_membership_flow(person,'request_team',jsonb_build_object('club_id',c,'team_id',t,'role_key','player'));raise exception 'Pending club request bypassed gate';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t,'user_id',person,'role_key','player','email','teams-coach@example.invalid'));raise exception 'Email bypassed club approval';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_membership_flow(b,'review_request',jsonb_build_object('club_id',c,'id',req,'decision','approved'));raise exception 'Other club admin reviewed request';exception when insufficient_privilege then null;end;
 begin perform public.pfd_membership_flow(person,'review_request',jsonb_build_object('club_id',c,'id',req,'decision','approved'));raise exception 'Applicant approved self';exception when insufficient_privilege then null;end;
 perform public.pfd_membership_flow(a,'review_request',jsonb_build_object('club_id',c,'id',req,'decision','approved'));
 if not exists(select 1 from public.pfd_club_memberships where club_id=c and user_id=person) or exists(select 1 from public.pfd_team_memberships where user_id=person) then raise exception 'Club approval incorrectly assigned team';end if;
 r:=public.pfd_membership_flow(person,'club_teams',jsonb_build_object('club_id',c));if jsonb_array_length(r)<>1 then raise exception 'Approved club teams scope failed';end if;
 begin perform public.pfd_membership_flow(person,'request_team',jsonb_build_object('club_id',c,'team_id','54000000-0000-4000-8000-000000000002','role_key','player'));raise exception 'Cross-club team request';exception when invalid_parameter_value then null;end;
 r:=public.pfd_club_teams(a,c,'candidates',jsonb_build_object('team_id',t,'role_key','player','query','Fixture Coach'));if (r->>'total')::int<>1 then raise exception 'Approved unassigned member not in picker';end if;
 r:=public.pfd_membership_flow(person,'request_team',jsonb_build_object('club_id',c,'team_id',t,'role_key','player'));req:=(r->>'id')::uuid;
 perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t,'user_id',person,'role_key','player'));
 if not exists(select 1 from public.pfd_access_requests where id=req and status='approved') then raise exception 'Direct assignment left request pending';end if;
 if not exists(select 1 from public.pfd_team_memberships where team_id=t and user_id=person and role_key='player') then raise exception 'Team assignment failed';end if;
 r:=public.pfd_membership_flow(person,'request_team',jsonb_build_object('club_id',c,'team_id',t,'role_key','coach'));req:=(r->>'id')::uuid;
 perform public.pfd_membership_flow(a,'review_request',jsonb_build_object('club_id',c,'id',req,'decision','approved'));
 if (select count(*) from public.pfd_team_memberships where team_id=t and user_id=person)<>2 then raise exception 'Approved second role replaced first';end if;
 r:=public.pfd_membership_flow(other_person,'request_club',jsonb_build_object('club_id',c));req:=(r->>'id')::uuid;
 begin perform public.pfd_membership_flow(a,'review_request',jsonb_build_object('club_id',c,'id',req,'decision','rejected'));raise exception 'Rejection without note';exception when invalid_parameter_value then null;end;
 perform public.pfd_membership_flow(a,'review_request',jsonb_build_object('club_id',c,'id',req,'decision','rejected','reason','Fixture rejection'));
 if exists(select 1 from public.pfd_club_memberships where club_id=c and user_id=other_person) then raise exception 'Rejection admitted user';end if;
 r:=public.pfd_membership_flow(other_person,'my_access');if exists(select 1 from jsonb_array_elements(r->'requests')x where x->>'id'<>req::text) then raise exception 'Own request history leaked other accounts';end if;
 r:=public.pfd_membership_flow(other_person,'request_club',jsonb_build_object('club_id',other_club));
 perform public.pfd_membership_flow(b,'review_request',jsonb_build_object('club_id',other_club,'id',r->>'id','decision','approved'));
 begin perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t,'user_id',other_person,'role_key','player'));raise exception 'Other club membership used in this club';exception when invalid_parameter_value then null;end;
end $$;
reset role;
update public.pfd_role_permissions set enabled=false where role_key='club_admin' and permission_key='members.approve';
set local role service_role;
do $$ declare r jsonb;begin
 r:=public.pfd_membership_flow('51000000-0000-4000-8000-000000000004','request_club','{"club_id":"52000000-0000-4000-8000-000000000001"}');
 begin perform public.pfd_membership_flow('51000000-0000-4000-8000-000000000001','review_request',jsonb_build_object('club_id','52000000-0000-4000-8000-000000000001','id',r->>'id','decision','approved'));raise exception 'Disabled approval permission bypassed';exception when insufficient_privilege then null;end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$ begin
 begin insert into public.pfd_club_memberships(club_id,user_id)values('52000000-0000-4000-8000-000000000001',auth.uid());raise exception 'Self-admission by direct insert';exception when insufficient_privilege then null;end;
 begin perform public.pfd_membership_flow(auth.uid(),'my_access');raise exception 'Direct client invoked service RPC';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pfd_club_memberships where user_id<>auth.uid()) then raise exception 'Other memberships exposed';end if;
end $$;
reset role;
select 'PASS: club-first admission, pending gates, approved-only picker, no email bypass, separate team requests, role approval, direct-assignment resolution, rejection, club isolation, permission revocation and direct-client denial' as result;
rollback;
