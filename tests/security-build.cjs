const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),Module=require('node:module'),ts=require('typescript');
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const files=walk('out');let pages=0;
for(const f of files){if(!/\.(html|js|json|txt)$/.test(f))continue;const body=fs.readFileSync(f,'utf8');assert(!/sb_secret_[A-Za-z0-9_-]+|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|SUPABASE_SERVICE_ROLE_KEY/.test(body),'Privileged credential reference in '+f);
 for(const match of body.matchAll(/eyJ[A-Za-z0-9_-]+\.([A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+/g)){try{assert.notEqual(JSON.parse(Buffer.from(match[1],'base64url')).role,'service_role','Service JWT in '+f);}catch(e){if(e.code==='ERR_ASSERTION')throw e;}}
 if(!f.endsWith('.html'))continue;pages++;
 const csp=body.match(/<meta http-equiv="Content-Security-Policy" content="([^"]*)"/)[1];assert(!/script-src[^;]*unsafe-inline/.test(csp));assert(csp.includes("object-src 'none'"));assert(body.includes('name="referrer" content="no-referrer"'));
 for(const m of body.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){if(!/\bsrc\s*=/.test(m[1])&&m[2])assert(csp.includes("'sha256-"+crypto.createHash('sha256').update(m[2]).digest('base64')+"'"),'Unhashed bootstrap in '+f);}
}
let handler;global.Deno={serve:fn=>handler=fn};const file=path.resolve('supabase/functions/pfd-account-register/index.ts'),mod=new Module(file,module);mod._compile(ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText,file);
(async()=>{const r=await handler(new Request('https://fixture.invalid',{method:'POST'}));assert.equal(r.status,410);console.log(`PASS: ${pages} pages have hash-based CSP; no privileged keys in exported files; administrative signup bypass retired.`);})().catch(e=>{console.error(e);process.exitCode=1});
