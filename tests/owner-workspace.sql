-- Privileged rollback-only integration/security tests. No fixtures survive.
begin;
insert into auth.users(id,aud,role,email,raw_user_meta_data,raw_app_meta_data,created_at,updated_at) values
 ('31000000-0000-4000-8000-000000000001','authenticated','authenticated','workspace-fixture-one@example.invalid','{"full_name":"Workspace Fixture One"}','{}',now(),now()),
 ('31000000-0000-4000-8000-000000000002','authenticated','authenticated','workspace-fixture-two@example.invalid','{"full_name":"Workspace Fixture Two"}','{}',now(),now());
update auth.users set raw_user_meta_data='{"full_name":"Workspace Fixture Renamed"}',last_sign_in_at=now() where id='31000000-0000-4000-8000-000000000001';
insert into public.pfd_clubs(id,name,location,city,state,country,contact_email,contact_number,league,sport,status) values
 ('32000000-0000-4000-8000-000000000001','Workspace Fixture Club','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture League','Soccer','active'),
 ('32000000-0000-4000-8000-000000000002','Other Fixture Club','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture League','Soccer','active'),
 ('32000000-0000-4000-8000-000000000003','Archived Fixture Club','Adelaide, SA, Australia','Adelaide','SA','Australia','fixture@example.invalid','0412345678','Fixture League','Soccer','archived');
insert into public.pfd_teams(id,club_id,name,age_group,season) values
 ('33000000-0000-4000-8000-000000000001','32000000-0000-4000-8000-000000000001','Fixture U14','U14','2026'),
 ('33000000-0000-4000-8000-000000000002','32000000-0000-4000-8000-000000000002','Other U14','U14','2026');
