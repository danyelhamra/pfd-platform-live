-- Defense in depth for direct REST/RPC/storage requests and service-backed Edges.
create schema if not exists pfd_private;
revoke all on schema pfd_private from public;
grant usage on schema pfd_private to authenticated,service_role;

create function pfd_private.valid_session(actor uuid, session_key uuid, assurance text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
   select 1 from auth.users u join auth.sessions s on s.user_id=u.id
   where u.id=actor and s.id=session_key
     and u.email_confirmed_at is not null and u.deleted_at is null
     and (u.banned_until is null or u.banned_until<=now())
     and (s.not_after is null or s.not_after>now())
     and (not exists(select 1 from auth.mfa_factors f where f.user_id=u.id and f.status='verified')
          or (assurance='aal2' and s.aal::text='aal2'))
 );
$$;
revoke all on function pfd_private.valid_session(uuid,uuid,text) from public,anon,authenticated;
grant execute on function pfd_private.valid_session(uuid,uuid,text) to service_role;

-- No actor parameter: clients can only check their own JWT-backed session.
create function pfd_private.session_allowed()
returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 return pfd_private.valid_session(auth.uid(),nullif(auth.jwt()->>'session_id','')::uuid,auth.jwt()->>'aal');
exception when invalid_text_representation then return false;
end;
$$;
revoke all on function pfd_private.session_allowed() from public,anon;
grant execute on function pfd_private.session_allowed() to authenticated,service_role;

-- Only service_role can call this with a previously Auth-verified actor/token.
create function public.pfd_check_session(actor_id uuid,session_id uuid,assurance text)
returns boolean language sql stable security invoker set search_path='' as $$
 select pfd_private.valid_session(actor_id,session_id,assurance);
$$;
revoke all on function public.pfd_check_session(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pfd_check_session(uuid,uuid,text) to service_role;

-- Restrictive policies AND with every existing scoped policy; they grant no rows.
do $$declare tab record;begin
 for tab in select tablename from pg_tables where schemaname='public' and tablename like 'pfd\_%' escape '\' loop
  execute format('create policy pfd_active_session on public.%I as restrictive for all to authenticated using ((select pfd_private.session_allowed())) with check ((select pfd_private.session_allowed()))',tab.tablename);
 end loop;
end$$;
create policy pfd_active_storage_session on storage.objects as restrictive for all to authenticated
 using (bucket_id not in ('pfd-development-resources','pfd-club-files') or (select pfd_private.session_allowed()))
 with check (bucket_id not in ('pfd-development-resources','pfd-club-files') or (select pfd_private.session_allowed()));

create function public.pfd_session_status()
returns boolean language sql stable security invoker set search_path='' as $$
 select pfd_private.session_allowed();
$$;
revoke all on function public.pfd_session_status() from public,anon;
grant execute on function public.pfd_session_status() to authenticated;
