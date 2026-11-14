"use client";
import Link from "next/link";
import { openPrivateFile } from "../../lib/private-files";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";
import { getSupabase } from "../../lib/supabase";
import { membershipRequest, type MyAccess } from "../../lib/memberships";
import {
  playerWorkspaceClient,
  type PlayerOptions,
} from "../../lib/player-workspace";
import {
  type WorkspaceClient,
  type Report,
  type Resource,
  type Page,
  dateLabel,
} from "../../lib/workspace-api";
import {
  calendarDownload,
  type ClubWorkspaceOptions,
} from "../../lib/club-workspace";
import { ActivityList } from "./club-activity";
import { ChatPanel, ProgressChart } from "./club-workspace-panels";
import { useWorkspaceList } from "./owner-management";
import ReportsManager from "./reports-manager";
import MemberAccount from "./member-account";
import { Badge, ErrorNotice, Modal, Pagination } from "./workspace-controls";
const sections = [
  ["overview", "Overview", "Your next session. Your next step."],
  [
    "development",
    "My Development",
    "Understand your progress and reflect on your game.",
  ],
  ["homework", "Homework", "Practise with purpose. Share your progress."],
  [
    "schedule",
    "Training & Games",
    "Your teams’ sessions, games and availability.",
  ],
  ["teams", "My Teams", "The teams you belong to and their conversations."],
  ["events", "Events", "Club events you have been invited to."],
  [
    "library",
    "Development Library",
    "Individual practice from PFD, your club and your teams.",
  ],
  ["chats", "Chats", "Your team conversations and invited groups."],
  ["announcements", "Announcements", "The updates that matter to you."],
  ["account", "My Account", "Your details and club or team access."],
];
type PlayerStats = {
  reports: number | null;
  homework_due: number | null;
  upcoming: number | null;
  feedback: {
    title: string;
    feedback: string;
    review_status: string;
    updated_at: string;
  }[];
};
export default function PlayerDashboard({ user }: { user: User }) {
  const router = useRouter();
  const [access, setAccess] = useState<MyAccess | null>(null);
  const [selected, setSelected] = useState("");
  const [section, setSection] = useState("overview");
  const [options, setOptions] = useState<PlayerOptions | null>(null);
  const [stats, setStats] = useState<PlayerStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [revision, setRevision] = useState(0);
  const [desktop, setDesktop] = useState(true);
  const [mobile, setMobile] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const drawer = useRef<HTMLDialogElement>(null);
  const name =
    typeof user.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : user.email || "Player";
  const initials = name
    .split(/\s+/)
    .slice(0, 2)
    .map((s: string) => s[0])
    .join("")
    .toUpperCase();
  const request = useMemo(() => playerWorkspaceClient(selected), [selected]);
  const refresh = useCallback(() => setRevision((r) => r + 1), []);
  const clubs =
    access?.clubs.filter(
      (c) =>
        c.status === "active" &&
        access.teams.some(
          (t) =>
            t.club_id === c.id &&
            t.status === "active" &&
            t.role_key === "player",
        ),
    ) || [];
  const current = clubs.find((c) => c.id === selected);
  useEffect(() => {
    let live = true;
    membershipRequest<MyAccess>("my_access")
      .then((x) => {
        if (!live) return;
        setAccess(x);
        setSelected((previous) => {
          let remembered = "";
          try {
            remembered =
              sessionStorage.getItem("pfd-player-club:" + user.id) || "";
          } catch {}
          const eligible = x.clubs.filter(
            (c) =>
              c.status === "active" &&
              x.teams.some(
                (t) =>
                  t.club_id === c.id &&
                  t.status === "active" &&
                  t.role_key === "player",
              ),
          );
          return (
            eligible.find((c) => c.id === previous)?.id ||
            eligible.find((c) => c.id === remembered)?.id ||
            eligible[0]?.id ||
            ""
          );
        });
        setError("");
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
  }, [revision, user.id]);
  useEffect(() => {
    setOptions(null);
    setStats(null);
    if (selected) {
      try {
        sessionStorage.setItem("pfd-player-club:" + user.id, selected);
      } catch {}
    }
  }, [selected, user.id]);
  useEffect(() => {
    if (!selected) return;
    let live = true;
    Promise.all([
      request<PlayerOptions>("options"),
      request<PlayerStats>("stats"),
    ])
      .then(([o, s]) => {
        if (!live) return;
        if (o.workspace_role !== "player" || o.self?.id !== user.id)
          throw Error(
            "Unable to verify your Player workspace. Please try again.",
          );
        setOptions(o);
        setStats(s);
        setError("");
      })
      .catch((e) => {
        if (live) {
          setOptions(null);
          setStats(null);
          setError(e.message);
        }
      });
    return () => {
      live = false;
    };
  }, [selected, request, revision, user.id]);
  useEffect(() => {
    const media = window.matchMedia("(max-width:900px)");
    const update = () => {
      setMobile(media.matches);
      if (!media.matches) drawer.current?.close();
    };
    update();
    media.addEventListener("change", update);
    const focused = () => refresh();
    window.addEventListener("focus", focused);
    return () => {
      media.removeEventListener("change", update);
      window.removeEventListener("focus", focused);
    };
  }, [refresh]);
  async function logout() {
    setBusy(true);
    try {
      const r = await getSupabase().auth.signOut({ scope: "local" });
      if (r.error) throw r.error;
      router.replace("/");
    } catch {
      setError("Unable to log out. Please try again.");
    } finally {
      setBusy(false);
    }
  }
  function navigate(key: string) {
    setSection(key);
    drawer.current?.close();
    window.scrollTo({ top: 0, behavior: "instant" });
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
            <span className="side-brand-tag">PLAYER</span>
          )}
        </div>
        <div className="club-switcher">
          <label
            htmlFor={inDrawer ? "player-mobile-club" : "player-desktop-club"}
          >
            YOUR CLUB
          </label>
          <select
            id={inDrawer ? "player-mobile-club" : "player-desktop-club"}
            value={selected}
            onChange={(e) => setSelected(e.target.value)}
            disabled={!clubs.length}
          >
            {!clubs.length && <option value="">No active player club</option>}
            {clubs.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <small>Your development. Every team you belong to.</small>
        </div>
        <nav className="owner-nav" aria-label="Player navigation">
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
                      development: "↗",
                      homework: "✓",
                      schedule: "▦",
                      teams: "⚑",
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
              <small>Player</small>
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
  const allowed = (keys: string[]) =>
    options?.permissions.some((p) => keys.includes(p));
  const chatOptions = options
    ? ({
        ...options,
        people: [],
        permissions: options.permissions.filter((p) => p === "chats.view"),
      } as ClubWorkspaceOptions)
    : null;
  const needed: Record<string, string[]> = {
    development: ["reports.view_own", "reports.self_assess"],
    homework: ["homework.view"],
    schedule: ["events.view"],
    teams: ["teams.view"],
    events: ["events.view"],
    library: ["library.view"],
    chats: ["chats.view"],
    announcements: ["announcements.view"],
  };
  return (
    <div
      className={
        "owner-shell club-shell player-shell" +
        (desktop ? "" : " sidebar-collapsed")
      }
    >
      <aside id="player-sidebar" className="owner-sidebar" hidden={!desktop}>
        <Sidebar />
      </aside>
      <dialog
        ref={drawer}
        id="player-mobile-sidebar"
        className="owner-drawer"
        aria-label="Player navigation"
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
            aria-controls={mobile ? "player-mobile-sidebar" : "player-sidebar"}
            onClick={() => {
              if (mobile) {
                if (drawer.current?.open) drawer.current.close();
                else {
                  drawer.current?.showModal();
                  setDrawerOpen(true);
                }
              } else setDesktop((x) => !x);
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
            <span>{current?.name || "Player workspace"}</span>
            <span>/</span>
            <strong>{active[1]}</strong>
          </div>
          <span className="topbar-avatar">{initials}</span>
        </header>
        <main className="owner-main">
          <div className="owner-page-heading">
            <div>
              <p className="eyebrow">PLAYER WORKSPACE</p>
              <h1>
                {section === "overview"
                  ? `Your next step, ${name.split(" ")[0]}.`
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
            <p role="status">Opening your Player workspace…</p>
          ) : section === "account" ? (
            <MemberAccount user={user} />
          ) : !current ? (
            <section className="owner-panel club-feature">
              <h2>Join your next team</h2>
              <p>
                Your team membership may have changed. Request access or ask
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
              <p role="status">Checking your player permissions…</p>
            )
          ) : needed[section] && !allowed(needed[section]) ? (
            <section className="owner-panel club-feature">
              <h2>This section isn’t enabled for your role.</h2>
              <p>Your club and PFD Owner manage role permissions.</p>
            </section>
          ) : section === "overview" ? (
            <>
              <section className="club-welcome owner-panel">
                <div>
                  <p className="eyebrow">KEEP MOVING FORWARD</p>
                  <h2>{current.name}</h2>
                  <p>
                    {options.teams.length} team
                    {options.teams.length === 1 ? "" : "s"} · {current.sport}
                  </p>
                  <small>
                    Your practice, feedback and progress in one place.
                  </small>
                </div>
              </section>
              <div className="player-priorities">
                <button
                  className="player-priority"
                  disabled={!allowed(["homework.view"])}
                  onClick={() => navigate("homework")}
                >
                  <span>YOUR NEXT PRACTICE</span>
                  <strong>Homework</strong>
                  <p>
                    {stats?.homework_due ?? "—"} assignments waiting for you
                  </p>
                  <small>Open your practice ↗</small>
                </button>
                <button
                  className="player-priority player-priority-light"
                  disabled={
                    !allowed(["reports.view_own", "reports.self_assess"])
                  }
                  onClick={() => navigate("development")}
                >
                  <span>YOUR DEVELOPMENT JOURNEY</span>
                  <strong>My Development</strong>
                  <p>
                    {stats?.reports ?? "—"} submitted reports in your record
                  </p>
                  <small>See your progress ↗</small>
                </button>
              </div>
              <div className="owner-stat-grid">
                {[
                  ["Your teams", options.teams.length],
                  ["Homework to complete", stats?.homework_due],
                  ["Upcoming sessions & events", stats?.upcoming],
                ].map(([title, value]) => (
                  <article className="owner-stat" key={title}>
                    <p>{title}</p>
                    <strong>{value ?? "—"}</strong>
                    <small>Your selected club</small>
                  </article>
                ))}
              </div>
              {allowed(["events.view"]) && (
                <section className="owner-panel club-feature">
                  <div className="club-card-top">
                    <h2>Coming up</h2>
                    <button
                      className="text-link"
                      onClick={() => navigate("schedule")}
                    >
                      Full schedule ↗
                    </button>
                  </div>
                  <PlayerCalendar request={request} options={options} compact />
                </section>
              )}
              {!!stats?.feedback.length && (
                <section className="owner-panel club-feature">
                  <h2>Latest feedback</h2>
                  <div className="club-cards">
                    {stats.feedback.map((f, i) => (
                      <article className="club-card" key={i}>
                        <h3>{f.title}</h3>
                        <Badge value={f.review_status} />
                        <p className="club-preserve">{f.feedback}</p>
                        <small>{dateLabel(f.updated_at, true)}</small>
                      </article>
                    ))}
                  </div>
                </section>
              )}
            </>
          ) : section === "development" ? (
            <PlayerDevelopment
              options={options}
              request={request}
              clubId={selected}
              onChanged={refresh}
            />
          ) : section === "homework" ? (
            <section className="owner-panel club-feature">
              <ActivityList
                request={request}
                tab="my_homework"
                canSubmit={allowed(["homework.submit"]) || false}
              />
            </section>
          ) : section === "schedule" || section === "events" ? (
            <section className="owner-panel club-feature">
              <PlayerCalendar
                key={section + selected}
                request={request}
                options={options}
                kind={section === "events" ? "event" : undefined}
                sessionsOnly={section === "schedule"}
              />
            </section>
          ) : section === "teams" ? (
            <PlayerTeams
              options={options}
              request={request}
              chatOptions={chatOptions!}
            />
          ) : section === "library" ? (
            <PlayerLibrary request={request} />
          ) : section === "chats" ? (
            <ChatPanel request={request} options={chatOptions!} />
          ) : section === "announcements" ? (
            <section className="owner-panel club-feature">
              <ActivityList
                request={request}
                tab="my_announcements"
                canSubmit={false}
              />
            </section>
          ) : null}
        </main>
      </div>
    </div>
  );
}
function PlayerDevelopment({
  options,
  request,
  clubId,
  onChanged,
}: {
  options: PlayerOptions;
  request: WorkspaceClient;
  clubId: string;
  onChanged: () => void;
}) {
  const [progress, setProgress] = useState<Report[]>([]);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const canView = options.permissions.includes("reports.view_own");
  useEffect(() => {
    if (!canView) return;
    let live = true;
    request<Report[]>("player_progress")
      .then((x) => {
        if (live) {
          setProgress(x);
          setError("");
        }
      })
      .catch((e) => {
        if (live) setError(e.message);
      });
    return () => {
      live = false;
    };
  }, [request, canView, revision]);
  const reportRequest = useMemo<WorkspaceClient>(
    () =>
      <T,>(action: string, payload: Record<string, unknown> = {}) =>
        !canView && action === "reports_list"
          ? Promise.resolve({ items: [], page: 1, total: 0 } as T)
          : request<T>(action, payload),
    [canView, request],
  );
  return (
    <>
      <section className="owner-panel club-feature">
        <h2>Your development over time</h2>
        <p>
          Coach reports are read-only. Self-assessments record your own
          perspective and are clearly marked in your record.
        </p>
        <ErrorNotice error={error} />
        {canView && (
          <ProgressChart reports={progress} subjectId={options.self.id} />
        )}
      </section>
      <ReportsManager
        options={options}
        request={reportRequest}
        ownerName={options.self.name}
        selfSubject={options.self}
        selfTemplates={options.self_templates}
        scopedClub={clubId}
        canCreate={options.permissions.includes("reports.self_assess")}
        onChanged={() => {
          setRevision((x) => x + 1);
          onChanged();
        }}
      />
    </>
  );
}
type CalendarItem = {
  id: string;
  title: string;
  kind: string;
  starts_at: string;
  ends_at: string;
  timezone: string;
  location: string;
  notes: string;
  status: string;
  response: string;
  team_name: string;
};
function PlayerCalendar({
  request,
  options,
  kind,
  sessionsOnly = false,
  compact = false,
}: {
  request: WorkspaceClient;
  options: PlayerOptions;
  kind?: string;
  sessionsOnly?: boolean;
  compact?: boolean;
}) {
  const [filters, setFilters] = useState({ page: 1, team_id: "", date: "" });
  const from = compact
    ? new Date().toISOString()
    : filters.date
      ? new Date(filters.date + "T00:00:00").toISOString()
      : "";
  const stableFrom = useMemo(
    () => (compact ? new Date().toISOString() : from),
    [compact, filters.date],
  );
  const list = useWorkspaceList<CalendarItem>(
    "my_calendar",
    {
      page: filters.page,
      team_id: filters.team_id,
      kind: kind || "",
      sessions_only: sessionsOnly,
      from_date: stableFrom,
    },
    request,
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function respond(item: CalendarItem, response: string) {
    setBusy(true);
    setError("");
    try {
      await request("player_event_response", { id: item.id, response });
      list.reload();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <>
      {!compact && (
        <div className="management-filters">
          <label>
            Team
            <select
              value={filters.team_id}
              onChange={(e) =>
                setFilters({ ...filters, team_id: e.target.value, page: 1 })
              }
            >
              <option value="">All my teams</option>
              {options.teams.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            From date
            <input
              type="date"
              value={filters.date}
              onChange={(e) =>
                setFilters({ ...filters, date: e.target.value, page: 1 })
              }
            />
          </label>
          <button className="owner-refresh" onClick={list.reload}>
            Refresh schedule
          </button>
        </div>
      )}
      <ErrorNotice error={error || list.error} />
      {list.loading ? (
        <p role="status">Loading your schedule…</p>
      ) : (
        <div className="club-cards">
          {(compact ? list.data.items.slice(0, 3) : list.data.items).map(
            (item) => (
              <article className="club-card" key={item.id}>
                <Badge value={item.status} />
                <small>
                  {item.kind === "game"
                    ? "Game"
                    : item.kind === "training"
                      ? "Training"
                      : "Club event"}{" "}
                  · {item.team_name || "Your invitation"}
                </small>
                <h3>{item.title}</h3>
                <strong>{dateLabel(item.starts_at, true)}</strong>
                <p>
                  Until{" "}
                  {new Date(item.ends_at).toLocaleTimeString([], {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}{" "}
                  · {item.location || "Location to be confirmed"}
                </p>
                <p className="club-preserve">{item.notes}</p>
                <p>
                  Your availability:{" "}
                  <strong>
                    {item.response === "attending"
                      ? "Attending"
                      : item.response === "declined"
                        ? "Unavailable"
                        : "Not confirmed"}
                  </strong>
                </p>
                <div className="club-actions">
                  <button onClick={() => calendarDownload(item)}>
                    Add to calendar
                  </button>
                  {item.status === "scheduled" &&
                    new Date(item.ends_at) > new Date() && (
                      <>
                        <button
                          disabled={busy || item.response === "attending"}
                          onClick={() => void respond(item, "attending")}
                        >
                          I’m attending
                        </button>
                        <button
                          disabled={busy || item.response === "declined"}
                          onClick={() => void respond(item, "declined")}
                        >
                          Unavailable
                        </button>
                      </>
                    )}
                </div>
              </article>
            ),
          )}
          {!list.data.items.length && (
            <p>
              No{" "}
              {compact
                ? "upcoming sessions or events"
                : kind === "event"
                  ? "invited events"
                  : "sessions"}{" "}
              to show yet.
            </p>
          )}
        </div>
      )}
      {!compact && (
        <Pagination
          page={filters.page}
          total={list.data.total}
          loading={list.loading}
          change={(page) => setFilters({ ...filters, page })}
        />
      )}
      <small>
        Times display in your device timezone. Calendar downloads use the
        event’s actual start and end times.
      </small>
    </>
  );
}
function PlayerTeams({
  options,
  request,
  chatOptions,
}: {
  options: PlayerOptions;
  request: WorkspaceClient;
  chatOptions: ClubWorkspaceOptions;
}) {
  const [team, setTeam] = useState("");
  return (
    <>
      <div className="club-cards">
        {options.teams.map((t) => (
          <article className="club-card" key={t.id}>
            <span className="eyebrow">APPROVED PLAYER</span>
            <h3>{t.name}</h3>
            <p>
              {t.age_group} · {t.season}
            </p>
            {options.permissions.includes("chats.view") && (
              <button
                className="button secondary"
                onClick={() => setTeam(t.id)}
              >
                Open team chat ↗
              </button>
            )}
          </article>
        ))}
      </div>
      {team && (
        <ChatPanel
          key={team}
          request={request}
          options={chatOptions}
          teamId={team}
          canOpenTeamChat
        />
      )}
      <section className="owner-panel club-feature">
        <h3>Another team in mind?</h3>
        <p>
          Use My Account to request access to additional clubs or teams. Club
          Admin approves membership.
        </p>
      </section>
    </>
  );
}
function PlayerLibrary({ request }: { request: WorkspaceClient }) {
  const [filters, setFilters] = useState({
    query: "",
    scope: "",
    difficulty: "",
    page: 1,
  });
  const list = useWorkspaceList<Resource>("resources_list", filters, request);
  const [viewing, setViewing] = useState<Resource | null>(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  async function file(resource: Resource, path: string) {
    setBusy(true);
    setError("");
    try {
      await openPrivateFile(() =>
        request<{ url: string }>("resource_file_access", {
          resource_id: resource.id,
          path,
        }),
      );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="owner-panel club-feature">
      <div className="management-filters">
        <label>
          Find individual practice
          <input
            type="search"
            placeholder="Search drills or skills"
            value={filters.query}
            onChange={(e) =>
              setFilters({ ...filters, query: e.target.value, page: 1 })
            }
          />
        </label>
        <label>
          Library level
          <select
            value={filters.scope}
            onChange={(e) =>
              setFilters({ ...filters, scope: e.target.value, page: 1 })
            }
          >
            <option value="">All available levels</option>
            <option value="global">Global / PFD shared</option>
            <option value="club">Club</option>
            <option value="team">My teams</option>
          </select>
        </label>
        <label>
          Difficulty
          <select
            value={filters.difficulty}
            onChange={(e) =>
              setFilters({ ...filters, difficulty: e.target.value, page: 1 })
            }
          >
            <option value="">Any difficulty</option>
            {["all", "beginner", "intermediate", "advanced"].map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
      </div>
      <ErrorNotice error={error || list.error} />
      {list.loading ? (
        <p role="status">Loading drills…</p>
      ) : (
        <div className="club-cards">
          {list.data.items.map((r) => (
            <article className="club-card" key={r.id}>
              <span className="eyebrow">
                {r.team_id ? "TEAM" : r.club_id ? "CLUB" : "PFD SHARED"}{" "}
                PRACTICE
              </span>
              <h3>{r.title}</h3>
              <p>
                {r.category || "Individual development"} · {r.duration_minutes}{" "}
                min
              </p>
              <p>{r.instructions.slice(0, 180)}</p>
              <button
                className="button secondary"
                onClick={() => setViewing(r)}
              >
                Open drill ↗
              </button>
            </article>
          ))}
          {!list.data.items.length && (
            <p>No published individual drills match your search yet.</p>
          )}
        </div>
      )}
      <Pagination
        page={filters.page}
        total={list.data.total}
        loading={list.loading}
        change={(page) => setFilters({ ...filters, page })}
      />
      {viewing && (
        <Modal
          title={viewing.title}
          close={() => setViewing(null)}
          busy={busy}
          wide
          eyebrow="INDIVIDUAL PRACTICE"
        >
          <p>
            {viewing.duration_minutes} min · {viewing.category}
          </p>
          <div className="management-prose">{viewing.instructions}</div>
          {/^https?:\/\//.test(viewing.video_url) && (
            <a
              className="text-link"
              href={viewing.video_url}
              target="_blank"
              rel="noopener noreferrer"
            >
              Watch drill video ↗
            </a>
          )}
          <div className="club-actions">
            {viewing.attachments.map((a) => (
              <button
                className="owner-refresh"
                disabled={busy}
                key={a.path}
                onClick={() => void file(viewing, a.path)}
              >
                Open {a.name} ↗
              </button>
            ))}
          </div>
          <ErrorNotice error={error} />
        </Modal>
      )}
    </section>
  );
}
