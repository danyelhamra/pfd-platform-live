// Execute all five real protected handlers. Auth and DB are mocked, not replaced handlers.
const assert=require('node:assert/strict'),fs=require('node:fs'),Module=require('node:module'),ts=require('typescript'),path=require('node:path');
const jwt='fixture.'+Buffer.from(JSON.stringify({session_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',aal:'aal1'})).toString('base64url')+'.signature';
for(const endpoint of ['pfd-club-teams','pfd-memberships','pfd-club-workspace','pfd-owner-clubs','pfd-owner-dashboard']){
 let handler,mode='unverified',sensitiveCalls=0;
 const client={auth:{getUser:async()=>({data:{user:{id:'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',email_confirmed_at:mode==='unverified'?null:'2026-11-13T00:00:00Z',user_metadata:{role:'owner'}}},error:null})},rpc:async(name,args)=>{
  if(name==='pfd_check_session'){assert.equal(args.actor_id,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');assert.equal(args.session_id,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');return mode==='database-error'?{error:{message:'offline'}}:{data:false,error:null};}
  sensitiveCalls++;throw Error('Scoped RPC must not execute');
 },from:()=>{sensitiveCalls++;throw Error('Protected table must not be queried');}};
 global.Deno={env:{get:()=> 'server-placeholder'},serve:fn=>handler=fn};
 function compile(file){const m=new Module(file,module);m.filename=file;m.paths=module.paths;m.require=id=>id.startsWith('npm:')?{createClient:()=>client}:id.startsWith('.')?compile(path.resolve(path.dirname(file),id)):require(id);m._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,file);return m.exports;}
 compile(path.resolve('supabase/functions',endpoint,'index.ts'));
 const request=token=>new Request('https://fixture.invalid',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:'{}'});
 (async()=>{
  assert.equal((await handler(request(jwt))).status,401,endpoint+' unverified');
  mode='revoked';assert.equal((await handler(request(jwt))).status,401,endpoint+' revoked');
  mode='database-error';assert.equal((await handler(request(jwt))).status,503,endpoint+' fail closed');
  assert.equal((await handler(request('malformed'))).status,401,endpoint+' malformed');
  assert.equal(sensitiveCalls,0);console.log('PASS session boundary:',endpoint);
 })().catch(e=>{console.error(e);process.exitCode=1;});
}
