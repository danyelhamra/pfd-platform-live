"use client";

import Link from "next/link";
import { useEffect, useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "../auth-provider";
import AccountMenu from "../account-menu";
import OwnerDashboard from "./owner-dashboard";
import ClubAdminDashboard from "./club-admin-dashboard";
import CoachDashboard from "./coach-dashboard";
import PlayerDashboard from "./player-dashboard";
import { membershipRequest, type MyAccess } from "../../lib/memberships";
import MembershipJourney from "./membership-journey";
import { getSupabase } from "../../lib/supabase";

function PersonalWorkspace() {
  const { user, ready, isOwner } = useAuth();
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [section, setSection] = useState<"overview" | "profile">("overview");
  async function logout() {
    setBusy(true);
    setError("");
    try {
      const { error } = await getSupabase().auth.signOut({ scope: "local" });
      if (error) throw error;
      router.replace("/");
    } catch {
      setError("Unable to log out. Please try again.");
    } finally {
      setBusy(false);
    }
  }
  async function saveProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const name = String(
      new FormData(event.currentTarget).get("name") || "",
    ).trim();
    setBusy(true);
    setError("");
    setNotice("");
    try {
      if (!name || name.length > 150)
        throw new Error("Enter a name of 1 to 150 characters.");
      const { error } = await getSupabase().auth.updateUser({
        data: { full_name: name },
      });
      if (error) throw error;
      setNotice("Your name has been updated.");
    } catch (error) {
      setError(
        error instanceof Error ? error.message : "Unable to save your name.",
      );
    } finally {
      setBusy(false);
    }
  }
  const name =
    typeof user?.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : "";
  if (ready && user && isOwner) return <OwnerDashboard user={user} />;

  return (
    <>
      <header className="site-header">
        <div className="container header-inner">
          <Link href="/" className="wordmark" aria-label="PFD home">
            PFD<span>.</span>
          </Link>
          <span className="workspace-header-label">YOUR DEVELOPMENT SPACE</span>
          {ready && user ? (
            <button className="account-button" onClick={logout} disabled={busy}>
              {busy ? "Please wait…" : "Log out"}
            </button>
          ) : (
            <AccountMenu />
          )}
        </div>
      </header>
      {!ready ? (
        <main className="container workspace-main">
          <p role="status">Opening your account…</p>
        </main>
      ) : !user ? (
        <main className="container workspace-main">
          <p className="eyebrow">YOUR ACCOUNT</p>
          <h1 className="workspace-title">Welcome to PFD.</h1>
          <p className="workspace-description">
            Log in or create your account using the Account button above.
          </p>
          <Link href="/" className="text-link">
            ← Back to the platform
          </Link>
        </main>
      ) : (
        <main className="container workspace-main">
          <p className="eyebrow">PLAYER FOCUSED DEVELOPMENT</p>
          {isOwner && (
            <p className="owner-label">PFD Owner · Platform-wide access</p>
          )}
          <h1 className="workspace-title">
            {name ? `Welcome, ${name.split(" ")[0]}.` : "Welcome to PFD."}
          </h1>
          <p className="workspace-description">
            One account. Your development. Every team you belong to.
          </p>
          <nav aria-label="Account sections" className="workspace-tabs">
            <button
              aria-pressed={section === "overview"}
              onClick={() => {
                setSection("overview");
                setNotice("");
                setError("");
              }}
            >
              Overview
            </button>
            <button
              aria-pressed={section === "profile"}
              onClick={() => {
                setSection("profile");
                setNotice("");
                setError("");
              }}
            >
              My profile
            </button>
          </nav>
          {error && (
            <p role="alert" className="form-alert">
              {error}
            </p>
          )}
          {notice && (
            <p role="status" className="form-success">
              {notice}
            </p>
          )}
          {section === "overview" ? (
            <MembershipJourney />
          ) : (
            <section className="workspace-card profile-card">
              <p className="eyebrow">MY PROFILE</p>
              <h2>Your details.</h2>
              <form
                className="account-form"
                key={user.id}
                onSubmit={saveProfile}
              >
                <label htmlFor="profile-name">
                  Full name
                  <input
                    id="profile-name"
                    name="name"
                    defaultValue={name}
                    required
                    maxLength={150}
                    autoComplete="name"
                    disabled={busy}
                  />
                </label>
                <label htmlFor="profile-email">
                  Email address
                  <input
                    id="profile-email"
                    type="email"
                    value={user.email || ""}
                    readOnly
                    aria-describedby="email-note"
                  />
                </label>
                <p id="email-note" className="field-hint">
                  This is the email you use to log in.
                </p>
                <button
                  type="submit"
                  className="button primary"
                  disabled={busy}
                >
                  {busy ? "Saving…" : "Save changes"}
                </button>
              </form>
            </section>
          )}
        </main>
      )}
    </>
  );
}

// Discover the canonical membership before choosing a workspace. Metadata is not a role.
export default function AccountWorkspace() {
  const { user, ready, isOwner } = useAuth();
  const [access, setAccess] = useState<{
    userId: string;
    assigned: boolean;
    coach: boolean;
    player: boolean;
  } | null>(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    setAccess(null);
    setError("");
    if (!ready || !user || isOwner) return;
    let active = true;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    Promise.resolve(
      getSupabase()
        .from("pfd_club_admins")
        .select("club_id")
        .eq("user_id", user.id)
        .limit(1)
        .abortSignal(controller.signal),
    )
      .then(async (result) => {
        if (!active) return;
        if (result.error)
          setError("Unable to check your club access. Please try again.");
        else {
          let coach = false;
          let player = false;
          if (!result.data?.length) {
            const mine = await membershipRequest<MyAccess>("my_access");
            coach = mine.teams.some(
              (t) =>
                t.role_key === "coach" &&
                t.status === "active" &&
                mine.clubs.some(
                  (c) => c.id === t.club_id && c.status === "active",
                ),
            );
            player = mine.teams.some(
              (t) =>
                t.role_key === "player" &&
                t.status === "active" &&
                mine.clubs.some(
                  (c) => c.id === t.club_id && c.status === "active",
                ),
            );
          }
          if (active)
            setAccess({
              userId: user.id,
              assigned: !!result.data?.length,
              coach,
              player,
            });
        }
      })
      .catch(() => {
        if (active)
          setError("Unable to check your club access. Please try again.");
      })
      .finally(() => clearTimeout(timeout));
    return () => {
      active = false;
      clearTimeout(timeout);
      controller.abort();
    };
  }, [ready, user?.id, isOwner, revision]);
  if (ready && user && !isOwner) {
    if (error)
      return (
        <main className="container workspace-main">
          <p className="form-alert" role="alert">
            {error}
          </p>
          <button
            className="button primary"
            onClick={() => setRevision((v) => v + 1)}
          >
            Try again
          </button>
        </main>
      );
    if (access?.userId !== user.id)
      return (
        <main className="container workspace-main">
          <p role="status">Checking your club access…</p>
        </main>
      );
    if (access.assigned)
      return <ClubAdminDashboard key={user.id} user={user} />;
    if (access.coach) return <CoachDashboard key={user.id} user={user} />;
    if (access.player) return <PlayerDashboard key={user.id} user={user} />;
  }
  return <PersonalWorkspace />;
}
