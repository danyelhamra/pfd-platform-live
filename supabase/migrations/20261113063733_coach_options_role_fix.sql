-- Add the canonical role to the exact options response the dashboards consume.
-- Preserve all existing membership, permission and team-scope checks.
do $patch$
declare definition text:=pg_get_functiondef('public.pfd_club_workspace(uuid,uuid,text,jsonb)'::regprocedure);
 old_fragment text:=$old$   'permissions',to_jsonb(perms));end if;
  if action='stats'$old$;
 new_fragment text:=$new$   'workspace_role',case when is_admin then 'club_admin' when is_coach then 'coach' else 'member' end,
   'permissions',to_jsonb(perms));end if;
  if action='stats'$new$;
begin
 if strpos(definition,old_fragment)=0 then raise exception 'Expected workspace options response not found. No changes applied.';end if;
 execute replace(definition,old_fragment,new_fragment);
end $patch$;
