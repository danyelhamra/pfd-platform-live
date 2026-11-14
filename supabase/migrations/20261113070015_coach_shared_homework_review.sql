-- Review follows actual assigned players in current coaching teams, regardless of author.
create function pfd_private.coach_has_player(actor uuid,c uuid,player uuid,target_teams uuid[])returns boolean
language sql stable security invoker set search_path=''as $$
 select exists(select 1 from public.pfd_teams t
 join public.pfd_clubs club on club.id=t.club_id and club.status='active'
 join public.pfd_team_memberships coach on coach.team_id=t.id and coach.user_id=actor and coach.role_key='coach'
 join public.pfd_team_memberships pupil on pupil.team_id=t.id and pupil.user_id=player and pupil.role_key='player'
 join public.pfd_club_memberships cm on cm.club_id=t.club_id and cm.user_id=actor
 join public.pfd_club_memberships pm on pm.club_id=t.club_id and pm.user_id=player
 where t.club_id=c and t.status='active' and(cardinality(target_teams)=0 or t.id=any(target_teams)))
$$;
create function pfd_private.coach_homework_visible(actor uuid,h public.pfd_homework)returns boolean
language sql stable security invoker set search_path=''as $$
 select exists(select 1 from public.pfd_homework_recipients hr where hr.homework_id=h.id and pfd_private.coach_has_player(actor,h.club_id,hr.user_id,h.team_ids))
$$;
revoke all on function pfd_private.coach_has_player(uuid,uuid,uuid,uuid[]),pfd_private.coach_homework_visible(uuid,public.pfd_homework)from public,anon,authenticated;
grant execute on function pfd_private.coach_has_player(uuid,uuid,uuid,uuid[]),pfd_private.coach_homework_visible(uuid,public.pfd_homework)to service_role;
do $patch$
declare definition text:=pg_get_functiondef('public.pfd_club_workspace(uuid,uuid,text,jsonb)'::regprocedure);previous text;replacement text;
begin
 for previous,replacement in select *from(values
 ($old$hs.review_status='submitted' and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams))$old$,
  $new$hs.review_status='submitted' and(not is_coach or pfd_private.coach_has_player(actor,club,hs.user_id,h.team_ids))$new$),
 ($old$(select count(*) from public.pfd_homework where club_id=club and(not is_coach or (cardinality(team_ids)>0 and team_ids<@coach_teams)) and status='active')$old$,
  $new$(select count(*) from public.pfd_homework h where h.club_id=club and(not is_coach or pfd_private.coach_homework_visible(actor,h)) and h.status='active')$new$),
 ($old$with filtered as(select h.*,(select count(*)from public.pfd_homework_recipients hr where hr.homework_id=h.id)as recipient_count,(select count(*)from public.pfd_homework_submissions hs where hs.homework_id=h.id)as submission_count,$old$,
  $new$with filtered as(select h.*,(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams))as can_edit,(select count(*)from public.pfd_homework_recipients hr where hr.homework_id=h.id and(not is_coach or pfd_private.coach_has_player(actor,club,hr.user_id,h.team_ids)))as recipient_count,(select count(*)from public.pfd_homework_submissions hs where hs.homework_id=h.id and(not is_coach or pfd_private.coach_has_player(actor,club,hs.user_id,h.team_ids)))as submission_count,$new$),
 ($old$(action='homework_list' and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams)))$old$,
  $new$(action='homework_list' and(not is_coach or pfd_private.coach_homework_visible(actor,h)))$new$),
 ($old$select * into hw from public.pfd_homework where id=(payload->>'id')::uuid and club_id=club and(not is_coach or(cardinality(team_ids)>0 and team_ids<@coach_teams));$old$,
  $new$select h.* into hw from public.pfd_homework h where h.id=(payload->>'id')::uuid and h.club_id=club and(not is_coach or pfd_private.coach_homework_visible(actor,h));$new$),
 ($old$where hr.homework_id=hw.id)x));$old$,
  $new$where hr.homework_id=hw.id and(not is_coach or pfd_private.coach_has_player(actor,club,hr.user_id,hw.team_ids)))x));$new$),
 ($old$and h.club_id=club and(not is_coach or(cardinality(h.team_ids)>0 and h.team_ids<@coach_teams)) for update of s;$old$,
  $new$and h.club_id=club and(not is_coach or pfd_private.coach_has_player(actor,club,s.user_id,h.team_ids)) for update of s;$new$),
 ($old$(is_coach and exists(select 1 from public.pfd_homework sh where sh.id=submission.homework_id and cardinality(sh.team_ids)>0 and sh.team_ids<@coach_teams))$old$,
  $new$(is_coach and exists(select 1 from public.pfd_homework sh where sh.id=submission.homework_id and pfd_private.coach_has_player(actor,club,submission.user_id,sh.team_ids)))$new$)
 )as patches(before_text,after_text)loop
  if strpos(definition,previous)=0 then raise exception 'Expected homework scope fragment missing. No changes applied: %',left(previous,100);end if;
  definition:=replace(definition,previous,replacement);
 end loop;
 execute definition;
end $patch$;
