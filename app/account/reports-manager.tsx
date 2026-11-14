"use client";
import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import {
  dateLabel,
  localDate,
  workspaceRequest,
  type Options,
  type Report,
  type ReportData,
  type Template,
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
import {
  StructuredReportFields,
  TeamPlayerRatings,
} from "./structured-report-fields";
import { useWorkspaceList } from "./owner-management";
const fitnessFields = [
  ["sprint10", "10 m sprint (seconds)"],
  ["sprint30", "30 m sprint (seconds)"],
  ["agility", "Agility test & result"],
  ["endurance", "Endurance test & result"],
  ["jump", "Standing broad jump (cm)"],
  ["effort", "Player-reported effort (0–10)"],
];
const newData = (preparedBy: string): ReportData => ({
  info: {
    name: "",
    age: "",
    team: "",
    date: localDate(),
    position: "",
    foot: "",
  },
  ratings: {},
  progress: {},
  values: {},
  extra: {},
  notes: ["", "", "", ""],
  prepared_by: preparedBy,
  reviewer: "",
  review_date: "",
  consent: false,
  metrics: {},
  team_ratings: {},
});
const blankReport = (
  key: string,
  definition: Template["definition"],
  preparedBy: string,
): Report => ({
  id: crypto.randomUUID(),
  subject_id: "",
  club_id: null,
  team_id: null,
  template_key: key,
  template_snapshot: definition,
  report_date: localDate(),
  status: "draft",
  data: newData(preparedBy),
  updated_at: "",
});
export default function ReportsManager({
  options,
  ownerName,
  initialReport,
  onChanged,
  initialTemplate,
  request = workspaceRequest,
  scopedClub,
  canCreate = true,
  selfSubject,
  selfTemplates,
}: {
  options: Options;
  selfSubject?: { id: string; name: string };
  selfTemplates?: string[];
  request?: WorkspaceClient;
  scopedClub?: string;
  canCreate?: boolean;
  ownerName: string;
  initialReport?: string;
  initialTemplate?: { key: string; preview: boolean };
  onChanged: () => void;
}) {
  const [filters, setFilters] = useState({
    query: "",
    template_key: "",
    club_id: "",
    team_id: "",
    status: "",
    from_date: "",
    to_date: "",
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
  const { data, loading, error, reload } = useWorkspaceList<Report>(
    "reports_list",
    filters,
    request,
  );
  const [report, setReport] = useState<Report | null>(null);
  const [preview, setPreview] = useState(false);
  const [activeCategory, setActiveCategory] = useState("");
  const [busy, setBusy] = useState(false);
  const [saveError, setSaveError] = useState("");
  const [notice, setNotice] = useState("");
  const [opening, setOpening] = useState(false);
  const dirty = useRef(false);
  const readOnly =
    preview || !!report?.read_only || report?.status !== "draft" || !canCreate;
  async function open(id: string) {
    setOpening(true);
    setSaveError("");
    try {
      const r = await request<Report>("report_get", { id });
      setReport(r);
      setPreview(false);
      setActiveCategory(Object.keys(r.template_snapshot.categories)[0]);
      dirty.current = false;
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Unable to open report.");
    } finally {
      setOpening(false);
    }
  }
  useEffect(() => {
    if (initialReport) void open(initialReport);
  }, [initialReport]);
  useEffect(() => {
    if (!report) return;
    const warn = (e: BeforeUnloadEvent) => {
      if (dirty.current) e.preventDefault();
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [report]);
  function start(template: Template, isPreview = false) {
    setReport({
      ...blankReport(template.key, template.definition, ownerName),
      club_id: scopedClub || null,
      subject_id: selfSubject?.id || "",
      team_id:
        selfSubject && options.teams.length === 1 ? options.teams[0].id : null,
      data: {
        ...newData(ownerName),
        ...(selfSubject
          ? {
              entry_kind: "self_assessment",
              info: {
                ...newData(ownerName).info,
                name: selfSubject.name,
                team: options.teams.length === 1 ? options.teams[0].name : "",
              },
            }
          : {}),
        subject_kind: template.key === "coaches" ? "coach" : "player",
      },
    });
    setPreview(isPreview);
    setSaveError("");
    setActiveCategory(Object.keys(template.definition.categories)[0]);
    dirty.current = false;
  }
  useEffect(() => {
    if (initialTemplate) {
      const t = options.templates.find((t) => t.key === initialTemplate.key);
      if (t) start(t, initialTemplate.preview);
    }
  }, [initialTemplate?.key, initialTemplate?.preview]);
  function patchData(values: Partial<ReportData>) {
    dirty.current = true;
    setReport((r) => r && { ...r, data: { ...r.data, ...values } });
  }
  function patch(values: Partial<Report>) {
    dirty.current = true;
    setReport((r) => r && { ...r, ...values });
  }
  function close() {
    if (
      !dirty.current ||
      window.confirm("Discard your unsaved report changes?")
    )
      setReport(null);
  }
  async function save(status: "draft" | "submitted") {
    if (!report || busy || readOnly) return;
    setBusy(true);
    setSaveError("");
    try {
      const next = await request<Report>("report_save", {
        ...report,
        status,
        data: {
          ...report.data,
          info: { ...report.data.info, date: report.report_date },
        },
      });
      dirty.current = false;
      setReport(next);
      setNotice(
        status === "submitted"
          ? "Report submitted and saved to the linked account."
          : "Draft saved to PFD.",
      );
      reload();
      onChanged();
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Unable to save report.");
    } finally {
      setBusy(false);
    }
  }
  const average = useMemo(() => {
    const values = Object.values(report?.data.ratings || {}).filter(
      (n) => n >= 1 && n <= 5,
    );
    return {
      count: values.length,
      value: values.length
        ? (values.reduce((a, b) => a + b, 0) / values.length).toFixed(1)
        : "—",
    };
  }, [report]);
  function originalField(
    key: string,
    label: string,
    type = "text",
    area: "info" | "extra" = "info",
  ) {
    if (!report) return null;
    const value = report.data[area][key] || "";
    return (
      <label key={key}>
        {label}
        <input
          type={type}
          maxLength={250}
          value={key === "date" ? report.report_date : value}
          readOnly={readOnly || (!!selfSubject && key === "name")}
          disabled={busy}
          onChange={(e) => {
            if (key === "date") patch({ report_date: e.target.value });
            else
              patchData({
                [area]: { ...report.data[area], [key]: e.target.value },
              });
          }}
        />
        <span className="report-print-value">
          {key === "date" ? dateLabel(report.report_date) : value || "—"}
        </span>
      </label>
    );
  }
  return (
    <div className="management-section">
      <div className="management-toolbar">
        <div>
          <h2>Every assessment. A clearer picture.</h2>
          <p>{data.submitted ?? 0} submitted reports · assessment templates.</p>
        </div>
        <button className="owner-refresh" disabled={loading} onClick={reload}>
          Refresh reports
        </button>
      </div>
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
            <div>
              <button
                className="management-link"
                onClick={() => start(t, true)}
              >
                Preview
              </button>
              <button
                className="owner-refresh"
                disabled={
                  !canCreate ||
                  (!!selfTemplates && !selfTemplates.includes(t.key))
                }
                onClick={() => start(t)}
              >
                Create report ↗
              </button>
            </div>
          </article>
        ))}
      </div>
      <div className="management-filters">
        <label>
          Search
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Account name, email or club"
          />
        </label>
        <label>
          Report type
          <select
            value={filters.template_key}
            onChange={(e) =>
              setFilters((f) => ({
                ...f,
                template_key: e.target.value,
                page: 1,
              }))
            }
          >
            <option value="">All report types</option>
            {options.templates.map((t) => (
              <option key={t.key} value={t.key}>
                {t.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          Club
          <select
            value={filters.club_id}
            onChange={(e) =>
              setFilters((f) => ({
                ...f,
                club_id: e.target.value,
                team_id: "",
                page: 1,
              }))
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
        <label>
          Team
          <select
            value={filters.team_id}
            onChange={(e) =>
              setFilters((f) => ({ ...f, team_id: e.target.value, page: 1 }))
            }
          >
            <option value="">All teams</option>
            {options.teams
              .filter((t) => !filters.club_id || t.club_id === filters.club_id)
              .map((t) => (
                <option value={t.id} key={t.id}>
                  {t.name}
                </option>
              ))}
          </select>
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
            <option>draft</option>
            <option>submitted</option>
          </select>
        </label>
        <label>
          From
          <input
            type="date"
            value={filters.from_date}
            onChange={(e) =>
              setFilters((f) => ({ ...f, from_date: e.target.value, page: 1 }))
            }
          />
        </label>
        <label>
          To
          <input
            type="date"
            value={filters.to_date}
            min={filters.from_date}
            onChange={(e) =>
              setFilters((f) => ({ ...f, to_date: e.target.value, page: 1 }))
            }
          />
        </label>
      </div>
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      <ErrorNotice error={error} retry={reload} />
      {!report && <ErrorNotice error={saveError} />}
      {opening && <p role="status">Opening report…</p>}
      <section className="owner-panel">
        {loading ? (
          <p role="status" className="owner-loading">
            Loading reports…
          </p>
        ) : data.items.length ? (
          <div className="owner-table-scroll" tabIndex={0} aria-label="Reports">
            <table className="owner-table">
              <thead>
                <tr>
                  <th>Subject</th>
                  <th>Report</th>
                  <th>Club / team</th>
                  <th>Date</th>
                  <th>Submitted by</th>
                  <th>Status</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {data.items.map((r) => (
                  <tr key={r.id}>
                    <td>
                      <strong>{r.subject_name || "Name not provided"}</strong>
                      <span>{r.subject_email}</span>
                    </td>
                    <td>
                      {
                        options.templates.find((t) => t.key === r.template_key)
                          ?.label
                      }
                      {r.entry_kind === "self_assessment" && (
                        <Badge value="self_assessment" />
                      )}
                    </td>
                    <td>
                      <strong>{r.club_name || "Independent assessment"}</strong>
                      <span>{r.team_name}</span>
                    </td>
                    <td>{dateLabel(r.report_date)}</td>
                    <td>{r.author_name || "PFD Owner"}</td>
                    <td>
                      <Badge value={r.status} />
                    </td>
                    <td>
                      <button
                        className="management-link"
                        disabled={opening}
                        onClick={() => void open(r.id)}
                      >
                        {r.status === "draft"
                          ? "Continue draft"
                          : "View report"}{" "}
                        ↗
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
              title="Development starts with an observation."
              text="Create an assessment using a PFD template. Saved reports will appear here."
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
      {report && (
        <Modal
          title={
            preview
              ? "Preview · " + report.template_snapshot.short
              : report.template_snapshot.title
          }
          eyebrow={
            scopedClub
              ? options.workspace_role === "player"
                ? "PLAYER"
                : options.workspace_role === "coach"
                  ? "COACH"
                  : "CLUB ADMINISTRATOR"
              : "PFD OWNER"
          }
          close={close}
          busy={busy}
          wide
        >
          <div className="report-editor">
            <div className="report-heading">
              <div>
                <span className="eyebrow">PLAYER FOCUSED DEVELOPMENT</span>
                <h2>{report.template_snapshot.intro}</h2>
                <p>{report.template_snapshot.desc}</p>
                {report.data.entry_kind === "self_assessment" && (
                  <Badge value="self_assessment" />
                )}
              </div>
              {Object.keys(report.template_snapshot.categories).length > 0 && (
                <>
                  <div className="report-score">
                    <strong>{average.value}</strong>
                    <span>{average.count} observed ratings · / 5</span>
                  </div>
                </>
              )}
            </div>
            {preview && (
              <p className="permission-note">
                Template preview. Unobserved items stay blank; no report is
                saved.
              </p>
            )}
            {!preview && report.status !== "draft" && (
              <p className="permission-note">
                Submitted report · read-only record. Create a new assessment to
                record future progress.
              </p>
            )}
            <form
              className="management-form"
              onSubmit={(e: FormEvent) => {
                e.preventDefault();
                void save("submitted");
              }}
            >
              {!preview && (
                <section className="report-section report-context">
                  <h3>
                    <span>01</span>
                    {report.template_snapshot.team_report
                      ? "Club & team record"
                      : "Account & club record"}
                  </h3>
                  {!selfSubject && !report.template_snapshot.team_report && (
                    <>
                      {report.template_key === "coaches" && (
                        <label className="management-label">
                          This Coaches report belongs to
                          <select
                            value={report.data.subject_kind || "coach"}
                            disabled={readOnly || busy}
                            onChange={(e) => {
                              patch({ subject_id: "" });
                              patchData({
                                subject_kind: e.target.value as
                                  | "coach"
                                  | "player",
                                info: { ...report.data.info, name: "" },
                              });
                            }}
                          >
                            <option value="coach">A coach</option>
                            <option value="player">A player</option>
                          </select>
                        </label>
                      )}
                      <AccountPicker
                        request={request}
                        role={
                          scopedClub
                            ? report.data.subject_kind ||
                              (report.template_key === "coaches"
                                ? "coach"
                                : "player")
                            : undefined
                        }
                        value={report.subject_id || ""}
                        label={report.data.info.name}
                        disabled={readOnly || busy}
                        select={(id, name) => {
                          patch({ subject_id: id });
                          patchData({ info: { ...report.data.info, name } });
                        }}
                      />
                    </>
                  )}
                  {selfSubject && (
                    <p>
                      Saved under your account:{" "}
                      <strong>{selfSubject.name}</strong>
                    </p>
                  )}
                  <ClubTeamFields
                    teamRequired={!!selfSubject}
                    options={options}
                    required={!!scopedClub}
                    club={report.club_id || ""}
                    team={report.team_id || ""}
                    disabled={readOnly || busy}
                    change={(c, t) => {
                      patch({ club_id: c || null, team_id: t || null });
                      patchData({
                        team_ratings: {},
                        info: {
                          ...report.data.info,
                          ...(report.template_snapshot.team_report
                            ? {
                                name:
                                  options.teams.find((x) => x.id === t)?.name ||
                                  "",
                              }
                            : {}),
                          team:
                            options.teams.find((x) => x.id === t)?.name ||
                            report.data.info.team,
                        },
                      });
                    }}
                  />
                </section>
              )}
              <section className="report-section">
                <h3>
                  <span>{preview ? "01" : "02"}</span>Report details
                </h3>
                <div className="management-form-grid">
                  {report.template_snapshot.fields ? (
                    <StructuredReportFields
                      fields={report.template_snapshot.fields}
                      report={report}
                      readOnly={readOnly}
                      busy={busy}
                      change={patchData}
                      date={(value) => patch({ report_date: value })}
                    />
                  ) : (
                    <>
                      {(report.template_key === "coaches"
                        ? [
                            ["name", "Coach being reviewed *"],
                            ["team", "Team / age group"],
                            ["date", "Session / review date"],
                            ["session", "Session topic"],
                            ["location", "Location"],
                            ["duration", "Session duration"],
                          ]
                        : [
                            ["name", "Player name *"],
                            ["age", "Age"],
                            ["team", "Team / age group"],
                            ["date", "Report date"],
                            ["position", "Position"],
                            ["foot", "Dominant foot"],
                            ...(report.template_key === "parent"
                              ? [
                                  ["parent", "Parent / carer name"],
                                  ["email", "Contact email (optional)"],
                                ]
                              : []),
                          ]
                      ).map(([key, label]) =>
                        originalField(
                          key,
                          label,
                          key === "date"
                            ? "date"
                            : key === "email"
                              ? "email"
                              : "text",
                        ),
                      )}
                    </>
                  )}
                </div>
              </section>
              {Object.keys(report.template_snapshot.categories).length > 0 && (
                <>
                  <section className="report-section">
                    <h3>
                      <span>{preview ? "02" : "03"}</span>Assessment
                    </h3>
                    <div
                      className="report-category-tabs"
                      role="group"
                      aria-label="Assessment categories"
                    >
                      {Object.keys(report.template_snapshot.categories).map(
                        (c) => (
                          <button
                            type="button"
                            key={c}
                            aria-pressed={activeCategory === c}
                            onClick={() => setActiveCategory(c)}
                          >
                            {c}
                          </button>
                        ),
                      )}
                    </div>
                    <p className="management-footnote">
                      {report.template_key === "parent"
                        ? "1 Strongly disagree · 3 Neutral · 5 Strongly agree"
                        : "1 Needs support · 3 Consistent · 5 Excellent"}{" "}
                      · Leave unobserved items blank.
                    </p>
                    {Object.entries(report.template_snapshot.categories).map(
                      ([category, questions]) => (
                        <section
                          key={category}
                          className={
                            "report-assessment-group" +
                            (activeCategory !== category
                              ? " report-category-hidden"
                              : "")
                          }
                        >
                          <h4>{category}</h4>
                          {questions.map((question, i) => {
                            const key = category + "-" + i;
                            const scale =
                              report.template_key === "parent"
                                ? [
                                    "Strongly disagree",
                                    "Disagree",
                                    "Neutral",
                                    "Agree",
                                    "Strongly agree",
                                  ]
                                : [
                                    "Needs support",
                                    "Developing",
                                    "Consistent",
                                    "Strong",
                                    "Excellent",
                                  ];
                            return (
                              <div className="report-question" key={key}>
                                <p>
                                  <small>
                                    {String(i + 1).padStart(2, "0")}
                                  </small>
                                  {question}
                                </p>
                                <div
                                  className="report-rating"
                                  role="radiogroup"
                                  aria-label={question}
                                >
                                  {[1, 2, 3, 4, 5].map((n) => (
                                    <label key={n}>
                                      <input
                                        type="radio"
                                        name={key}
                                        value={n}
                                        checked={report.data.ratings[key] === n}
                                        disabled={readOnly || busy}
                                        aria-label={`${n} ${scale[n - 1]}`}
                                        onChange={() =>
                                          patchData({
                                            ratings: {
                                              ...report.data.ratings,
                                              [key]: n,
                                            },
                                          })
                                        }
                                      />
                                      <span>{n}</span>
                                    </label>
                                  ))}
                                  {!readOnly && (
                                    <button
                                      type="button"
                                      className="report-clear"
                                      disabled={
                                        busy || !report.data.ratings[key]
                                      }
                                      aria-label={"Clear rating: " + question}
                                      onClick={() => {
                                        const ratings = {
                                          ...report.data.ratings,
                                        };
                                        delete ratings[key];
                                        patchData({ ratings });
                                      }}
                                    >
                                      Clear
                                    </button>
                                  )}
                                </div>
                              </div>
                            );
                          })}
                        </section>
                      ),
                    )}
                  </section>
                </>
              )}
              {report.template_snapshot.team_report && (
                <TeamPlayerRatings
                  request={request}
                  teamId={report.team_id}
                  values={report.data.team_ratings || {}}
                  readOnly={readOnly}
                  busy={busy}
                  change={(team_ratings) => patchData({ team_ratings })}
                />
              )}
              {report.template_key === "fitness" && (
                <section className="report-section">
                  <h3>Fitness test results</h3>
                  <p className="management-footnote">
                    Enter actual measurements and test conditions.
                  </p>
                  <div className="management-form-grid">
                    {fitnessFields.map(([key, label]) =>
                      originalField(key, label, "text", "extra"),
                    )}
                  </div>
                </section>
              )}
              {report.template_key === "player" && (
                <>
                  <section className="report-section">
                    <h3>Exercise progress</h3>
                    <div className="report-exercise-grid">
                      {report.template_snapshot.exercises.map(
                        ([name, duration], e) => (
                          <article key={name}>
                            <h4>{name}</h4>
                            <small>{duration}</small>
                            {[0, 1, 2].map((l) => (
                              <div className="report-progress-level" key={l}>
                                <span>Level {l + 1}</span>
                                <div>
                                  {[0, 1, 2].map((a) => {
                                    const key = e + "-" + l + "-" + a,
                                      value = report.data.progress[key] || 0;
                                    return (
                                      <button
                                        type="button"
                                        key={a}
                                        className={
                                          "progress-marker progress-" + value
                                        }
                                        disabled={readOnly || busy}
                                        aria-label={`${name}, level ${l + 1}, attempt ${a + 1}: ${["Unmarked", "Completed", "In progress", "To improve"][value]}`}
                                        onClick={() =>
                                          patchData({
                                            progress: {
                                              ...report.data.progress,
                                              [key]: (value + 1) % 4,
                                            },
                                          })
                                        }
                                      >
                                        {["○", "✓", "◐", "↗"][value]}
                                      </button>
                                    );
                                  })}
                                </div>
                              </div>
                            ))}
                          </article>
                        ),
                      )}
                    </div>
                    <p className="management-footnote">
                      ○ Unmarked · ✓ Completed · ◐ In progress · ↗ To improve
                    </p>
                  </section>
                  <section className="report-section">
                    <h3>Values &amp; behaviours</h3>
                    <div className="report-values-grid">
                      {Object.entries(report.template_snapshot.behaviours).map(
                        ([category, values]) => (
                          <fieldset key={category}>
                            <legend>{category}</legend>
                            {values.map((v) => (
                              <label key={v}>
                                <input
                                  type="checkbox"
                                  checked={!!report.data.values[v]}
                                  disabled={readOnly || busy}
                                  onChange={(e) =>
                                    patchData({
                                      values: {
                                        ...report.data.values,
                                        [v]: e.target.checked,
                                      },
                                    })
                                  }
                                />
                                {v}
                              </label>
                            ))}
                          </fieldset>
                        ),
                      )}
                    </div>
                  </section>
                </>
              )}
              <section className="report-section">
                <h3>Observations &amp; next steps</h3>
                <div className="management-form-grid">
                  {report.template_snapshot.notes.map((label, i) => (
                    <label key={label}>
                      {label}
                      <textarea
                        rows={5}
                        maxLength={6000}
                        value={report.data.notes[i] || ""}
                        readOnly={readOnly}
                        disabled={busy}
                        onChange={(e) => {
                          const notes = [...report.data.notes];
                          notes[i] = e.target.value;
                          patchData({ notes });
                        }}
                      />
                      <span className="report-print-value">
                        {report.data.notes[i] || "—"}
                      </span>
                    </label>
                  ))}
                </div>
                <div className="management-form-grid">
                  {(["prepared_by", "reviewer", "review_date"] as const).map(
                    (key, i) => (
                      <label key={key}>
                        {
                          [
                            report.template_key === "parent"
                              ? "Your name *"
                              : "Prepared by *",
                            "Reviewed by (optional)",
                            "Next review date",
                          ][i]
                        }
                        <input
                          type={key === "review_date" ? "date" : "text"}
                          maxLength={250}
                          value={report.data[key]}
                          readOnly={readOnly || !!selfSubject}
                          disabled={busy}
                          onChange={(e) => patchData({ [key]: e.target.value })}
                        />
                        <span className="report-print-value">
                          {report.data[key] || "—"}
                        </span>
                      </label>
                    ),
                  )}
                </div>
              </section>
              {!readOnly && (
                <label className="report-consent">
                  <input
                    type="checkbox"
                    checked={report.data.consent}
                    disabled={busy}
                    onChange={(e) => patchData({ consent: e.target.checked })}
                  />
                  <span>
                    I am authorised to submit this report to the selected
                    account’s development record. Reports remain private to
                    authorised platform access.
                  </span>
                </label>
              )}
              <ErrorNotice error={saveError} />
              <div className="management-actions report-actions">
                {preview ? (
                  <button
                    type="button"
                    className="button primary"
                    onClick={() => {
                      setPreview(false);
                      dirty.current = false;
                    }}
                  >
                    Use this template
                  </button>
                ) : (
                  <>
                    <button
                      type="button"
                      className="owner-refresh"
                      onClick={() => window.print()}
                    >
                      Print / Save PDF
                    </button>
                    {!readOnly && (
                      <>
                        <button
                          type="button"
                          className="owner-refresh"
                          disabled={
                            busy ||
                            (!report.template_snapshot.team_report
                              ? !report.subject_id
                              : !report.team_id)
                          }
                          onClick={() => void save("draft")}
                        >
                          Save draft
                        </button>
                        <button
                          className="button primary"
                          disabled={
                            busy ||
                            (!report.template_snapshot.team_report
                              ? !report.subject_id
                              : !report.team_id) ||
                            !report.data.consent
                          }
                        >
                          {busy ? "Saving…" : "Submit report"}
                        </button>
                      </>
                    )}
                  </>
                )}
              </div>
            </form>
          </div>
        </Modal>
      )}
    </div>
  );
}
