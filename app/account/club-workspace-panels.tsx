"use client";
import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type FormEvent,
} from "react";
import {
  clubWorkspaceClient,
  calendarDownload,
  type ClubWorkspaceOptions,
} from "../../lib/club-workspace";
import {
  type WorkspaceClient,
  type Page,
  type AccountRow,
  type Resource,
  type Report,
  type Options,
  dateLabel,
} from "../../lib/workspace-api";
import { useWorkspaceList, LibraryManager } from "./owner-management";
import ReportsManager from "./reports-manager";
import { Modal, ErrorNotice, Pagination, Badge } from "./workspace-controls";
type Audience = { team_ids: string[]; role_keys: string[]; user_ids: string[] };
type ClubRecord = Audience & {
  can_edit?: boolean;
  id: string;
  title: string;
  body: string;
  instructions: string;
  notes: string;
  location: string;
  kind: string;
  team_id: string;
  team_name: string;
  starts_at: string;
  ends_at: string;
  timezone: string;
  due_at: string;
  plan_id: string;
  resource_id: string;
  status: string;
  updated_at: string;
  recipient_count: number;
  submission_count: number;
  resource_snapshot?: Resource;
  plan_snapshot?: Resource;
};
type PersonDetail = {
  profile: AccountRow;
  teams: { id: string; name: string; season: string; role_key: string }[];
  reports: Report[];
};
type Attendee = {
  response?: string;
  id: string;
  name: string;
  email: string;
  attendance: string;
  notes: string;
};
type Submission = {
  id: string;
  name: string;
  email: string;
  submission_id: string | null;
  notes: string;
  attachments: { name: string; path: string }[];
  feedback: string;
  review_status: string;
  updated_at: string;
};
type Room = {
  id: string;
  title: string;
  team_id: string | null;
  updated_at: string;
};
type Message = {
  id: string;
  name: string;
  body: string;
  created_at: string;
  user_id: string;
};
const roles = [
  ["club_admin", "Club administrators"],
  ["coach", "Coaches"],
  ["player", "Players"],
];
const blankAudience: Audience = { team_ids: [], role_keys: [], user_ids: [] };
const label = (s: string) => s.replace(/_/g, " ");
const localInput = (s: string) => {
  const d = new Date(s);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
};
function AudienceFields({
  value,
  change,
  options,
  playersOnly = false,
}: {
  value: Audience;
  change: (v: Audience) => void;
  options: ClubWorkspaceOptions;
  playersOnly?: boolean;
}) {
  const toggle = (key: keyof Audience, id: string) =>
    change({
      ...value,
      [key]: value[key].includes(id)
        ? value[key].filter((x) => x !== id)
        : [...value[key], id],
    });
  return (
    <fieldset className="club-audience">
      <legend>Who is this for?</legend>
      {options.workspace_role === "coach" && (
        <p>
          Select at least one of your coaching teams. Choose individual players
          as an additional filter when needed.
        </p>
      )}
      <p>
        {options.workspace_role === "coach" ? (
          "Recipients must belong to the selected teams and match any individual filter."
        ) : (
          <>
            Leave filters empty for{" "}
            {playersOnly ? "all players" : "the whole club"}. When you choose
            more than one filter, recipients must match each filter.
          </>
        )}
      </p>
      <div className="club-form-grid">
        <div>
          <strong>Teams</strong>
          {options.teams.map((t) => (
            <label className="club-check" key={t.id}>
              <input
                type="checkbox"
                checked={value.team_ids.includes(t.id)}
                onChange={() => toggle("team_ids", t.id)}
              />
              {t.name} · {t.season}
            </label>
          ))}
        </div>
        {!playersOnly && options.workspace_role !== "coach" && (
          <div>
            <strong>Roles</strong>
            {roles.map(([key, title]) => (
              <label className="club-check" key={key}>
                <input
                  type="checkbox"
                  checked={value.role_keys.includes(key)}
                  onChange={() => toggle("role_keys", key)}
                />
                {title}
              </label>
            ))}
          </div>
        )}
        <div>
          <strong>Specific people</strong>
          <div className="club-people-select">
            {options.people
              .filter((p) => !playersOnly || p.roles.includes("player"))
              .map((p) => (
                <label className="club-check" key={p.id}>
                  <input
                    type="checkbox"
                    checked={value.user_ids.includes(p.id)}
                    onChange={() => toggle("user_ids", p.id)}
                  />
                  {p.name || p.email}
                </label>
              ))}
          </div>
        </div>
      </div>
    </fieldset>
  );
}
export default function ClubWorkspacePanel({
  clubId,
  section,
  name,
  teamId,
  onChanged,
  mode = "club_admin",
}: {
  mode?: "club_admin" | "coach";
  clubId: string;
  section: string;
  name: string;
  teamId?: string;
  onChanged?: () => void;
}) {
  const request = useMemo(() => clubWorkspaceClient(clubId), [clubId]);
  const [options, setOptions] = useState<ClubWorkspaceOptions | null>(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [template, setTemplate] = useState<
    { key: string; preview: boolean } | undefined
  >();
  useEffect(() => {
    let live = true;
    request<ClubWorkspaceOptions>("options")
      .then((x) => {
        if (live) {
          setOptions(x);
          setError("");
        }
      })
      .catch((e) => {
        if (live) setError(e.message);
      });
    return () => {
      live = false;
    };
  }, [request, revision]);
  const changed = () => {
    onChanged?.();
    setRevision((r) => r + 1);
  };
  if (error)
    return (
      <div className="form-alert" role="alert">
        {error}
        <button onClick={() => setRevision((r) => r + 1)}>Try again</button>
      </div>
    );
  if (!options) return <p role="status">Opening {label(section)}…</p>;
  if (section === "people")
    return <PeoplePanel request={request} teamId={teamId} />;
  if (section === "reports" || template)
    return (
      <div>
        {section === "library" && (
          <button className="text-link" onClick={() => setTemplate(undefined)}>
            ← Back to Development Library
          </button>
        )}
        <ReportsManager
          options={options}
          ownerName={name}
          request={request}
          scopedClub={clubId}
          canCreate={options.permissions.includes("reports.create")}
          onChanged={changed}
          initialTemplate={template}
        />
      </div>
    );
  if (section === "library")
    return (
      <LibraryManager
        options={options}
        request={request}
        scopedClub={clubId}
        mode={mode}
        canManage={options.permissions.includes(
          mode === "coach" ? "library.manage_team" : "library.manage_club",
        )}
        openTemplates={(key, preview) =>
          setTemplate({ key: key || "fitness", preview: !!preview })
        }
      />
    );
  if (section === "settings")
    return (
      <SettingsPanel
        request={request}
        canEdit={options.permissions.includes("clubs.edit")}
        onChanged={changed}
      />
    );
  if (section === "chats")
    return <ChatPanel request={request} options={options} teamId={teamId} />;
  return (
    <RecordsPanel
      request={request}
      options={options}
      section={section}
      teamId={teamId}
      onChanged={changed}
    />
  );
}
export function PeoplePanel({
  request,
  teamId,
}: {
  request: WorkspaceClient;
  teamId?: string;
}) {
  const [filters, setFilters] = useState({
    query: "",
    role: "",
    page: 1,
    team_id: teamId || "",
  });
  const list = useWorkspaceList<AccountRow>("people_list", filters, request);
  const [person, setPerson] = useState<PersonDetail | null>(null);
  const [error, setError] = useState("");
  const [opening, setOpening] = useState(false);
  async function open(id: string) {
    setOpening(true);
    setError("");
    try {
      setPerson(await request<PersonDetail>("person_detail", { id }));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setOpening(false);
    }
  }
  return (
    <section className="owner-panel club-feature">
      <div className="management-toolbar">
        <input
          aria-label="Search club members"
          placeholder="Search name or email"
          value={filters.query}
          onChange={(e) =>
            setFilters({ ...filters, query: e.target.value, page: 1 })
          }
        />
        <select
          aria-label="Filter by role"
          value={filters.role}
          onChange={(e) =>
            setFilters({ ...filters, role: e.target.value, page: 1 })
          }
        >
          <option value="">All approved members</option>
          <option value="member">Awaiting team assignment</option>
          {roles.map(([key, title]) => (
            <option key={key} value={key}>
              {title}
            </option>
          ))}
        </select>
        <button onClick={list.reload}>Refresh</button>
      </div>
      <ErrorNotice error={list.error || error} />

      {list.loading ? (
        <p role="status">Loading people…</p>
      ) : (
        <div className="club-cards">
          {list.data?.items.map((p) => (
            <article className="club-card" key={p.id}>
              <h3>{p.name || "Club member"}</h3>
              <p>{p.email}</p>
              <small>
                {p.roles.map(label).join(" · ") ||
                  "Approved member · no team yet"}
              </small>
              <button
                className="button secondary"
                disabled={opening}
                onClick={() => void open(p.id)}
              >
                Development profile ↗
              </button>
            </article>
          ))}
          {!list.data?.items.length && <p>No matching club members.</p>}
        </div>
      )}
      <Pagination
        page={filters.page}
        total={list.data?.total || 0}
        loading={list.loading}
        change={(page) => setFilters({ ...filters, page })}
      />
      {person && (
        <Modal
          title={person.profile.name || "Development profile"}
          close={() => setPerson(null)}
          wide
          eyebrow="CLUB DEVELOPMENT"
        >
          <p>{person.profile.email}</p>
          <h3>Teams & roles</h3>
          {person.teams.map((t) => (
            <p key={t.id + t.role_key}>
              {t.name} · {t.season} · {label(t.role_key)}
            </p>
          ))}
          <h3>Development over time</h3>
          <ProgressChart
            reports={person.reports}
            subjectId={person.profile.id}
          />
          <h3>Submitted reports</h3>
          {!person.reports.length && (
            <p>No submitted reports visible for this member yet.</p>
          )}
          {person.reports.map((r) => (
            <article className="club-card" key={r.id}>
              <strong>{label(r.template_key)}</strong>
              <p>{dateLabel(r.report_date)}</p>
              <p>
                {r.data.notes?.filter(Boolean).join(" · ") ||
                  "No summary notes."}
              </p>
            </article>
          ))}
        </Modal>
      )}
    </section>
  );
}
export function ProgressChart({
  reports,
  subjectId,
}: {
  reports: Report[];
  subjectId: string;
}) {
  const [metric, setMetric] = useState("ratings");
  const keys = Array.from(
    new Set(reports.flatMap((r) => Object.keys(r.data.metrics || {}))),
  );
  const points = reports
    .map((r) => {
      let value: number | undefined;
      if (metric === "ratings") {
        const values = Object.values(r.data.ratings || {}).filter(
          Number.isFinite,
        );
        value = values.length
          ? values.reduce((a, b) => a + b, 0) / values.length
          : undefined;
      } else if (metric === "match_rating")
        value = r.data.team_ratings?.[subjectId]?.rating;
      else value = r.data.metrics?.[metric];
      return { date: r.report_date, value };
    })
    .filter((p): p is { date: string; value: number } => p.value !== undefined)
    .sort((a, b) => a.date.localeCompare(b.date));
  const max = Math.max(1, ...points.map((p) => p.value));
  const min = Math.min(0, ...points.map((p) => p.value));
  const x = (i: number) => 35 + (i * 530) / Math.max(1, points.length - 1);
  const y = (v: number) => 155 - ((v - min) / (max - min)) * 125;
  return (
    <div className="club-chart">
      <label>
        Measure
        <select value={metric} onChange={(e) => setMetric(e.target.value)}>
          <option value="ratings">Average assessment rating (1–5)</option>
          <option value="match_rating">Match review player rating (1–5)</option>
          {keys.map((k) => (
            <option key={k} value={k}>
              {label(k)}
            </option>
          ))}
        </select>
      </label>
      <p>
        Compare the same measure over time. Assessment averages can cover
        different questions; they are a guide, not an overall player score.
      </p>
      {points.length < 2 ? (
        <p>
          At least two reports with this measure are needed to show a trend.
        </p>
      ) : (
        <>
          <svg
            viewBox="0 0 600 190"
            role="img"
            aria-label={`${label(metric)} over ${points.length} reports`}
          >
            <path d="M35 20V155H580" fill="none" stroke="#b9d5dc" />
            <polyline
              points={points.map((p, i) => `${x(i)},${y(p.value)}`).join(" ")}
              fill="none"
              stroke="#087f9b"
              strokeWidth="3"
            />
            {points.map((p, i) => (
              <circle key={i} cx={x(i)} cy={y(p.value)} r="4" fill="#087f9b">
                <title>
                  {p.date}: {p.value.toFixed(2)}
                </title>
              </circle>
            ))}
          </svg>
          <details>
            <summary>View values</summary>
            {points.map((p, i) => (
              <p key={i}>
                {dateLabel(p.date)}: {p.value.toFixed(2)}
              </p>
            ))}
          </details>
        </>
      )}
    </div>
  );
}
function RecordsPanel({
  request,
  options,
  section,
  teamId,
  onChanged,
}: {
  request: WorkspaceClient;
  options: ClubWorkspaceOptions;
  section: string;
  teamId?: string;
  onChanged: () => void;
}) {
  const calendar = section === "events" || section === "schedule";
  const announcement = section === "announcements";
  const action = calendar
    ? "events_list"
    : announcement
      ? "announcements_list"
      : "homework_list";
  const [filters, setFilters] = useState({
    query: "",
    page: 1,
    kind: section === "events" ? "event" : "",
    team_id: teamId || "",
    from_date: "",
    sessions_only: section === "schedule",
  });
  const list = useWorkspaceList<ClubRecord>(action, filters, request);
  const [editing, setEditing] = useState<ClubRecord | null>(null);
  const [detail, setDetail] = useState<ClubRecord | null>(null);
  const [error, setError] = useState("");
  const canManage = options.permissions.includes(
    calendar
      ? "events.manage"
      : announcement
        ? "announcements.publish"
        : "homework.assign",
  );
  function create() {
    const start = new Date();
    start.setMinutes(0, 0, 0);
    start.setHours(start.getHours() + 1);
    setEditing({
      ...blankAudience,
      id: crypto.randomUUID(),
      title: "",
      body: "",
      instructions: "",
      notes: "",
      location: "",
      kind: section === "events" ? "event" : "training",
      team_id: teamId || "",
      team_name: "",
      starts_at: start.toISOString(),
      ends_at: new Date(+start + 3600000).toISOString(),
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      due_at: new Date(+start + 86400000).toISOString(),
      plan_id: "",
      resource_id: "",
      status: announcement ? "draft" : calendar ? "scheduled" : "active",
      updated_at: "",
      recipient_count: 0,
      submission_count: 0,
    });
  }
  const items = list.data?.items || [];
  return (
    <section className="owner-panel club-feature">
      <div className="management-toolbar">
        <input
          aria-label="Search"
          placeholder={`Search ${label(section)}`}
          value={filters.query}
          onChange={(e) =>
            setFilters({ ...filters, query: e.target.value, page: 1 })
          }
        />
        {calendar && (
          <>
            <select
              aria-label="Team"
              value={filters.team_id}
              disabled={!!teamId}
              onChange={(e) =>
                setFilters({ ...filters, team_id: e.target.value, page: 1 })
              }
            >
              <option value="">All teams</option>
              {options.teams.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name} · {t.season}
                </option>
              ))}
            </select>
            {section === "schedule" && (
              <select
                aria-label="Session type"
                value={filters.kind}
                onChange={(e) =>
                  setFilters({ ...filters, kind: e.target.value, page: 1 })
                }
              >
                <option value="">Training & games</option>
                <option value="training">Training</option>
                <option value="game">Games</option>
              </select>
            )}
            <label>
              From
              <input
                type="date"
                value={filters.from_date}
                onChange={(e) =>
                  setFilters({ ...filters, from_date: e.target.value, page: 1 })
                }
              />
            </label>
          </>
        )}
        <button onClick={list.reload}>Refresh</button>
        {canManage && (
          <button className="button primary" onClick={create}>
            +{" "}
            {calendar
              ? "Schedule " + (section === "events" ? "event" : "session")
              : announcement
                ? "Announcement"
                : "Assign homework"}
          </button>
        )}
      </div>
      <ErrorNotice error={error || list.error} />
      {calendar && (
        <p>
          Times display in your device’s timezone (
          {Intl.DateTimeFormat().resolvedOptions().timeZone}). Training and
          games always belong to a team.
        </p>
      )}
      {list.loading ? (
        <p role="status">Loading…</p>
      ) : (
        <div className="club-cards">
          {items
            .filter((r) => section !== "schedule" || r.kind !== "event")
            .map((r) => (
              <article className="club-card" key={r.id}>
                <div className="club-card-top">
                  <Badge value={r.status} />
                  <small>
                    {calendar
                      ? label(r.kind)
                      : `${r.recipient_count} recipients`}
                  </small>
                </div>
                <h3>{r.title}</h3>
                {calendar ? (
                  <>
                    <strong>{new Date(r.starts_at).toLocaleString()}</strong>
                    <p>
                      {r.team_name || "Club event"} ·{" "}
                      {r.location || "Location to be confirmed"}
                    </p>
                    <p>{r.notes}</p>
                  </>
                ) : announcement ? (
                  <p className="club-preserve">{r.body}</p>
                ) : (
                  <>
                    <p>Due {new Date(r.due_at).toLocaleString()}</p>
                    <p>
                      {r.submission_count} / {r.recipient_count} submitted
                    </p>
                    <p>{r.instructions}</p>
                  </>
                )}
                <div className="club-actions">
                  {calendar && (
                    <button onClick={() => calendarDownload(r)}>
                      Add to calendar
                    </button>
                  )}
                  {(calendar ||
                    (!announcement &&
                      options.permissions.includes("homework.review"))) && (
                    <button onClick={() => setDetail(r)}>
                      {calendar ? "Attendance & details" : "Review submissions"}
                    </button>
                  )}
                  {canManage && r.can_edit !== false && (
                    <button
                      onClick={() => {
                        setError("");
                        setEditing(r);
                      }}
                    >
                      Edit
                    </button>
                  )}
                </div>
              </article>
            ))}
          {!items.length && (
            <div className="owner-empty">
              <h3>No {label(section)} yet.</h3>
              <p>
                {canManage
                  ? "Create the first one for your club."
                  : "Items will appear here when your club adds them."}
              </p>
            </div>
          )}
        </div>
      )}
      <Pagination
        page={filters.page}
        total={list.data?.total || 0}
        loading={list.loading}
        change={(page) => setFilters({ ...filters, page })}
      />
      {editing && (
        <RecordEditor
          record={editing}
          section={section}
          options={options}
          request={request}
          close={() => setEditing(null)}
          saved={() => {
            setEditing(null);
            list.reload();
            onChanged();
          }}
        />
      )}
      {detail && (
        <DetailPanel
          record={detail}
          calendar={calendar}
          request={request}
          canManage={
            calendar
              ? options.permissions.includes("events.manage")
              : options.permissions.includes("homework.review")
          }
          close={() => setDetail(null)}
        />
      )}
    </section>
  );
}
function RecordEditor({
  record,
  section,
  options,
  request,
  close,
  saved,
}: {
  record: ClubRecord;
  section: string;
  options: ClubWorkspaceOptions;
  request: WorkspaceClient;
  close: () => void;
  saved: () => void;
}) {
  const [value, setValue] = useState(record);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [resources, setResources] = useState<Resource[]>([]);
  const calendar = section === "events" || section === "schedule";
  const announcement = section === "announcements";
  useEffect(() => {
    if (announcement || !options.permissions.includes("library.view")) return;
    let live = true;
    request<Page<Resource>>("resources_list", {
      kind: calendar ? "training_plan" : "individual_drill",
      status: "published",
      page: 1,
    })
      .then((p) => {
        if (live) setResources(p.items);
      })
      .catch((e) => {
        if (live) setError(e.message);
      });
    return () => {
      live = false;
    };
  }, [request, calendar, announcement, options.permissions]);
  const patch = (next: Partial<ClubRecord>) =>
    setValue((v) => ({ ...v, ...next }));
  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await request(
        calendar
          ? "event_save"
          : announcement
            ? "announcement_save"
            : "homework_save",
        {
          ...value,
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          plan_id: value.plan_id || null,
          resource_id: value.resource_id || null,
        },
      );
      saved();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title={`${record.updated_at ? "Edit" : "Create"} ${calendar ? (section === "events" ? "event" : "session") : announcement ? "announcement" : "homework"}`}
      close={close}
      busy={busy}
      wide
      eyebrow={
        options.workspace_role === "coach" ? "COACH" : "CLUB ADMINISTRATOR"
      }
    >
      <form onSubmit={save}>
        <fieldset disabled={busy} className="club-editor">
          <label>
            Title
            <input
              required
              maxLength={160}
              value={value.title}
              onChange={(e) => patch({ title: e.target.value })}
            />
          </label>
          {calendar ? (
            <>
              <div className="club-form-grid">
                {section === "schedule" && (
                  <>
                    <label>
                      Type
                      <select
                        value={value.kind}
                        onChange={(e) => patch({ kind: e.target.value })}
                      >
                        <option value="training">Training</option>
                        <option value="game">Game</option>
                      </select>
                    </label>
                    <label>
                      Team
                      <select
                        required
                        value={value.team_id}
                        onChange={(e) => patch({ team_id: e.target.value })}
                      >
                        <option value="">Choose team</option>
                        {options.teams.map((t) => (
                          <option key={t.id} value={t.id}>
                            {t.name} · {t.season}
                          </option>
                        ))}
                      </select>
                    </label>
                  </>
                )}
                <label>
                  Starts
                  <input
                    type="datetime-local"
                    required
                    value={localInput(value.starts_at)}
                    onChange={(e) => {
                      if (e.target.value)
                        patch({
                          starts_at: new Date(e.target.value).toISOString(),
                        });
                    }}
                  />
                </label>
                <label>
                  Ends
                  <input
                    type="datetime-local"
                    required
                    min={localInput(value.starts_at)}
                    value={localInput(value.ends_at)}
                    onChange={(e) => {
                      if (e.target.value)
                        patch({
                          ends_at: new Date(e.target.value).toISOString(),
                        });
                    }}
                  />
                </label>
              </div>
              <p>
                Enter times in your device timezone:{" "}
                {Intl.DateTimeFormat().resolvedOptions().timeZone}.
              </p>
              <label>
                Location
                <input
                  maxLength={240}
                  value={value.location}
                  onChange={(e) => patch({ location: e.target.value })}
                />
              </label>
              <label>
                Notes
                <textarea
                  maxLength={6000}
                  rows={4}
                  value={value.notes}
                  onChange={(e) => patch({ notes: e.target.value })}
                />
              </label>
              {section === "schedule" && (
                <label>
                  Training plan
                  <select
                    value={value.plan_id || ""}
                    onChange={(e) => patch({ plan_id: e.target.value })}
                  >
                    <option value="">No plan</option>
                    {resources
                      .filter((r) => !r.team_id || r.team_id === value.team_id)
                      .map((r) => (
                        <option key={r.id} value={r.id}>
                          {r.title} ·{" "}
                          {r.plan_blocks?.reduce((a, b) => a + b.minutes, 0) ||
                            0}{" "}
                          min
                        </option>
                      ))}
                  </select>
                  <small>
                    Published training plans only. The first 20 appear here; use
                    the library to manage them.
                  </small>
                </label>
              )}
              <label>
                Status
                <select
                  value={value.status}
                  onChange={(e) => patch({ status: e.target.value })}
                >
                  <option value="scheduled">Scheduled</option>
                  <option value="cancelled">Cancelled</option>
                </select>
              </label>
            </>
          ) : announcement ? (
            <>
              <label>
                Message
                <textarea
                  required
                  rows={7}
                  maxLength={6000}
                  value={value.body}
                  onChange={(e) => patch({ body: e.target.value })}
                />
              </label>
              <label>
                Status
                <select
                  value={value.status}
                  onChange={(e) => patch({ status: e.target.value })}
                >
                  <option value="draft">Draft</option>
                  <option value="published">Published</option>
                  <option value="archived">Archived</option>
                </select>
              </label>
            </>
          ) : (
            <>
              <label>
                Individual drill
                <select
                  value={value.resource_id || ""}
                  onChange={(e) => patch({ resource_id: e.target.value })}
                >
                  <option value="">Custom assignment</option>
                  {resources
                    .filter(
                      (r) =>
                        !r.team_id ||
                        (value.team_ids.length === 1 &&
                          r.team_id === value.team_ids[0]),
                    )
                    .map((r) => (
                      <option key={r.id} value={r.id}>
                        {r.title} · {r.duration_minutes || "—"} min
                      </option>
                    ))}
                </select>
                <small>
                  Published individual drills only. The first 20 appear here.
                </small>
              </label>
              <label>
                Instructions
                <textarea
                  rows={5}
                  maxLength={6000}
                  value={value.instructions}
                  onChange={(e) => patch({ instructions: e.target.value })}
                />
              </label>
              <label>
                Due
                <input
                  type="datetime-local"
                  required
                  value={localInput(value.due_at)}
                  onChange={(e) => {
                    if (e.target.value)
                      patch({ due_at: new Date(e.target.value).toISOString() });
                  }}
                />
              </label>
              <label>
                Status
                <select
                  value={value.status}
                  onChange={(e) => patch({ status: e.target.value })}
                >
                  <option value="active">Active</option>
                  <option value="archived">Archived</option>
                </select>
              </label>
            </>
          )}
          {(!calendar || section === "events") && (
            <AudienceFields
              value={value}
              change={patch}
              options={options}
              playersOnly={!calendar && !announcement}
            />
          )}
          <ErrorNotice error={error} />
          <div className="club-actions">
            <button type="button" onClick={close}>
              Cancel
            </button>
            <button className="button primary" type="submit">
              {busy ? "Saving…" : "Save"}
            </button>
          </div>
        </fieldset>
      </form>
    </Modal>
  );
}
export function DetailPanel({
  record,
  calendar,
  request,
  canManage,
  close,
}: {
  record: ClubRecord;
  calendar: boolean;
  request: WorkspaceClient;
  canManage: boolean;
  close: () => void;
}) {
  const [data, setData] = useState<
    (ClubRecord & { attendees: Attendee[]; players: Submission[] }) | null
  >(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    request<ClubRecord & { attendees: Attendee[]; players: Submission[] }>(
      calendar ? "event_detail" : "homework_detail",
      { id: record.id },
    )
      .then((x) => {
        if (live) setData(x);
      })
      .catch((e) => {
        if (live) setError(e.message);
      });
    return () => {
      live = false;
    };
  }, [request, record.id, calendar, revision]);
  async function mark(p: Attendee, status: string) {
    if (!status) return;
    setBusy(true);
    setError("");
    try {
      await request("attendance_save", {
        event_id: record.id,
        user_id: p.id,
        status,
        notes: p.notes || "",
      });
      setRevision((r) => r + 1);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function review(p: Submission, e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const f = new FormData(e.currentTarget);
    try {
      await request("homework_review", {
        id: p.submission_id,
        updated_at: p.updated_at,
        feedback: f.get("feedback"),
        review_status: f.get("review_status"),
      });
      setRevision((r) => r + 1);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function file(p: Submission, path: string) {
    setBusy(true);
    setError("");
    try {
      const { url } = await request<{ url: string }>("file_access", {
        submission_id: p.submission_id,
        path,
      });
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal
      title={record.title}
      close={close}
      busy={busy}
      wide
      eyebrow={calendar ? "EVENT ATTENDANCE" : "HOMEWORK REVIEW"}
    >
      <ErrorNotice error={error} />
      {!data ? (
        <p role="status">Loading details…</p>
      ) : (
        <>
          {data.plan_snapshot && (
            <section className="club-card">
              <h3>{data.plan_snapshot.title}</h3>
              {data.plan_snapshot.plan_blocks?.map((b) => (
                <p key={b.id}>
                  {b.title} · {b.minutes} min
                </p>
              ))}
            </section>
          )}
          {calendar ? (
            <>
              <h3>{data.attendees.length} attendees</h3>
              {data.attendees.map((p) => (
                <article className="club-attendee" key={p.id}>
                  <span>
                    <strong>{p.name || p.email}</strong>
                    <small>{p.email}</small>
                    <small>
                      Availability:{" "}
                      {p.response === "attending"
                        ? "Attending"
                        : p.response === "declined"
                          ? "Unavailable"
                          : "Awaiting response"}
                    </small>
                  </span>
                  <select
                    aria-label={`Attendance for ${p.name}`}
                    disabled={busy || !canManage}
                    value={p.attendance || ""}
                    onChange={(e) => void mark(p, e.target.value)}
                  >
                    <option value="">Not marked</option>
                    {["present", "absent", "late", "excused"].map((s) => (
                      <option key={s}>{s}</option>
                    ))}
                  </select>
                </article>
              ))}
            </>
          ) : (
            <>
              <h3>Player submissions</h3>
              {data.resource_snapshot && (
                <p>
                  Drill: {data.resource_snapshot.title} ·{" "}
                  {data.resource_snapshot.duration_minutes || "—"} min
                </p>
              )}
              {data.players.map((p) => (
                <article className="club-card" key={p.id}>
                  <h3>{p.name || p.email}</h3>
                  {!p.submission_id ? (
                    <p>Awaiting submission</p>
                  ) : (
                    <>
                      <Badge value={p.review_status} />
                      <p>{p.notes}</p>
                      <div className="club-actions">
                        {p.attachments.map((a) => (
                          <button
                            key={a.path}
                            disabled={busy}
                            onClick={() => void file(p, a.path)}
                          >
                            Open {a.name || "uploaded file"} ↗
                          </button>
                        ))}
                      </div>
                      <form onSubmit={(e) => void review(p, e)}>
                        <label>
                          Feedback
                          <textarea
                            name="feedback"
                            rows={3}
                            maxLength={6000}
                            defaultValue={p.feedback}
                            key={p.updated_at}
                          />
                        </label>
                        <select
                          name="review_status"
                          defaultValue={p.review_status}
                        >
                          <option value="submitted">Awaiting review</option>
                          <option value="reviewed">Reviewed</option>
                          <option value="resubmit">
                            Request another attempt
                          </option>
                        </select>
                        <button disabled={busy || !canManage}>
                          Save feedback
                        </button>
                      </form>
                    </>
                  )}
                </article>
              ))}
            </>
          )}
        </>
      )}
    </Modal>
  );
}
export function ChatPanel({
  request,
  options,
  teamId,
  canOpenTeamChat = false,
}: {
  request: WorkspaceClient;
  options: ClubWorkspaceOptions;
  teamId?: string;
  canOpenTeamChat?: boolean;
}) {
  const [rooms, setRooms] = useState<Room[]>([]);
  const [selected, setSelected] = useState("");
  const [messages, setMessages] = useState<Message[]>([]);
  const [members, setMembers] = useState<string[]>([]);
  const [page, setPage] = useState(1);
  const [more, setMore] = useState(false);
  const [body, setBody] = useState("");
  const [editing, setEditing] = useState<
    (Room & { user_ids: string[] }) | null
  >(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const canManage = options.permissions.includes("chats.manage");
  useEffect(() => {
    let live = true;
    (async () => {
      if (teamId && (canManage || canOpenTeamChat)) {
        const room = await request<Room>("team_chat", { team_id: teamId });
        if (live) setSelected(room.id);
      }
      const x = await request<Room[]>("rooms_list");
      if (live) setRooms(x);
    })().catch((e) => {
      if (live) setError(e.message);
    });
    return () => {
      live = false;
    };
  }, [request, teamId, canManage, canOpenTeamChat, revision]);
  useEffect(() => {
    if (!selected) return;
    let live = true;
    async function load() {
      try {
        const data = await request<{
          items: Message[];
          members: string[];
          has_more: boolean;
        }>("room_messages", { room_id: selected, page });
        if (live) {
          setMessages(data.items);
          setMembers(data.members);
          setMore(data.has_more);
          setError("");
        }
      } catch (e) {
        if (live) setError((e as Error).message);
      }
    }
    void load();
    const timer = setInterval(() => {
      if (document.visibilityState === "visible") void load();
    }, 5000);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [selected, request, page, revision]);
  async function send(e: FormEvent) {
    e.preventDefault();
    if (!body.trim() || busy) return;
    setBusy(true);
    try {
      await request("send_message", {
        id: crypto.randomUUID(),
        room_id: selected,
        body,
      });
      setBody("");
      setPage(1);
      setRevision((r) => r + 1);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!editing) return;
    setBusy(true);
    setError("");
    try {
      const room = await request<Room>("room_save", editing);
      setSelected(room.id);
      setPage(1);
      setEditing(null);
      setRevision((r) => r + 1);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  const current = rooms.find((r) => r.id === selected);
  return (
    <section className="owner-panel club-feature">
      <div className="management-toolbar">
        <h2>{teamId ? "Team conversation" : "Club conversations"}</h2>
        {canManage && !teamId && (
          <button
            className="button primary"
            onClick={() =>
              setEditing({
                id: crypto.randomUUID(),
                title: "",
                team_id: null,
                updated_at: "",
                user_ids: [],
              })
            }
          >
            + Group chat
          </button>
        )}
        <button onClick={() => setRevision((r) => r + 1)}>Refresh</button>
      </div>
      <ErrorNotice error={error} />
      <div className="club-chat-layout">
        <nav aria-label="Conversations">
          {rooms
            .filter((r) => !teamId || r.team_id === teamId)
            .map((r) => (
              <button
                className={selected === r.id ? "selected" : ""}
                key={r.id}
                onClick={() => {
                  setMessages([]);
                  setSelected(r.id);
                  setPage(1);
                }}
              >
                {r.title}
              </button>
            ))}
          {!rooms.length && <p>No conversations yet.</p>}
        </nav>
        <div>
          {selected ? (
            <>
              <div className="club-card-top">
                <h3>{current?.title || "Conversation"}</h3>
                {current && !current.team_id && canManage && (
                  <button
                    onClick={() =>
                      setEditing({ ...current, user_ids: members })
                    }
                  >
                    Edit group
                  </button>
                )}
              </div>
              <div className="club-messages" role="log" aria-label="Messages">
                {messages.map((m) => (
                  <article key={m.id}>
                    <strong>{m.name || "Club member"}</strong>
                    <time>{new Date(m.created_at).toLocaleString()}</time>
                    <p className="club-preserve">{m.body}</p>
                  </article>
                ))}
                {!messages.length && <p>No messages on this page.</p>}
              </div>
              <div className="club-actions">
                <button
                  disabled={page === 1}
                  onClick={() => setPage((p) => p - 1)}
                >
                  Newer
                </button>
                <span>Page {page}</span>
                <button disabled={!more} onClick={() => setPage((p) => p + 1)}>
                  Older
                </button>
              </div>
              <form className="club-message-form" onSubmit={send}>
                <label className="sr-only" htmlFor="club-message">
                  Message
                </label>
                <textarea
                  id="club-message"
                  required
                  maxLength={4000}
                  value={body}
                  onChange={(e) => setBody(e.target.value)}
                  placeholder="Write a message…"
                />
                <button
                  className="button primary"
                  disabled={busy || !body.trim()}
                >
                  Send
                </button>
              </form>
              <small>
                Messages refresh every 5 seconds while this tab is visible.
              </small>
            </>
          ) : (
            <p>Select a conversation.</p>
          )}
        </div>
      </div>
      {editing && (
        <Modal
          title={editing.updated_at ? "Edit group" : "New group chat"}
          close={() => setEditing(null)}
          busy={busy}
          eyebrow="CLUB CONVERSATION"
        >
          <form onSubmit={save}>
            <label>
              Group name
              <input
                required
                maxLength={160}
                value={editing.title}
                onChange={(e) =>
                  setEditing({ ...editing, title: e.target.value })
                }
              />
            </label>
            <h3>Choose approved club members</h3>
            <div className="club-people-select">
              {options.people.map((p) => (
                <label className="club-check" key={p.id}>
                  <input
                    type="checkbox"
                    checked={editing.user_ids.includes(p.id)}
                    onChange={() =>
                      setEditing({
                        ...editing,
                        user_ids: editing.user_ids.includes(p.id)
                          ? editing.user_ids.filter((id) => id !== p.id)
                          : [...editing.user_ids, p.id],
                      })
                    }
                  />
                  {p.name || p.email} · {p.roles.map(label).join(", ")}
                </label>
              ))}
            </div>
            <p>Your account is included automatically.</p>
            <ErrorNotice error={error} />
            <button className="button primary" disabled={busy}>
              Save group
            </button>
          </form>
        </Modal>
      )}
    </section>
  );
}
function SettingsPanel({
  request,
  canEdit,
  onChanged,
}: {
  request: WorkspaceClient;
  canEdit: boolean;
  onChanged: () => void;
}) {
  const [data, setData] = useState<Record<string, string> | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    request<Record<string, string>>("settings_get")
      .then((x) => {
        if (live) {
          setData(x);
          setError("");
        }
      })
      .catch((e) => {
        if (live) setError(e.message);
      });
    return () => {
      live = false;
    };
  }, [request, revision]);
  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    setNotice("");
    try {
      setData(await request("settings_save", data!));
      setNotice("Club details saved.");
      onChanged();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="owner-panel club-feature">
      <h2>Club details</h2>
      <ErrorNotice error={error} />
      {notice && <p role="status">{notice}</p>}
      {!data ? (
        <p>Loading…</p>
      ) : (
        <form onSubmit={save}>
          <fieldset disabled={busy || !canEdit} className="club-editor">
            <div className="club-form-grid">
              {[
                ["name", "Club name"],
                ["sport", "Sport"],
                ["league", "League"],
                ["city", "City"],
                ["state", "State"],
                ["country", "Country"],
                ["contact_email", "Contact email"],
                ["contact_number", "Contact number"],
              ].map(([key, title]) => (
                <label key={key}>
                  {title}
                  <input
                    required
                    type={
                      key === "contact_email"
                        ? "email"
                        : key === "contact_number"
                          ? "tel"
                          : "text"
                    }
                    maxLength={key === "contact_email" ? 254 : 180}
                    value={data[key] || ""}
                    onChange={(e) =>
                      setData({ ...data, [key]: e.target.value })
                    }
                  />
                </label>
              ))}
            </div>
            <label>
              Description
              <textarea
                rows={5}
                maxLength={2000}
                value={data.description || ""}
                onChange={(e) =>
                  setData({ ...data, description: e.target.value })
                }
              />
            </label>
            <button className="button primary">
              {busy ? "Saving…" : "Save details"}
            </button>
          </fieldset>
          {!canEdit && (
            <p>
              Your role can view these details. Ask the PFD Owner for edit
              access.
            </p>
          )}
        </form>
      )}
      <button
        className="text-link"
        disabled={busy}
        onClick={() => setRevision((r) => r + 1)}
      >
        Reload saved details
      </button>
    </section>
  );
}
