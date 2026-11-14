"use client";
import ClubWorkspacePanel from "./club-workspace-panels";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import {
  clubTeamRequest,
  type Candidate,
  type ClubTeam,
  type TeamList,
  type TeamMember,
  type TeamPage,
  type TeamPermissions,
} from "../../lib/club-teams";
import type { ShellClub } from "../../lib/club-shell";
import { dateLabel } from "../../lib/workspace-api";
import {
  Badge,
  Empty,
  ErrorNotice,
  Modal,
  Pagination,
} from "./workspace-controls";

type Tab = "overview" | "coaches" | "players" | "schedule" | "chat";
const noPermissions: TeamPermissions = {
  manage: false,
  members: false,
  coaches: false,
  players: false,
};
export default function ClubTeamsManager({
  club,
  onChanged,
}: {
  club: ShellClub;
  onChanged: () => void;
}) {
  const [query, setQuery] = useState("");
  const [filters, setFilters] = useState({
    query: "",
    status: "active",
    season: "",
    page: 1,
  });
  const [list, setList] = useState<TeamList>({
    items: [],
    total: 0,
    page: 1,
    permissions: noPermissions,
    seasons: [],
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [revision, setRevision] = useState(0);
  const [team, setTeam] = useState<ClubTeam | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [opening, setOpening] = useState(false);
  const [editing, setEditing] = useState<ClubTeam | "new" | null>(null);
  const [confirmStatus, setConfirmStatus] = useState(false);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState("");
  const detailRevision = useRef(0);
  useEffect(() => {
    const timer = setTimeout(
      () => setFilters((f) => ({ ...f, query, page: 1 })),
      250,
    );
    return () => clearTimeout(timer);
  }, [query]);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    clubTeamRequest<TeamList>(club.id, "list", filters)
      .then((d) => {
        if (active) setList(d);
      })
      .catch((e) => {
        if (active) {
          setError(e.message);
          setList({
            items: [],
            total: 0,
            page: 1,
            permissions: noPermissions,
            seasons: [],
          });
          setTeam(null);
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [club.id, filters, revision]);
  useEffect(
    () => () => {
      detailRevision.current++;
    },
    [],
  );
  const loadDetail = useCallback(
    async (id: string, first = false) => {
      const current = ++detailRevision.current;
      if (first) setOpening(true);
      setError("");
      try {
        const d = await clubTeamRequest<ClubTeam>(club.id, "get", {
          team_id: id,
        });
        if (current === detailRevision.current) setTeam(d);
      } catch (e) {
        if (current === detailRevision.current) {
          setTeam(null);
          setError(e instanceof Error ? e.message : "Unable to open team.");
        }
      } finally {
        if (current === detailRevision.current) setOpening(false);
      }
    },
    [club.id],
  );
  function refresh() {
    setRevision((r) => r + 1);
    onChanged();
  }
  function open(t: ClubTeam) {
    setTab("overview");
    setNotice("");
    void loadDetail(t.id, true);
  }
  function back() {
    detailRevision.current++;
    setTeam(null);
    setNotice("");
    setError("");
    setOpening(false);
  }
  async function status() {
    if (!team || busy) return;
    setBusy(true);
    setActionError("");
    try {
      const result = await clubTeamRequest<ClubTeam>(club.id, "set_status", {
        team_id: team.id,
        updated_at: team.updated_at,
        status: team.status === "active" ? "archived" : "active",
      });
      setTeam((current) => current && { ...current, ...result });
      setConfirmStatus(false);
      setNotice(
        result.status === "archived"
          ? "Team archived. Memberships and historical records are retained."
          : "Team restored.",
      );
      refresh();
    } catch (e) {
      setActionError(
        e instanceof Error ? e.message : "Unable to update team status.",
      );
    } finally {
      setBusy(false);
    }
  }
  const permissions = team?.permissions || list.permissions;
  return (
    <div className="management-section">
      <ErrorNotice
        error={error}
        retry={() => {
          setRevision((r) => r + 1);
          if (team) void loadDetail(team.id);
        }}
      />
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      {opening && (
        <p className="owner-loading" role="status">
          Opening team…
        </p>
      )}
      {!team ? (
        <>
          <div className="management-toolbar">
            <div>
              <h2>Your teams. Their next step.</h2>
              <p>Create the team structure for {club.name}.</p>
            </div>
            <button
              className="button primary"
              disabled={loading || !list.permissions.manage}
              onClick={() => {
                setEditing("new");
                setActionError("");
              }}
            >
              Create team
            </button>
          </div>
          <div className="management-filters">
            <label>
              Search teams
              <input
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Name, age group or season"
              />
            </label>
            <label>
              Status
              <select
                value={filters.status}
                onChange={(e) =>
                  setFilters((f) => ({ ...f, status: e.target.value, page: 1 }))
                }
              >
                <option value="active">Active teams</option>
                <option value="archived">Archived teams</option>
                <option value="all">All teams</option>
              </select>
            </label>
            <label>
              Season
              <select
                value={filters.season}
                onChange={(e) =>
                  setFilters((f) => ({ ...f, season: e.target.value, page: 1 }))
                }
              >
                <option value="">All seasons</option>
                {list.seasons.map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </select>
            </label>
          </div>
          {loading ? (
            <p className="owner-loading" role="status">
              Loading teams…
            </p>
          ) : list.items.length ? (
            <div className="club-team-grid">
              {list.items.map((t) => (
                <article className="owner-panel club-team-card" key={t.id}>
                  <div className="club-team-card-head">
                    <span className="team-age-badge">
                      {t.age_group || "Age group needed"}
                    </span>
                    <Badge value={t.status} />
                  </div>
                  <h3>{t.name}</h3>
                  <p>Season {t.season || "not set"}</p>
                  <div className="club-team-counts">
                    <span>
                      <strong>{t.coach_count}</strong> coaches
                    </span>
                    <span>
                      <strong>{t.player_count}</strong> players
                    </span>
                  </div>
                  <button
                    className="management-link"
                    disabled={opening}
                    onClick={() => open(t)}
                  >
                    Open team ↗
                  </button>
                </article>
              ))}
            </div>
          ) : (
            !error && (
              <section className="owner-panel">
                <Empty
                  title={
                    filters.query ||
                    filters.status !== "active" ||
                    filters.season
                      ? "No matching teams."
                      : "Every team starts here."
                  }
                  text={
                    list.permissions.manage
                      ? "Create a team, then add its coaches and players."
                      : "No teams to display. The PFD Owner controls team-management permissions."
                  }
                />
              </section>
            )
          )}
          <Pagination
            page={filters.page}
            total={list.total}
            loading={loading}
            change={(page) => setFilters((f) => ({ ...f, page }))}
          />
        </>
      ) : (
        <>
          <div className="management-toolbar">
            <button className="management-link" onClick={back}>
              ← All teams
            </button>
            <div className="management-actions">
              <button
                className="owner-refresh"
                onClick={() => void loadDetail(team.id)}
                disabled={opening}
              >
                Refresh team
              </button>
              {permissions.manage && (
                <>
                  <button
                    className="owner-refresh"
                    onClick={() => setEditing(team)}
                  >
                    Edit team
                  </button>
                  <button
                    className="owner-refresh"
                    onClick={() => {
                      setConfirmStatus(true);
                      setActionError("");
                    }}
                  >
                    {team.status === "active" ? "Archive team" : "Restore team"}
                  </button>
                </>
              )}
            </div>
          </div>
          <section className="owner-panel team-detail-heading">
            <div>
              <p className="eyebrow">{club.name}</p>
              <h2>{team.name}</h2>
              <p>
                {team.age_group} · Season {team.season}
              </p>
            </div>
            <Badge value={team.status} />
          </section>
          {team.status === "archived" && (
            <p className="permission-note">
              This team is archived. Its members and records are retained;
              restore it before changing membership.
            </p>
          )}
          <div
            className="settings-tabs team-detail-tabs"
            role="group"
            aria-label="Team sections"
          >
            {(
              [
                ["overview", "Overview"],
                ["coaches", "Coaches"],
                ["players", "Players"],
                ["schedule", "Team Schedule"],
                ["chat", "Team Chat"],
              ] as [Tab, string][]
            ).map(([id, label]) => (
              <button
                key={id}
                aria-pressed={tab === id}
                onClick={() => setTab(id)}
              >
                {label}
              </button>
            ))}
          </div>
          {tab === "overview" ? (
            <div className="team-overview-grid">
              <section className="owner-panel team-information">
                <h3>Team details</h3>
                <dl className="management-details">
                  <div>
                    <dt>Age group</dt>
                    <dd>{team.age_group}</dd>
                  </div>
                  <div>
                    <dt>Season</dt>
                    <dd>{team.season}</dd>
                  </div>
                  <div>
                    <dt>Coaches</dt>
                    <dd>{team.coach_count}</dd>
                  </div>
                  <div>
                    <dt>Players</dt>
                    <dd>{team.player_count}</dd>
                  </div>
                  <div>
                    <dt>Created</dt>
                    <dd>{dateLabel(team.created_at)}</dd>
                  </div>
                  <div>
                    <dt>Status</dt>
                    <dd>{team.status}</dd>
                  </div>
                </dl>
                <p className="management-prose">
                  {team.description || "No team notes added."}
                </p>
              </section>
              <section className="owner-panel team-information">
                <p className="eyebrow">BUILD YOUR TEAM</p>
                <h3>The right support for every player.</h3>
                <p className="management-muted">
                  Assign approved club members as coaches and players. One
                  account can belong to more than one team.
                </p>
                <div className="management-actions">
                  <button
                    className="owner-refresh"
                    onClick={() => setTab("coaches")}
                  >
                    View coaches ↗
                  </button>
                  <button
                    className="owner-refresh"
                    onClick={() => setTab("players")}
                  >
                    View players ↗
                  </button>
                </div>
              </section>
            </div>
          ) : tab === "coaches" || tab === "players" ? (
            <TeamRoster
              key={team.id + tab}
              clubId={club.id}
              team={team}
              role={tab === "coaches" ? "coach" : "player"}
              permissions={permissions}
              onChanged={() => {
                void loadDetail(team.id);
                refresh();
              }}
            />
          ) : (
            <ClubWorkspacePanel
              key={team.id + tab}
              clubId={club.id}
              section={tab === "schedule" ? "schedule" : "chats"}
              teamId={team.id}
              name="Club administrator"
              onChanged={onChanged}
            />
          )}
        </>
      )}
      {editing && (
        <TeamForm
          key={editing === "new" ? "new" : editing.id}
          clubId={club.id}
          team={editing === "new" ? null : editing}
          close={() => setEditing(null)}
          saved={(result) => {
            setEditing(null);
            setNotice(
              editing === "new"
                ? "Team created. You can now add coaches and players."
                : "Team details saved.",
            );
            setTab("overview");
            void loadDetail(result.id);
            refresh();
          }}
        />
      )}
      {confirmStatus && team && (
        <Modal
          title={team.status === "active" ? "Archive team" : "Restore team"}
          eyebrow="CLUB ADMINISTRATOR"
          close={() => setConfirmStatus(false)}
          busy={busy}
        >
          <p className="management-muted">
            {team.status === "active"
              ? `Archive ${team.name}? This keeps its memberships and historical records, while removing it from active team lists.`
              : `Restore ${team.name}? Its existing memberships will become active with the team again.`}
          </p>
          <ErrorNotice error={actionError} />
          <div className="management-actions">
            <button
              className="owner-refresh"
              disabled={busy}
              onClick={() => setConfirmStatus(false)}
            >
              Cancel
            </button>
            <button
              className="button primary"
              disabled={busy}
              onClick={() => void status()}
            >
              {busy
                ? "Saving…"
                : team.status === "active"
                  ? "Archive team"
                  : "Restore team"}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
function TeamForm({
  clubId,
  team,
  close,
  saved,
}: {
  clubId: string;
  team: ClubTeam | null;
  close: () => void;
  saved: (team: ClubTeam) => void;
}) {
  const id = useRef(team?.id || crypto.randomUUID());
  const [name, setName] = useState(team?.name || "");
  const [age, setAge] = useState(team?.age_group || "");
  const [season, setSeason] = useState(
    team?.season || String(new Date().getFullYear()),
  );
  const [description, setDescription] = useState(team?.description || "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const dirty =
    name !== (team?.name || "") ||
    age !== (team?.age_group || "") ||
    description !== (team?.description || "") ||
    season !== (team?.season || String(new Date().getFullYear()));
  useEffect(() => {
    if (!dirty) return;
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);
  function leave() {
    if (!dirty || window.confirm("Discard unsaved team details?")) close();
  }
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      const result = await clubTeamRequest<ClubTeam>(
        clubId,
        team ? "update" : "create",
        {
          id: id.current,
          team_id: team?.id,
          name: name.trim(),
          age_group: age.trim(),
          season: season.trim(),
          description: description.trim(),
          updated_at: team?.updated_at,
        },
      );
      saved(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unable to save team.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title={team ? "Edit team" : "Create team"}
      eyebrow="CLUB ADMINISTRATOR"
      close={leave}
      busy={busy}
    >
      <form className="management-form" onSubmit={submit}>
        <label>
          Team name *
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
            maxLength={120}
            disabled={busy}
            placeholder="e.g. U14 Development"
          />
        </label>
        <div className="management-form-grid">
          <label>
            Age group *
            <input
              value={age}
              onChange={(e) => setAge(e.target.value)}
              required
              maxLength={80}
              disabled={busy}
              placeholder="e.g. U14 or Seniors"
            />
          </label>
          <label>
            Season *
            <input
              value={season}
              onChange={(e) => setSeason(e.target.value)}
              required
              maxLength={40}
              disabled={busy}
              placeholder="e.g. 2026"
            />
          </label>
        </div>
        <label>
          Team notes (optional)
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            maxLength={2000}
            disabled={busy}
          />
        </label>
        <p className="management-footnote">
          This team belongs to the selected club. Coaches, players, schedules
          and chat stay linked to this team.
        </p>
        <ErrorNotice error={error} />
        <div className="management-actions">
          <button
            className="owner-refresh"
            type="button"
            disabled={busy}
            onClick={leave}
          >
            Cancel
          </button>
          <button className="button primary" disabled={busy}>
            {busy ? "Saving…" : team ? "Save team" : "Create team"}
          </button>
        </div>
      </form>
    </Modal>
  );
}
function TeamRoster({
  clubId,
  team,
  role,
  permissions,
  onChanged,
}: {
  clubId: string;
  team: ClubTeam;
  role: "coach" | "player";
  permissions: TeamPermissions;
  onChanged: () => void;
}) {
  const [query, setQuery] = useState("");
  const [filters, setFilters] = useState({ query: "", page: 1 });
  const [data, setData] = useState<TeamPage<TeamMember>>({
    items: [],
    total: 0,
    page: 1,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState<TeamMember | null>(null);
  const [busy, setBusy] = useState(false);
  const [removeError, setRemoveError] = useState("");
  const [notice, setNotice] = useState("");
  const canChange =
    permissions.members &&
    (role === "coach" ? permissions.coaches : permissions.players) &&
    team.status === "active";
  useEffect(() => {
    const t = setTimeout(
      () => setFilters((f) => ({ ...f, query, page: 1 })),
      250,
    );
    return () => clearTimeout(t);
  }, [query]);
  useEffect(() => {
    if (!permissions.members) {
      setLoading(false);
      return;
    }
    let active = true;
    setLoading(true);
    setError("");
    clubTeamRequest<TeamPage<TeamMember>>(clubId, "members", {
      ...filters,
      team_id: team.id,
      role_key: role,
    })
      .then((r) => {
        if (active) setData(r);
      })
      .catch((e) => {
        if (active) {
          setError(e.message);
          setData({ items: [], total: 0, page: 1 });
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [clubId, team.id, role, permissions.members, filters, revision]);
  function changed() {
    setRevision((r) => r + 1);
    onChanged();
  }
  async function remove() {
    if (!removing || busy) return;
    setBusy(true);
    setRemoveError("");
    try {
      await clubTeamRequest(clubId, "remove_member", {
        team_id: team.id,
        user_id: removing.user_id,
        role_key: role,
        created_at: removing.created_at,
      });
      setRemoving(null);
      setNotice(
        `${role === "coach" ? "Coach" : "Player"} removed from this team. Their account and other memberships are unchanged.`,
      );
      changed();
    } catch (e) {
      setRemoveError(
        e instanceof Error ? e.message : "Unable to remove membership.",
      );
    } finally {
      setBusy(false);
    }
  }
  if (!permissions.members)
    return (
      <section className="owner-panel">
        <Empty
          title="Member directory access is not enabled."
          text="The PFD Owner controls this role permission."
        />
      </section>
    );
  return (
    <div className="management-section">
      <div className="management-toolbar">
        <div>
          <h2>{role === "coach" ? "Team coaches" : "Team players"}</h2>
          <p>
            {data.total} {role}
            {data.total === 1 ? "" : "s"} in {team.name}.
          </p>
        </div>
        <button
          className="button primary"
          disabled={!canChange}
          onClick={() => setAdding(true)}
        >
          Add {role}
        </button>
      </div>
      <div className="management-filters">
        <label>
          Find a {role}
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Name or email"
          />
        </label>
      </div>
      <ErrorNotice error={error} retry={() => setRevision((r) => r + 1)} />
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      <section className="owner-panel">
        {loading ? (
          <p className="owner-loading" role="status">
            Loading {role}s…
          </p>
        ) : data.items.length ? (
          <div
            className="owner-table-scroll"
            tabIndex={0}
            aria-label={role === "coach" ? "Team coaches" : "Team players"}
          >
            <table className="owner-table">
              <thead>
                <tr>
                  <th>Name / email</th>
                  <th>Added</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {data.items.map((m) => (
                  <tr key={m.user_id}>
                    <td>
                      <strong>{m.name || "Name not provided"}</strong>
                      <span>{m.email}</span>
                    </td>
                    <td>{dateLabel(m.created_at)}</td>
                    <td>
                      {canChange && (
                        <button
                          className="management-link"
                          onClick={() => {
                            setRemoving(m);
                            setRemoveError("");
                          }}
                        >
                          Remove from team
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          !error && (
            <Empty
              title={`No ${role}s added yet.`}
              text={`Add an approved club member as a ${role} for this team.`}
            />
          )
        )}
        <Pagination
          page={filters.page}
          total={data.total}
          loading={loading}
          change={(page) => setFilters((f) => ({ ...f, page }))}
        />
      </section>
      {adding && (
        <MemberPicker
          clubId={clubId}
          team={team}
          role={role}
          close={() => setAdding(false)}
          added={() => {
            setAdding(false);
            setNotice(
              `${role === "coach" ? "Coach" : "Player"} added to this team.`,
            );
            changed();
          }}
        />
      )}
      {removing && (
        <Modal
          title={`Remove ${role} from team`}
          eyebrow="CLUB ADMINISTRATOR"
          close={() => setRemoving(null)}
          busy={busy}
        >
          <p className="management-muted">
            Remove {removing.name || removing.email} as a {role} from{" "}
            {team.name}? This does not delete their account, reports or other
            team memberships.
          </p>
          <ErrorNotice error={removeError} />
          <div className="management-actions">
            <button
              className="owner-refresh"
              disabled={busy}
              onClick={() => setRemoving(null)}
            >
              Cancel
            </button>
            <button
              className="management-danger"
              disabled={busy}
              onClick={() => void remove()}
            >
              {busy ? "Removing…" : "Remove from team"}
            </button>
          </div>
        </Modal>
      )}
    </div>
  );
}
function MemberPicker({
  clubId,
  team,
  role,
  close,
  added,
}: {
  clubId: string;
  team: ClubTeam;
  role: "coach" | "player";
  close: () => void;
  added: () => void;
}) {
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState({ query: "", page: 1 });
  const [data, setData] = useState<TeamPage<Candidate>>({
    items: [],
    total: 0,
    page: 1,
  });
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [selected, setSelected] = useState<Candidate | null>(null);
  useEffect(() => {
    const t = setTimeout(() => setSearch({ query, page: 1 }), 250);
    return () => clearTimeout(t);
  }, [query]);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    setSelected(null);
    clubTeamRequest<TeamPage<Candidate>>(clubId, "candidates", {
      ...search,
      team_id: team.id,
      role_key: role,
    })
      .then((r) => {
        if (active) setData(r);
      })
      .catch((e) => {
        if (active) {
          setError(e.message);
          setData({ items: [], total: 0, page: 1 });
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [clubId, team.id, role, search]);
  async function add() {
    if (!selected || busy) return;
    setBusy(true);
    setError("");
    try {
      await clubTeamRequest(clubId, "add_member", {
        team_id: team.id,
        user_id: selected.id,
        role_key: role,
      });
      added();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unable to add member.");
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title={`Add ${role} to ${team.name}`}
      eyebrow="CLUB ADMINISTRATOR"
      close={close}
      busy={busy}
    >
      <div className="management-stack">
        <label className="management-label">
          Search approved club members
          <input
            className="team-picker-input"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            disabled={busy}
            placeholder="Name or email within this club"
          />
        </label>
        <p className="permission-note">
          Only approved members of this club can be assigned to a team. Approve
          new people in Access Requests first.
        </p>
        <ErrorNotice error={error} />
        {loading ? (
          <p role="status">Loading club members…</p>
        ) : data.items.length ? (
          <div
            className="team-candidate-list"
            role="radiogroup"
            aria-label={`Choose a ${role}`}
          >
            {data.items.map((p) => (
              <label key={p.id}>
                <input
                  type="radio"
                  name="team-member"
                  checked={selected?.id === p.id}
                  disabled={busy}
                  onChange={() => setSelected(p)}
                />
                <span>
                  <strong>{p.name || "Name not provided"}</strong>
                  <small>{p.email}</small>
                </span>
              </label>
            ))}
          </div>
        ) : (
          !error && (
            <p className="management-muted">
              No matching approved club members. They may already have this team
              role or need club approval first.
            </p>
          )
        )}
        <Pagination
          page={search.page}
          total={data.total}
          loading={loading || busy}
          change={(page) => setSearch((s) => ({ ...s, page }))}
        />
        <div className="management-actions">
          <button className="owner-refresh" disabled={busy} onClick={close}>
            Cancel
          </button>
          <button
            className="button primary"
            disabled={!selected || busy || loading}
            onClick={() => void add()}
          >
            {busy ? "Adding…" : `Add ${role}`}
          </button>
        </div>
      </div>
    </Modal>
  );
}
