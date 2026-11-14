// Static export: hash Next's generated inline bootstrap instead of permitting inline JS.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
function walk(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const pages=walk('out').filter(f=>f.endsWith('.html'));
const hashes=new Set();
for(const file of pages){for(const m of fs.readFileSync(file,'utf8').matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi)){if(!/\bsrc\s*=/.test(m[1])&&m[2])hashes.add("'sha256-"+crypto.createHash('sha256').update(m[2]).digest('base64')+"'");}}
const {loadEnvConfig}=require('@next/env');
loadEnvConfig(process.cwd());
const api=new URL(process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://tzdgdjvxtckkrbbplpzf.supabase.co');
const csp=["default-src 'self'",`script-src 'self' ${[...hashes].join(' ')}`,"style-src 'self' 'unsafe-inline'","img-src 'self' data: blob: https:","media-src 'self' blob: https:","font-src 'self'",`connect-src 'self' ${api.origin} wss://${api.host}`,"object-src 'none'","base-uri 'self'","form-action 'self'","frame-src 'none'"].join('; ');
const escaped=csp.replaceAll('&','&amp;').replaceAll('"','&quot;');
for(const file of pages){let html=fs.readFileSync(file,'utf8');html=html.replace(/<meta http-equiv="Content-Security-Policy"[^>]*>/g,'');html=html.replace('<head>','<head><meta http-equiv="Content-Security-Policy" content="'+escaped+'"><meta name="referrer" content="no-referrer">');fs.writeFileSync(file,html);}
const headers=[{key:'Content-Security-Policy',value:csp},{key:'X-Content-Type-Options',value:'nosniff'},{key:'Referrer-Policy',value:'no-referrer'},{key:'Permissions-Policy',value:'camera=(), microphone=(), geolocation=()'},{key:'Strict-Transport-Security',value:'max-age=31536000'}];
// Per-build CSP lives in each HTML meta tag. Vercel reads config BEFORE build,
// so never write build-dependent hashes into its response headers. Other headers are static.
fs.writeFileSync('out/_headers','/*\n'+headers.map(h=>'  '+h.key+': '+h.value).join('\n')+'\n');
fs.writeFileSync('vercel.json',JSON.stringify({framework:null,buildCommand:'npm run build',installCommand:'npm ci',outputDirectory:'out',headers:[{source:'/(.*)',headers:headers.filter(h=>h.key!=='Content-Security-Policy')}]},null,2)+'\n');
console.log(`Added CSP to ${pages.length} static pages; ${hashes.size} inline script hashes. No unsafe-inline JavaScript.`);
