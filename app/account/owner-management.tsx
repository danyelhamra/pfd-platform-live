"use client";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import TrainingPlanBuilder from "./training-plan-builder";
import { getSupabase } from "../../lib/supabase";
import {
  dateLabel,
  roleLabel,
  workspaceRequest,
  type AccountRow,
  type Attachment,
  type Options,
  type Page,
  type RequestRow,
  type Resource,
  type WorkspaceClient,
} from "../../lib/workspace-api";
import {
  AccountPicker,
  Badge,
  ClubTeamFields,
  Empty,
  ErrorNotice,
  Modal,
  Pagination,
} from "./workspace-controls";

export function useWorkspaceList<T>(
  action: string,
  filters: Record<string, unknown>,
  request: WorkspaceClient = workspaceRequest,
) {
  const [data, setData] = useState<Page<T>>({ items: [], total: 0, page: 1 });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const key = JSON.stringify(filters);
  const reload = useCallback(() => setRevision((v) => v + 1), []);
  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    request<Page<T>>(action, JSON.parse(key))
      .then((result) => {
        if (active) setData(result);
      })
      .catch((e) => {
        if (active)
          setError(e instanceof Error ? e.message : "Unable to load records.");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [action, key, revision, request]);
  return { data, loading, error, reload };
}
type Membership = {
  club_id: string;
  club_name: string;
  team_id: string | null;
  team_name: string | null;
  role_key: string;
  status: string;
  created_at: string;
};
type UserDetail = {
  profile: AccountRow;
  is_owner: boolean;
  memberships: Membership[];
  report_count: number;
  created_reports: number;
  pending_requests: number;
  recent_reports: {
    id: string;
    template_key: string;
    report_date: string;
    status: string;
  }[];
};
export function UsersManager({
  options,
  openReport,
}: {
  options: Options;
  openReport: (id: string) => void;
}) {
  const [filters, setFilters] = useState({
    query: "",
    role: "",
    club_id: "",
    page: 1,
  });
  const [search, setSearch] = useState("");
  useEffect(() => {
    const t = setTimeout(
      () => setFilters((f) => ({ ...f, query: search, page: 1 })),
      250,
    );
    return () => clearTimeout(t);
  }, [search]);
  const { data, loading, error, reload } = useWorkspaceList<AccountRow>(
    "users_list",
    filters,
  );
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<UserDetail | null>(null);
  const [detailError, setDetailError] = useState("");
  useEffect(() => {
    if (!selected) return;
    let active = true;
    setDetail(null);
    setDetailError("");
    workspaceRequest<UserDetail>("user_detail", { id: selected })
      .then((d) => {
        if (active) setDetail(d);
      })
      .catch((e) => {
        if (active) setDetailError(e.message);
      });
    return () => {
      active = false;
    };
  }, [selected]);
  return (
    <div className="management-section">
      <div className="management-toolbar">
        <div>
          <h2>People on PFD</h2>
          <p>
            {data.total_accounts ?? "—"} registered accounts · roles follow club
            and team memberships.
          </p>
        </div>
        <button className="owner-refresh" disabled={loading} onClick={reload}>
          Refresh
        </button>
      </div>
      <div className="management-filters">
        <label>
          Search
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Name or email"
          />
        </label>
        <label>
          Role
          <select
            value={filters.role}
            onChange={(e) =>
              setFilters((f) => ({ ...f, role: e.target.value, page: 1 }))
            }
          >
            <option value="">All roles</option>
            {["owner", "club_admin", "coach", "player", "member"].map((r) => (
              <option key={r} value={r}>
                {roleLabel(r)}
              </option>
            ))}
          </select>
        </label>
        <label>
          Club
          <select
            value={filters.club_id}
            onChange={(e) =>
              setFilters((f) => ({ ...f, club_id: e.target.value, page: 1 }))
            }
          >
            <option value="">All clubs</option>
            {options.clubs.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
      </div>
      <ErrorNotice error={error} retry={reload} />
      <section className="owner-panel">
        {loading ? (
          <p className="owner-loading" role="status">
            Loading accounts…
          </p>
        ) : data.items.length ? (
          <div className="owner-table-scroll" tabIndex={0} aria-label="Users">
            <table className="owner-table">
              <thead>
                <tr>
                  <th>Name / email</th>
                  <th>Roles</th>
                  <th>Joined</th>
                  <th>Last sign-in</th>
                  <th>Reports</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {data.items.map((u) => (
                  <tr key={u.id}>
                    <td>
                      <strong>{u.name || "Name not provided"}</strong>
                      <span>{u.email}</span>
                    </td>
                    <td>
                      <div className="badge-list">
                        {(u.roles.length ? u.roles : ["member"]).map((r) => (
                          <span className="access-badge" key={r}>
                            {roleLabel(r)}
                          </span>
                        ))}
                      </div>
                    </td>
                    <td>{dateLabel(u.created_at)}</td>
                    <td>{dateLabel(u.last_sign_in_at)}</td>
                    <td>{u.report_count}</td>
                    <td>
                      <button
                        className="management-link"
                        onClick={() => setSelected(u.id)}
                      >
                        View profile ↗
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
              title="No matching accounts"
              text="Try another name, role or club."
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
        <Modal title="User profile" close={() => setSelected(null)} wide>
          <ErrorNotice error={detailError} />
          {!detail && !detailError ? (
            <p role="status">Loading profile…</p>
          ) : (
            detail && (
              <>
                <div className="profile-summary">
                  <div className="management-avatar">
                    {(detail.profile.name || detail.profile.email)
                      .slice(0, 1)
                      .toUpperCase()}
                  </div>
                  <div>
                    <h3>{detail.profile.name || "Name not provided"}</h3>
                    <p>{detail.profile.email}</p>
                    {detail.is_owner && (
                      <span className="access-badge owner-access">
                        PFD Owner
                      </span>
                    )}
                  </div>
                </div>
                <dl className="management-details">
                  <div>
                    <dt>Joined</dt>
                    <dd>{dateLabel(detail.profile.created_at)}</dd>
                  </div>
                  <div>
                    <dt>Last sign-in</dt>
                    <dd>{dateLabel(detail.profile.last_sign_in_at, true)}</dd>
                  </div>
                  <div>
                    <dt>Submitted reports about this account</dt>
                    <dd>{detail.report_count}</dd>
                  </div>
                  <div>
                    <dt>Reports created</dt>
                    <dd>{detail.created_reports}</dd>
                  </div>
                  <div>
                    <dt>Pending requests</dt>
                    <dd>{detail.pending_requests}</dd>
                  </div>
                </dl>
                <h3>Club &amp; team memberships</h3>
                {detail.memberships.length ? (
                  <div className="management-stack">
                    {detail.memberships.map((m, i) => (
                      <article className="management-list-card" key={i}>
                        <div>
                          <strong>
                            {m.club_name}
                            {m.team_name ? " · " + m.team_name : ""}
                          </strong>
                          <p>
                            {roleLabel(m.role_key)} · Assigned{" "}
                            {dateLabel(m.created_at)}
                          </p>
                        </div>
                        <Badge value={m.status} />
                      </article>
                    ))}
                  </div>
                ) : (
                  <p className="management-muted">
                    No club or team memberships. An Owner does not need a club
                    membership to oversee PFD.
                  </p>
                )}
                <h3>Recent assessments</h3>
                {detail.recent_reports.length ? (
                  <div className="management-stack">
                    {detail.recent_reports.map((r) => (
                      <button
                        className="management-list-card management-clickable"
                        key={r.id}
                        onClick={() => {
                          setSelected(null);
                          openReport(r.id);
                        }}
                      >
                        <div>
                          <strong>
                            {options.templates.find(
                              (t) => t.key === r.template_key,
                            )?.label || r.template_key}
                          </strong>
                          <p>{dateLabel(r.report_date)}</p>
                        </div>
                        <Badge value={r.status} />
                      </button>
                    ))}
                  </div>
                ) : (
                  <p className="management-muted">
                    No assessments saved for this account yet.
                  </p>
                )}
                <p className="management-footnote">
                  Permission rules are managed in Settings. Memberships are
                  assigned through clubs, teams and approved access requests.
                </p>
              </>
            )
          )}
        </Modal>
      )}
    </div>
  );
}
export function RequestsManager({
  options,
  onChanged,
}: {
  options: Options;
  onChanged: () => void;
}) {
  const [filters, setFilters] = useState({
    query: "",
    status: "pending",
    role: "",
    club_id: "",
    page: 1,
  });
  const [search, setSearch] = useState("");
  useEffect(() => {
    const t = setTimeout(
      () => setFilters((f) => ({ ...f, query: search, page: 1 })),
      250,
    );
    return () => clearTimeout(t);
  }, [search]);
  const { data, loading, error, reload } = useWorkspaceList<RequestRow>(
    "requests_list",
    filters,
  );
  const [selected, setSelected] = useState<RequestRow | null>(null);
  const [create, setCreate] = useState(false);
  const [user, setUser] = useState("");
  const [club, setClub] = useState("");
  const [team, setTeam] = useState("");
  const [role, setRole] = useState("club_admin");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [reason, setReason] = useState("");
  const [saveError, setSaveError] = useState("");
  const [notice, setNotice] = useState("");
  async function createRequest(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setSaveError("");
    try {
      await workspaceRequest("request_create", {
        user_id: user,
        club_id: club,
        team_id: ["club_admin", "member"].includes(role) ? "" : team,
        role_key: role,
        message,
      });
      setCreate(false);
      setNotice("Request recorded. Review it to approve or reject access.");
      reload();
      onChanged();
    } catch (e) {
      setSaveError(
        e instanceof Error ? e.message : "Unable to record request.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function review(decision: string) {
    if (!selected || busy) return;
    setBusy(true);
    setSaveError("");
    try {
      await workspaceRequest("request_review", {
        id: selected.id,
        decision,
        reason,
      });
      setSelected(null);
      setNotice(
        decision === "approved"
          ? "Request approved and membership granted."
          : "Request rejected. The decision is saved in request history.",
      );
      reload();
      onChanged();
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
          <h2>Access, with a clear record.</h2>
          <p>{data.pending ?? 0} pending requests across your clubs.</p>
        </div>
        <button
          className="button primary"
          onClick={() => {
            setCreate(true);
            setUser("");
            setClub("");
            setTeam("");
            setRole("club_admin");
            setMessage("");
            setSaveError("");
          }}
        >
          Record request
        </button>
      </div>
      <p className="management-footnote">
        Review requests submitted by users for club and team access. You can
        also record a request on behalf of an existing account.
      </p>
      <div className="management-filters">
        <label>
          Search
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Applicant or club"
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
            <option value="">All requests</option>
            {["pending", "approved", "rejected"].map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
        <label>
          Role
          <select
            value={filters.role}
            onChange={(e) =>
              setFilters((f) => ({ ...f, role: e.target.value, page: 1 }))
            }
          >
            <option value="">All roles</option>
            {["member", "club_admin", "coach", "player"].map((r) => (
              <option value={r} key={r}>
                {roleLabel(r)}
              </option>
            ))}
          </select>
        </label>
        <label>
          Club
          <select
            value={filters.club_id}
            onChange={(e) =>
              setFilters((f) => ({ ...f, club_id: e.target.value, page: 1 }))
            }
          >
            <option value="">All clubs</option>
            {options.clubs.map((c) => (
              <option value={c.id} key={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
      </div>
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      <ErrorNotice error={error} retry={reload} />
      <section className="owner-panel">
        {loading ? (
          <p className="owner-loading" role="status">
            Loading requests…
          </p>
        ) : data.items.length ? (
          <div
            className="owner-table-scroll"
            tabIndex={0}
            aria-label="Access requests"
          >
            <table className="owner-table">
              <thead>
                <tr>
                  <th>Applicant</th>
                  <th>Requested access</th>
                  <th>Club / team</th>
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
                    <td>{roleLabel(r.role_key)}</td>
                    <td>
                      <strong>{r.club_name}</strong>
                      <span>{r.team_name || "Club-wide"}</span>
                    </td>
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
              title={
                filters.status === "pending"
                  ? "All caught up."
                  : "No matching requests."
              }
              text="Access requests and their decisions will be organised here."
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
      {create && (
        <Modal
          title="Record an access request"
          close={() => setCreate(false)}
          busy={busy}
        >
          <form className="management-form" onSubmit={createRequest}>
            <AccountPicker
              value={user}
              select={(id) => setUser(id)}
              disabled={busy}
            />
            <label>
              Requested role
              <select
                value={role}
                onChange={(e) => {
                  setRole(e.target.value);
                  setTeam("");
                }}
                disabled={busy}
              >
                {["member", "club_admin", "coach", "player"].map((r) => (
                  <option value={r} key={r}>
                    {roleLabel(r)}
                  </option>
                ))}
              </select>
            </label>
            <ClubTeamFields
              options={options}
              club={club}
              team={team}
              required
              disabled={busy}
              change={(c, t) => {
                setClub(c);
                setTeam(["club_admin", "member"].includes(role) ? "" : t);
              }}
            />
            {!["club_admin", "member"].includes(role) && (
              <p className="management-footnote">
                A coach or player request requires an active team in the
                selected club.
              </p>
            )}
            <label>
              Applicant message / context
              <textarea
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                maxLength={2000}
                disabled={busy}
              />
            </label>
            <ErrorNotice error={saveError} />
            <div className="management-actions">
              <button
                type="button"
                className="owner-refresh"
                disabled={busy}
                onClick={() => setCreate(false)}
              >
                Cancel
              </button>
              <button
                className="button primary"
                disabled={
                  busy ||
                  !user ||
                  !club ||
                  (!["club_admin", "member"].includes(role) && !team)
                }
              >
                {busy ? "Recording…" : "Record request"}
              </button>
            </div>
          </form>
        </Modal>
      )}
      {selected && (
        <Modal
          title={
            selected.status === "pending"
              ? "Review access request"
              : "Request decision"
          }
          close={() => setSelected(null)}
          busy={busy}
        >
          <div className="management-stack">
            <h3>{selected.name || selected.email}</h3>
            <p className="management-muted">{selected.email}</p>
            <dl className="management-details">
              <div>
                <dt>Requested role</dt>
                <dd>{roleLabel(selected.role_key)}</dd>
              </div>
              <div>
                <dt>Club / team</dt>
                <dd>
                  {selected.club_name}
                  {selected.team_name ? " · " + selected.team_name : ""}
                </dd>
              </div>
              <div>
                <dt>Submitted</dt>
                <dd>{dateLabel(selected.created_at, true)}</dd>
              </div>
            </dl>
            <Badge value={selected.status} />
            {selected.message && (
              <div className="management-prose">{selected.message}</div>
            )}
            {selected.status === "pending" ? (
              <>
                <p className="permission-note">
                  Approving grants only the requested membership in this club or
                  team. It does not grant PFD Owner access.
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
                    onClick={() => void review("rejected")}
                  >
                    Reject request
                  </button>
                  <button
                    className="button primary"
                    disabled={busy}
                    onClick={() => void review("approved")}
                  >
                    {busy ? "Saving…" : "Approve access"}
                  </button>
                </div>
              </>
            ) : (
              <>
                <p>
                  Reviewed by {selected.reviewer_name || "PFD Owner"} ·{" "}
                  {dateLabel(selected.reviewed_at, true)}
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
const resourceLabels: Record<string, string> = {
  report_template: "Report template",
  individual_drill: "Individual Drill",
  team_drill: "Team Drill",
  training_plan: "Training-plan template",
};
const blankResource = (kind: string): Resource => ({
  id: crypto.randomUUID(),
  title: "",
  kind,
  duration_minutes: null,
  plan_blocks: [],
  category: "",
  difficulty: "all",
  instructions: "",
  video_url: "",
  attachments: [],
  audience: "all_clubs",
  status: "draft",
  club_ids: [],
  updated_at: "",
});
export function LibraryManager({
  options,
  openTemplates,
  request = workspaceRequest,
  scopedClub,
  canManage = true,
  mode = "club_admin",
}: {
  options: Options;
  mode?: "club_admin" | "coach";
  request?: WorkspaceClient;
  scopedClub?: string;
  canManage?: boolean;
  openTemplates: (key?: string, preview?: boolean) => void;
}) {
  const [filters, setFilters] = useState({
    scope: "",
    query: "",
    kind: "report_template",
    status: "",
    difficulty: "",
    page: 1,
  });
  const [search, setSearch] = useState("");
  useEffect(() => {
    const t = setTimeout(
      () => setFilters((f) => ({ ...f, query: search, page: 1 })),
      250,
    );
    return () => clearTimeout(t);
  }, [search]);
  const { data, loading, error, reload } = useWorkspaceList<Resource>(
    "resources_list",
    filters,
    request,
  );
  const [editing, setEditing] = useState<Resource | null>(null);
  const [viewing, setViewing] = useState<Resource | null>(null);
  const [files, setFiles] = useState<File[]>([]);
  const [busy, setBusy] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [notice, setNotice] = useState("");
  const [links, setLinks] = useState<Record<string, string>>({});
  const [linkError, setLinkError] = useState("");
  const dirty = useRef(false);
  useEffect(() => {
    if (!viewing) return;
    let active = true;
    setLinks({});
    setLinkError("");
    Promise.all(
      viewing.attachments.map(async (a) => {
        if (scopedClub) {
          const r = await request<{ url: string }>("resource_file_access", {
            resource_id: viewing.id,
            path: a.path,
          });
          return [a.path, r.url];
        }
        const r = await getSupabase()
          .storage.from(
            a.bucket ||
              (viewing.club_id
                ? "pfd-club-files"
                : "pfd-development-resources"),
          )
          .createSignedUrl(a.path, 600);
        if (r.error) throw r.error;
        return [a.path, r.data.signedUrl];
      }),
    )
      .then((pairs) => {
        if (active) setLinks(Object.fromEntries(pairs));
      })
      .catch(() => {
        if (active)
          setLinkError(
            "Unable to open one or more files. Close and reopen this resource to retry.",
          );
      });
    return () => {
      active = false;
    };
  }, [viewing, scopedClub, request]);
  useEffect(() => {
    if (!editing) return;
    const warn = (e: BeforeUnloadEvent) => {
      if (dirty.current) e.preventDefault();
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [editing]);
  function edit(resource: Resource) {
    setViewing(null);
    setEditing({ ...resource, club_ids: resource.club_ids || [] });
    setFiles([]);
    setSaveError("");
    dirty.current = false;
  }
  function close() {
    if (!dirty.current || window.confirm("Discard unsaved resource changes?"))
      setEditing(null);
  }
  function patch(values: Partial<Resource>) {
    dirty.current = true;
    setEditing((r) => r && { ...r, ...values });
  }
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!editing || busy) return;
    setBusy(true);
    setSaveError("");
    const uploaded: string[] = [];
    let saveAttempted = false;
    try {
      const attachments: Attachment[] = [...editing.attachments];
      if (attachments.length + files.length > 5)
        throw Error("Choose up to five supporting files.");
      for (const file of files) {
        if (file.size > 50 * 1024 * 1024)
          throw Error("Each file must be 50 MB or smaller.");
        if (
          ![
            "application/pdf",
            "image/jpeg",
            "image/png",
            "image/webp",
            "video/mp4",
            "video/webm",
          ].includes(file.type)
        )
          throw Error("Use PDF, JPG, PNG, WebP, MP4 or WebM files.");
        const suffix =
          file.name
            .split(".")
            .pop()
            ?.replace(/[^a-z0-9]/gi, "")
            .slice(0, 10) || "file";
        let path: string;
        let uploadError: Error | null = null;
        if (scopedClub) {
          const access = await request<{
            bucket: string;
            path: string;
            token: string;
          }>("prepare_resource_upload", {
            team_id: editing.team_id || null,
            mime: file.type,
            size: file.size,
          });
          path = access.path;
          const result = await getSupabase()
            .storage.from(access.bucket)
            .uploadToSignedUrl(path, access.token, file, {
              contentType: file.type,
            });
          uploadError = result.error;
        } else {
          path = editing.id + "/" + crypto.randomUUID() + "." + suffix;
          const result = await getSupabase()
            .storage.from("pfd-development-resources")
            .upload(path, file, { upsert: false, contentType: file.type });
          uploadError = result.error;
        }
        const r = { error: uploadError };
        if (r.error) throw r.error;
        uploaded.push(path);
        attachments.push({
          path,
          name: file.name,
          size: file.size,
          mime: file.type,
        });
      }
      if (editing.video_url) {
        const u = new URL(editing.video_url);
        if (!["https:", "http:"].includes(u.protocol))
          throw Error("Use an http or https video link.");
      }
      saveAttempted = true;
      await request<Resource>("resource_save", {
        ...editing,
        attachments,
      });
      dirty.current = false;
      setEditing(null);
      setNotice(
        scopedClub
          ? "Club resource saved."
          : "Resource saved. Published resources are available to eligible clubs.",
      );
      reload();
    } catch (e) {
      if (uploaded.length && !saveAttempted && !scopedClub)
        await getSupabase()
          .storage.from(
            scopedClub ? "pfd-club-files" : "pfd-development-resources",
          )
          .remove(uploaded);
      setSaveError(e instanceof Error ? e.message : "Unable to save resource.");
    } finally {
      setBusy(false);
    }
  }
  async function promote(resource: Resource) {
    setBusy(true);
    setSaveError("");
    setNotice("");
    try {
      await request(scopedClub ? "resource_share_club" : "resource_promote", {
        id: resource.id,
        updated_at: resource.updated_at,
      });
      setViewing(null);
      setNotice(
        scopedClub
          ? "Approved copy shared with this club. The team original is unchanged."
          : "Approved copy added to Global. The local original is unchanged.",
      );
      reload();
    } catch (e) {
      setSaveError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const scopeName = (r: Resource) =>
    r.team_id ? "Team" : r.club_id ? "Club" : "Global";
  function PromotionButton({ resource }: { resource: Resource }) {
    return canManage &&
      resource.status === "published" &&
      ((!scopedClub && resource.club_id) ||
        (scopedClub && mode !== "coach" && resource.team_id)) ? (
      <button
        className="button secondary"
        disabled={busy}
        onClick={() => void promote(resource)}
      >
        {scopedClub ? "Approve club copy" : "Approve global copy"}
      </button>
    ) : null;
  }
  return (
    <div className="management-section">
      <div className="management-toolbar">
        <div>
          <h2>Build the development toolkit.</h2>
          <p>
            {data.published ?? 0} published resources ·{" "}
            {options.templates.length} report templates, including the original
            five.
          </p>
        </div>
        <button
          className="button primary"
          disabled={!canManage}
          onClick={() =>
            edit({
              ...blankResource(filters.kind),
              ...(scopedClub
                ? {
                    club_id: scopedClub,
                    team_id:
                      mode === "coach" ? options.teams[0]?.id || null : null,
                  }
                : {}),
            })
          }
        >
          {filters.kind === "training_plan"
            ? "Create training plan"
            : filters.kind === "report_template"
              ? "Add template brief"
              : "Add drill"}
        </button>
      </div>
      <p className="management-muted">
        {scopedClub
          ? mode === "coach"
            ? "Create within your team. Club Admin approves club-wide sharing; the PFD Owner approves Global."
            : "Resources stay in this club. Approve team resources here to create a club-wide copy."
          : "You curate Global. Browse club and team resources below, review them, and approve a global copy. Matching global titles are blocked to avoid duplicates."}
      </p>
      <label className="management-label">
        Library level
        <select
          value={filters.scope}
          onChange={(e) =>
            setFilters((f) => ({ ...f, scope: e.target.value, page: 1 }))
          }
        >
          <option value="">All available levels</option>
          <option value="global">Global / PFD shared</option>
          <option value="club">Club</option>
          <option value="team">Team</option>
          {!scopedClub && <option value="local">Club & team review</option>}
        </select>
      </label>
      <div
        className="library-section-buttons"
        role="group"
        aria-label="Resource sections"
      >
        {Object.entries(resourceLabels).map(([kind, label]) => (
          <button
            type="button"
            key={kind}
            aria-pressed={filters.kind === kind}
            onClick={() => setFilters((f) => ({ ...f, kind, page: 1 }))}
          >
            <strong>
              {kind === "report_template"
                ? "Report Templates"
                : kind === "training_plan"
                  ? "Training Plans"
                  : label + "s"}
            </strong>
            <small>
              {kind === "individual_drill"
                ? "Individual work & homework"
                : kind === "team_drill"
                  ? "Group activities"
                  : kind === "training_plan"
                    ? "Build a timed session"
                    : "Assessments & match reviews"}
            </small>
          </button>
        ))}
      </div>
      {filters.kind === "report_template" && (
        <div className="report-template-grid">
          {options.templates.map((t) => (
            <article className="owner-panel report-template-card" key={t.key}>
              <span className="eyebrow">
                {["performance", "match_review", "gps"].includes(t.key)
                  ? "MATCH & PERFORMANCE"
                  : "ORIGINAL PFD"}
              </span>
              <h3>{t.label}</h3>
              <p>{t.definition.intro}</p>
              <button
                className="management-link"
                onClick={() => openTemplates(t.key, true)}
              >
                Preview template ↗
              </button>
              <button
                className="owner-refresh"
                onClick={() => openTemplates(t.key, false)}
              >
                Create report
              </button>
            </article>
          ))}
        </div>
      )}
      <div className="management-filters">
        <label>
          Search
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Title, category or instructions"
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
            <option value="">All statuses</option>
            {["draft", "published", "archived"].map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
        <label>
          Difficulty
          <select
            value={filters.difficulty}
            onChange={(e) =>
              setFilters((f) => ({ ...f, difficulty: e.target.value, page: 1 }))
            }
          >
            <option value="">Any difficulty</option>
            {["all", "beginner", "intermediate", "advanced"].map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
      </div>
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      <ErrorNotice error={saveError || error} retry={reload} />
      {loading ? (
        <p role="status" className="owner-loading">
          Loading resources…
        </p>
      ) : data.items.length ? (
        <div className="resource-grid">
          {data.items.map((r) => (
            <article className="owner-panel resource-card" key={r.id}>
              <div className="resource-card-top">
                <span>{resourceLabels[r.kind]}</span>
                <Badge value={r.status} />
              </div>
              <h3>{r.title}</h3>
              <p className="resource-origin">
                <strong>{scopeName(r)}</strong>
                {r.club_name ? " · " + r.club_name : ""}
                {r.team_name
                  ? " · " + r.team_name
                  : r.team_id
                    ? " · " +
                      (options.teams.find((t) => t.id === r.team_id)?.name ||
                        "Team")
                    : ""}
                {r.author_name ? " · " + r.author_name : ""}
                {r.source_resource_id ? " · Approved copy" : ""}
              </p>
              <p>
                {r.instructions.slice(0, 180) || "No instructions added yet."}
              </p>
              <div className="badge-list">
                <span className="access-badge">
                  {r.category || "Uncategorised"}
                </span>
                <span className="access-badge">
                  {r.difficulty === "all" ? "All levels" : r.difficulty}
                </span>
              </div>
              {(r.duration_minutes || r.kind === "training_plan") && (
                <strong className="resource-duration">
                  {r.kind === "training_plan"
                    ? Number(
                        (r.plan_blocks || [])
                          .reduce((sum, b) => sum + Number(b.minutes), 0)
                          .toFixed(1),
                      )
                    : r.duration_minutes}{" "}
                  min
                  {r.kind === "training_plan"
                    ? ` · ${(r.plan_blocks || []).length} drills`
                    : ""}
                </strong>
              )}
              <small>
                {r.audience === "all_clubs"
                  ? "All clubs"
                  : `${r.club_ids.length} selected club(s)`}{" "}
                · {r.attachments.length} file(s)
              </small>
              <div className="management-actions">
                <button
                  className="management-link"
                  onClick={() => setViewing(r)}
                >
                  View resource ↗
                </button>
                <button
                  className="owner-refresh"
                  disabled={!canManage || r.read_only}
                  onClick={() => edit(r)}
                >
                  Edit
                </button>
                <PromotionButton resource={r} />
              </div>
            </article>
          ))}
        </div>
      ) : (
        !error && (
          <section className="owner-panel">
            <Empty
              title="Your library starts here."
              text="Add a drill, homework activity or reusable template for your clubs."
            />
          </section>
        )
      )}
      <Pagination
        page={filters.page}
        total={data.total}
        loading={loading}
        change={(page) => setFilters((f) => ({ ...f, page }))}
      />
      {editing && (
        <Modal
          title={editing.updated_at ? "Edit resource" : "Add resource"}
          eyebrow={
            scopedClub
              ? mode === "coach"
                ? "COACH"
                : "CLUB ADMINISTRATOR"
              : "PFD OWNER"
          }
          close={close}
          busy={busy}
          wide
        >
          <form className="management-form" onSubmit={save}>
            {scopedClub && (
              <label>
                Visibility within the club
                <select
                  required={mode === "coach"}
                  value={editing.team_id || ""}
                  disabled={busy || !!editing.updated_at}
                  onChange={(e) => patch({ team_id: e.target.value || null })}
                >
                  {mode !== "coach" && <option value="">Whole club</option>}
                  {options.teams.map((t) => (
                    <option key={t.id} value={t.id}>
                      Team: {t.name} · {t.season}
                    </option>
                  ))}
                </select>
                <small>
                  Visibility is fixed after creation. Sharing upwards creates a
                  separate approved copy.
                </small>
              </label>
            )}
            <label>
              Title *
              <input
                required
                maxLength={160}
                value={editing.title}
                disabled={busy}
                onChange={(e) => patch({ title: e.target.value })}
              />
            </label>
            <div className="management-form-grid">
              <label>
                Resource type
                <select
                  value={editing.kind}
                  disabled
                  onChange={(e) => patch({ kind: e.target.value })}
                >
                  {Object.entries(resourceLabels).map(([k, v]) => (
                    <option key={k} value={k}>
                      {v}
                    </option>
                  ))}
                </select>
              </label>
              <label>
                Category
                <input
                  value={editing.category}
                  maxLength={80}
                  disabled={busy}
                  onChange={(e) => patch({ category: e.target.value })}
                  placeholder="e.g. Passing, ball mastery"
                />
              </label>
              <label>
                Difficulty
                <select
                  value={editing.difficulty}
                  disabled={busy}
                  onChange={(e) => patch({ difficulty: e.target.value })}
                >
                  {["all", "beginner", "intermediate", "advanced"].map((d) => (
                    <option key={d}>{d}</option>
                  ))}
                </select>
              </label>
              <label>
                Status
                <select
                  value={editing.status}
                  disabled={busy}
                  onChange={(e) => patch({ status: e.target.value })}
                >
                  {["draft", "published", "archived"].map((s) => (
                    <option key={s}>{s}</option>
                  ))}
                </select>
              </label>
            </div>
            {["individual_drill", "team_drill"].includes(editing.kind) && (
              <label>
                Estimated duration (minutes) *
                <input
                  type="number"
                  min={0.1}
                  max={240}
                  step={0.1}
                  required
                  value={editing.duration_minutes ?? ""}
                  disabled={busy}
                  onChange={(e) =>
                    patch({
                      duration_minutes: e.target.value
                        ? Number(e.target.value)
                        : null,
                    })
                  }
                />
              </label>
            )}
            {editing.kind === "training_plan" && (
              <TrainingPlanBuilder
                teamId={editing.team_id}
                request={request}
                blocks={editing.plan_blocks || []}
                change={(blocks) => patch({ plan_blocks: blocks })}
                disabled={busy}
              />
            )}
            <label>
              Instructions{" "}
              {editing.status === "published" ? "*" : "(optional for drafts)"}
              <textarea
                rows={8}
                required={editing.status === "published"}
                maxLength={12000}
                value={editing.instructions}
                disabled={busy}
                onChange={(e) => patch({ instructions: e.target.value })}
              />
            </label>
            {editing.kind === "report_template" && (
              <p className="management-footnote">
                Use this for a reusable report brief or attach a template
                document. All assessment forms remain available in Reports; this
                field does not create a new interactive assessment form.
              </p>
            )}
            <label>
              Supporting video link
              <input
                type="url"
                value={editing.video_url}
                disabled={busy}
                onChange={(e) => patch({ video_url: e.target.value })}
                placeholder="https://…"
              />
            </label>
            <label>
              Supporting files (up to 5, 50 MB each)
              <input
                type="file"
                multiple
                accept=".pdf,.jpg,.jpeg,.png,.webp,.mp4,.webm"
                disabled={busy}
                onChange={(e) => {
                  setFiles(Array.from(e.target.files || []));
                  dirty.current = true;
                }}
              />
            </label>
            <p className="management-footnote">
              PDF, images or videos. Files stay private. Removing a file here
              removes its link from this resource.
            </p>
            {editing.attachments.map((a) => (
              <div className="attachment-row" key={a.path}>
                <span>{a.name}</span>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() =>
                    patch({
                      attachments: editing.attachments.filter(
                        (x) => x.path !== a.path,
                      ),
                    })
                  }
                >
                  Remove
                </button>
              </div>
            ))}
            {files.map((f, i) => (
              <div className="attachment-row" key={i}>
                {f.name} · ready to upload
              </div>
            ))}
            {!scopedClub && (
              <>
                <label>
                  Availability
                  <select
                    value={editing.audience}
                    disabled={busy}
                    onChange={(e) => patch({ audience: e.target.value })}
                  >
                    <option value="all_clubs">All clubs</option>
                    <option value="selected_clubs">Selected clubs</option>
                  </select>
                </label>
                {editing.audience === "selected_clubs" && (
                  <fieldset className="resource-club-choices">
                    <legend>Choose clubs</legend>
                    {options.clubs
                      .filter(
                        (c) =>
                          c.status === "active" ||
                          editing.club_ids.includes(c.id),
                      )
                      .map((c) => (
                        <label key={c.id}>
                          <input
                            type="checkbox"
                            checked={editing.club_ids.includes(c.id)}
                            disabled={busy}
                            onChange={(e) =>
                              patch({
                                club_ids: e.target.checked
                                  ? [...editing.club_ids, c.id]
                                  : editing.club_ids.filter(
                                      (id) => id !== c.id,
                                    ),
                              })
                            }
                          />
                          {c.name}
                          {c.status === "archived" ? " (archived)" : ""}
                        </label>
                      ))}
                  </fieldset>
                )}
              </>
            )}
            <ErrorNotice error={saveError} />
            <div className="management-actions">
              <button
                type="button"
                className="owner-refresh"
                disabled={busy}
                onClick={close}
              >
                Cancel
              </button>
              <button className="button primary" disabled={busy}>
                {busy ? "Saving resource…" : "Save resource"}
              </button>
            </div>
          </form>
        </Modal>
      )}
      {viewing && (
        <Modal
          title={viewing.title}
          eyebrow={
            scopedClub
              ? mode === "coach"
                ? "COACH"
                : "CLUB ADMINISTRATOR"
              : "PFD OWNER"
          }
          close={() => setViewing(null)}
          wide
        >
          <div className="management-stack">
            <div className="badge-list">
              <Badge value={viewing.status} />
              <span className="access-badge">
                {resourceLabels[viewing.kind]}
              </span>
              <span className="access-badge">
                {viewing.difficulty === "all"
                  ? "All levels"
                  : viewing.difficulty}
              </span>
            </div>
            {viewing.kind === "training_plan" && (
              <div className="plan-view">
                <h3>
                  Session ·{" "}
                  {Number(
                    (viewing.plan_blocks || [])
                      .reduce((sum, b) => sum + Number(b.minutes), 0)
                      .toFixed(1),
                  )}{" "}
                  minutes
                </h3>
                {(viewing.plan_blocks || []).map((b, i) => (
                  <details key={b.id}>
                    <summary>
                      {i + 1}. {b.title} · {b.minutes} min
                    </summary>
                    <div className="management-prose">
                      {b.instructions || "No saved drill instructions."}
                    </div>
                  </details>
                ))}
              </div>
            )}
            <div className="management-prose">
              {viewing.instructions || "No instructions added."}
            </div>
            {viewing.video_url && /^https?:\/\//.test(viewing.video_url) && (
              <a
                className="management-link"
                href={viewing.video_url}
                target="_blank"
                rel="noopener noreferrer"
              >
                Open supporting video ↗
              </a>
            )}
            {viewing.attachments.length > 0 && (
              <>
                <h3>Supporting files</h3>
                <ErrorNotice error={linkError} />
                {viewing.attachments.map((a) =>
                  links[a.path] ? (
                    <a
                      className="attachment-row"
                      key={a.path}
                      href={links[a.path]}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      {a.name} ↗
                    </a>
                  ) : (
                    <p key={a.path}>
                      {a.name} ·{" "}
                      {linkError ? "Unavailable" : "Preparing private link…"}
                    </p>
                  ),
                )}
              </>
            )}
            <p className="management-muted">
              {viewing.audience === "all_clubs"
                ? "Available to all clubs when their library is connected."
                : "Selected clubs: " +
                  viewing.club_ids
                    .map(
                      (id) =>
                        options.clubs.find((c) => c.id === id)?.name ||
                        "Club unavailable",
                    )
                    .join(", ")}
            </p>
            <div className="management-actions">
              <button
                className="button primary"
                disabled={!canManage || viewing.read_only}
                onClick={() => edit(viewing)}
              >
                Edit resource
              </button>
              <PromotionButton resource={viewing} />
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
