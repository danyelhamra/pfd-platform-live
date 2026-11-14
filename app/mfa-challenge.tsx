"use client";
import { useState, type FormEvent } from "react";
import { getSupabase } from "../lib/supabase";
export default function MfaChallenge({ factorId }: { factorId: string }) {
  const [busy,setBusy]=useState(false),[message,setMessage]=useState("");
  async function submit(event:FormEvent<HTMLFormElement>) {
    event.preventDefault(); if(busy)return;
    const code=String(new FormData(event.currentTarget).get("code")||"").trim();
    if(!/^\d{6}$/.test(code)){setMessage("Enter the six-digit code from your authenticator.");return;}
    setBusy(true);setMessage("");
    try {
      const r=await getSupabase().auth.mfa.challengeAndVerify({factorId,code});
      if(r.error)throw r.error;
    }catch{setMessage("Code not accepted. Check the latest code and try again. Too many attempts will require a short wait.");}
    finally{setBusy(false);}
  }
  return <main className="auth-page"><section className="auth-card"><span className="wordmark">PFD<span>.</span></span>
    <h1>Two-step verification</h1><p>Enter the code from your authenticator to open your account.</p>
    <form className="account-form" onSubmit={submit}><label>Authenticator code<input name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required disabled={busy}/></label>
    <button className="button primary" disabled={busy}>{busy?"Checking…":"Verify"}</button></form>
    {message&&<p role="alert">{message}</p>}<button className="button" disabled={busy} onClick={()=>void getSupabase().auth.signOut({scope:"local"})}>Log out</button>
  </section></main>;
}
