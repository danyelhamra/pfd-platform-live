-- Actual restrictive RLS, verified-email, session-revocation and MFA checks.
begin;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data,created_at,updated_at) values
('91000000-0000-4000-8000-000000000001','secure-owner@local.invalid',now(),'{"role":"owner"}',now(),now()),
('91000000-0000-4000-8000-000000000002','unverified@local.invalid',null,'{"role":"owner"}',now(),now()),
('91000000-0000-4000-8000-000000000003','forged-role@local.invalid',now(),'{"role":"owner","is_admin":true}',now(),now());
insert into public.pfd_platform_owners(user_id)values('91000000-0000-4000-8000-000000000001');
insert into auth.sessions(id,user_id,aal)select id,id,'aal1' from auth.users where id::text like '91000000-%';
set local role service_role;
do $$begin
 if not public.pfd_check_session('91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','aal1') then raise exception 'Valid session denied';end if;
 if public.pfd_check_session('91000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000002','aal1') then raise exception 'Unverified email passed';end if;
 if public.pfd_check_session('91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000003','aal1') then raise exception 'Foreign session passed';end if;
end$$;
reset role;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000001","session_id":"91000000-0000-4000-8000-000000000001","aal":"aal1"}',true);
set local role authenticated;
do $$begin
 if (select count(*) from public.pfd_platform_owners)<>1 then raise exception 'Active owner cannot read own grant';end if;
 begin perform public.pfd_check_session(auth.uid(),auth.uid(),'aal1');raise exception 'Client invoked service session checker';exception when insufficient_privilege then null;end;
end$$;
reset role;
delete from auth.sessions where id='91000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$begin
 if exists(select 1 from public.pfd_platform_owners) then raise exception 'Revoked JWT still read owner grant';end if;
 begin perform public.pfd_owner_workspace('overview');raise exception 'Revoked JWT called owner workspace';exception when insufficient_privilege then null;end;
end$$;
reset role;
insert into auth.sessions(id,user_id,aal)values('91000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','aal1');
update auth.users set banned_until=now()+interval '1 hour' where id='91000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$begin if pfd_private.session_allowed() then raise exception 'Banned account passed';end if;end$$;
reset role;
update auth.users set banned_until=null where id='91000000-0000-4000-8000-000000000001';
update auth.sessions set not_after=now()-interval '1 second' where id='91000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$begin if pfd_private.session_allowed() then raise exception 'Expired session passed';end if;end$$;
reset role;
update auth.sessions set not_after=null where id='91000000-0000-4000-8000-000000000001';
insert into auth.mfa_factors(id,user_id,status,factor_type,secret,created_at,updated_at)values('91000000-0000-4000-8000-000000000099','91000000-0000-4000-8000-000000000001','verified','totp','rollback-fixture-only',now(),now());
set local role authenticated;
do $$begin if pfd_private.session_allowed() then raise exception 'MFA bypass via aal1';end if;end$$;
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000001","session_id":"91000000-0000-4000-8000-000000000001","aal":"aal2"}',true);
do $$begin if pfd_private.session_allowed() then raise exception 'aal2 claim without elevated session passed';end if;end$$;
reset role;
update auth.sessions set aal='aal2' where id='91000000-0000-4000-8000-000000000001';
set local role authenticated;
do $$begin if not pfd_private.session_allowed() then raise exception 'Verified MFA session denied';end if;end$$;
select set_config('request.jwt.claim.sub','91000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"91000000-0000-4000-8000-000000000003","session_id":"91000000-0000-4000-8000-000000000003","aal":"aal1"}',true);
do $$begin
 if exists(select 1 from public.pfd_platform_owners) then raise exception 'Metadata spoofing became owner';end if;
 begin perform public.pfd_owner_workspace('overview');raise exception 'Forged metadata entered owner workspace';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claims','{"session_id":"malformed"}',true);
do $$begin if pfd_private.session_allowed() then raise exception 'Malformed session passed';end if;end$$;
reset role;
select 'PASS: verified active sessions, immediate revocation, bans, expiry, MFA and metadata spoofing' as result;
rollback;
