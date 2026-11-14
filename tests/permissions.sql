-- Rollback-only security regression checks. Requires a privileged SQL test session.
-- Uses the existing canonical owner without changing its identity or password.
begin;
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
 ('10000000-0000-4000-8000-000000000001','authenticated','authenticated','permissions-fixture-admin@example.invalid','{}','{}',now(),now()),
 ('10000000-0000-4000-8000-000000000002','authenticated','authenticated','permissions-fixture-member@example.invalid','{}','{}',now(),now());
insert into public.pfd_clubs(id,name,location,city,state,country,contact_email,contact_number,league,sport,status) values
 ('20000000-0000-4000-8000-000000000001','Permission fixture one','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture League','Soccer','active'),
 ('20000000-0000-4000-8000-000000000002','Permission fixture other','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture League','Soccer','active'),
 ('20000000-0000-4000-8000-000000000003','Permission fixture archived','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture League','Soccer','archived');
insert into public.pfd_club_admins(club_id,user_id) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001'),
 ('20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001');
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$ declare n integer; begin
 if not public.pfd_has_club_permission('20000000-0000-4000-8000-000000000001','clubs.view') then raise exception 'Assigned club permission denied'; end if;
 if public.pfd_has_club_permission('20000000-0000-4000-8000-000000000002','clubs.view') then raise exception 'Cross-club access leaked'; end if;
 if public.pfd_has_club_permission('20000000-0000-4000-8000-000000000003','clubs.view') then raise exception 'Archived club leaked'; end if;
 if public.pfd_has_club_permission('20000000-0000-4000-8000-000000000001','roles.manage') then raise exception 'Owner privilege leaked'; end if;
 if not public.pfd_has_club_permission('20000000-0000-4000-8000-000000000001','reports.create') then raise exception 'Report creation permission unavailable'; end if;
 if (select count(*) from public.pfd_clubs where id::text like '20000000-%')<>1 then raise exception 'RLS club scope failed'; end if;
 begin perform public.pfd_get_role_permissions(); raise exception 'Nonowner read editor'; exception when insufficient_privilege then null; end;
 begin perform public.pfd_save_role_permissions(1,'[{"role_key":"club_admin","permission_key":"clubs.view","enabled":false}]'); raise exception 'Nonowner changed config'; exception when insufficient_privilege then null; end;
 update public.pfd_role_permissions set enabled=false where permission_key='clubs.view';
 get diagnostics n=row_count;
 if n<>0 then raise exception 'Direct nonowner UPDATE bypassed RLS'; end if;
 begin insert into public.pfd_platform_owners(user_id) values(auth.uid()); raise exception 'Self promotion succeeded'; exception when insufficient_privilege then null; end;
end $$;
-- Use an existing owner selected under privileged test context, never user metadata.
reset role;
select set_config('request.jwt.claim.sub',(select user_id::text from public.pfd_platform_owners order by granted_at limit 1),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
set local role authenticated;
do $$ declare snap jsonb; rev bigint; result jsonb; begin
 snap:=public.pfd_get_role_permissions(); rev:=(snap->'settings'->>'revision')::bigint;
 if jsonb_array_length(snap->'permissions')<>34 or jsonb_array_length(snap->'grants')<>102 then raise exception 'Incomplete permission catalog'; end if;
 result:=public.pfd_save_role_permissions(rev,'[{"role_key":"club_admin","permission_key":"clubs.view","enabled":false}]');
 if (result->>'revision')::bigint<>rev+1 then raise exception 'Save revision failed'; end if;
 if not exists(select 1 from public.pfd_permission_audit where revision=rev+1 and actor_id=auth.uid()) then raise exception 'Audit missing'; end if;
 if not public.pfd_has_club_permission('20000000-0000-4000-8000-000000000001','clubs.view') then raise exception 'Owner locked out'; end if;
 begin perform public.pfd_save_role_permissions(rev,'[{"role_key":"coach","permission_key":"reports.create","enabled":false}]'); raise exception 'Stale save accepted'; exception when serialization_failure then null; end;
 begin perform public.pfd_save_role_permissions(rev+1,'[{"role_key":"owner","permission_key":"clubs.view","enabled":false}]'); raise exception 'Owner edited'; exception when invalid_parameter_value then null; end;
 begin perform public.pfd_save_role_permissions(rev+1,'[{"role_key":"club_admin","permission_key":"roles.manage","enabled":true}]'); raise exception 'Reserved permission delegated'; exception when invalid_parameter_value then null; end;
 begin update public.pfd_role_permissions set enabled=true where role_key='coach' and permission_key='roles.manage'; raise exception 'Direct reserved permission delegated'; exception when insufficient_privilege then null; end;
 begin perform public.pfd_save_role_permissions(rev+1,'[{"role_key":"coach","permission_key":"reports.create","enabled":"false"}]'); raise exception 'String boolean accepted'; exception when invalid_parameter_value then null; end;
 begin perform public.pfd_save_role_permissions(rev+1,'[{"role_key":"coach","permission_key":"reports.create","enabled":false},{"role_key":"coach","permission_key":"reports.create","enabled":true}]'); raise exception 'Duplicate change accepted'; exception when invalid_parameter_value then null; end;
 -- Entire batch must roll back if a later permission is invalid.
 begin perform public.pfd_save_role_permissions(rev+1,'[{"role_key":"coach","permission_key":"reports.create","enabled":false},{"role_key":"player","permission_key":"unknown","enabled":true}]'); raise exception 'Invalid batch accepted'; exception when invalid_parameter_value then null; end;
 if not (select enabled from public.pfd_role_permissions where role_key='coach' and permission_key='reports.create') then raise exception 'Failed batch partially committed'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$ begin
 if exists(select 1 from public.pfd_clubs where id='20000000-0000-4000-8000-000000000001') then raise exception 'Disabled permission still reads club'; end if;
 if public.pfd_has_club_permission('20000000-0000-4000-8000-000000000001','clubs.view') then raise exception 'Disabled helper still allows'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$ begin
 if exists(select 1 from public.pfd_clubs) then raise exception 'Unassigned account reads club'; end if;
 if exists(select 1 from public.pfd_permission_audit) then raise exception 'Member reads audit'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.pfd_get_role_permissions(); raise exception 'Anon editor access'; exception when insufficient_privilege then null; end;
 begin perform * from public.pfd_role_permissions; raise exception 'Anon table access'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: owner protection, direct-write denial, club isolation, archived denial, live revocation, stale saves, validation, atomic batch and audit' as result;
rollback;
