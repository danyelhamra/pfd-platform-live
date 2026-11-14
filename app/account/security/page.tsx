"use client";
import { useEffect, useState, type FormEvent } from "react";
import Link from "next/link";
import { useAuth } from "../../auth-provider";
import { getSupabase } from "../../../lib/supabase";
export default function AccountSecurity() {
  const {user,ready}=useAuth();
  const [factor,setFactor]=useState<string|null>(null);
  const [pending,setPending]=useState<{id:string;qr:string}|null>(null);
  const [loaded,setLoaded]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState("");
  useEffect(()=>{
    if(!user)return;
    getSupabase().auth.mfa.listFactors().then(r=>{
      if(r.error){setMessage("Unable to load two-step verification. Refresh to try again.");return;}
      setFactor(r.data.totp[0]?.id||null);setLoaded(true);
    }).catch(()=>setMessage("Unable to load security settings."));
  },[user]);
  async function enroll(){
    if(busy||!loaded)return;setBusy(true);setMessage("");
    try{
      // Reuse only our own unfinished enrollment, so abandoned setups do not accumulate.
      const all=await getSupabase().auth.mfa.listFactors();if(all.error)throw all.error;
      for(const f of all.data.all.filter(f=>f.factor_type==="totp"&&f.status==="unverified"&&f.friendly_name==="PFD authenticator")){
        const removed=await getSupabase().auth.mfa.unenroll({factorId:f.id});if(removed.error)throw removed.error;
      }
      const r=await getSupabase().auth.mfa.enroll({factorType:"totp",friendlyName:"PFD authenticator"});
      if(r.error)throw r.error;
      // Secret QR stays in this user's UI only; never stored in application tables/logs.
      setPending({id:r.data.id,qr:r.data.totp.qr_code});
    }catch{setMessage("Unable to start authenticator setup. Refresh and try again.");}
    finally{setBusy(false);}
  }
  async function verify(e:FormEvent<HTMLFormElement>){
    e.preventDefault();if(!pending||busy)return;
    const code=String(new FormData(e.currentTarget).get("code")||"").trim();
    if(!/^\d{6}$/.test(code)){setMessage("Enter the six-digit code.");return;}
    setBusy(true);setMessage("");
    try{
      const r=await getSupabase().auth.mfa.challengeAndVerify({factorId:pending.id,code});if(r.error)throw r.error;
      setFactor(pending.id);setPending(null);setMessage("Two-step verification is enabled. Keep your authenticator backed up securely.");
    }catch{setMessage("Code not accepted. Check your authenticator and try again.");}
    finally{setBusy(false);}
  }
  async function logoutEverywhere(){
    setBusy(true);setMessage("");
    try{const r=await getSupabase().auth.signOut({scope:"global"});if(r.error)throw r.error;window.location.replace("/");}
    catch{setMessage("Unable to sign out all devices. Please try again.");setBusy(false);}
  }
  if(!ready)return <main className="auth-page"><p>Checking account security…</p></main>;
  if(!user)return <main className="auth-page"><section className="auth-card"><h1>Please log in</h1><Link href="/">Return home to log in</Link></section></main>;
  return <main className="auth-page"><section className="auth-card"><Link className="wordmark" href="/account/">PFD<span>.</span></Link>
    <h1>Account security</h1><p>{user.email}</p>
    <h2>Authenticator app</h2><p>{factor?"Two-step verification is enabled. You will need your authenticator code when logging in.":"Add a second step to protect your account, even if someone learns your password."}</p>
    {!factor&&!pending&&<button className="button primary" disabled={busy||!loaded} onClick={enroll}>{busy?"Starting…":"Set up authenticator"}</button>}
    {pending&&<><p>Scan this QR code in your authenticator app, then enter its code below. Save the authenticator in a secure backup before continuing. Anyone with this QR can generate your codes.</p>
      <img className="security-qr" src={pending.qr.startsWith("data:")?pending.qr:"data:image/svg+xml;charset=utf-8,"+encodeURIComponent(pending.qr)} alt="Private authenticator setup QR code"/>
      <form className="account-form" onSubmit={verify}><label>Six-digit code<input name="code" inputMode="numeric" autoComplete="one-time-code" maxLength={6} pattern="[0-9]{6}" required disabled={busy}/></label><button className="button primary" disabled={busy}>{busy?"Verifying…":"Enable two-step verification"}</button></form></>}
    <h2>Active sessions</h2><p>Sign out on every device if you lose a device or suspect someone accessed your account.</p>
    <button className="button" disabled={busy} onClick={logoutEverywhere}>Sign out all devices</button>
    {message&&<p role="status" className="form-alert">{message}</p>}<Link href="/account/">Back to dashboard</Link>
  </section></main>;
}
