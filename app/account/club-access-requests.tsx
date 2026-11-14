"use client";
import { useEffect, useState } from "react";
import {
  membershipRequest,
  accessLabel,
  type JoinRequest,
} from "../../lib/memberships";
import type { TeamPage } from "../../lib/club-teams";
import { dateLabel } from "../../lib/workspace-api";
import {
  Badge,
  Empty,
  ErrorNotice,
  Modal,
  Pagination,
} from "./workspace-controls";
export default function ClubAccessRequests({
  clubId,
  teamId,
  coach = false,
}: {
  clubId: string;
  teamId?: string;
  coach?: boolean;
}) {
  const [query, setQuery] = useState("");
  const [filters, setFilters] = useState({
    query: "",
    status: "pending",
    role_key: "",
    page: 1,
  });
  const [data, setData] = useState<TeamPage<JoinRequest>>({
    items: [],
    total: 0,
    page: 1,
  });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [selected, setSelected] = useState<JoinRequest | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [notice, setNotice] = useState("");
  useEffect(() => {
    const t = setTimeout(
      () => setFilters((f) => ({ ...f, query, page: 1 })),
      250,
    );
    return () => clearTimeout(t);
  }, [query]);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    membershipRequest<TeamPage<JoinRequest>>("admin_requests", {
      club_id: clubId,
      ...filters,
      ...(teamId ? { team_id: teamId } : {}),
    })
      .then((d) => {
        if (active) setData(d);
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
  }, [clubId, teamId, filters, revision]);
  async function decide(decision: string) {
    if (!selected || busy) return;
    setBusy(true);
    setSaveError("");
    try {
      await membershipRequest("review_request", {
        club_id: clubId,
        id: selected.id,
        decision,
        reason,
      });
      setNotice(
        decision === "approved"
          ? selected.role_key === "member"
            ? "Club membership approved. This person can now request a team or be assigned by the club."
            : "Team role approved. Membership has been added."
          : "Request rejected. Your reason is visible to the applicant.",
      );
      setSelected(null);
      setRevision((r) => r + 1);
    } catch (e) {
      setSaveError(
        e instanceof Error ? e.message : "Unable to review request.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="management-section">
      <div className="management-toolbar">
        <div>
          <h2>
            {coach
              ? "Player requests for your team"
              : "Club first. Then the team."}
          </h2>
          <p className="management-muted">
            {coach
              ? "Review player requests from people already approved into the club. Club admission and coach appointments remain with Club Admin."
              : "Approve club admission before assigning a team or reviewing a team request."}
          </p>
        </div>
        <button
          className="owner-refresh"
          disabled={loading}
          onClick={() => setRevision((r) => r + 1)}
        >
          Refresh requests
        </button>
      </div>
      <div className="management-filters">
        <label>
          Search
          <input
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Applicant name or email"
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
            {["pending", "approved", "rejected", "all"].map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
        <label>
          Request type
          <select
            value={filters.role_key}
            onChange={(e) =>
              setFilters((f) => ({ ...f, role_key: e.target.value, page: 1 }))
            }
          >
            <option value="">All allowed types</option>
            {!coach && <option value="member">Join club</option>}
            {!coach && <option value="coach">Join team as coach</option>}
            <option value="player">Join team as player</option>
          </select>
        </label>
      </div>
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      <ErrorNotice error={error} retry={() => setRevision((r) => r + 1)} />
      <section className="owner-panel">
        {loading ? (
          <p className="owner-loading" role="status">
            Loading requests…
          </p>
        ) : data.items.length ? (
          <div
            className="owner-table-scroll"
            tabIndex={0}
            aria-label="Club access requests"
          >
            <table className="owner-table">
              <thead>
                <tr>
                  <th>Applicant</th>
                  <th>Request</th>
                  <th>Team</th>
                  <th>Submitted</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {data.items.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <strong>{r.name || "Name not provided"}</strong>
                      <span>{r.email}</span>
                    </td>
                    <td>{accessLabel(r.role_key)}</td>
                    <td>{r.team_name || "Club admission"}</td>
                    <td>{dateLabel(r.created_at)}</td>
                    <td>
                      <Badge value={r.status} />
                    </td>
                    <td>
                      <button
                        className="management-link"
                        onClick={() => {
                          setSelected(r);
                          setReason("");
                          setSaveError("");
                        }}
                      >
                        {r.status === "pending" ? "Review" : "View decision"} ↗
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          !error && (
            <Empty
              title="No matching requests."
              text="Club admission requests will arrive here after signup. Team requests appear only after club approval."
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
      {selected && (
        <Modal
          title={
            selected.status === "pending"
              ? "Review access request"
              : "Request decision"
          }
          eyebrow={coach ? "COACH" : "CLUB ADMINISTRATOR"}
          close={() => setSelected(null)}
          busy={busy}
        >
          <div className="management-stack">
            <h3>{selected.name || selected.email}</h3>
            <p className="management-muted">
              {accessLabel(selected.role_key)}
              {selected.team_name ? " · " + selected.team_name : ""}
            </p>
            {selected.message && (
              <div className="management-prose">{selected.message}</div>
            )}
            {selected.status === "pending" ? (
              <>
                <p className="permission-note">
                  {selected.role_key === "member"
                    ? "Approval admits this account to your club. It does not assign a team or coach/player role."
                    : "Approval grants only this requested role in this team."}
                </p>
                <label className="management-label">
                  Decision note (required to reject)
                  <textarea
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    maxLength={2000}
                    disabled={busy}
                  />
                </label>
                <ErrorNotice error={saveError} />
                <div className="management-actions">
                  <button
                    className="management-danger"
                    disabled={busy || !reason.trim()}
                    onClick={() => void decide("rejected")}
                  >
                    Reject
                  </button>
                  <button
                    className="button primary"
                    disabled={busy}
                    onClick={() => void decide("approved")}
                  >
                    {busy ? "Saving…" : "Approve"}
                  </button>
                </div>
              </>
            ) : (
              <>
                <Badge value={selected.status} />
                <p className="management-muted">
                  Reviewed {dateLabel(selected.reviewed_at, true)}
                  {selected.reviewer_name
                    ? " by " + selected.reviewer_name
                    : ""}
                </p>
                <div className="management-prose">
                  {selected.reason || "No decision note added."}
                </div>
              </>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}
