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
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role service_role;
do $$ declare a uuid:='51000000-0000-4000-8000-000000000001';b uuid:='51000000-0000-4000-8000-000000000002';c uuid:='52000000-0000-4000-8000-000000000001';other_club uuid:='52000000-0000-4000-8000-000000000002';r jsonb;t jsonb;second_team jsonb;other_team jsonb;m jsonb;begin
 t:=public.pfd_club_teams(a,c,'create','{"id":"53000000-0000-4000-8000-000000000001","name":" U14 Development ","age_group":"U14","season":"2026","description":"Fixture team"}');
 if t->>'name'<>'U14 Development' then raise exception 'Team normalization failed';end if;
 begin perform public.pfd_club_teams(a,c,'create','{"id":"53000000-0000-4000-8000-000000000009","name":"u14 development","age_group":"U14","season":"2026"}');raise exception 'Duplicate team accepted';exception when unique_violation then null;end;
 second_team:=public.pfd_club_teams(a,c,'create','{"id":"53000000-0000-4000-8000-000000000002","name":"U14 Development","age_group":"U14","season":"2027"}');
 other_team:=public.pfd_club_teams(b,other_club,'create','{"id":"53000000-0000-4000-8000-000000000003","name":"U14 Development","age_group":"U14","season":"2026"}');
 r:=public.pfd_club_teams(a,c,'list','{"query":"Development","season":"2026"}');if (r->>'total')::int<>1 then raise exception 'Search/season/club filter failed';end if;
 begin perform public.pfd_club_teams(a,other_club,'list');raise exception 'Cross club request accepted';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_teams(a,c,'get',jsonb_build_object('team_id',other_team->>'id'));raise exception 'Cross club team ID accepted';exception when no_data_found then null;end;
 begin perform public.pfd_club_teams('51000000-0000-4000-8000-000000000003',c,'list');raise exception 'Unassigned account accepted';exception when insufficient_privilege then null;end;
 begin perform public.pfd_club_teams(a,'52000000-0000-4000-8000-000000000003','list');raise exception 'Archived parent club accepted';exception when insufficient_privilege then null;end;
 r:=public.pfd_club_teams(a,c,'update',jsonb_build_object('team_id',t->>'id','updated_at',t->>'updated_at','name','U14 First Team','age_group','U14','season','2026','description','Updated'));
 begin perform public.pfd_club_teams(a,c,'update',jsonb_build_object('team_id',t->>'id','updated_at',t->>'updated_at','name','Stale','age_group','U14','season','2026'));raise exception 'Stale edit accepted';exception when serialization_failure then null;end;
 t:=r;
 r:=public.pfd_club_teams(a,c,'candidates',jsonb_build_object('team_id',t->>'id','role_key','coach'));
 if exists(select 1 from jsonb_array_elements(r->'items') x where x->>'id'='51000000-0000-4000-8000-000000000003') then raise exception 'Unrelated directory leaked';end if;
 begin perform public.pfd_club_teams(a,c,'candidates',jsonb_build_object('team_id',t->>'id','role_key','coach','email','teams-coach@example.invalid'));raise exception 'Outside email lookup accepted';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t->>'id','role_key','coach','user_id','51000000-0000-4000-8000-000000000003'));raise exception 'Unscoped arbitrary user ID accepted';exception when invalid_parameter_value then null;end;
 insert into public.pfd_club_memberships(club_id,user_id,approved_by) values(c,'51000000-0000-4000-8000-000000000003',a),(c,'51000000-0000-4000-8000-000000000004',a);
 perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t->>'id','role_key','coach','user_id','51000000-0000-4000-8000-000000000003','email','teams-coach@example.invalid'));
 begin perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t->>'id','role_key','coach','user_id','51000000-0000-4000-8000-000000000003'));raise exception 'Duplicate membership accepted';exception when unique_violation then null;end;
 perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t->>'id','role_key','player','user_id','51000000-0000-4000-8000-000000000003'));
 perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t->>'id','role_key','player','user_id','51000000-0000-4000-8000-000000000004','email','teams-player@example.invalid'));
 perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',second_team->>'id','role_key','player','user_id','51000000-0000-4000-8000-000000000004'));
 r:=public.pfd_club_teams(a,c,'members',jsonb_build_object('team_id',t->>'id','role_key','coach'));if (r->>'total')::int<>1 then raise exception 'Coach roster failed';end if;m:=r->'items'->0;
 begin perform public.pfd_club_teams(a,c,'remove_member',jsonb_build_object('team_id',t->>'id','role_key','coach','user_id',m->>'user_id','created_at','2000-01-01T00:00:00Z'));raise exception 'Stale membership removal accepted';exception when serialization_failure then null;end;
 perform public.pfd_club_teams(a,c,'remove_member',jsonb_build_object('team_id',t->>'id','role_key','coach','user_id',m->>'user_id','created_at',m->>'created_at'));
 if not exists(select 1 from public.pfd_team_memberships where team_id=(t->>'id')::uuid and user_id=(m->>'user_id')::uuid and role_key='player') then raise exception 'Other role removed';end if;
 if not exists(select 1 from public.pfd_team_memberships where team_id=(second_team->>'id')::uuid and user_id='51000000-0000-4000-8000-000000000004') then raise exception 'Other team membership removed';end if;
 t:=public.pfd_club_teams(a,c,'get',jsonb_build_object('team_id',t->>'id'));r:=public.pfd_club_teams(a,c,'set_status',jsonb_build_object('team_id',t->>'id','updated_at',t->>'updated_at','status','archived'));t:=r;
 if (select count(*) from public.pfd_team_memberships where team_id=(t->>'id')::uuid)<>2 then raise exception 'Archive deleted memberships';end if;
 begin perform public.pfd_club_teams(a,c,'add_member',jsonb_build_object('team_id',t->>'id','role_key','coach','user_id','51000000-0000-4000-8000-000000000003'));raise exception 'Archived membership changed';exception when invalid_parameter_value then null;end;
 r:=public.pfd_club_teams(a,c,'stats');if (r->>'teams')::int<>1 or (r->>'players')::int<>1 then raise exception 'Active team counts incorrect';end if;
 perform public.pfd_club_teams(a,c,'set_status',jsonb_build_object('team_id',t->>'id','updated_at',t->>'updated_at','status','active'));
