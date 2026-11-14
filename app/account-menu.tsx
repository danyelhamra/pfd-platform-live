"use client";

import { useRef, useState, type FormEvent } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "./auth-provider";
import { getSupabase, registerAccount, authCallbackUrl } from "../lib/supabase";

export default function AccountMenu() {
  const dialog = useRef<HTMLDialogElement>(null);
  const [mode, setMode] = useState<"login" | "signup" | "reset" | "resend">("login");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const { user, ready } = useAuth();
  const router = useRouter();
  const signup = mode === "signup";
  const emailOnly = mode === "reset" || mode === "resend";

  function open() {
    setMode("login");
    setMessage("");
    dialog.current?.showModal();
  }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const form = new FormData(event.currentTarget);
    setBusy(true);
    setMessage("");
    const email = String(form.get("email") || "")
      .trim()
      .toLowerCase();
    const password = String(form.get("password") || "");
    try {
      if (emailOnly) {
        const result = mode === "reset"
          ? await getSupabase().auth.resetPasswordForEmail(email, { redirectTo: authCallbackUrl() })
          : await getSupabase().auth.resend({ type: "signup", email, options: { emailRedirectTo: authCallbackUrl() } });
        if (result.error && (result.error.status === 429 || (result.error.status || 0) >= 500)) throw result.error;
        setMessage("If this email is eligible, a link will arrive shortly. Check spam too. Wait a minute before requesting another.");
        return;
      }
      if (signup) {
        const name = String(form.get("name") || "").trim();
        if (!name) throw new Error("Enter your full name.");
        if (password !== String(form.get("confirm-password") || ""))
          throw new Error("Your passwords do not match.");
        await registerAccount(name, email, password);
        setMode("login");
        setMessage("Check your email to confirm your account before logging in. If you already have an account, log in or reset your password.");
        return;
      }
      const { error } = await getSupabase().auth.signInWithPassword({
        email,
        password,
      });
      if (error) {
        throw new Error(
          error.status === 429 ? "Too many attempts. Wait a few minutes before trying again." :
          error.code === "email_not_confirmed" ? "Confirm your email first. Use Resend confirmation below if needed." :
          error.code === "invalid_credentials"
            ? "Email or password is incorrect. Please try again."
            : error.message,
        );
      }
      dialog.current?.close();
      router.push("/account/");
    } catch (error) {
      setMessage(
        error instanceof Error
          ? ("status" in error && error.status === 429 ? "Too many attempts. Wait a few minutes before trying again." : error.message)
          : "We couldn't connect. Please try again.",
      );
    } finally {
      setBusy(false);
    }
  }

  if (ready && user)
    return (
      <Link className="account-button" href="/account/">
        My account <span aria-hidden="true">↗</span>
      </Link>
    );
  return (
    <>
      <button
        type="button"
        className="account-button"
        onClick={open}
        aria-haspopup="dialog"
      >
        Account <span aria-hidden="true">↗</span>
      </button>
      <dialog
        ref={dialog}
        className="account-dialog"
        aria-labelledby="account-title"
        onCancel={(event) => {
          if (busy) event.preventDefault();
        }}
        onClose={() => setMessage("")}
        onClick={(event) => {
          if (busy || event.target !== event.currentTarget) return;
          const r = event.currentTarget.getBoundingClientRect();
          if (
            event.clientX < r.left ||
            event.clientX > r.right ||
            event.clientY < r.top ||
            event.clientY > r.bottom
          )
            dialog.current?.close();
        }}
      >
        <div className="dialog-top">
          <span className="wordmark">
            PFD<span>.</span>
          </span>
          <button
            type="button"
            className="close-button"
            onClick={() => dialog.current?.close()}
            disabled={busy}
            aria-label="Close account popup"
          >
            ×
          </button>
        </div>
        <p className="eyebrow dialog-eyebrow">YOUR DEVELOPMENT STARTS HERE</p>
        <h2 id="account-title">
          {mode === "reset" ? "Reset your password." : mode === "resend" ? "Confirm your email." : signup ? "Your next chapter." : "Welcome back."}
        </h2>
        <p className="dialog-description">
          {signup
            ? "Create your account, then select a club to request access."
            : "Your club, your team and your development."}
        </p>
        <div className="account-tabs" aria-label="Account options">
          <button
            type="button"
            disabled={busy}
            aria-pressed={mode === "login"}
            onClick={() => {
              setMode("login");
              setMessage("");
            }}
          >
            Log in
          </button>
          <button
            type="button"
            disabled={busy}
            aria-pressed={signup}
            onClick={() => {
              setMode("signup");
              setMessage("");
            }}
          >
            Sign up
          </button>
        </div>
        <form
          key={mode}
          className="account-form"
          onSubmit={submit}
          aria-busy={busy}
        >
          {signup && (
            <label htmlFor="account-name">
              Full name
              <input
                id="account-name"
                name="name"
                autoComplete="name"
                required
                maxLength={150}
                disabled={busy}
              />
            </label>
          )}
          <label htmlFor="account-email">
            Email address
            <input
              id="account-email"
              type="email"
              name="email"
              autoComplete="email"
              autoCapitalize="none"
              spellCheck={false}
              maxLength={254}
              required
              disabled={busy}
            />
          </label>
          {!emailOnly && <label htmlFor="account-password">
            Password
            <input
              id="account-password"
              type="password"
              name="password"
              autoComplete={signup ? "new-password" : "current-password"}
              minLength={signup ? 8 : undefined}
              maxLength={128}
              required
              disabled={busy}
            />
          </label>}
          {signup && (
            <>
              <p className="field-hint">Use at least 8 characters. A longer, unique passphrase works well.</p>
              <label htmlFor="confirm-password">
                Confirm password
                <input
                  id="confirm-password"
                  type="password"
                  name="confirm-password"
                  autoComplete="new-password"
                  required
                  minLength={8}
                  maxLength={128}
                  disabled={busy}
                />
              </label>
            </>
          )}
          {message && (
            <p role="alert" className="form-alert">
              {message}
            </p>
          )}
          <button
            className="button primary submit-button"
            type="submit"
            disabled={busy}
          >
            {emailOnly ? (busy ? "Sending…" : "Send email link") : busy
              ? signup
                ? "Creating your account…"
                : "Logging in…"
              : signup
                ? "Create account"
                : "Log in"}
          </button>
          {!signup && <div className="auth-help">
            <button type="button" disabled={busy} onClick={() => { setMode("reset"); setMessage(""); }}>Forgot password?</button>
            <button type="button" disabled={busy} onClick={() => { setMode("resend"); setMessage(""); }}>Resend confirmation</button>
          </div>}
          {signup && (
            <p className="access-note">
              Request club access after signup. Once approved, you can request
              teams within that club.
            </p>
          )}
        </form>
      </dialog>
    </>
  );
}
