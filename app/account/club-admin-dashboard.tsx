"use client";

import Link from "next/link";
import ClubWorkspacePanel from "./club-workspace-panels";
import { clubWorkspaceClient } from "../../lib/club-workspace";
import ClubTeamsManager from "./club-teams-manager";
import ClubAccessRequests from "./club-access-requests";
import { clubTeamRequest, type TeamStats } from "../../lib/club-teams";
import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { getSupabase } from "../../lib/supabase";
import { loadClubShell, type ClubShellContext } from "../../lib/club-shell";

type Section =
  | "overview"
  | "teams"
  | "people"
  | "requests"
  | "reports"
  | "homework"
  | "events"
  | "chats"
  | "schedule"
  | "library"
  | "announcements"
  | "settings";
const sections: {
  id: Section;
  label: string;
  description: string;
  permissions: string[];
  next: string;
  icon: string;
}[] = [
  {
    id: "overview",
    label: "Overview",
    description: "Your club. Every player’s development in view.",
    permissions: [],
    next: "Your club at a glance.",
    icon: "grid",
  },
  {
    id: "teams",
    label: "Teams",
    description: "The teams and people at the heart of your club.",
    permissions: ["teams.view", "teams.create"],
    next: "Create teams, assign coaches and organise players.",
    icon: "shield",
  },
  {
    id: "people",
    label: "People",
    description: "Coaches, players and their development journeys.",
    permissions: ["members.view"],
    next: "Browse club members and open their development profiles.",
    icon: "users",
  },
  {
    id: "requests",
    label: "Access Requests",
    description: "A clear place for people joining your club.",
    permissions: ["members.approve", "coaches.approve", "players.approve"],
    next: "Review coach and player membership requests for this club.",
    icon: "clock",
  },
  {
    id: "reports",
    label: "Reports",
    description: "Assessments that turn observations into action.",
    permissions: ["reports.view_team", "reports.create", "reports.view_own"],
    next: "Create and view development and match reports within this club.",
    icon: "report",
  },
  {
    id: "homework",
    label: "Homework",
    description: "Keep development moving between sessions.",
    permissions: ["homework.assign", "homework.review", "homework.view"],
    next: "Assign individual drills, review submissions and give feedback.",
    icon: "check",
  },
  {
    id: "schedule",
    label: "Training & Games",
    description: "Purposeful sessions. Prepared teams.",
    permissions: ["events.view", "events.manage"],
    next: "Schedule training and matches, using timed training-plan templates.",
    icon: "calendar",
  },
  {
    id: "events",
    label: "Events",
    description: "Meetings and events for the right people in your club.",
    permissions: ["events.view", "events.manage"],
    next: "Create club events, select coaches, teams or individual attendees, and add them to their PFD calendars.",
    icon: "calendar",
  },
  {
    id: "chats",
    label: "Chats",
    description: "Keep the right people connected.",
    permissions: ["chats.view"],
    next: "Create separate group chats and choose specific club members, including coaches-only groups.",
    icon: "users",
  },
  {
    id: "library",
    label: "Development Library",
    description: "A shared toolkit for purposeful development.",
    permissions: ["library.view", "library.manage_club"],
    next: "Browse shared PFD resources and manage your club’s resources.",
    icon: "book",
  },
  {
    id: "announcements",
    label: "Announcements",
    description: "Keep the club connected and informed.",
    permissions: ["announcements.view", "announcements.publish"],
    next: "Publish announcements to the whole club, selected teams or selected roles, such as coaches.",
    icon: "speaker",
  },
  {
    id: "settings",
    label: "Club Settings",
    description: "The details that make this club yours.",
    permissions: ["clubs.view"],
    next: "Review and update club details as we build this section.",
    icon: "settings",
  },
];
function Icon({ name }: { name: string }) {
  const paths: Record<string, React.ReactNode> = {
    grid: (
      <>
        <rect x="3" y="3" width="7" height="7" rx="1" />
        <rect x="14" y="3" width="7" height="7" rx="1" />
        <rect x="3" y="14" width="7" height="7" rx="1" />
        <rect x="14" y="14" width="7" height="7" rx="1" />
      </>
    ),
    shield: <path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6z" />,
    users: (
      <>
        <circle cx="9" cy="8" r="3" />
        <path d="M3 21v-3a6 6 0 0 1 12 0v3M16 5a3 3 0 0 1 0 6m2 4a5 5 0 0 1 3 4v2" />
      </>
    ),
    clock: (
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v5l3 2" />
      </>
    ),
    report: <path d="M14 3H5v18h14V8zM14 3v5h5M8 12h8M8 16h5" />,
    check: (
      <>
        <rect x="4" y="3" width="16" height="18" rx="2" />
        <path d="m8 11 3 3 5-6" />
      </>
    ),
    calendar: (
      <>
        <rect x="3" y="5" width="18" height="16" rx="2" />
        <path d="M7 3v4m10-4v4M3 11h18m-13 4h2m4 0h2" />
      </>
    ),
    book: (
      <path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1zM12 5v15" />
    ),
    speaker: (
      <>
        <path d="m3 10 14-6v16L3 14zM6 15l2 6h3l-2-5M21 8v8" />
      </>
    ),
    settings: (
      <>
        <path d="M4 6h16M4 12h16M4 18h16" />
        <circle cx="8" cy="6" r="2" />
        <circle cx="16" cy="12" r="2" />
        <circle cx="10" cy="18" r="2" />
      </>
    ),
    menu: <path d="M4 6h16M4 12h16M4 18h16" />,
    logout: <path d="M10 4H4v16h6M10 12h11m-4-4 4 4-4 4" />,
  };
  return (
    <svg
      aria-hidden="true"
      width="19"
      height="19"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {paths[name]}
    </svg>
  );
}
export default function ClubAdminDashboard({ user }: { user: User }) {
  const router = useRouter();
  const [context, setContext] = useState<ClubShellContext | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState("");
  const [section, setSection] = useState<Section>("overview");
  const [desktopOpen, setDesktopOpen] = useState(true);
  const [mobile, setMobile] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [workspaceStats, setWorkspaceStats] = useState<
    Record<string, number | null>
  >({});
  const [teamStats, setTeamStats] = useState<TeamStats | null>(null);
  const [teamRevision, setTeamRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  const drawer = useRef<HTMLDialogElement>(null);
  const requestId = useRef(0);
  const name =
    typeof user.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : "";
  const initials = (name || user.email || "PFD")
    .split(/\s+/)
    .slice(0, 2)
    .map((s: string) => s[0])
    .join("")
    .toUpperCase();
  const load = useCallback(
    async (silent = false) => {
      const current = ++requestId.current;
      if (!silent) {
        setLoading(true);
        setContext(null);
      }
      setError("");
      try {
        const next = await loadClubShell();
        if (current !== requestId.current) return;
        setContext(next);
        setSelected((previous) => {
          let remembered = "";
          try {
            remembered =
              sessionStorage.getItem("pfd-club-selection:" + user.id) || "";
          } catch {}
          return (
            next.clubs.find((c) => c.id === previous)?.id ||
            next.clubs.find((c) => c.id === remembered)?.id ||
            next.clubs[0]?.id ||
            ""
          );
        });
      } catch (e) {
        if (current === requestId.current) {
          setContext(null);
          setError(
            e instanceof Error ? e.message : "Unable to open club workspace.",
          );
        }
      } finally {
        if (current === requestId.current) setLoading(false);
      }
    },
    [user.id],
  );
  useEffect(() => {
    void load();
    const refresh = () => {
      void load(true);
    };
    window.addEventListener("focus", refresh);
    return () => {
      requestId.current++;
      window.removeEventListener("focus", refresh);
    };
  }, [load]);
  useEffect(() => {
    const query = window.matchMedia("(max-width: 820px)");
    const sync = () => {
      setMobile(query.matches);
      if (!query.matches) {
        drawer.current?.close();
        setMobileOpen(false);
      }
    };
    sync();
    query.addEventListener("change", sync);
    try {
      setDesktopOpen(
        localStorage.getItem("pfd-club-sidebar:" + user.id) !== "hidden",
      );
    } catch {}
    const read = () => {
      const value = window.location.hash.replace("#club-", "");
      if (sections.some((s) => s.id === value)) setSection(value as Section);
    };
    read();
    window.addEventListener("hashchange", read);
    return () => {
      query.removeEventListener("change", sync);
      window.removeEventListener("hashchange", read);
    };
  }, [user.id]);
  useEffect(() => {
    if (!mobileOpen) return;
    const old = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = old;
    };
  }, [mobileOpen]);
  useEffect(() => {
    let active = true;
    setTeamStats(null);
    setWorkspaceStats({});
    if (context && selected && context.permissions["teams.view"])
      clubTeamRequest<TeamStats>(selected, "stats")
        .then((stats) => {
          if (active) setTeamStats(stats);
        })
        .catch(() => {
          if (active) setTeamStats(null);
        });
    return () => {
      active = false;
    };
  }, [selected, context, teamRevision]);
  useEffect(() => {
    let live = true;
    if (selected && context) {
      clubWorkspaceClient(selected)<Record<string, number | null>>("stats")
        .then((x) => {
          if (live) setWorkspaceStats(x);
        })
        .catch(() => {
          if (live) setWorkspaceStats({});
        });
    }
    return () => {
      live = false;
    };
  }, [selected, context, teamRevision, section]);
  const club = context?.clubs.find((c) => c.id === selected);
  const active = sections.find((s) => s.id === section)!;
  const allowed =
    !active.permissions.length ||
    active.permissions.some((key) => context?.permissions[key]);
  function navigate(id: Section) {
    setSection(id);
    window.history.replaceState(window.history.state, "", "#club-" + id);
    drawer.current?.close();
    setMobileOpen(false);
    window.scrollTo({ top: 0, behavior: "instant" });
  }
  function chooseClub(id: string) {
    if (!context?.clubs.some((c) => c.id === id)) return;
    setSelected(id);
    try {
      sessionStorage.setItem("pfd-club-selection:" + user.id, id);
    } catch {}
    navigate("overview");
  }
  function toggle() {
    if (mobile) {
      if (drawer.current?.open) drawer.current.close();
      else {
        drawer.current?.showModal();
        setMobileOpen(true);
      }
    } else
      setDesktopOpen((value) => {
        try {
          localStorage.setItem(
            "pfd-club-sidebar:" + user.id,
            value ? "hidden" : "open",
          );
        } catch {}
        return !value;
      });
  }
  async function logout() {
    if (busy) return;
    setBusy(true);
    setError("");
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
  function Sidebar({ inDrawer = false }: { inDrawer?: boolean }) {
    return (
      <div className="owner-side-content">
        <div className="owner-brand">
          <Link href="/" className="wordmark" aria-label="PFD home">
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
            <span className="side-brand-tag">CLUB ADMIN</span>
          )}
        </div>
        <div className="club-switcher">
          <label
            htmlFor={inDrawer ? "club-mobile-select" : "club-desktop-select"}
          >
            YOUR CLUB
          </label>
          <select
            id={inDrawer ? "club-mobile-select" : "club-desktop-select"}
            value={selected}
            disabled={loading || !context?.clubs.length}
            onChange={(e) => chooseClub(e.target.value)}
          >
            {!context?.clubs.length && (
              <option value="">
                {loading ? "Loading clubs…" : "No active clubs"}
              </option>
            )}
            {context?.clubs.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          {club && <small>{club.sport || "Club workspace"}</small>}
        </div>
        <nav
          className="owner-nav"
          aria-label={inDrawer ? "Mobile club navigation" : "Club navigation"}
        >
          {sections.map((s) => (
            <button
              key={s.id}
              onClick={() => navigate(s.id)}
              aria-current={s.id === section ? "page" : undefined}
            >
              <Icon name={s.icon} />
              <span>{s.label}</span>
              {s.id === section && <span className="nav-active-dot" />}
            </button>
          ))}
        </nav>
        <div className="owner-side-bottom">
          <a className="owner-logout" href="/account/security/">Account security</a>
          <div className="side-user">
            <span className="owner-avatar">{initials}</span>
            <span>
              <strong>{name || user.email || "Your account"}</strong>
              <small>Club Administrator</small>
            </span>
          </div>
          <button
            className="owner-logout"
            disabled={busy}
            onClick={() => void logout()}
          >
            <Icon name="logout" />
            {busy ? "Logging out…" : "Log out"}
          </button>
        </div>
      </div>
    );
  }
  return (
    <div
      className={
        "owner-shell club-shell" + (desktopOpen ? "" : " sidebar-collapsed")
      }
    >
      <aside
        id="club-desktop-sidebar"
        className="owner-sidebar"
        hidden={!desktopOpen}
      >
        <Sidebar />
      </aside>
      <dialog
        ref={drawer}
        id="club-mobile-sidebar"
        className="owner-drawer"
        aria-label="Club navigation"
        onClose={() => setMobileOpen(false)}
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
            onClick={toggle}
            aria-label={
              (mobile ? mobileOpen : desktopOpen)
                ? "Hide navigation"
                : "Show navigation"
            }
            aria-expanded={mobile ? mobileOpen : desktopOpen}
            aria-controls={
              mobile ? "club-mobile-sidebar" : "club-desktop-sidebar"
            }
          >
            <Icon name="menu" />
          </button>
          <div className="owner-breadcrumb">
            <span>{club?.name || "Club workspace"}</span>
            <span aria-hidden="true">/</span>
            <strong>{active.label}</strong>
          </div>
          <span className="topbar-avatar" title={name || user.email}>
            {initials}
          </span>
        </header>
        <main className="owner-main" id="club-content">
          <div className="owner-page-heading">
            <div>
              <p className="eyebrow">CLUB ADMINISTRATOR</p>
              <h1>
                {section === "overview"
                  ? "A clear path for your club."
                  : active.label}
              </h1>
              <p>{active.description}</p>
            </div>
            <button
              className="owner-refresh"
              disabled={loading}
              onClick={() => void load()}
            >
              {loading ? "Refreshing…" : "Refresh access"}
            </button>
          </div>
          {error && (
            <div className="form-alert" role="alert">
              {error}
              <button className="inline-retry" onClick={() => void load()}>
                Try again
              </button>
            </div>
          )}
          {loading ? (
            <p className="owner-loading" role="status">
              Opening your club workspace…
            </p>
          ) : !error && !club ? (
            <section className="owner-panel owner-empty">
              <span className="empty-icon">
                <Icon name="shield" />
              </span>
              <h2>No active club available.</h2>
              <p>
                Ask the PFD Owner to check your club assignment, club status and
                role permissions.
              </p>
              <Link href="/account/" className="text-link">
                Back to my account ↗
              </Link>
            </section>
          ) : (
            club && (
              <>
                {!allowed ? (
                  <section className="owner-panel owner-empty">
                    <span className="empty-icon">
                      <Icon name="shield" />
                    </span>
                    <h2>This section is not enabled for your role.</h2>
                    <p>
                      The PFD Owner manages role permissions. Your access
                      remains limited to your assigned clubs.
                    </p>
                  </section>
                ) : section === "requests" ? (
                  <ClubAccessRequests key={club.id} clubId={club.id} />
                ) : section === "teams" ? (
                  <ClubTeamsManager
                    key={club.id}
                    club={club}
                    onChanged={() => setTeamRevision((r) => r + 1)}
                  />
                ) : section === "overview" ? (
                  <>
                    <section className="club-welcome owner-panel">
                      <div>
                        <p className="eyebrow">YOUR CLUB WORKSPACE</p>
                        <h2>{club.name}</h2>
                        <p>
                          {[club.sport, club.league]
                            .filter(Boolean)
                            .join(" · ") || "Player Focused Development"}
                        </p>
                        <small>
                          {[club.city, club.state, club.country]
                            .filter(Boolean)
                            .join(", ") || "Club location needs completing"}
                        </small>
                      </div>
                      <div className="club-welcome-mark" aria-hidden="true">
                        <Icon name="shield" />
                      </div>
                    </section>
                    <div className="owner-stat-grid">
                      {[
                        ["Teams", "Organise your club"],
                        ["Coaches", "Support purposeful coaching"],
                        ["Players", "Put development first"],
                        ["Pending requests", "Manage membership"],
                        ["Reports", "Track player progress"],
                        ["Upcoming sessions", "Plan the next step"],
                      ].map(([label, note]) => (
                        <article className="owner-stat" key={label}>
                          <p>{label}</p>
                          <strong>
                            {label === "Teams"
                              ? (teamStats?.teams ?? "—")
                              : label === "Coaches"
                                ? (teamStats?.coaches ?? "—")
                                : label === "Players"
                                  ? (teamStats?.players ?? "—")
                                  : label === "Pending requests"
                                    ? (workspaceStats.requests ?? "—")
                                    : label === "Reports"
                                      ? (workspaceStats.reports ?? "—")
                                      : (workspaceStats.sessions ?? "—")}
                          </strong>
                          <small>{note}</small>
                        </article>
                      ))}
                    </div>
                    <p className="metrics-note">
                      Team, coach and player totals reflect active teams in this
                      club. Report totals count submitted reports; upcoming
                      sessions include scheduled club events.
                    </p>
                    <div className="club-start-grid">
                      <section className="owner-panel club-next-step">
                        <p className="eyebrow">YOUR TEAM STRUCTURE</p>
                        <h2>Build your teams.</h2>
                        <p>
                          Create teams and assign coaches and players. Their
                          schedules, conversations and development records will
                          connect to that structure.
                        </p>
                        <button
                          className="button primary"
                          onClick={() => navigate("teams")}
                        >
                          Open Teams ↗
                        </button>
                      </section>
                      <section className="owner-panel club-shortcuts">
                        <h2>Your club workspace</h2>
                        {(["reports", "library", "schedule"] as Section[]).map(
                          (id) => {
                            const s = sections.find((s) => s.id === id)!;
                            return (
                              <button key={id} onClick={() => navigate(id)}>
                                <Icon name={s.icon} />
                                <span>{s.label}</span>
                                <span aria-hidden="true">↗</span>
                              </button>
                            );
                          },
                        )}
                      </section>
                    </div>
                  </>
                ) : (
                  <ClubWorkspacePanel
                    key={club.id + section}
                    clubId={club.id}
                    section={section}
                    name={name || user.email || "Club administrator"}
                    onChanged={() => {
                      setTeamRevision((r) => r + 1);
                      if (section === "settings") void load(true);
                    }}
                  />
                )}
              </>
            )
          )}
        </main>
      </div>
    </div>
  );
}
