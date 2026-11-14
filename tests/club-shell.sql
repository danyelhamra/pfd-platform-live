-- Rollback-only checks for the exact tables used by the Club Admin shell.
begin;
insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at) values
 ('41000000-0000-4000-8000-000000000001','authenticated','authenticated','club-shell-one@example.invalid','{"full_name":"Fixture admin","role":"owner","is_owner":true}','{}',now(),now()),
 ('41000000-0000-4000-8000-000000000002','authenticated','authenticated','club-shell-two@example.invalid','{}','{}',now(),now());
insert into public.pfd_clubs(id,name,location,city,state,country,contact_email,contact_number,league,sport,status) values
 ('42000000-0000-4000-8000-000000000001','Shell fixture A','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture league','Soccer','active'),
 ('42000000-0000-4000-8000-000000000002','Shell fixture B','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture league','Soccer','active'),
 ('42000000-0000-4000-8000-000000000003','Shell fixture archived','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture league','Soccer','archived');
insert into public.pfd_club_admins(club_id,user_id) values
 ('42000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000001'),
 ('42000000-0000-4000-8000-000000000003','41000000-0000-4000-8000-000000000001'),
 ('42000000-0000-4000-8000-000000000002','41000000-0000-4000-8000-000000000002');
update public.pfd_role_permissions set enabled=true where role_key='club_admin' and permission_key='clubs.view';
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$ begin
 if exists(select 1 from public.pfd_platform_owners where user_id=auth.uid()) then raise exception 'Metadata incorrectly granted owner';end if;
 if (select count(*) from public.pfd_club_admins where user_id=auth.uid())<>2 then raise exception 'Own assignment lookup failed';end if;
 if exists(select 1 from public.pfd_club_admins where user_id='41000000-0000-4000-8000-000000000002') then raise exception 'Other membership leaked';end if;
 if (select count(*) from public.pfd_clubs where status='active' and id::text like '42000000-%')<>1 then raise exception 'Club switcher scope incorrect';end if;
 if exists(select 1 from public.pfd_clubs where id in ('42000000-0000-4000-8000-000000000002','42000000-0000-4000-8000-000000000003')) then raise exception 'Other or archived club exposed';end if;
end $$;
reset role;
delete from public.pfd_club_admins where club_id='42000000-0000-4000-8000-000000000001' and user_id='41000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$ begin if exists(select 1 from public.pfd_clubs where id='42000000-0000-4000-8000-000000000001') then raise exception 'Revoked membership still exposes club';end if;end $$;
reset role;
insert into public.pfd_club_admins(club_id,user_id) values('42000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000001');
update public.pfd_role_permissions set enabled=false where role_key='club_admin' and permission_key='clubs.view';
set local role authenticated;
do $$ begin if exists(select 1 from public.pfd_clubs where id='42000000-0000-4000-8000-000000000001') then raise exception 'Revoked permission still exposes club';end if;end $$;
reset role;
select set_config('request.jwt.claim.sub',(select user_id::text from public.pfd_platform_owners order by granted_at limit 1),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
set local role authenticated;
do $$ begin if (select count(*) from public.pfd_clubs where status='active' and id::text like '42000000-%')<>2 then raise exception 'Owner preview failed';end if;end $$;
reset role;
select 'PASS: assigned club scope, archived exclusion, other-assignment isolation, metadata escalation denied, membership/permission revocation, owner preview' as result;
rollback;
