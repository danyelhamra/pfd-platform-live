"use client";
import { useEffect, useRef, useState, type ReactNode } from "react";
import {
  workspaceRequest,
  type AccountRow,
  type Page,
  type Options,
  type WorkspaceClient,
} from "../../lib/workspace-api";

export function Modal({
  title,
  children,
  close,
  busy = false,
  wide = false,
  eyebrow = "PFD OWNER",
}: {
  title: string;
  children: ReactNode;
  close: () => void;
  busy?: boolean;
  wide?: boolean;
  eyebrow?: string;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    ref.current?.showModal();
    const body = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = body;
    };
  }, []);
  return (
    <dialog
      ref={ref}
      className={"management-dialog" + (wide ? " management-dialog-wide" : "")}
      aria-label={title}
      onCancel={(e) => {
        e.preventDefault();
        if (!busy) close();
      }}
      onClick={(e) => {
        if (e.target !== e.currentTarget || busy) return;
        const r = e.currentTarget.getBoundingClientRect();
        if (
          e.clientX < r.left ||
          e.clientX > r.right ||
          e.clientY < r.top ||
          e.clientY > r.bottom
        )
          close();
      }}
    >
      <header>
        <div>
          <p className="eyebrow">{eyebrow}</p>
          <h2>{title}</h2>
        </div>
        <button
          className="close-button"
          type="button"
          aria-label="Close dialog"
          disabled={busy}
          onClick={close}
        >
          ×
        </button>
      </header>
      {children}
    </dialog>
  );
}
export function Pagination({
  page,
  total,
  loading,
  change,
}: {
  page: number;
  total: number;
  loading: boolean;
  change: (page: number) => void;
}) {
  return (
    <div className="owner-pagination">
      <span>
        {total} result{total === 1 ? "" : "s"} · Page {page} of{" "}
        {Math.max(1, Math.ceil(total / 20))}
      </span>
      <button disabled={loading || page <= 1} onClick={() => change(page - 1)}>
        Previous
      </button>
      <button
        disabled={loading || page * 20 >= total}
        onClick={() => change(page + 1)}
      >
        Next
      </button>
    </div>
  );
}
export function Empty({ title, text }: { title: string; text: string }) {
  return (
    <div className="management-empty">
      <span aria-hidden="true">↗</span>
      <h3>{title}</h3>
      <p>{text}</p>
    </div>
  );
}
export function Badge({ value }: { value: string }) {
  return (
    <span className={"management-badge status-" + value}>
      {value.replaceAll("_", " ")}
    </span>
  );
}
export function AccountPicker({
  value,
  label,
  select,
  disabled = false,
  request = workspaceRequest,
  role,
}: {
  value: string;
  label?: string;
  select: (id: string, name: string) => void;
  disabled?: boolean;
  request?: WorkspaceClient;
  role?: string;
}) {
  const [query, setQuery] = useState("");
  const [items, setItems] = useState<AccountRow[]>([]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    let current = true;
    const timer = setTimeout(async () => {
      setLoading(true);
      setError("");
      try {
        const r = await request<Page<AccountRow>>("users_list", {
          query,
          role,
        });
        if (current) setItems(r.items);
      } catch (e) {
        if (current)
          setError(e instanceof Error ? e.message : "Unable to find accounts.");
      } finally {
        if (current) setLoading(false);
      }
    }, 250);
    return () => {
      current = false;
      clearTimeout(timer);
    };
  }, [query, role, request]);
  return (
    <div className="account-picker">
      <label>
        Find an account
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search name or email"
          disabled={disabled}
        />
      </label>
      <label>
        Account
        <select
          required
          value={value}
          disabled={disabled || loading}
          onChange={(e) => {
            const p = items.find((i) => i.id === e.target.value);
            select(e.target.value, p?.name || "");
          }}
        >
          <option value="">
            {loading ? "Loading accounts…" : "Select an existing account"}
          </option>
          {value && !items.some((i) => i.id === value) && (
            <option value={value}>{label || "Selected account"}</option>
          )}
          {items.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name || p.email} · {p.email}
            </option>
          ))}
        </select>
      </label>
      {error && (
        <p className="form-alert" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}
export function ClubTeamFields({
  options,
  club,
  team,
  change,
  disabled = false,
  required = false,
  teamRequired = false,
}: {
  teamRequired?: boolean;
  options: Options;
  club: string;
  team: string;
  change: (club: string, team: string) => void;
  disabled?: boolean;
  required?: boolean;
}) {
  return (
    <div className="management-form-grid">
      <label>
        Club{required ? " *" : " (optional)"}
        <select
          value={club}
          disabled={disabled}
          required={required}
          onChange={(e) => change(e.target.value, "")}
        >
          <option value="">{required ? "Select club" : "No club"}</option>
          {options.clubs
            .filter((c) => c.status === "active" || c.id === club)
            .map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
                {c.status === "archived" ? " (archived)" : ""}
              </option>
            ))}
        </select>
      </label>
      <label>
        Team {teamRequired ? "*" : "(optional)"}
        <select
          value={team}
          required={teamRequired}
          disabled={disabled || !club}
          onChange={(e) => change(club, e.target.value)}
        >
          <option value="">No team</option>
          {options.teams
            .filter(
              (t) =>
                t.club_id === club && (t.status === "active" || t.id === team),
            )
            .map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
        </select>
      </label>
    </div>
  );
}
export function ErrorNotice({
  error,
  retry,
}: {
  error: string;
  retry?: () => void;
}) {
  return error ? (
    <div className="form-alert" role="alert">
      {error}
      {retry && (
        <button className="inline-retry" onClick={retry}>
          Try again
        </button>
      )}
    </div>
  ) : null;
}
