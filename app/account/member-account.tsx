"use client";
import { useState, type FormEvent } from "react";
import type { User } from "@supabase/supabase-js";
import { getSupabase } from "../../lib/supabase";
import { ErrorNotice } from "./workspace-controls";
import MembershipJourney from "./membership-journey";
export default function MemberAccount({ user }: { user: User }) {
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError("");
    setNotice("");
    try {
      const name = String(
        new FormData(e.currentTarget).get("name") || "",
      ).trim();
      if (!name || name.length > 150)
        throw Error("Enter your name, up to 150 characters.");
      const r = await getSupabase().auth.updateUser({
        data: { full_name: name },
      });
      if (r.error) throw r.error;
      setNotice("Your details have been saved.");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      <section className="owner-panel club-feature">
        <h2>Your details</h2>
        <form className="club-editor" onSubmit={save}>
          <label>
            Name
            <input
              name="name"
              required
              maxLength={150}
              defaultValue={user.user_metadata?.full_name || ""}
            />
          </label>
          <label>
            Email
            <input value={user.email || ""} readOnly />
          </label>
          <ErrorNotice error={error} />
          {notice && <p role="status">{notice}</p>}
          <button className="button primary" disabled={busy}>
            Save details
          </button>
        </form>
      </section>
      <MembershipJourney />
    </>
  );
}