select set_config('request.jwt.claim.sub',(select user_id::text from public.pfd_platform_owners order by granted_at limit 1),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role authenticated;
do $$ declare result jsonb; req uuid; report_id uuid; item record; draft jsonb; saved jsonb; report_data jsonb; resource jsonb; actor uuid:=auth.uid(); begin
 result:=public.pfd_owner_workspace('users_list','{"query":"workspace-fixture-"}');
 if (result->>'total')::int<>2 then raise exception 'Directory search failed'; end if;
 if (select name from public.pfd_profiles where id='31000000-0000-4000-8000-000000000001')<>'Workspace Fixture Renamed' then raise exception 'Profile sync failed'; end if;
 if (select last_sign_in_at from public.pfd_profiles where id='31000000-0000-4000-8000-000000000001') is null then raise exception 'Last sign in sync failed'; end if;
 result:=public.pfd_owner_workspace('options');
 if jsonb_array_length(result->'templates')<>8 then raise exception 'Five original templates missing'; end if;
 if (select sum(jsonb_array_length(c.value)) from public.pfd_report_templates t cross join lateral jsonb_each(t.definition->'categories') c where t.source_commit='a1890fb76f404244e9512faebe9c9d803da75791')<>75 then raise exception 'Original question count changed'; end if;
 begin perform public.pfd_owner_workspace('request_create','{"user_id":"31000000-0000-4000-8000-000000000001","club_id":"32000000-0000-4000-8000-000000000001","team_id":"33000000-0000-4000-8000-000000000002","role_key":"player"}');raise exception 'Cross club request accepted';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_owner_workspace('request_create','{"user_id":"31000000-0000-4000-8000-000000000001","club_id":"32000000-0000-4000-8000-000000000003","role_key":"club_admin"}');raise exception 'Archived club request accepted';exception when invalid_parameter_value then null;end;
 result:=public.pfd_owner_workspace('request_create','{"user_id":"31000000-0000-4000-8000-000000000001","club_id":"32000000-0000-4000-8000-000000000001","role_key":"club_admin","message":"Fixture request"}');req:=(result->>'id')::uuid;
 begin perform public.pfd_owner_workspace('request_create','{"user_id":"31000000-0000-4000-8000-000000000001","club_id":"32000000-0000-4000-8000-000000000001","role_key":"club_admin"}');raise exception 'Duplicate pending request accepted';exception when unique_violation then null;end;
 perform public.pfd_owner_workspace('request_review',jsonb_build_object('id',req,'decision','approved','reason','Fixture approval'));
 if not exists(select 1 from public.pfd_club_admins where club_id='32000000-0000-4000-8000-000000000001' and user_id='31000000-0000-4000-8000-000000000001') then raise exception 'Approval did not grant club membership';end if;
 begin perform public.pfd_owner_workspace('request_review',jsonb_build_object('id',req,'decision','rejected','reason','Too late'));raise exception 'Reviewed request changed';exception when serialization_failure then null;end;
 for item in select unnest(array['coach','player']) as role_key loop
  result:=public.pfd_owner_workspace('request_create',jsonb_build_object('user_id','31000000-0000-4000-8000-000000000001','club_id','32000000-0000-4000-8000-000000000001','team_id','33000000-0000-4000-8000-000000000001','role_key',item.role_key));
  perform public.pfd_owner_workspace('request_review',jsonb_build_object('id',result->>'id','decision','approved'));
 end loop;
 if (select count(*) from public.pfd_team_memberships where user_id='31000000-0000-4000-8000-000000000001')<>2 then raise exception 'Team memberships failed';end if;
 result:=public.pfd_owner_workspace('users_list','{"role":"coach","club_id":"32000000-0000-4000-8000-000000000001"}');if (result->>'total')::int<>1 then raise exception 'Role/club filter failed';end if;
 result:=public.pfd_owner_workspace('request_create','{"user_id":"31000000-0000-4000-8000-000000000002","club_id":"32000000-0000-4000-8000-000000000001","role_key":"club_admin"}');req:=(result->>'id')::uuid;
 begin perform public.pfd_owner_workspace('request_review',jsonb_build_object('id',req,'decision','rejected'));raise exception 'Rejection without reason accepted';exception when invalid_parameter_value then null;end;
 perform public.pfd_owner_workspace('request_review',jsonb_build_object('id',req,'decision','rejected','reason','Fixture rejection'));
 if exists(select 1 from public.pfd_club_admins where club_id='32000000-0000-4000-8000-000000000001' and user_id='31000000-0000-4000-8000-000000000002') then raise exception 'Rejection granted access';end if;
 -- Draft -> submit every original template; the exact definition is snapshotted.
 for item in select key,definition from public.pfd_report_templates where source_commit='a1890fb76f404244e9512faebe9c9d803da75791' loop
  report_id:=gen_random_uuid();
  report_data:=jsonb_build_object('info',jsonb_build_object('name','Fixture Player','team','Fixture U14','U14','2026'),'ratings',jsonb_build_object((select key||'-0' from jsonb_each(item.definition->'categories') limit 1),4),'progress','{}'::jsonb,'values','{}'::jsonb,'extra','{}'::jsonb,'notes',jsonb_build_array('Strengths','Focus','Actions','Feedback'),'prepared_by','Fixture Owner','reviewer','','review_date','','consent',true);
  draft:=public.pfd_owner_workspace('report_save',jsonb_build_object('id',report_id,'subject_id','31000000-0000-4000-8000-000000000001','template_key',item.key,'report_date','2026-11-13','status','draft','data',report_data));
  begin perform public.pfd_owner_workspace('report_save',jsonb_build_object('id',report_id,'subject_id','31000000-0000-4000-8000-000000000001','template_key',item.key,'report_date','2026-11-13','status','draft','data',report_data));raise exception 'Stale report accepted';exception when serialization_failure then null;end;
  saved:=public.pfd_owner_workspace('report_save',jsonb_build_object('id',report_id,'subject_id','31000000-0000-4000-8000-000000000001','template_key',item.key,'report_date','2026-11-13','status','submitted','data',report_data,'updated_at',draft->>'updated_at'));
  if saved->'template_snapshot' is distinct from item.definition then raise exception 'Template snapshot mismatch';end if;
  begin perform public.pfd_owner_workspace('report_save',jsonb_build_object('id',report_id,'subject_id','31000000-0000-4000-8000-000000000001','template_key',item.key,'report_date','2026-11-13','status','draft','data',report_data,'updated_at',saved->>'updated_at'));raise exception 'Submitted report edited';exception when invalid_parameter_value then null;end;
 end loop;
 result:=public.pfd_owner_workspace('reports_list','{"query":"workspace-fixture-one","from_date":"2026-11-13","to_date":"2026-11-13"}');if (result->>'total')::int<>5 then raise exception 'Report search/date filter failed';end if;
 result:=public.pfd_owner_workspace('user_detail','{"id":"31000000-0000-4000-8000-000000000001"}');if (result->>'report_count')::int<>5 or jsonb_array_length(result->'memberships')<>3 then raise exception 'Profile activity failed';end if;
 begin perform public.pfd_owner_workspace('report_save',jsonb_build_object('id',gen_random_uuid(),'subject_id','31000000-0000-4000-8000-000000000001','template_key','fitness','report_date','2026-11-13','status','draft','data',report_data||'{"ratings":{"Fake-0":6}}'::jsonb));raise exception 'Invalid question/rating accepted';exception when invalid_parameter_value then null;end;
 resource:=jsonb_build_object('id',gen_random_uuid(),'title','Fixture passing drill','kind','individual_drill','duration_minutes',12.5,'category','Passing','difficulty','beginner','instructions','Three players. Two touches.','video_url','https://example.com/fixture','attachments','[]'::jsonb,'audience','selected_clubs','club_ids',jsonb_build_array('32000000-0000-4000-8000-000000000001'),'status','draft');
 saved:=public.pfd_owner_workspace('resource_save',resource);
 if not exists(select 1 from public.pfd_resource_clubs where resource_id=(saved->>'id')::uuid) then raise exception 'Resource club scope missing';end if;
 begin perform public.pfd_owner_workspace('resource_save',resource);raise exception 'Stale resource save accepted';exception when serialization_failure then null;end;
 resource:=resource||jsonb_build_object('updated_at',saved->>'updated_at','status','published');saved:=public.pfd_owner_workspace('resource_save',resource);
 resource:=resource||jsonb_build_object('updated_at',saved->>'updated_at','status','archived');saved:=public.pfd_owner_workspace('resource_save',resource);
 if saved->>'status'<>'archived' then raise exception 'Resource archive failed';end if;
 begin perform public.pfd_owner_workspace('resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'video_url','javascript:alert(1)'));raise exception 'Unsafe video URL accepted';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_owner_workspace('resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'club_ids','[]'::jsonb));raise exception 'Empty selected-club scope accepted';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_owner_workspace('resource_save',resource||jsonb_build_object('id',gen_random_uuid(),'attachments','[{"name":"missing.pdf","path":"missing.pdf"}]'::jsonb));raise exception 'Missing file accepted';exception when invalid_parameter_value then null;end;

