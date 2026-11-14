"use client";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";
import { getSupabase } from "../../lib/supabase";
import { membershipRequest, type MyAccess } from "../../lib/memberships";
import {
  clubWorkspaceClient,
  type ClubWorkspaceOptions,
} from "../../lib/club-workspace";
import ClubWorkspacePanel, { PeoplePanel } from "./club-workspace-panels";
import { ActivityList } from "./club-activity";
import ClubAccessRequests from "./club-access-requests";
import MemberAccount from "./member-account";
import { ErrorNotice } from "./workspace-controls";
const sections = [
  ["overview", "Overview", "Your teams. Every player’s next step."],
  ["teams", "My Teams", "Players, team conversations and access requests."],
  ["reports", "Reports", "Turn observations into purposeful development."],
  ["homework", "Homework", "Assign practice, review videos and give feedback."],
  ["schedule", "Training & Games", "Plan sessions and prepare your teams."],
  ["events", "Events", "Meetings and events you have been invited to."],
  [
    "library",
    "Development Library",
    "Global ideas. Club resources. Your team’s practice.",
  ],
  ["chats", "Chats", "Your team conversations and invited groups."],
  ["announcements", "Announcements", "Updates shared with you and your teams."],
  ["account", "My Account", "Your details and club or team access."],
];
export default function CoachDashboard({ user }: { user: User }) {
  const router = useRouter();
  const [access, setAccess] = useState<MyAccess | null>(null);
  const [selected, setSelected] = useState("");
  const [section, setSection] = useState("overview");
  const [options, setOptions] = useState<ClubWorkspaceOptions | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [revision, setRevision] = useState(0);
  const [stats, setStats] = useState<Record<string, number | null>>({});
  const [desktop, setDesktop] = useState(true);
  const [mobile, setMobile] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const drawer = useRef<HTMLDialogElement>(null);
  const name =
    typeof user.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : user.email || "Coach";
  const initials = name
    .split(/\s+/)
    .slice(0, 2)
    .map((s: string) => s[0])
    .join("")
    .toUpperCase();
  const clubs =
    access?.clubs.filter(
      (c) =>
        c.status === "active" &&
        access.teams.some(
          (t) =>
            t.club_id === c.id &&
            t.status === "active" &&
            t.role_key === "coach",
        ),
    ) || [];
  const current = clubs.find((c) => c.id === selected);
  const request = useMemo(() => clubWorkspaceClient(selected), [selected]);
  const refresh = useCallback(() => setRevision((r) => r + 1), []);
  useEffect(() => {
    let live = true;
    membershipRequest<MyAccess>("my_access")
      .then((x) => {
        if (live) {
          setAccess(x);
          setSelected((old) =>
            x.clubs.some(
              (c) =>
                c.id === old &&
                c.status === "active" &&
                x.teams.some(
                  (t) =>
                    t.club_id === c.id &&
                    t.status === "active" &&
                    t.role_key === "coach",
                ),
            )
              ? old
              : x.clubs.find(
                  (c) =>
                    c.status === "active" &&
                    x.teams.some(
                      (t) =>
                        t.club_id === c.id &&
                        t.status === "active" &&
                        t.role_key === "coach",
                    ),
                )?.id || "",
          );
          setError("");
        }
      })
      .catch((e) => {
        if (live) {
          setError(e.message);
          setAccess(null);
          setOptions(null);
        }
      })
      .finally(() => {
        if (live) setLoading(false);
      });
    return () => {
      live = false;
    };
  }, [revision]);
  useEffect(() => {
    setOptions(null);
  }, [selected]);
  useEffect(() => {
    if (!selected) return;
    let live = true;
    setStats({});
    Promise.all([
      request<ClubWorkspaceOptions>("options"),
      request<Record<string, number | null>>("stats"),
    ])
      .then(([o, s]) => {
        if (live) {
          if (!o.workspace_role)
            throw Error(
              "Unable to verify your coaching role. Please try again.",
            );
          if (o.workspace_role !== "coach")
            throw Error(
              "Use your separate Coach account. Club Administrators have their own workspace.",
            );
          setOptions(o);
          setStats(s);
          setError("");
        }
      })
      .catch((e) => {
        if (live) {
          setError(e.message);
          setOptions(null);
        }
      });
    return () => {
      live = false;
    };
  }, [selected, request, revision]);
  useEffect(() => {
    const media = window.matchMedia("(max-width: 900px)");
    const update = () => {
      setMobile(media.matches);
      if (!media.matches) drawer.current?.close();
    };
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  useEffect(() => {
    const focused = () => refresh();
    window.addEventListener("focus", focused);
    return () => window.removeEventListener("focus", focused);
  }, [refresh]);
  async function logout() {
    setBusy(true);
    try {
      const result = await getSupabase().auth.signOut({ scope: "local" });
      if (result.error) throw result.error;
      router.replace("/");
    } catch {
      setError("Unable to log out. Please try again.");
    } finally {
      setBusy(false);
    }
  }
  function navigate(id: string) {
    setSection(id);
    drawer.current?.close();
    window.scrollTo({ top: 0, behavior: "instant" });
  }
  function Sidebar({ inDrawer = false }: { inDrawer?: boolean }) {
    return (
      <div className="owner-side-content">
        <div className="owner-brand">
          <Link href="/" className="wordmark">
            PFD<span>.</span>
          </Link>
          {inDrawer ? (
            <button
              className="close-button"
              aria-label="Close navigation"
              onClick={() => drawer.current?.close()}
            >
              ×
            </button>
          ) : (
            <span className="side-brand-tag">COACH</span>
          )}
        </div>
        <div className="club-switcher">
          <label
            htmlFor={inDrawer ? "coach-mobile-club" : "coach-desktop-club"}
          >
            YOUR CLUB
          </label>
          <select
            id={inDrawer ? "coach-mobile-club" : "coach-desktop-club"}
            value={selected}
            onChange={(e) => setSelected(e.target.value)}
            disabled={!clubs.length}
          >
            {!clubs.length && <option value="">No active coaching club</option>}
            {clubs.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <small>Approved coaching teams only</small>
        </div>
        <nav className="owner-nav" aria-label="Coach navigation">
          {sections.map(([key, title]) => (
            <button
              aria-current={section === key ? "page" : undefined}
              key={key}
              onClick={() => navigate(key)}
            >
              <span className="coach-nav-icon" aria-hidden="true">
                {
                  (
                    {
                      overview: "◫",
                      teams: "⚑",
                      reports: "▤",
                      homework: "✓",
                      schedule: "▦",
                      events: "◷",
                      library: "▥",
                      chats: "☷",
                      announcements: "◉",
                      account: "⚙",
                    } as Record<string, string>
                  )[key]
                }
              </span>
              <span>{title}</span>
              {section === key && <span className="nav-active-dot" />}
            </button>
          ))}
        </nav>
        <div className="owner-side-bottom">
          <a className="owner-logout" href="/account/security/">Account security</a>
          <div className="side-user">
            <span className="owner-avatar">{initials}</span>
            <span>
              <strong>{name}</strong>
              <small>Coach</small>
            </span>
          </div>
          <button
            className="owner-logout"
            disabled={busy}
            onClick={() => void logout()}
          >
            Log out
          </button>
        </div>
      </div>
    );
  }
  const active = sections.find((s) => s[0] === section)!;
  return (
    <div
      className={
        "owner-shell club-shell coach-shell" +
        (desktop ? "" : " sidebar-collapsed")
      }
    >
      <aside id="coach-sidebar" className="owner-sidebar" hidden={!desktop}>
        <Sidebar />
      </aside>
      <dialog
        ref={drawer}
        id="coach-mobile-sidebar"
        className="owner-drawer"
        aria-label="Coach navigation"
        onClose={() => setDrawerOpen(false)}
        onClick={(e) => {
          if (e.target !== e.currentTarget) return;
          const r = e.currentTarget.getBoundingClientRect();
          if (
            e.clientX < r.left ||
            e.clientX > r.right ||
            e.clientY < r.top ||
            e.clientY > r.bottom
          )
            drawer.current?.close();
        }}
      >
        <Sidebar inDrawer />
      </dialog>
      <div className="owner-body">
        <header className="owner-topbar">
          <button
            className="sidebar-toggle"
            aria-label="Toggle navigation"
            aria-expanded={mobile ? drawerOpen : desktop}
            aria-controls={mobile ? "coach-mobile-sidebar" : "coach-sidebar"}
            onClick={() => {
              if (mobile) {
                if (drawer.current?.open) drawer.current.close();
                else {
                  drawer.current?.showModal();
                  setDrawerOpen(true);
                }
              } else setDesktop((v) => !v);
            }}
          >
            <svg
              width="22"
              height="22"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
            >
              <path d="M3 6h18M3 12h18M3 18h18" />
            </svg>
          </button>
          <div className="owner-breadcrumb">
            <span>{current?.name || "Coach workspace"}</span>
            <span>/</span>
            <strong>{active[1]}</strong>
          </div>
          <span className="topbar-avatar">{initials}</span>
        </header>
        <main className="owner-main">
          <div className="owner-page-heading">
            <div>
              <p className="eyebrow">COACH WORKSPACE</p>
              <h1>
                {section === "overview"
                  ? `Ready for the next step, ${name.split(" ")[0]}?`
                  : active[1]}
              </h1>
              <p>{active[2]}</p>
            </div>
            <button className="owner-refresh" onClick={refresh}>
              Refresh access
            </button>
          </div>
          <ErrorNotice error={error} retry={refresh} />
          {loading ? (
            <p role="status">Opening your coaching workspace…</p>
          ) : section === "account" ? (
            <MemberAccount user={user} />
          ) : !current ? (
            <section className="owner-panel club-feature">
              <h2>No active coaching team</h2>
              <p>
                Your coaching membership may have changed. Request access or ask
                Club Admin to assign you.
              </p>
              <button
                className="button primary"
                onClick={() => navigate("account")}
              >
                Manage my access
              </button>
            </section>
          ) : !options ? (
            error ? null : (
              <p role="status">Checking team permissions…</p>
            )
          ) : section === "overview" ? (
            <>
              <section className="club-welcome owner-panel">
                <div>
                  <p className="eyebrow">YOUR COACHING SPACE</p>
                  <h2>{current.name}</h2>
                  <p>
                    {options.teams.length} approved coaching team
                    {options.teams.length === 1 ? "" : "s"} · {current.sport}
                  </p>
                  <small>{current.league}</small>
                </div>
              </section>
              <div className="owner-stat-grid">
                {[
                  ["My teams", options.teams.length],
                  ["Submitted reports", stats.reports],
                  ["Upcoming sessions", stats.sessions],
                  ["Active homework", stats.homework],
                  ["Awaiting review", stats.awaiting_review],
                  ["Player requests", stats.requests],
                ].map(([title, value]) => (
                  <article className="owner-stat" key={title}>
                    <p>{title}</p>
                    <strong>{value ?? "—"}</strong>
                    <small>Within your approved teams</small>
                  </article>
                ))}
              </div>
              <div className="club-cards">
                {[
                  ["teams", "Open My Teams"],
                  ["reports", "Create a development report"],
                  ["homework", "Review homework"],
                  ["schedule", "Plan the next session"],
                ].map(([key, title]) => (
                  <button
                    key={key}
                    className="club-card coach-shortcut"
                    onClick={() => navigate(key)}
                  >
                    {title} ↗
                  </button>
                ))}
              </div>
            </>
          ) : section === "teams" ? (
            <CoachTeams
              key={selected}
              clubId={selected}
              options={options}
              name={name}
            />
          ) : section === "events" || section === "announcements" ? (
            <section className="owner-panel club-feature">
              <ActivityList
                request={request}
                tab={section === "events" ? "my_calendar" : "my_announcements"}
                kind={section === "events" ? "event" : undefined}
                canSubmit={false}
              />
            </section>
          ) : (
            <ClubWorkspacePanel
              key={selected + section}
              clubId={selected}
              section={section}
              name={name}
              mode="coach"
              onChanged={refresh}
            />
          )}
        </main>
      </div>
    </div>
  );
}
function CoachTeams({
  clubId,
  options,
  name,
}: {
  clubId: string;
  options: ClubWorkspaceOptions;
  name: string;
}) {
  const [selected, setSelected] = useState(options.teams[0]?.id || "");
  const [tab, setTab] = useState("players");
  const request = useMemo(() => clubWorkspaceClient(clubId), [clubId]);
  return (
    <>
      <div className="club-cards">
        {options.teams.map((t) => (
          <button
            className="club-card coach-team-choice"
            aria-pressed={selected === t.id}
            key={t.id}
            onClick={() => setSelected(t.id)}
          >
            <h3>{t.name}</h3>
            <p>
              {t.age_group} · {t.season}
            </p>
            <small>Approved coach</small>
          </button>
        ))}
      </div>
      <nav className="club-actions" aria-label="Team sections">
        {[
          ["players", "Players"],
          ["schedule", "Schedule"],
          ["chats", "Team Chat"],
          ["requests", "Player Requests"],
        ].map(([key, title]) => (
          <button
            className="owner-refresh"
            aria-pressed={tab === key}
            key={key}
            onClick={() => setTab(key)}
          >
            {title}
          </button>
        ))}
      </nav>
      {selected &&
        (tab === "players" ? (
          <PeoplePanel key={selected} request={request} teamId={selected} />
        ) : tab === "requests" ? (
          <ClubAccessRequests
            key={selected}
            clubId={clubId}
            teamId={selected}
            coach
          />
        ) : (
          <ClubWorkspacePanel
            key={selected + tab}
            clubId={clubId}
            section={tab}
            teamId={selected}
            name={name}
            mode="coach"
          />
        ))}
    </>
  );
}