end $$;
reset role;
update public.pfd_role_permissions set enabled=false where role_key='club_admin' and permission_key='teams.create';
set local role service_role;
do $$ declare r jsonb;begin
 r:=public.pfd_club_teams('51000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000001','list');if (r->'permissions'->>'manage')::boolean then raise exception 'Disabled manage permission exposed';end if;
 begin perform public.pfd_club_teams('51000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000001','create','{"id":"53000000-0000-4000-8000-000000000008","name":"Denied","age_group":"U14","season":"2026"}');raise exception 'Disabled permission allowed create';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.pfd_role_permissions set enabled=false where role_key='club_admin' and permission_key='teams.view';
set local role service_role;
do $$ begin begin perform public.pfd_club_teams('51000000-0000-4000-8000-000000000001','52000000-0000-4000-8000-000000000001','list');raise exception 'Disabled view allowed list';exception when insufficient_privilege then null;end;end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','51000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$ begin
 begin perform public.pfd_club_teams(auth.uid(),'52000000-0000-4000-8000-000000000001','list');raise exception 'Client directly invoked privileged RPC';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pfd_profiles) then raise exception 'Global profiles exposed';end if;
 if exists(select 1 from public.pfd_teams) then raise exception 'Direct teams RLS widened';end if;
end $$;
reset role;
set local role anon;
do $$ begin begin perform public.pfd_club_teams(null,null,'list');raise exception 'Anonymous RPC access';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: team CRUD, filters, duplicate and stale protection, approved-club member lookup, multi-role/multi-team membership, archive/restore, scoped stats, role revocation and client/anonymous RPC denial' as result;
rollback;
