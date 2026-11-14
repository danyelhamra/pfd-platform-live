"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { defaultEnabled, grantKey, loadPermissions, roles, savePermissions, type EditableRole, type Grant, type PermissionSnapshot, type Role } from "../../lib/permissions";

function dateLabel(value: string) {
  return new Intl.DateTimeFormat("en-AU", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
export default function RolesPermissions({ onDirtyChange }: { onDirtyChange: (dirty: boolean) => void }) {
  const [snapshot, setSnapshot] = useState<PermissionSnapshot | null>(null);
  const [draft, setDraft] = useState<Record<string, boolean>>({});
  const [role, setRole] = useState<Role>("club_admin");
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [conflict, setConflict] = useState(false);
  const load = useCallback(async () => {
    setLoading(true); setError(""); setConflict(false);
    try {
      const next = await loadPermissions();
      setSnapshot(next);
      setDraft(Object.fromEntries(next.grants.map((g) => [grantKey(g.role_key, g.permission_key), g.enabled])));
    } catch (e) { setError(e instanceof Error ? e.message : "Unable to load permissions."); }
    finally { setLoading(false); }
  }, []);
  useEffect(() => { void load(); }, [load]);
  const changes = useMemo<Grant[]>(() => snapshot?.grants.filter((g) => !snapshot.permissions.find((p) => p.key === g.permission_key)?.owner_only && draft[grantKey(g.role_key, g.permission_key)] !== g.enabled).map((g) => ({ ...g, enabled: !!draft[grantKey(g.role_key, g.permission_key)] })) || [], [snapshot, draft]);
  const dirty = changes.length > 0;
  useEffect(() => { onDirtyChange(dirty); return () => onDirtyChange(false); }, [dirty, onDirtyChange]);
  useEffect(() => {
    if (!dirty) return;
    const warn = (event: BeforeUnloadEvent) => { event.preventDefault(); };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [dirty]);
  async function save() {
    if (!snapshot || !changes.length || saving || conflict) return;
    setSaving(true); setError(""); setNotice("");
    try {
      const result = await savePermissions(snapshot.settings.revision, changes);
      // Acknowledged writes become the baseline even if a later network read fails.
      setSnapshot((current) => current && ({ ...current, grants: current.grants.map((g) => changes.find((c) => c.role_key === g.role_key && c.permission_key === g.permission_key) || g), settings: { ...current.settings, ...result }, history: [{ id: "revision-" + result.revision, revision: result.revision, created_at: result.updated_at, change_count: changes.length }, ...current.history].slice(0, 5) }));
      setNotice("Role permissions saved. Changes apply to all accounts with these roles within their assigned scope.");
    } catch (e) {
      const message = e instanceof Error ? e.message : "Unable to save permissions.";
      setError(message);
      if (message.includes("changed elsewhere")) setConflict(true);
    } finally { setSaving(false); }
  }
  const active = roles.find((r) => r.key === role)!;
  const visible = snapshot?.permissions.filter((p) => (p.label + " " + p.category + " " + p.description).toLowerCase().includes(query.toLowerCase())) || [];
  const categories = [...new Set(visible.map((p) => p.category))];
  const enabledCount = snapshot?.permissions.filter((p) => role === "owner" || (!p.owner_only && draft[grantKey(role, p.key)])).length || 0;
  function reload() {
    if (dirty && !window.confirm("Discard your unsaved permission changes and load the latest settings?")) return;
    setNotice(""); void load();
  }
  function resetDefaults() {
    if (role === "owner" || !snapshot || saving) return;
    setNotice("");
    setDraft((current) => ({ ...current, ...Object.fromEntries(snapshot.permissions.filter((p) => !p.owner_only).map((p) => [grantKey(role, p.key), defaultEnabled(role, p.key)])) }));
  }
  return (
    <section className="roles-editor" aria-labelledby="roles-title">
      <div className="owner-panel roles-intro">
        <div><p className="eyebrow">PLATFORM SETTINGS</p><h2 id="roles-title">Roles &amp; Permissions</h2><p>Decide what each role can do. Club and team assignments still determine where they can do it.</p></div>
        <span className="access-badge owner-access">Owner controlled</span>
      </div>
      {error && <div className="form-alert" role="alert">{error} <button className="inline-retry" disabled={loading || saving} onClick={reload}>{conflict ? "Reload latest settings" : "Reload"}</button></div>}
      {notice && <p className="form-success" role="status">{notice}</p>}
      {loading ? <p className="owner-loading" role="status">Loading role permissions…</p> : snapshot && <>
        <div className="role-picker" role="group" aria-label="Choose a role">
          {roles.map((r) => <button key={r.key} type="button" aria-pressed={role === r.key} onClick={() => setRole(r.key)}><span>{r.label}</span><small>{r.key === "owner" ? "Protected" : r.key === "club_admin" ? "Club scope" : r.key === "coach" ? "Team scope" : "Own account"}</small></button>)}
        </div>
        <section className="owner-panel role-permission-panel" aria-label={active.label + " permissions"}>
          <div className="role-summary"><div><h3>{active.label}</h3><p>{active.scope}</p></div><strong>{enabledCount}<span> / {snapshot.permissions.length} enabled</span></strong></div>
          <p className="permission-note">{role === "owner" ? "Owner access cannot be removed here. Owner-only controls are never available to other roles." : "Permissions apply within assigned clubs and teams. Enabling a permission does not create a role assignment or grant access to another club."}</p>
          <div className="permission-tools"><label className="permission-search">Search permissions<input type="search" placeholder="Try reports or homework" value={query} onChange={(e) => setQuery(e.target.value)} /></label>{role !== "owner" && <button className="owner-refresh" type="button" onClick={resetDefaults} disabled={saving}>Use suggested defaults</button>}</div>
          {categories.map((category) => <fieldset className="permission-group" key={category}><legend>{category}</legend>{visible.filter((p) => p.category === category).map((p) => {
            const checked = role === "owner" || (!p.owner_only && !!draft[grantKey(role as EditableRole, p.key)]);
            const locked = role === "owner" || p.owner_only;
            return <label className={"permission-row" + (locked ? " permission-locked" : "")} key={p.key}><input type="checkbox" checked={checked} disabled={locked || saving || conflict} onChange={(event) => { if (role === "owner") return; const enabled = event.target.checked; setNotice(""); setDraft((current) => ({ ...current, [grantKey(role, p.key)]: enabled })); }} /><span className="permission-copy"><strong>{p.label}</strong><small>{p.description}</small></span><span className={"permission-status" + (p.available ? " permission-live" : "")}>{p.owner_only ? "Owner only" : p.available ? "Live" : "Upcoming"}</span></label>;
          })}</fieldset>)}
          {!visible.length && <p className="owner-loading">No permissions match your search.</p>}
        </section>
        <div className="permission-save-bar"><div><strong>{changes.length ? `${changes.length} unsaved change${changes.length === 1 ? "" : "s"}` : "All changes saved"}</strong><small>Last saved {dateLabel(snapshot.settings.updated_at)}</small></div><div><button type="button" className="owner-refresh" disabled={!dirty || saving} onClick={() => { setDraft(Object.fromEntries(snapshot.grants.map((g) => [grantKey(g.role_key, g.permission_key), g.enabled]))); setNotice(""); }}>Discard changes</button><button className="button primary" type="button" disabled={!dirty || saving || conflict} onClick={() => void save()}>{saving ? "Saving…" : "Save permissions"}</button></div></div>
        <details className="owner-panel permission-history"><summary>Recent permission changes</summary>{snapshot.history.length ? <ul>{snapshot.history.map((h) => <li key={h.id}><span>{dateLabel(h.created_at)}</span><strong>{h.change_count} permission{h.change_count === 1 ? "" : "s"} updated</strong><small>Revision {h.revision}</small></li>)}</ul> : <p>No permission changes saved yet.</p>}</details>
      </>}
    </section>
  );
}
