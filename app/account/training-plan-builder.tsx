"use client";
import { useEffect, useState, type DragEvent } from "react";
import {
  workspaceRequest,
  type WorkspaceClient,
  type PlanBlock,
} from "../../lib/workspace-api";
import { ErrorNotice } from "./workspace-controls";
type Drill = {
  id: string;
  title: string;
  kind: string;
  duration_minutes: number | null;
  status: string;
  category: string;
};
export default function TrainingPlanBuilder({
  blocks,
  change,
  disabled,
  request = workspaceRequest,
  teamId,
}: {
  blocks: PlanBlock[];
  change: (blocks: PlanBlock[]) => void;
  disabled: boolean;
  request?: WorkspaceClient;
  teamId?: string | null;
}) {
  const [drills, setDrills] = useState<Drill[]>([]);
  const [query, setQuery] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let active = true;
    request<Drill[]>("drill_catalog", { team_id: teamId || "" })
      .then((r) => {
        if (active) setDrills(r);
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
  }, [request, teamId]);
  function add(id: string, index = blocks.length) {
    const drill = drills.find((d) => d.id === id);
    if (!drill?.duration_minutes || disabled || blocks.length >= 100) return;
    const next = [...blocks];
    next.splice(index, 0, {
      id: crypto.randomUUID(),
      resource_id: drill.id,
      title: drill.title,
      kind: drill.kind,
      minutes: Number(drill.duration_minutes),
    });
    change(next);
  }
  function move(from: number, to: number) {
    if (
      disabled ||
      !Number.isInteger(from) ||
      from < 0 ||
      from >= blocks.length ||
      !Number.isInteger(to) ||
      to < 0 ||
      to >= blocks.length ||
      from === to
    )
      return;
    const next = [...blocks];
    const [block] = next.splice(from, 1);
    next.splice(to, 0, block);
    change(next);
  }
  function drop(e: DragEvent, index: number) {
    e.preventDefault();
    e.stopPropagation();
    if (disabled) return;
    const id = e.dataTransfer.getData("application/x-pfd-drill");
    if (id) {
      add(id, index);
      return;
    }
    const source = e.dataTransfer.getData("application/x-pfd-block");
    if (source !== "") move(Number(source), Math.min(index, blocks.length - 1));
  }
  const total = blocks.reduce((s, b) => s + Number(b.minutes || 0), 0);
  return (
    <section className="plan-builder">
      <div className="plan-builder-heading">
        <div>
          <h3>Build your training session</h3>
          <p>
            Drag drills into the session. On a phone, use Add and the move
            buttons.
          </p>
        </div>
        <strong>
          {Number(total.toFixed(1))}
          <span> minutes total</span>
        </strong>
      </div>
      <ErrorNotice error={error} />
      <div className="plan-builder-columns">
        <div className="plan-drill-catalog">
          <label>
            Find a drill
            <input
              type="search"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search drills or categories"
              disabled={disabled}
            />
          </label>
          {loading ? (
            <p role="status">Loading drills…</p>
          ) : (
            drills
              .filter((d) =>
                (d.title + " " + d.category)
                  .toLowerCase()
                  .includes(query.toLowerCase()),
              )
              .map((d) => (
                <article
                  key={d.id}
                  draggable={!disabled && !!d.duration_minutes}
                  onDragStart={(e) => {
                    e.dataTransfer.setData("application/x-pfd-drill", d.id);
                    e.dataTransfer.effectAllowed = "copy";
                  }}
                >
                  <div>
                    <strong>{d.title}</strong>
                    <small>
                      {d.kind === "team_drill" ? "Team" : "Individual"} ·{" "}
                      {d.duration_minutes
                        ? `${d.duration_minutes} min`
                        : "Duration needed"}{" "}
                      · {d.status}
                    </small>
                  </div>
                  <button
                    type="button"
                    className="owner-refresh"
                    disabled={
                      disabled || !d.duration_minutes || blocks.length >= 100
                    }
                    onClick={() => add(d.id)}
                  >
                    Add
                  </button>
                </article>
              ))
          )}
          {!loading && !drills.length && (
            <p className="management-muted">
              Add individual or team drills first, including their estimated
              duration.
            </p>
          )}
        </div>
        <div
          className="plan-session"
          onDragOver={(e) => {
            if (!disabled) e.preventDefault();
          }}
          onDrop={(e) => drop(e, blocks.length)}
        >
          <h4>Session order · {blocks.length} drills</h4>
          {!blocks.length && (
            <div className="plan-drop-empty">
              Drop drills here or use Add to start your session.
            </div>
          )}
          {blocks.map((b, i) => (
            <article
              className="plan-block"
              key={b.id}
              draggable={!disabled}
              onDragStart={(e) => {
                e.dataTransfer.setData("application/x-pfd-block", String(i));
                e.dataTransfer.effectAllowed = "move";
              }}
              onDragOver={(e) => {
                if (!disabled) e.preventDefault();
              }}
              onDrop={(e) => drop(e, i)}
            >
              <div className="plan-block-title">
                <span aria-hidden="true">⠿</span>
                <div>
                  <strong>
                    {i + 1}. {b.title}
                  </strong>
                  <small>
                    {b.kind === "team_drill"
                      ? "Team drill"
                      : "Individual drill"}
                  </small>
                </div>
              </div>
              <label>
                Minutes
                <input
                  type="number"
                  min={0.1}
                  max={240}
                  step={0.1}
                  required
                  value={b.minutes || ""}
                  disabled={disabled}
                  onChange={(e) =>
                    change(
                      blocks.map((x, n) =>
                        n === i ? { ...x, minutes: Number(e.target.value) } : x,
                      ),
                    )
                  }
                />
              </label>
              <div className="plan-block-actions">
                <button
                  type="button"
                  aria-label={"Move " + b.title + " earlier"}
                  disabled={disabled || i === 0}
                  onClick={() => move(i, i - 1)}
                >
                  ↑
                </button>
                <button
                  type="button"
                  aria-label={"Move " + b.title + " later"}
                  disabled={disabled || i === blocks.length - 1}
                  onClick={() => move(i, i + 1)}
                >
                  ↓
                </button>
                <button
                  type="button"
                  disabled={disabled}
                  onClick={() => change(blocks.filter((_, n) => i !== n))}
                >
                  Remove
                </button>
              </div>
            </article>
          ))}
        </div>
      </div>
      <p className="management-footnote">
        Drill order and timings are saved with the template. Publishing requires
        published drills and compatible club availability. Sharing a plan with a
        team will be added with the team workspace.
      </p>
    </section>
  );
}
