"use client";
import { useEffect, useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { getSupabase } from "../../../lib/supabase";

type LinkSession = { access_token: string; refresh_token: string; recovery: boolean };
export default function AuthCallback() {
  const captured = useRef(false);
  const link = useRef<LinkSession | null>(null);
  const [ready, setReady] = useState(false);
  const [recovery, setRecovery] = useState(false);
  const [email, setEmail] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  useEffect(() => {
    if (captured.current) return;
    captured.current = true;
    const fragment = new URLSearchParams(window.location.hash.slice(1));
    // Strip credentials before making any request or rendering a navigation link.
    window.history.replaceState(null, "", "/auth/callback/");
    const access_token = fragment.get("access_token");
    const refresh_token = fragment.get("refresh_token");
    const type = fragment.get("type");
    if (!access_token || !refresh_token || !["signup", "recovery", "email_change", "invite", "magiclink"].includes(type || "")) {
      setMessage("This link has expired or is invalid. Return home to request a fresh confirmation or password reset email.");
      return;
    }
    link.current = { access_token, refresh_token, recovery: type === "recovery" };
    getSupabase().auth.getUser(access_token).then(({ data, error }) => {
      if (error || !data.user?.email_confirmed_at) {
        link.current = null;
        setMessage("This link has expired or is invalid. Please request a new email.");
      } else {
        setEmail(data.user.email || "your account");
        setReady(true);
      }
    }).catch(() => setMessage("Unable to check this link. Request a new email and try again."));
  }, []);
  async function accept() {
    if (!link.current || busy) return;
    setBusy(true); setMessage("");
    try {
      const result = await getSupabase().auth.setSession(link.current);
      if (result.error) throw result.error;
      const reset = link.current.recovery;
      link.current = null;
      if (reset) { setRecovery(true); setReady(false); }
      else { window.location.replace("/account/"); }
    } catch { setMessage("Unable to open this session. Request a new email link."); }
    finally { setBusy(false); }
  }
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (busy) return;
    const form = new FormData(event.currentTarget);
    const password = String(form.get("password") || "");
    if (password.length < 8 || password !== form.get("confirm")) { setMessage("Use at least 8 characters and make both passwords match."); return; }
    setBusy(true); setMessage("");
    try {
      const result = await getSupabase().auth.updateUser({ password });
      if (result.error) throw result.error;
      // Invalidate every refresh session after recovery, not just this tab.
      const logout = await getSupabase().auth.signOut({ scope: "global" });
      setDone(true); setRecovery(false);
      setMessage(logout.error ? "Password saved. Session sign-out could not be confirmed; use Account security to sign out all devices." : "Password saved and all sessions signed out. Return home and log in with your new password.");
    } catch { setMessage("Unable to change the password. Use a different, longer password or request a fresh reset link. If you use two-step verification, complete it first."); }
    finally { setBusy(false); }
  }
  return <main className="auth-page"><section className="auth-card">
    <Link href="/" className="wordmark">PFD<span>.</span></Link>
    <h1>{recovery ? "Choose a new password" : done ? "Password updated" : "Confirm your account"}</h1>
    {ready && <><p>Continue with the email link for <strong>{email}</strong>. Only continue if this is your account and you requested this email.</p><button className="button primary" onClick={accept} disabled={busy}>{busy ? "Checking…" : "Continue securely"}</button></>}
    {recovery && <form className="account-form" onSubmit={save}>
      <label>New password<input name="password" type="password" autoComplete="new-password" minLength={8} maxLength={128} required disabled={busy}/></label>
      <label>Confirm password<input name="confirm" type="password" autoComplete="new-password" minLength={8} maxLength={128} required disabled={busy}/></label>
      <p className="field-hint">At least 8 characters. Use a unique passphrase.</p>
      <button className="button primary" disabled={busy}>{busy ? "Saving…" : "Save password"}</button>
    </form>}
    {message && <p role="status" className="form-alert">{message}</p>}
    <Link href="/">Return home</Link>
  </section></main>;
}