end $$;
select set_config('request.jwt.claim.sub','31000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
do $$ declare n integer; begin
 begin perform public.pfd_owner_workspace('users_list');raise exception 'Nonowner invoked directory';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pfd_profiles) or exists(select 1 from public.pfd_reports) or exists(select 1 from public.pfd_resources) or exists(select 1 from public.pfd_access_requests) then raise exception 'Private owner data exposed';end if;
 update public.pfd_access_requests set status='approved';get diagnostics n=row_count;if n<>0 then raise exception 'Nonowner changed requests';end if;
 begin insert into public.pfd_resources(id,title,kind) values(gen_random_uuid(),'Unauthorized','individual_drill');raise exception 'Nonowner inserted resource';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.pfd_platform_owners) then raise exception 'Membership promoted to owner';end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.pfd_owner_workspace('users_list');raise exception 'Anonymous directory call accepted';exception when insufficient_privilege then null;end;
 begin perform * from public.pfd_reports;raise exception 'Anonymous report read accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if not exists(select 1 from storage.buckets where id='pfd-development-resources' and not public and file_size_limit=52428800) then raise exception 'Private bucket configuration failed';end if;
end $$;
select 'PASS: profile sync, directory/search/filter, request approval/rejection/membership, duplicate review, all 5 original reports, immutable snapshots, report validation, library lifecycle, selected clubs, unsafe links, missing files, nonowner/anonymous isolation' as result;
rollback;
