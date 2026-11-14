"use client";

import Link from "next/link";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import type { User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";
import { getSupabase } from "../../lib/supabase";
import ClubsManager from "./clubs-manager";
import RolesPermissions from "./roles-permissions";
import {
  UsersManager,
  RequestsManager,
  LibraryManager,
} from "./owner-management";
import ReportsManager from "./reports-manager";
import { workspaceRequest, type Options } from "../../lib/workspace-api";

type Section =
  | "overview"
  | "clubs"
  | "users"
  | "requests"
  | "reports"
  | "library"
  | "settings";
const sections: { id: Section; label: string; description: string }[] = [
  {
    id: "overview",
    label: "Overview",
    description: "Your platform at a glance.",
  },
  {
    id: "clubs",
    label: "Clubs",
    description: "Your clubs, their administrators and the teams inside them.",
  },
  {
    id: "users",
    label: "Users",
    description: "Accounts across Player Focused Development.",
  },
  {
    id: "requests",
    label: "Access Requests",
    description:
      "Review club administrator requests and oversee membership access.",
  },
  {
    id: "reports",
    label: "Reports",
    description: "Player development reports across your clubs and teams.",
  },
  {
    id: "library",
    label: "Development Library",
    description: "Shared resources to support purposeful player development.",
  },
  {
    id: "settings",
    label: "Settings",
    description: "Your account and platform preferences.",
  },
];
type Account = {
  id: string;
  email: string;
  name: string;
  createdAt: string;
  lastSignInAt: string | null;
  access: string;
};
type DashboardData = {
  totalAccounts: number;
  totalOwners: number;
  totalClubs: number;
  totalClubAdministrators: number;
  page: number;
  perPage: number;
  hasNext: boolean;
  users: Account[];
};

function Icon({ name }: { name: Section | "menu" | "logout" | "arrow" }) {
  const paths: Record<string, React.ReactNode> = {
    overview: (
      <>
        <rect x="3" y="3" width="7" height="7" rx="1" />
        <rect x="14" y="3" width="7" height="7" rx="1" />
        <rect x="3" y="14" width="7" height="7" rx="1" />
        <rect x="14" y="14" width="7" height="7" rx="1" />
      </>
    ),
    clubs: (
      <>
        <path d="M4 21V7l8-4 8 4v14M2 21h20M9 21v-5h6v5M8 9h1m6 0h1M8 12h1m6 0h1" />
      </>
    ),
    users: (
      <>
        <circle cx="9" cy="8" r="3" />
        <path d="M3 21v-3a6 6 0 0 1 12 0v3M16 5a3 3 0 0 1 0 6m2 4a5 5 0 0 1 3 4v2" />
      </>
    ),
    requests: (
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v5l3 2" />
      </>
    ),
    reports: (
      <>
        <path d="M14 3H5v18h14V8zM14 3v5h5M8 12h8M8 16h5" />
      </>
    ),
    library: (
      <>
        <path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1zM12 5v15" />
      </>
    ),
    settings: (
      <>
        <path d="M4 6h16M4 12h16M4 18h16" />
        <circle cx="8" cy="6" r="2" fill="currentColor" />
        <circle cx="16" cy="12" r="2" fill="currentColor" />
        <circle cx="10" cy="18" r="2" fill="currentColor" />
      </>
    ),
    menu: <path d="M4 6h16M4 12h16M4 18h16" />,
    logout: (
      <>
        <path d="M10 4H4v16h6M10 12h11m-4-4 4 4-4 4" />
      </>
    ),
    arrow: <path d="M5 12h14m-5-5 5 5-5 5" />,
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
function dateLabel(value: string | null) {
  if (!value) return "—";
  return new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(value));
}

export default function OwnerDashboard({ user }: { user: User }) {
  const router = useRouter();
  const [section, setSection] = useState<Section>("overview");
  const [desktopOpen, setDesktopOpen] = useState(true);
  const [mobile, setMobile] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const drawer = useRef<HTMLDialogElement>(null);
  const page = 1;
  const [data, setData] = useState<DashboardData | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const requestId = useRef(0);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [options, setOptions] = useState<Options | null>(null);
  const [workspaceError, setWorkspaceError] = useState("");
  const [templateFocus, setTemplateFocus] = useState<{
    key: string;
    preview: boolean;
  }>();
  const [reportFocus, setReportFocus] = useState<string>();
  const [stats, setStats] = useState<{
    coaches: number;
    players: number;
    reports: number;
    requests: number;
  } | null>(null);
  const loadWorkspace = useCallback(async () => {
    setWorkspaceError("");
    try {
      const [nextOptions, nextStats] = await Promise.all([
        workspaceRequest<Options>("options"),
        workspaceRequest<{
          coaches: number;
          players: number;
          reports: number;
          requests: number;
        }>("stats"),
      ]);
      setOptions({
        ...nextOptions,
        templates: [...nextOptions.templates].sort(
          (a, b) =>
            [
              "player",
              "fitness",
              "tactical",
              "parent",
              "coaches",
              "performance",
              "match_review",
              "gps",
            ].indexOf(a.key) -
            [
              "player",
              "fitness",
              "tactical",
              "parent",
              "coaches",
              "performance",
              "match_review",
              "gps",
            ].indexOf(b.key),
        ),
      });
      setStats(nextStats);
    } catch (e) {
      setWorkspaceError(
        e instanceof Error ? e.message : "Unable to load workspace.",
      );
    }
  }, []);
  useEffect(() => {
    void loadWorkspace();
  }, [loadWorkspace]);
  const [settingsTab, setSettingsTab] = useState<"profile" | "roles">(
    "profile",
  );
  const permissionsDirty = useRef(false);
  const trackPermissionChanges = useCallback((dirty: boolean) => {
    permissionsDirty.current = dirty;
  }, []);
  function canLeavePermissions() {
    return (
      !permissionsDirty.current ||
      window.confirm("Discard your unsaved permission changes?")
    );
  }
  const name =
    typeof user.user_metadata?.full_name === "string"
      ? user.user_metadata.full_name
      : "";
  const initials = (name || user.email || "PFD")
    .split(/\s+/)
    .slice(0, 2)
    .map((part: string) => part[0])
    .join("")
    .toUpperCase();
  const active = sections.find((item) => item.id === section)!;

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
        localStorage.getItem("pfd-owner-sidebar:" + user.id) !== "hidden",
      );
    } catch {}
    const readSection = () => {
      const hash = window.location.hash.slice(1);
      if (hash !== "settings" && !canLeavePermissions()) {
        window.history.replaceState(window.history.state, "", "#settings");
        return;
      }
      if (sections.some((item) => item.id === hash))
        setSection(hash as Section);
    };
    readSection();
    window.addEventListener("hashchange", readSection);
    return () => {
      query.removeEventListener("change", sync);
      window.removeEventListener("hashchange", readSection);
    };
  }, [user.id]);

  const load = useCallback(async () => {
    const current = ++requestId.current;
    setLoading(true);
    setLoadError("");
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);
    try {
      const result = await getSupabase().functions.invoke(
        "pfd-owner-dashboard",
        { body: { page }, signal: controller.signal },
      );
      if (result.error) {
        let message = "Unable to load accounts. Please try again.";
        if (result.error.context instanceof Response) {
          try {
            message = (await result.error.context.json()).error || message;
          } catch {}
        }
        throw new Error(message);
      }
      if (result.data?.error) throw new Error(result.data.error);
      if (current === requestId.current) setData(result.data as DashboardData);
    } catch (error) {
      if (current === requestId.current)
        setLoadError(
          error instanceof Error ? error.message : "Unable to load accounts.",
        );
    } finally {
      clearTimeout(timeout);
      if (current === requestId.current) setLoading(false);
    }
  }, [page]);
  useEffect(() => {
    void load();
    return () => {
      requestId.current++;
    };
  }, [load]);

  function navigate(next: Section) {
    if (next !== section && !canLeavePermissions()) return;
    setSection(next);
    setNotice("");
    setError("");
    window.history.replaceState(window.history.state, "", "#" + next);
    drawer.current?.close();
    setMobileOpen(false);
    window.scrollTo({ top: 0, behavior: "instant" });
  }
  function toggleSidebar() {
    if (mobile) {
      if (drawer.current?.open) {
        drawer.current.close();
      } else {
        drawer.current?.showModal();
        setMobileOpen(true);
      }
    } else {
      setDesktopOpen((open) => {
        const next = !open;
        try {
          localStorage.setItem(
            "pfd-owner-sidebar:" + user.id,
            next ? "open" : "hidden",
          );
        } catch {}
        return next;
      });
    }
  }
  async function logout() {
    if (!canLeavePermissions()) return;
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
    const fullName = String(
      new FormData(event.currentTarget).get("name") || "",
    ).trim();
    setBusy(true);
    setNotice("");
    setError("");
    try {
      if (!fullName || fullName.length > 150)
        throw new Error("Enter a name of 1 to 150 characters.");
      const { error } = await getSupabase().auth.updateUser({
        data: { full_name: fullName },
      });
      if (error) throw error;
      setNotice("Your details have been saved.");
    } catch (error) {
      setError(
        error instanceof Error ? error.message : "Unable to save your details.",
      );
    } finally {
      setBusy(false);
    }
  }
  function Sidebar({ inDrawer = false }: { inDrawer?: boolean }) {
    return (
      <div className="owner-side-content">
        <div className="owner-brand">
          <Link
            href="/"
            className="wordmark"
            aria-label="PFD home"
            onClick={(event) => {
              if (!canLeavePermissions()) event.preventDefault();
            }}
          >
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
            <span className="side-brand-tag">OWNER</span>
          )}
        </div>
        <p className="side-caption">PLATFORM</p>
        <nav
          className="owner-nav"
          aria-label={inDrawer ? "Mobile owner navigation" : "Owner navigation"}
        >
          {sections.map((item) => (
            <button
              key={item.id}
              onClick={() => navigate(item.id)}
              aria-current={section === item.id ? "page" : undefined}
            >
              <Icon name={item.id} />
              <span>{item.label}</span>
              {section === item.id && <span className="nav-active-dot" />}
            </button>
          ))}
        </nav>
        <div className="owner-side-bottom">
          <a className="owner-logout" href="/account/security/">Account security</a>
          <button className="side-user" onClick={() => navigate("settings")}>
            <span className="owner-avatar">{initials}</span>
            <span>
              <strong>{name || "Your account"}</strong>
              <small>PFD Owner</small>
            </span>
          </button>
          <button className="owner-logout" onClick={logout} disabled={busy}>
            <Icon name="logout" />
            {busy ? "Please wait…" : "Log out"}
          </button>
        </div>
      </div>
    );
  }
  function AccountsTable({ compact = false }: { compact?: boolean }) {
    const users = compact ? data?.users.slice(0, 5) : data?.users;
    return (
      <>
        {loading && !data ? (
          <p className="owner-loading" role="status">
            Loading accounts…
          </p>
        ) : users?.length ? (
          <div
            className="owner-table-scroll"
            tabIndex={0}
            aria-label="Account list"
          >
            <table className="owner-table">
              <thead>
                <tr>
                  <th>Name / email</th>
                  <th>Access</th>
                  <th>Joined</th>
                  {!compact && <th>Last sign-in</th>}
                </tr>
              </thead>
              <tbody>
                {users.map((account) => (
                  <tr key={account.id}>
                    <td>
                      <strong>{account.name || "Name not provided"}</strong>
                      <span>{account.email}</span>
                    </td>
                    <td>
                      <span
                        className={
                          account.access === "PFD Owner"
                            ? "access-badge owner-access"
                            : "access-badge"
                        }
                      >
                        {account.access}
                      </span>
                    </td>
                    <td>{dateLabel(account.createdAt)}</td>
                    {!compact && <td>{dateLabel(account.lastSignInAt)}</td>}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : !loadError ? (
          <p className="owner-loading">No accounts to display.</p>
        ) : null}
      </>
    );
  }

  return (
    <div className={"owner-shell" + (desktopOpen ? "" : " sidebar-collapsed")}>
      <aside
        id="owner-desktop-sidebar"
        className="owner-sidebar"
        hidden={!desktopOpen}
      >
        <Sidebar />
      </aside>
      <dialog
        ref={drawer}
        id="owner-mobile-sidebar"
        className="owner-drawer"
        aria-label="Owner navigation"
        onClose={() => setMobileOpen(false)}
        onClick={(event) => {
          if (event.target !== event.currentTarget) return;
          const rect = event.currentTarget.getBoundingClientRect();
          if (event.clientX > rect.right || event.clientX < rect.left)
            drawer.current?.close();
        }}
      >
        <Sidebar inDrawer />
      </dialog>
      <div className="owner-body">
        <header className="owner-topbar">
          <button
            className="sidebar-toggle"
            onClick={toggleSidebar}
            aria-label={
              (mobile ? mobileOpen : desktopOpen)
                ? "Hide navigation"
                : "Show navigation"
            }
            aria-expanded={mobile ? mobileOpen : desktopOpen}
            aria-controls={
              mobile ? "owner-mobile-sidebar" : "owner-desktop-sidebar"
            }
          >
            <Icon name="menu" />
          </button>
          <div className="owner-breadcrumb">
            <span>Owner workspace</span>
            <span aria-hidden="true">/</span>
            <strong>{active.label}</strong>
          </div>
          <span className="topbar-avatar" title={name || user.email}>
            {initials}
          </span>
        </header>
        <main id="dashboard-content" className="owner-main">
          <div className="owner-page-heading">
            <div>
              <p className="eyebrow">PFD OWNER</p>
              <h1>
                {section === "overview"
                  ? `Welcome back${name ? ", " + name.split(" ")[0] : ""}.`
                  : active.label}
              </h1>
              <p>{active.description}</p>
            </div>
            {section === "overview" && (
              <button
                className="owner-refresh"
                onClick={() => {
                  void load();
                  void loadWorkspace();
                }}
                disabled={loading}
              >
                {loading ? "Refreshing…" : "Refresh"}
              </button>
            )}
          </div>
          {error && (
            <p className="form-alert" role="alert">
              {error}
            </p>
          )}
          {notice && (
            <p className="form-success" role="status">
              {notice}
            </p>
          )}
          {section === "overview" && loadError && (
            <div className="form-alert" role="alert">
              {loadError}
              <button className="inline-retry" onClick={() => void load()}>
                Try again
              </button>
            </div>
          )}
          {section === "overview" && (
            <>
              <div className="owner-stat-grid">
                {[
                  ["Total accounts", data?.totalAccounts, "Registered on PFD"],
                  ["Clubs", data?.totalClubs, "Including archived clubs"],
                  ["Coaches", stats?.coaches, "Approved club coaches"],
                  ["Players", stats?.players, "Approved team players"],
                  [
                    "Reports generated",
                    stats?.reports,
                    "Submitted assessments",
                  ],
                  ["Pending requests", stats?.requests, "Awaiting approval"],
                ].map(([label, value, note]) => (
                  <article className="owner-stat" key={String(label)}>
                    <p>{label}</p>
                    <strong>{value ?? "—"}</strong>
                    <small>{note}</small>
                  </article>
                ))}
              </div>
              <p className="metrics-note">
                Club and development totals will appear as your clubs, teams and
                reports are added.
              </p>
              <div className="owner-overview-grid">
                <section className="owner-panel">
                  <div className="owner-panel-heading">
                    <h2>Accounts overview</h2>
                    <button onClick={() => navigate("users")}>
                      View all <span aria-hidden="true">↗</span>
                    </button>
                  </div>
                  <AccountsTable compact />
                </section>
                <section className="owner-panel workspace-shortcuts">
                  <p className="eyebrow">YOUR WORKSPACE</p>
                  <h2>
                    Build a clear path
                    <br />
                    for every player.
                  </h2>
                  <p>
                    Bring clubs, coaches and players together around purposeful
                    development.
                  </p>
                  <div>
                    {[
                      ["clubs", "Your clubs", "Teams and club administrators"],
                      [
                        "requests",
                        "Access requests",
                        "Keep membership organised",
                      ],
                      [
                        "library",
                        "Development library",
                        "Shared resources and templates",
                      ],
                    ].map(([id, title, description]) => (
                      <button key={id} onClick={() => navigate(id as Section)}>
                        <span>
                          <strong>{title}</strong>
                          <small>{description}</small>
                        </span>
                        <Icon name="arrow" />
                      </button>
                    ))}
                  </div>
                </section>
              </div>
            </>
          )}
          {section === "clubs" && (
            <ClubsManager
              onChanged={() => {
                void load();
                void loadWorkspace();
              }}
            />
          )}
          {["users", "requests", "reports", "library"].includes(section) &&
            workspaceError && (
              <div className="form-alert" role="alert">
                {workspaceError}
                <button
                  className="inline-retry"
                  onClick={() => void loadWorkspace()}
                >
                  Try again
                </button>
              </div>
            )}
          {["users", "requests", "reports", "library"].includes(section) &&
            !options &&
            !workspaceError && (
              <p className="owner-loading" role="status">
                Loading workspace…
              </p>
            )}
          {options && section === "users" && (
            <UsersManager
              options={options}
              openReport={(id) => {
                setTemplateFocus(undefined);
                setReportFocus(id);
                navigate("reports");
              }}
            />
          )}
          {options && section === "requests" && (
            <RequestsManager
              options={options}
              onChanged={() => {
                void load();
                void loadWorkspace();
              }}
            />
          )}
          {options && section === "reports" && (
            <ReportsManager
              options={options}
              ownerName={name || user.email || ""}
              initialReport={reportFocus}
              initialTemplate={templateFocus}
              onChanged={() => void loadWorkspace()}
            />
          )}
          {options && section === "library" && (
            <LibraryManager
              options={options}
              openTemplates={(key, preview = true) => {
                setTemplateFocus(key ? { key, preview } : undefined);
                setReportFocus(undefined);
                navigate("reports");
              }}
            />
          )}
          {section === "settings" && (
            <>
              <div
                className="settings-tabs"
                role="group"
                aria-label="Settings sections"
              >
                <button
                  type="button"
                  aria-pressed={settingsTab === "profile"}
                  onClick={() => {
                    if (settingsTab !== "profile" && canLeavePermissions())
                      setSettingsTab("profile");
                  }}
                >
                  My profile
                </button>
                <button
                  type="button"
                  aria-pressed={settingsTab === "roles"}
                  onClick={() => setSettingsTab("roles")}
                >
                  Roles &amp; Permissions
                </button>
              </div>
              {settingsTab === "roles" ? (
                <RolesPermissions onDirtyChange={trackPermissionChanges} />
              ) : (
                <div className="owner-settings-grid">
                  <section className="owner-panel owner-settings-card">
                    <p className="eyebrow">YOUR ACCOUNT</p>
                    <h2>Personal details</h2>
                    <form className="account-form" onSubmit={saveProfile}>
                      <label htmlFor="owner-name">
                        Full name
                        <input
                          id="owner-name"
                          name="name"
                          defaultValue={name}
                          required
                          maxLength={150}
                          autoComplete="name"
                          disabled={busy}
                        />
                      </label>
                      <label htmlFor="owner-email">
                        Email address
                        <input
                          id="owner-email"
                          type="email"
                          value={user.email || ""}
                          readOnly
                        />
                      </label>
                      <button className="button primary" disabled={busy}>
                        {busy ? "Saving…" : "Save changes"}
                      </button>
                    </form>
                  </section>
                  <section className="owner-panel owner-settings-card">
                    <p className="eyebrow">PLATFORM ACCESS</p>
                    <h2>PFD Owner</h2>
                    <p>
                      Your owner account has platform-wide access. Club
                      administrators manage only their assigned clubs.
                    </p>
                    <dl className="account-details">
                      <dt>Account</dt>
                      <dd>{user.email}</dd>
                      <dt>Role</dt>
                      <dd>
                        <span className="access-badge owner-access">
                          PFD Owner
                        </span>
                      </dd>
                    </dl>
                    <p className="settings-footnote">
                      Owner permissions are managed securely and cannot be
                      changed through your profile.
                    </p>
                  </section>
                </div>
              )}
            </>
          )}
        </main>
      </div>
    </div>
  );
}
