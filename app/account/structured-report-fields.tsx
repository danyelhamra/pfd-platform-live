"use client";
import { useEffect, useState } from "react";
import {
  workspaceRequest,
  type Report,
  type ReportData,
  type ReportField,
  type WorkspaceClient,
} from "../../lib/workspace-api";
import { ErrorNotice } from "./workspace-controls";
export function StructuredReportFields({
  fields,
  report,
  readOnly,
  busy,
  change,
  date,
}: {
  fields: ReportField[];
  report: Report;
  readOnly: boolean;
  busy: boolean;
  change: (value: Partial<ReportData>) => void;
  date: (value: string) => void;
}) {
  return (
    <>
      {fields.map((f) => {
        const numeric = f.type === "number";
        const value =
          f.key === "date"
            ? report.report_date
            : numeric
              ? (report.data.metrics?.[f.key] ?? "")
              : report.data.info[f.key] || "";
        return (
          <label key={f.key}>
            {f.label}
            {f.unit ? ` (${f.unit})` : ""}
            <input
              type={f.type}
              min={f.min}
              max={f.max}
              step={f.step}
              maxLength={250}
              value={value}
              readOnly={readOnly}
              disabled={busy}
              onChange={(e) => {
                if (f.key === "date") date(e.target.value);
                else if (numeric) {
                  const metrics = { ...report.data.metrics };
                  if (e.target.value === "") delete metrics[f.key];
                  else metrics[f.key] = Number(e.target.value);
                  change({ metrics });
                } else
                  change({
                    info: { ...report.data.info, [f.key]: e.target.value },
                  });
              }}
            />
            <span className="report-print-value">
              {value === "" ? "—" : value}
              {f.unit ? ` ${f.unit}` : ""}
            </span>
          </label>
        );
      })}
    </>
  );
}
export function TeamPlayerRatings({
  teamId,
  values,
  readOnly,
  busy,
  change,
  request = workspaceRequest,
}: {
  teamId: string | null;
  request?: WorkspaceClient;
  values: NonNullable<ReportData["team_ratings"]>;
  readOnly: boolean;
  busy: boolean;
  change: (value: NonNullable<ReportData["team_ratings"]>) => void;
}) {
  const [roster, setRoster] = useState<
    { id: string; name: string; email: string }[]
  >([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    if (readOnly || !teamId) {
      setRoster([]);
      return;
    }
    let active = true;
    setLoading(true);
    setError("");
    request<typeof roster>("team_roster", { team_id: teamId })
      .then((r) => {
        if (active) setRoster(r);
      })
      .catch((e) => {
        if (active) setError(e.message);
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [teamId, readOnly, request]);
  const rows = readOnly
    ? Object.entries(values).map(([id, v]) => ({ id, name: v.name, email: "" }))
    : roster;
  return (
    <section className="report-section">
      <h3>Player match ratings</h3>
      <p className="management-footnote">
        1–5 ratings for players in the selected team. Leave players you did not
        observe unrated.
      </p>
      <ErrorNotice error={error} />
      {loading ? (
        <p role="status">Loading team players…</p>
      ) : (
        rows.map((p) => (
          <div className="report-question" key={p.id}>
            <p>{p.name || p.email || "Player"}</p>
            <div
              className="report-rating"
              role="radiogroup"
              aria-label={`Match rating for ${p.name || p.email}`}
            >
              {[1, 2, 3, 4, 5].map((n) => (
                <label key={n}>
                  <input
                    type="radio"
                    name={"player-rating-" + p.id}
                    disabled={readOnly || busy}
                    checked={values[p.id]?.rating === n}
                    onChange={() =>
                      change({ ...values, [p.id]: { name: p.name, rating: n } })
                    }
                    aria-label={`${n} out of 5`}
                  />
                  <span>{n}</span>
                </label>
              ))}
              {!readOnly && (
                <button
                  type="button"
                  className="report-clear"
                  disabled={busy || !values[p.id]}
                  onClick={() => {
                    const next = { ...values };
                    delete next[p.id];
                    change(next);
                  }}
                >
                  Clear
                </button>
              )}
            </div>
          </div>
        ))
      )}
      {!loading && !rows.length && (
        <p className="management-muted">
          {readOnly
            ? "No individual player ratings were recorded."
            : teamId
              ? "There are no approved players in this team yet."
              : "Select a team to load its players."}
        </p>
      )}
    </section>
  );
}
