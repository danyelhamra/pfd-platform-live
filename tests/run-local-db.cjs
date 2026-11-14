// Run against an isolated in-memory PostgreSQL engine, never the live backend.
const {PGlite}=require(process.env.PFD_PGLITE_PACKAGE||'@electric-sql/pglite');const fs=require('node:fs');
const root=require('node:path').resolve(__dirname,'..');
(async()=>{
 const db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;create schema storage;grant usage on schema auth,storage,public to anon,authenticated,service_role;
 create table auth.users(id uuid primary key,instance_id uuid,aud text,role text,email text,encrypted_password text,email_confirmed_at timestamptz,banned_until timestamptz,deleted_at timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',created_at timestamptz default now(),updated_at timestamptz default now(),last_sign_in_at timestamptz);
 create function auth.uid()returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt()returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id),aal text default 'aal1',not_after timestamptz);
 create table auth.mfa_factors(id uuid primary key,user_id uuid references auth.users(id),status text,factor_type text,secret text,created_at timestamptz,updated_at timestamptz);
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,metadata jsonb,unique(bucket_id,name));alter table storage.objects enable row level security;grant all on storage.buckets,storage.objects to service_role;grant select,insert,update,delete on storage.objects to authenticated;
 create function storage.foldername(name text)returns text[]language sql immutable as $$select (string_to_array(name,'/'))[1:array_length(string_to_array(name,'/'),1)-1]$$;`);
 for(const file of ['bootstrap.sql','owner-access.sql','clubs.sql','club-required-details.sql','permissions.sql','owner-workspace.sql','library-plans-and-match-reports.sql','club-teams.sql','club-first-membership.sql','club-workspace.sql']){
  try{await db.exec(fs.readFileSync(root+'/supabase/'+file,'utf8'));console.log('APPLIED',file);}catch(e){console.error('FAILED',file,e.message,e.code,e.where);throw e;}
 }
 for(const migration of fs.readdirSync(root+'/supabase/migrations').filter(f=>f.endsWith('.sql')).sort()){await db.exec(fs.readFileSync(root+'/supabase/migrations/'+migration,'utf8'));console.log('APPLIED',migration);}
 await db.exec(`insert into auth.users(id,email,raw_user_meta_data)values('00000000-0000-4000-8000-000000000001','owner@local.invalid','{"full_name":"Local Owner"}');insert into public.pfd_platform_owners(user_id)values('00000000-0000-4000-8000-000000000001');`);
 for(const test of ['player-dashboard.sql','coach-homework-review.sql','coach-library.sql','club-workspace.sql','club-teams.sql','club-admission.sql','club-shell.sql','owner-workspace.sql','library-and-match-reports.sql','permissions.sql','session-security.sql']){try{const results=await db.exec(fs.readFileSync(root+'/tests/'+test,'utf8'));console.log('TEST PASSED',test,JSON.stringify(results.filter(r=>r.rows?.length).slice(-1)));}catch(e){console.error('TEST FAILED',test,e.message,e.where);throw e;}}
 await db.close();console.log('LOCAL SCHEMA AND WORKFLOW VALIDATION PASSED');
})().catch(e=>{console.error(e.message);process.exitCode=1});
