"use client";
import ClubActivity from "./club-activity";
import { useEffect, useRef, useState, type FormEvent } from "react";
import {
  membershipRequest,
  accessLabel,
  type ClubChoice,
  type MyAccess,
  type TeamChoice,
  type JoinRequest,
} from "../../lib/memberships";
import type { TeamPage } from "../../lib/club-teams";
import { dateLabel } from "../../lib/workspace-api";
import { Badge, ErrorNotice, Modal, Pagination } from "./workspace-controls";
export default function MembershipJourney() {
  const loaded = useRef(false);
  const [access, setAccess] = useState<MyAccess | null>(null);
  const [clubs, setClubs] = useState<TeamPage<ClubChoice>>({
    items: [],
    total: 0,
    page: 1,
  });
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState({ query: "", page: 1 });
  const [revision, setRevision] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [selectedClub, setSelectedClub] = useState("");
  const [teams, setTeams] = useState<TeamChoice[]>([]);
  const [teamsLoading, setTeamsLoading] = useState(false);
  const [teamsError, setTeamsError] = useState("");
  const [teamId, setTeamId] = useState("");
  const [role, setRole] = useState("player");
  const [request, setRequest] = useState<
    { club: ClubChoice } | { team: TeamChoice } | null
  >(null);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [saveError, setSaveError] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setFilter({ query, page: 1 }), 250);
    return () => clearTimeout(timer);
  }, [query]);
  useEffect(() => {
    let active = true;
    if (!loaded.current) setLoading(true);
    setError("");
    Promise.all([
      membershipRequest<MyAccess>("my_access"),
      membershipRequest<TeamPage<ClubChoice>>("browse_clubs", filter),
    ])
      .then(([mine, browse]) => {
        if (!active) return;
        loaded.current = true;
        setAccess(mine);
        setClubs(browse);
        setSelectedClub((current) =>
          mine.clubs.some((c) => c.id === current && c.status === "active")
            ? current
            : mine.clubs.find((c) => c.status === "active")?.id || "",
        );
      })
      .catch((e) => {
        if (active) {
          setError(e.message);
          setAccess(null);
          setClubs({ items: [], total: 0, page: 1 });
        }
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [filter, revision]);
  useEffect(() => {
    const refresh = () => setRevision((r) => r + 1);
    window.addEventListener("focus", refresh);
    return () => window.removeEventListener("focus", refresh);
  }, []);
  useEffect(() => {
    setTeamId("");
    setTeams([]);
    setTeamsError("");
    if (!selectedClub) return;
    let active = true;
    setTeamsLoading(true);
    membershipRequest<TeamChoice[]>("club_teams", { club_id: selectedClub })
      .then((r) => {
        if (active) setTeams(r);
      })
      .catch((e) => {
        if (active) setTeamsError(e.message);
      })
      .finally(() => {
        if (active) setTeamsLoading(false);
      });
    return () => {
      active = false;
    };
  }, [selectedClub, revision]);
  const activeClubs = access?.clubs.filter((c) => c.status === "active") || [];
  const selectedTeam = teams.find((t) => t.id === teamId);
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!request || busy) return;
    setBusy(true);
    setSaveError("");
    try {
      await membershipRequest(
        "club" in request ? "request_club" : "request_team",
        {
          club_id: "club" in request ? request.club.id : selectedClub,
          ...("team" in request
            ? { team_id: request.team.id, role_key: role }
            : {}),
          message,
        },
      );
      setRequest(null);
      setNotice(
        "Request sent. Your club will review it; no access is granted until approval.",
      );
      setRevision((r) => r + 1);
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Unable to send request.");
    } finally {
      setBusy(false);
    }
  }
  function begin(next: typeof request) {
    setRequest(next);
    setMessage("");
    setSaveError("");
  }
  return (
    <div className="management-section membership-journey">
      <div className="membership-steps" aria-label="Joining steps">
        <span className={activeClubs.length ? "step-complete" : "step-current"}>
          1. Select a club
        </span>
        <span
          className={
            activeClubs.length
              ? "step-complete"
              : access?.requests.some(
                    (r) => r.role_key === "member" && r.status === "pending",
                  )
                ? "step-current"
                : ""
          }
        >
          2. Club approval
        </span>
        <span className={activeClubs.length ? "step-current" : ""}>
          3. Join your teams
        </span>
      </div>
      <div className="management-toolbar">
        <div>
          <h2>
            {activeClubs.length ? "Your clubs and teams." : "Choose your club."}
          </h2>
          <p className="management-muted">
            Request club access first. Once approved, request a team or ask the
            club to assign you.
          </p>
        </div>
        <button
          className="owner-refresh"
          disabled={loading}
          onClick={() => setRevision((r) => r + 1)}
        >
          {loading ? "Refreshing…" : "Refresh access"}
        </button>
      </div>
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      <ErrorNotice error={error} retry={() => setRevision((r) => r + 1)} />
      {loading && !access ? (
        <p role="status">Loading clubs and requests…</p>
      ) : (
        access && (
          <>
            <section className="owner-panel membership-panel">
              <h3>Find a club</h3>
              <label className="management-label">
                Search clubs
                <input
                  className="team-picker-input"
                  type="search"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  placeholder="Club name, city or sport"
                />
              </label>
              <div className="membership-club-list">
                {clubs.items.map((c) => (
                  <article className="management-list-card" key={c.id}>
                    <div>
                      <strong>{c.name}</strong>
                      <p>
                        {[c.sport, c.league, c.city, c.state, c.country]
                          .filter(Boolean)
                          .join(" · ")}
                      </p>
                    </div>
                    {c.joined ? (
                      <Badge value="approved" />
                    ) : c.pending ? (
                      <Badge value="pending" />
                    ) : (
                      <button
                        className="owner-refresh"
                        onClick={() => begin({ club: c })}
                      >
                        Request access
                      </button>
                    )}
                  </article>
                ))}
              </div>
              {!clubs.items.length && (
                <p className="management-muted">No matching active clubs.</p>
              )}
              <Pagination
                page={filter.page}
                total={clubs.total}
                loading={loading}
                change={(page) => setFilter((f) => ({ ...f, page }))}
              />
            </section>
            {activeClubs.length > 0 && (
              <section className="owner-panel membership-panel">
                <p className="eyebrow">CLUB APPROVED</p>
                <h3>Request a team</h3>
                <div className="management-form-grid management-form">
                  <label>
                    Your club
                    <select
                      value={selectedClub}
                      onChange={(e) => setSelectedClub(e.target.value)}
                    >
                      {activeClubs.map((c) => (
                        <option key={c.id} value={c.id}>
                          {c.name}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Team
                    <select
                      value={teamId}
                      disabled={teamsLoading || !teams.length}
                      onChange={(e) => setTeamId(e.target.value)}
                    >
                      <option value="">
                        {teamsLoading ? "Loading teams…" : "Select a team"}
                      </option>
                      {teams.map((t) => (
                        <option key={t.id} value={t.id}>
                          {t.name} · {t.age_group} · {t.season}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    Requested team role
                    <select
                      value={role}
                      onChange={(e) => setRole(e.target.value)}
                    >
                      <option value="player">Player</option>
                      <option value="coach">Coach</option>
                    </select>
                  </label>
                </div>
                <ErrorNotice error={teamsError} />
                {!teamsLoading && !teams.length && !teamsError && (
                  <p className="management-muted">
                    No active teams in this club yet. Your club can assign you
                    after creating them.
                  </p>
                )}
                <div className="management-actions">
                  <button
                    className="button primary"
                    disabled={
                      !selectedTeam ||
                      selectedTeam.roles.includes(role) ||
                      selectedTeam.pending_roles.includes(role) ||
                      teamsLoading
                    }
                    onClick={() =>
                      selectedTeam && begin({ team: selectedTeam })
                    }
                  >
                    {selectedTeam?.roles.includes(role)
                      ? "Already a member"
                      : selectedTeam?.pending_roles.includes(role)
                        ? "Request pending"
                        : "Request team access"}
                  </button>
                </div>
                <p className="management-footnote">
                  The club can also assign your coach/player role directly. You
                  can belong to multiple teams.
                </p>
              </section>
            )}
            {access.teams.length > 0 && (
              <section className="owner-panel membership-panel">
                <h3>Your team memberships</h3>
                <div className="management-stack">
                  {access.teams.map((t) => (
                    <article
                      className="management-list-card"
                      key={t.id + t.role_key}
                    >
                      <div>
                        <strong>{t.name}</strong>
                        <p>
                          {access.clubs.find((c) => c.id === t.club_id)?.name} ·{" "}
                          {t.season}
                        </p>
                      </div>
                      <span className="access-badge">
                        {t.role_key === "coach" ? "Coach" : "Player"} ·{" "}
                        {t.status}
                      </span>
                    </article>
                  ))}
                </div>
              </section>
            )}
            {selectedClub && (
              <ClubActivity key={selectedClub} clubId={selectedClub} />
            )}
            <section className="owner-panel membership-panel">
              <h3>Recent requests</h3>
              {access.requests.length ? (
                <div className="management-stack">
                  {access.requests.map((r) => (
                    <article className="membership-request-card" key={r.id}>
                      <div className="management-list-card">
                        <div>
                          <strong>
                            {r.club_name}
                            {r.team_name ? " · " + r.team_name : ""}
                          </strong>
                          <p>
                            {accessLabel(r.role_key)} ·{" "}
                            {dateLabel(r.created_at)}
                          </p>
                        </div>
                        <Badge value={r.status} />
                      </div>
                      {r.reason && (
                        <p className="membership-decision-note">{r.reason}</p>
                      )}
                    </article>
                  ))}
                </div>
              ) : (
                <p className="management-muted">
                  Your club and team requests will appear here.
                </p>
              )}
            </section>
          </>
        )
      )}
      {request && (
        <Modal
          title={
            "club" in request ? "Request club access" : "Request team access"
          }
          eyebrow="YOUR PFD ACCOUNT"
          close={() => setRequest(null)}
          busy={busy}
        >
          <form className="management-form" onSubmit={submit}>
            <p className="management-muted">
              {"club" in request
                ? `Ask to join ${request.club.name}. Team choices become available after the club approves you.`
                : `Ask to join ${request.team.name} as a ${role}. Your club will review this role request.`}
            </p>
            <label>
              Message (optional)
              <textarea
                value={message}
                maxLength={2000}
                disabled={busy}
                onChange={(e) => setMessage(e.target.value)}
              />
            </label>
            <ErrorNotice error={saveError} />
            <div className="management-actions">
              <button
                type="button"
                className="owner-refresh"
                disabled={busy}
                onClick={() => setRequest(null)}
              >
                Cancel
              </button>
              <button className="button primary" disabled={busy}>
                {busy ? "Sending…" : "Send request"}
              </button>
            </div>
          </form>
        </Modal>
      )}
    </div>
  );
}
