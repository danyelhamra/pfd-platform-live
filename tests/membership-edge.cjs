// Tests the actual Edge handler with mocked Auth/RPC responses; no accounts are created.
const assert=require('node:assert/strict'),fs=require('node:fs'),Module=require('node:module'),ts=require('typescript');
const validToken='test.'+Buffer.from(JSON.stringify({session_id:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',aal:'aal1'})).toString('base64url')+'.signature';
let handler,captured,mode='ok';
const client={auth:{getUser:async token=>token===validToken?{data:{user:{id:'verified-user-id',email_confirmed_at:'2026-11-13T00:00:00Z'}},error:null}:{data:{user:null},error:new Error('Invalid token')}},rpc:async(name,args)=>{if(name==='pfd_check_session')return {data:true,error:null};captured={name,args};return mode==='denied'?{data:null,error:{code:'42501',message:'Club access denied'}}:{data:{items:[]},error:null};}};
global.Deno={env:{get:()=> 'server-managed-placeholder'},serve:fn=>{handler=fn;}};
const filename=process.cwd()+'/supabase/functions/pfd-memberships/index.ts';const m=new Module(filename,module);m.filename=filename;m.paths=module.paths;m.require=id=>id.startsWith('npm:@supabase/supabase-js')?{createClient:()=>client}:require(id);
m._compile(ts.transpileModule(fs.readFileSync(filename,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,filename);
const body={club_id:'11111111-1111-4111-8111-111111111111',action:'list',actor_id:'forged-owner-id',payload:{actor_id:'another-forged-id'}};
const request=(token=validToken,origin)=>new Request('https://fixture.invalid',{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),...(origin?{Origin:origin}:{})},body:JSON.stringify(body)});
(async()=>{
 assert.equal((await handler(request())).status,200);
 assert.equal(captured.args.actor_id,'verified-user-id');
 assert.equal(captured.args.target_club,undefined);
 assert.equal(captured.name,'pfd_membership_flow');
 assert.equal((await handler(request(''))).status,401);
 assert.equal((await handler(request('bad-token'))).status,401);
 assert.equal((await handler(request(validToken,'https://untrusted.example'))).status,403);
 mode='denied';assert.equal((await handler(request())).status,403);
 console.log('PASS: Edge uses verified identity, ignores forged actor IDs, rejects missing/invalid tokens and untrusted origins, and preserves database permission denial.');
})().catch(e=>{console.error(e);process.exitCode=1});
