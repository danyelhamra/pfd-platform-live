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
insert into public.pfd_team_memberships(team_id,user_id,role_key) values('33000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000001','player');
select set_config('request.jwt.claim.sub',(select user_id::text from public.pfd_platform_owners order by granted_at limit 1),true);
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('request.jwt.claim.sub'),'session_id',current_setting('request.jwt.claim.sub'),'aal','aal1')::text,true);
-- Confirm disposable fixtures and supply rollback-only Auth session records.
update auth.users set email_confirmed_at=now() where email like '%@local.invalid' or email like '%@example.invalid';
insert into auth.sessions(id,user_id,aal) select id,id,'aal1' from auth.users on conflict(id) do nothing;
set local role authenticated;
do $$ declare base jsonb; first_drill jsonb; second_drill jsonb; restricted jsonb; plan jsonb; saved jsonb; data jsonb; result jsonb; payload jsonb; begin
 base:=jsonb_build_object('title','Fixture individual drill','kind','individual_drill','category','Passing','difficulty','all','instructions','Fixture coaching instructions','video_url','','attachments','[]'::jsonb,'audience','all_clubs','club_ids','[]'::jsonb,'status','published','duration_minutes',10,'plan_blocks','[]'::jsonb);
 first_drill:=public.pfd_owner_workspace('resource_save',base||jsonb_build_object('id',gen_random_uuid()));
 second_drill:=public.pfd_owner_workspace('resource_save',base||jsonb_build_object('id',gen_random_uuid(),'title','Fixture team drill','kind','team_drill','duration_minutes',15));
 begin perform public.pfd_owner_workspace('resource_save',base||jsonb_build_object('id',gen_random_uuid(),'duration_minutes',0));raise exception 'Zero drill duration accepted';exception when invalid_parameter_value then null;end;
 plan:=base||jsonb_build_object('id',gen_random_uuid(),'title','Fixture training plan','kind','training_plan','duration_minutes',null,'plan_blocks',jsonb_build_array(jsonb_build_object('resource_id',second_drill->>'id','title','Untrusted title','minutes',15),jsonb_build_object('resource_id',first_drill->>'id','minutes',10)));
 saved:=public.pfd_owner_workspace('resource_save',plan);
 if saved->'plan_blocks'->0->>'title'<>'Fixture team drill' or saved->'plan_blocks'->1->>'title'<>'Fixture individual drill' then raise exception 'Canonical drill snapshots/order failed';end if;
 if (select sum((x->>'minutes')::numeric) from jsonb_array_elements(saved->'plan_blocks') x)<>25 then raise exception 'Plan timings failed';end if;
 plan:=plan||jsonb_build_object('updated_at',saved->>'updated_at','plan_blocks',jsonb_build_array(jsonb_build_object('resource_id',first_drill->>'id','minutes',12),jsonb_build_object('resource_id',second_drill->>'id','minutes',18)));
 saved:=public.pfd_owner_workspace('resource_save',plan);
 if saved->'plan_blocks'->0->>'title'<>'Fixture individual drill' or (select sum((x->>'minutes')::numeric) from jsonb_array_elements(saved->'plan_blocks')x)<>30 then raise exception 'Reordered/timed plan failed';end if;
 restricted:=public.pfd_owner_workspace('resource_save',base||jsonb_build_object('id',gen_random_uuid(),'title','Restricted drill','audience','selected_clubs','club_ids',jsonb_build_array('32000000-0000-4000-8000-000000000001')));
 begin perform public.pfd_owner_workspace('resource_save',plan||jsonb_build_object('id',gen_random_uuid(),'plan_blocks',jsonb_build_array(jsonb_build_object('resource_id',restricted->>'id','minutes',5))));raise exception 'Drill scope leaked through plan';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_owner_workspace('resource_save',plan||jsonb_build_object('id',gen_random_uuid(),'plan_blocks','[]'::jsonb));raise exception 'Published empty plan accepted';exception when invalid_parameter_value then null;end;
 result:=public.pfd_owner_workspace('team_roster','{"team_id":"33000000-0000-4000-8000-000000000001"}');if jsonb_array_length(result)<>1 then raise exception 'Team roster failed';end if;
 data:=jsonb_build_object('info',jsonb_build_object('name','Fixture Player','opposition','Opposition FC'),'ratings','{}'::jsonb,'progress','{}'::jsonb,'values','{}'::jsonb,'extra','{}'::jsonb,'notes',jsonb_build_array('Strengths','Focus','Observations','Actions'),'prepared_by','Fixture Owner','reviewer','','review_date','','consent',true,'metrics','{}'::jsonb,'team_ratings','{}'::jsonb);
 payload:=jsonb_build_object('id',gen_random_uuid(),'subject_id','31000000-0000-4000-8000-000000000001','template_key','performance','report_date','2026-11-13','status','submitted','data',data||'{"metrics":{"minutes_played":90,"goals":2,"shots":3,"shots_on_target":2},"ratings":{"Performance-0":4}}'::jsonb);
 saved:=public.pfd_owner_workspace('report_save',payload);
 if jsonb_typeof(saved->'data'->'metrics'->'goals')<>'number' then raise exception 'Performance metrics not numeric';end if;
 begin perform public.pfd_owner_workspace('report_save',payload||jsonb_build_object('id',gen_random_uuid(),'data',data||'{"metrics":{"shots":1,"shots_on_target":2}}'::jsonb));raise exception 'Impossible shooting statistics accepted';exception when invalid_parameter_value then null;end;
 payload:=payload||jsonb_build_object('id',gen_random_uuid(),'template_key','gps','data',data||'{"metrics":{"minutes_played":90,"total_distance_m":8000,"high_speed_distance_m":1200,"top_speed_kmh":28,"average_speed_kmh":6}}'::jsonb);
 saved:=public.pfd_owner_workspace('report_save',payload);
 if (saved->'data'->'metrics'->>'total_distance_m')::numeric<>8000 then raise exception 'GPS distance did not save';end if;
 begin perform public.pfd_owner_workspace('report_save',payload||jsonb_build_object('id',gen_random_uuid(),'data',data||'{"metrics":{"total_distance_m":1000,"high_speed_distance_m":2000}}'::jsonb));raise exception 'Impossible GPS distances accepted';exception when invalid_parameter_value then null;end;
 payload:=payload||jsonb_build_object('id',gen_random_uuid(),'template_key','match_review','subject_id',null,'club_id','32000000-0000-4000-8000-000000000001','team_id','33000000-0000-4000-8000-000000000001','data',data||'{"info":{"name":"Fixture U14"},"metrics":{"score_for":2,"score_against":1},"ratings":{"Team standards-0":4},"team_ratings":{"31000000-0000-4000-8000-000000000001":{"name":"Forged name","rating":5}}}'::jsonb);
 saved:=public.pfd_owner_workspace('report_save',payload);
 if saved->'subject_id'<>'null'::jsonb or saved->'data'->'team_ratings'->'31000000-0000-4000-8000-000000000001'->>'name'<>'Workspace Fixture Renamed' then raise exception 'Team ownership/roster snapshot failed';end if;
 result:=public.pfd_owner_workspace('user_detail','{"id":"31000000-0000-4000-8000-000000000001"}');if (result->>'report_count')::int<>3 then raise exception 'Match ratings not linked to player history';end if;
 result:=public.pfd_owner_workspace('reports_list','{"template_key":"match_review","club_id":"32000000-0000-4000-8000-000000000001"}');if (result->>'total')::int<>1 or result->'items'->0->>'subject_name'<>'Fixture U14' then raise exception 'Team match missing from report list';end if;
 begin perform public.pfd_owner_workspace('report_save',payload||jsonb_build_object('id',gen_random_uuid(),'data',data||'{"team_ratings":{"31000000-0000-4000-8000-000000000002":{"name":"Other","rating":4}}}'::jsonb));raise exception 'Player outside roster rated';exception when invalid_parameter_value then null;end;
 begin perform public.pfd_owner_workspace('report_save',payload||jsonb_build_object('id',gen_random_uuid(),'data',data||'{"team_ratings":{"31000000-0000-4000-8000-000000000001":{"name":"Player","rating":5.5}}}'::jsonb));raise exception 'Invalid player rating accepted';exception when invalid_parameter_value then null;end;
end $$;
reset role;
select 'PASS: timed drills, ordered plan snapshots, timing edits, scope restrictions, empty-plan rejection, performance/GPS metrics, team report ownership, roster validation and player history linkage' as result;
rollback;
