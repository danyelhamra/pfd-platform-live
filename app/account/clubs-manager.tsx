"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type FormEvent,
} from "react";
import { ownerRequest } from "../../lib/owner-api";

type Club = {
  id: string;
  name: string;
  location: string;
  city: string;
  state: string;
  country: string;
  contact_number: string;
  league: string;
  sport: string;
  contact_email: string;
  description: string;
  status: "active" | "archived";
  created_at: string;
  updated_at: string;
  administratorCount?: number;
};
type Administrator = {
  userId: string;
  name: string;
  email: string;
  grantedAt: string;
};
type Detail = { club: Club; administrators: Administrator[] };
type List = {
  clubs: Club[];
  total: number;
  page: number;
  perPage: number;
  hasNext: boolean;
};
type Accounts = {
  users: { id: string; name: string; email: string }[];
  totalAccounts: number;
  hasNext: boolean;
};
type Mode =
  "create" | "edit" | "assign" | "archive" | "restore" | "removeAdmin";
const SPORTS = [
  "Soccer",
  "AFL",
  "Futsal",
  "Basketball",
  "Netball",
  "Rugby League",
  "Rugby Union",
  "Cricket",
];
const clubLocation = (club: Club) =>
  [club.city, club.state, club.country].filter(Boolean).join(", ") ||
  club.location;
const detailsComplete = (club: Club) =>
  [
    club.city,
    club.state,
    club.country,
    club.contact_email,
    club.contact_number,
    club.league,
    club.sport,
  ].every((value) => typeof value === "string" && !!value.trim());
const date = (value: string) =>
  new Intl.DateTimeFormat("en-AU", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(value));
const message = (error: unknown) =>
  error instanceof Error ? error.message : "Unable to complete this request.";

export default function ClubsManager({ onChanged }: { onChanged: () => void }) {
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("active");
  const [page, setPage] = useState(1);
  const [list, setList] = useState<List | null>(null);
  const [loading, setLoading] = useState(true);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const listRequest = useRef(0);
  const detailRequest = useRef(0);
  const accountRequest = useRef(0);
  const dialog = useRef<HTMLDialogElement>(null);
  const [mode, setMode] = useState<Mode>("create");
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState("");
  const [sportChoice, setSportChoice] = useState("");
  const [formRevision, setFormRevision] = useState(0);
  const [createId, setCreateId] = useState("");
  const [target, setTarget] = useState<Administrator | null>(null);
  const [accountPage, setAccountPage] = useState(1);
  const [accounts, setAccounts] = useState<Accounts | null>(null);
  const [accountsLoading, setAccountsLoading] = useState(false);
  const [accountsError, setAccountsError] = useState("");

  useEffect(() => {
    const timer = setTimeout(() => {
      setQuery(search);
      setPage(1);
    }, 300);
    return () => clearTimeout(timer);
  }, [search]);
  const loadList = useCallback(async () => {
    const current = ++listRequest.current;
    setLoading(true);
    setError("");
    try {
      const result = await ownerRequest<List>("pfd-owner-clubs", {
        action: "list",
        query,
        status,
        page,
      });
      if (current === listRequest.current) setList(result);
    } catch (error) {
      if (current === listRequest.current) setError(message(error));
    } finally {
      if (current === listRequest.current) setLoading(false);
    }
  }, [query, status, page]);
  useEffect(() => {
    void loadList();
    return () => {
      listRequest.current++;
    };
  }, [loadList]);
  useEffect(
    () => () => {
      detailRequest.current++;
      accountRequest.current++;
    },
    [],
  );
  const loadDetail = useCallback(async (id: string) => {
    const current = ++detailRequest.current;
    setDetailLoading(true);
    setError("");
    try {
      const result = await ownerRequest<Detail>("pfd-owner-clubs", {
        action: "get",
        clubId: id,
      });
      if (current === detailRequest.current) setDetail(result);
    } catch (error) {
      if (current === detailRequest.current) setError(message(error));
    } finally {
      if (current === detailRequest.current) setDetailLoading(false);
    }
  }, []);
  async function loadAccounts(nextPage: number) {
    const current = ++accountRequest.current;
    setAccountsLoading(true);
    setAccountsError("");
    try {
      const result = await ownerRequest<Accounts>("pfd-owner-dashboard", {
        page: nextPage,
      });
      if (current === accountRequest.current) {
        setAccounts(result);
        setAccountPage(nextPage);
      }
    } catch (error) {
      if (current === accountRequest.current) setAccountsError(message(error));
    } finally {
      if (current === accountRequest.current) setAccountsLoading(false);
    }
  }
  function openClub(id: string) {
    setSelectedId(id);
    setDetail(null);
    setNotice("");
    void loadDetail(id);
  }
  function back() {
    detailRequest.current++;
    setSelectedId(null);
    setDetail(null);
    setError("");
    setNotice("");
  }
  function openForm(next: Mode, administrator: Administrator | null = null) {
    setMode(next);
    setFormRevision((value) => value + 1);
    const sport = next === "edit" ? detail?.club.sport || "" : "";
    setSportChoice(sport && !SPORTS.includes(sport) ? "Other" : sport);
    setFormError("");
    setTarget(administrator);
    if (next === "create") setCreateId(crypto.randomUUID());
    if (next === "assign") {
      setAccounts(null);
      setAccountPage(1);
      void loadAccounts(1);
    }
    dialog.current?.showModal();
  }
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const values = new FormData(event.currentTarget);
    setBusy(true);
    setFormError("");
    try {
      let nextId = selectedId;
      if (mode === "create" || mode === "edit") {
        const fields = {
          name: String(values.get("name") || "").trim(),
          city: String(values.get("city") || "").trim(),
          state: String(values.get("state") || "").trim(),
          country: String(values.get("country") || "").trim(),
          contact_number: String(values.get("contact_number") || "").trim(),
          league: String(values.get("league") || "").trim(),
          sport: String(
            values.get(sportChoice === "Other" ? "other_sport" : "sport") || "",
          ).trim(),
          contact_email: String(values.get("contact_email") || "").trim(),
          description: String(values.get("description") || "").trim(),
        };
        if (!fields.name) throw new Error("Enter a club name.");
        const response = await ownerRequest<{ club: Club }>(
          "pfd-owner-clubs",
          mode === "create"
            ? { action: "create", id: createId, ...fields }
            : {
                action: "update",
                clubId: selectedId,
                updatedAt: detail?.club.updated_at,
                ...fields,
              },
        );
        nextId = response.club.id;
      } else if (mode === "assign") {
        await ownerRequest("pfd-owner-clubs", {
          action: "assign_admin",
          clubId: selectedId,
          userId: values.get("userId"),
        });
      } else if (mode === "removeAdmin") {
        await ownerRequest("pfd-owner-clubs", {
          action: "remove_admin",
          clubId: selectedId,
          userId: target?.userId,
        });
      } else {
        await ownerRequest("pfd-owner-clubs", {
          action: "set_status",
          clubId: selectedId,
          updatedAt: detail?.club.updated_at,
          status: mode === "archive" ? "archived" : "active",
        });
      }
      dialog.current?.close();
      setNotice(
        {
          create: "Club created.",
          edit: "Club details saved.",
          assign: "Club administrator assigned.",
          removeAdmin: "Club administrator access removed.",
          archive: "Club archived. Its records have been kept.",
          restore: "Club restored.",
        }[mode],
      );
      await loadList();
      if (nextId) {
        setSelectedId(nextId);
        await loadDetail(nextId);
      }
      onChanged();
    } catch (error) {
      setFormError(message(error));
    } finally {
      setBusy(false);
    }
  }
  const club = detail?.club;
  const title = {
    create: "Create a club",
    edit: "Edit club details",
    assign: "Assign an administrator",
    archive: "Archive this club?",
    restore: "Restore this club?",
    removeAdmin: "Remove administrator access?",
  }[mode];

  return (
    <div className="clubs-manager">
      {error && (
        <div className="form-alert" role="alert">
          {error}
          <button
            className="inline-retry"
            onClick={() =>
              selectedId ? void loadDetail(selectedId) : void loadList()
            }
          >
            Try again
          </button>
        </div>
      )}
      {notice && (
        <p className="form-success" role="status">
          {notice}
        </p>
      )}
      {!selectedId ? (
        <>
          <div className="clubs-toolbar">
            <div className="clubs-filters">
              <label className="club-search">
                <span className="visually-hidden">Search clubs by name</span>
                <input
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                  placeholder="Search clubs by name…"
                  maxLength={120}
                />
              </label>
              <label>
                <span className="visually-hidden">Club status</span>
                <select
                  value={status}
                  onChange={(event) => {
                    setStatus(event.target.value);
                    setPage(1);
                  }}
                >
                  <option value="active">Active clubs</option>
                  <option value="archived">Archived clubs</option>
                  <option value="all">All clubs</option>
                </select>
              </label>
            </div>
            <button
              className="button primary"
              onClick={() => openForm("create")}
            >
              + Create club
            </button>
          </div>
          <div className="clubs-results-heading">
            <p>
              {list
                ? `${list.total} ${list.total === 1 ? "club" : "clubs"}`
                : "Your clubs"}
            </p>
            <button
              className="text-link"
              onClick={() => void loadList()}
              disabled={loading}
            >
              {loading ? "Refreshing…" : "Refresh"}
            </button>
          </div>
          {loading && !list ? (
            <p className="owner-loading" role="status">
              Loading clubs…
            </p>
          ) : list?.clubs.length ? (
            <>
              <div className="clubs-grid" aria-busy={loading}>
                {list.clubs.map((item) => (
                  <button
                    className="club-card"
                    key={item.id}
                    onClick={() => openClub(item.id)}
                  >
                    <div className="club-card-top">
                      <span className="club-initials">
                        {item.name
                          .split(/\s+/)
                          .slice(0, 2)
                          .map((word) => word[0])
                          .join("")
                          .toUpperCase()}
                      </span>
                      <span className={"club-status " + item.status}>
                        {item.status === "active" ? "Active" : "Archived"}
                      </span>
                    </div>
                    <h2>{item.name}</h2>
                    <div className="club-sport-line">
                      {item.sport && <span>{item.sport}</span>}
                      {!detailsComplete(item) && (
                        <span className="club-details-needed">
                          Details needed
                        </span>
                      )}
                    </div>
                    <p>{clubLocation(item) || "Location not added"}</p>
                    <div className="club-card-footer">
                      <span>
                        {item.administratorCount}{" "}
                        {item.administratorCount === 1
                          ? "administrator"
                          : "administrators"}
                      </span>
                      <span aria-hidden="true">↗</span>
                    </div>
                  </button>
                ))}
              </div>
              <div className="clubs-pagination">
                <span>Page {page}</span>
                <button
                  disabled={page === 1 || loading}
                  onClick={() => setPage((current) => current - 1)}
                >
                  Previous
                </button>
                <button
                  disabled={!list.hasNext || loading}
                  onClick={() => setPage((current) => current + 1)}
                >
                  Next
                </button>
              </div>
            </>
          ) : !error ? (
            <section className="owner-panel owner-empty">
              <span className="empty-icon" aria-hidden="true">
                ↗
              </span>
              <h2>
                {search || status !== "active"
                  ? "No matching clubs."
                  : "Create your first club."}
              </h2>
              <p>
                {search || status !== "active"
                  ? "Try a different name or status filter."
                  : "Add a club, then appoint its administrators and organise the teams within it."}
              </p>
              <button
                className="button primary"
                onClick={() => openForm("create")}
              >
                + Create club
              </button>
            </section>
          ) : null}
        </>
      ) : (
        <>
          <button className="club-back" onClick={back}>
            ← All clubs
          </button>
          {detailLoading && !club ? (
            <p className="owner-loading" role="status">
              Opening club…
            </p>
          ) : (
            club && (
              <>
                {!detailsComplete(club) && (
                  <div className="club-details-notice">
                    <p>
                      Complete the required location, contact, league and sport
                      details for this existing club.
                    </p>
                    <button onClick={() => openForm("edit")}>
                      Complete details
                    </button>
                  </div>
                )}
                <section className="owner-panel club-detail-heading">
                  <div>
                    <span className={"club-status " + club.status}>
                      {club.status === "active"
                        ? "Active club"
                        : "Archived club"}
                    </span>
                    <h2>{club.name}</h2>
                    <p>{clubLocation(club) || "Location not added"}</p>
                  </div>
                  <div className="club-detail-actions">
                    <button
                      className="club-secondary"
                      onClick={() => openForm("edit")}
                    >
                      Edit details
                    </button>
                    <button
                      className="club-secondary"
                      onClick={() =>
                        openForm(
                          club.status === "active" ? "archive" : "restore",
                        )
                      }
                    >
                      {club.status === "active"
                        ? "Archive club"
                        : "Restore club"}
                    </button>
                  </div>
                </section>
                <div className="club-details-grid">
                  <section className="owner-panel club-information">
                    <p className="eyebrow">CLUB DETAILS</p>
                    <dl>
                      <dt>Club name</dt>
                      <dd>{club.name}</dd>
                      <dt>City</dt>
                      <dd>{club.city || "Not added"}</dd>
                      <dt>State / region</dt>
                      <dd>{club.state || "Not added"}</dd>
                      <dt>Country</dt>
                      <dd>{club.country || "Not added"}</dd>
                      <dt>Sport</dt>
                      <dd>{club.sport || "Not added"}</dd>
                      <dt>League</dt>
                      <dd>{club.league || "Not added"}</dd>
                      <dt>Contact number</dt>
                      <dd>{club.contact_number || "Not added"}</dd>
                      <dt>Club email</dt>
                      <dd>{club.contact_email || "Not added"}</dd>
                      <dt>Created</dt>
                      <dd>{date(club.created_at)}</dd>
                    </dl>
                    {club.description && (
                      <div className="club-description">
                        <h3>About this club</h3>
                        <p>{club.description}</p>
                      </div>
                    )}
                  </section>
                  <section className="owner-panel club-administrators">
                    <div className="owner-panel-heading">
                      <h2>Club administrators</h2>
                      <button
                        onClick={() => openForm("assign")}
                        disabled={club.status !== "active"}
                        title={
                          club.status !== "active"
                            ? "Restore the club to assign administrators"
                            : undefined
                        }
                      >
                        + Assign
                      </button>
                    </div>
                    {detail.administrators.length ? (
                      <ul>
                        {detail.administrators.map((administrator) => (
                          <li key={administrator.userId}>
                            <div>
                              <strong>
                                {administrator.name || administrator.email}
                              </strong>
                              <span>{administrator.email}</span>
                              <small>
                                Assigned {date(administrator.grantedAt)}
                              </small>
                            </div>
                            <button
                              className="club-remove"
                              onClick={() =>
                                openForm("removeAdmin", administrator)
                              }
                            >
                              Remove
                            </button>
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <div className="club-admin-empty">
                        <p>No administrators assigned.</p>
                        <p>Choose someone who already has a PFD account.</p>
                        {club.status === "active" && (
                          <button
                            className="club-secondary"
                            onClick={() => openForm("assign")}
                          >
                            Assign administrator
                          </button>
                        )}
                      </div>
                    )}
                  </section>
                </div>
                <section className="owner-panel club-teams">
                  <p className="eyebrow">TEAMS</p>
                  <h2>Teams belong inside the club.</h2>
                  <p>
                    This is where the club&apos;s teams, coaches and players
                    will be organised.
                  </p>
                </section>
              </>
            )
          )}
        </>
      )}
      <dialog
        ref={dialog}
        className="account-dialog club-dialog"
        aria-labelledby="club-dialog-title"
        onCancel={(event) => {
          if (busy) event.preventDefault();
        }}
        onClick={(event) => {
          if (busy || event.target !== event.currentTarget) return;
          const rect = event.currentTarget.getBoundingClientRect();
          if (
            event.clientX < rect.left ||
            event.clientX > rect.right ||
            event.clientY < rect.top ||
            event.clientY > rect.bottom
          )
            dialog.current?.close();
        }}
      >
        <div className="club-dialog-heading">
          <div>
            <p className="eyebrow">CLUB MANAGEMENT</p>
            <h2 id="club-dialog-title">{title}</h2>
          </div>
          <button
            className="close-button"
            aria-label="Close club dialog"
            onClick={() => dialog.current?.close()}
            disabled={busy}
          >
            ×
          </button>
        </div>
        <form
          key={
            mode +
            (mode === "create" ? createId : selectedId || "") +
            ":" +
            formRevision
          }
          className="account-form"
          onSubmit={submit}
          aria-busy={busy}
        >
          {(mode === "create" || mode === "edit") && (
            <>
              <p className="club-required-note">
                All club details below are required. Description is optional.
              </p>
              <label htmlFor="club-name">
                Club name
                <input
                  id="club-name"
                  name="name"
                  defaultValue={mode === "edit" ? club?.name : ""}
                  required
                  maxLength={120}
                  disabled={busy}
                />
              </label>
              <fieldset className="club-location-fields">
                <legend>Club location</legend>
                <div className="club-form-columns">
                  <label htmlFor="club-city">
                    City
                    <input
                      id="club-city"
                      name="city"
                      defaultValue={mode === "edit" ? club?.city : ""}
                      required
                      maxLength={80}
                      autoComplete="address-level2"
                      disabled={busy}
                    />
                  </label>
                  <label htmlFor="club-state">
                    State / province / region
                    <input
                      id="club-state"
                      name="state"
                      defaultValue={mode === "edit" ? club?.state : ""}
                      required
                      maxLength={80}
                      autoComplete="address-level1"
                      disabled={busy}
                    />
                  </label>
                </div>
                <label htmlFor="club-country">
                  Country
                  <input
                    id="club-country"
                    name="country"
                    defaultValue={mode === "edit" ? club?.country : ""}
                    required
                    maxLength={80}
                    autoComplete="country-name"
                    disabled={busy}
                  />
                </label>
                {mode === "edit" && club && !club.city && club.location && (
                  <p className="field-hint">
                    Previous location: {club.location}
                  </p>
                )}
              </fieldset>
              <div className="club-form-columns">
                <label htmlFor="club-email">
                  Club email
                  <input
                    id="club-email"
                    name="contact_email"
                    type="email"
                    defaultValue={mode === "edit" ? club?.contact_email : ""}
                    required
                    maxLength={254}
                    autoComplete="email"
                    disabled={busy}
                  />
                </label>
                <label htmlFor="club-phone">
                  Contact number
                  <input
                    id="club-phone"
                    name="contact_number"
                    type="tel"
                    defaultValue={mode === "edit" ? club?.contact_number : ""}
                    required
                    maxLength={32}
                    autoComplete="tel"
                    disabled={busy}
                  />
                </label>
              </div>
              <div className="club-form-columns">
                <label htmlFor="club-sport">
                  Sport / club type
                  <select
                    id="club-sport"
                    name="sport"
                    value={sportChoice}
                    onChange={(event) => setSportChoice(event.target.value)}
                    required
                    disabled={busy}
                  >
                    <option value="" disabled>
                      Select a sport
                    </option>
                    {SPORTS.map((sport) => (
                      <option key={sport}>{sport}</option>
                    ))}
                    <option value="Other">Other</option>
                  </select>
                </label>
                <label htmlFor="club-league">
                  League / competition
                  <input
                    id="club-league"
                    name="league"
                    defaultValue={mode === "edit" ? club?.league : ""}
                    required
                    maxLength={160}
                    disabled={busy}
                  />
                </label>
              </div>
              {sportChoice === "Other" && (
                <label htmlFor="club-other-sport">
                  Specify sport
                  <input
                    id="club-other-sport"
                    name="other_sport"
                    defaultValue={
                      mode === "edit" && club && !SPORTS.includes(club.sport)
                        ? club.sport
                        : ""
                    }
                    required
                    maxLength={80}
                    disabled={busy}
                  />
                </label>
              )}
              <label htmlFor="club-description">
                Description <span className="optional">Optional</span>
                <textarea
                  id="club-description"
                  name="description"
                  defaultValue={mode === "edit" ? club?.description : ""}
                  rows={3}
                  maxLength={2000}
                  disabled={busy}
                />
              </label>
            </>
          )}
          {mode === "assign" && (
            <>
              <p className="club-dialog-explanation">
                Choose an existing PFD account to administer{" "}
                <strong>{club?.name}</strong>. This grants access to this club,
                not the whole platform.
              </p>
              {accountsError && (
                <div className="form-alert" role="alert">
                  {accountsError}
                  <button
                    type="button"
                    className="inline-retry"
                    onClick={() => void loadAccounts(accountPage)}
                  >
                    Try again
                  </button>
                </div>
              )}
              <label htmlFor="club-administrator">
                PFD account
                <select
                  id="club-administrator"
                  name="userId"
                  defaultValue=""
                  required
                  disabled={busy || accountsLoading}
                >
                  <option value="">
                    {accountsLoading
                      ? "Loading accounts…"
                      : "Select an account"}
                  </option>
                  {accounts?.users.map((account) => (
                    <option
                      value={account.id}
                      key={account.id}
                      disabled={detail?.administrators.some(
                        (admin) => admin.userId === account.id,
                      )}
                    >
                      {account.name || account.email} — {account.email}
                      {detail?.administrators.some(
                        (admin) => admin.userId === account.id,
                      )
                        ? " (Already assigned)"
                        : ""}
                    </option>
                  ))}
                </select>
              </label>
              {accounts && (
                <div className="club-account-pages">
                  <span>
                    Account page {accountPage} · {accounts.totalAccounts} total
                  </span>
                  <button
                    type="button"
                    disabled={accountPage === 1 || busy || accountsLoading}
                    onClick={() => void loadAccounts(accountPage - 1)}
                  >
                    Previous
                  </button>
                  <button
                    type="button"
                    disabled={!accounts.hasNext || busy || accountsLoading}
                    onClick={() => void loadAccounts(accountPage + 1)}
                  >
                    Next
                  </button>
                </div>
              )}
              <p className="field-hint">
                If they aren&apos;t listed, ask them to create a PFD account
                first.
              </p>
            </>
          )}
          {mode === "archive" && (
            <p className="club-dialog-explanation">
              <strong>{club?.name}</strong> will move to Archived. Its details
              and administrator assignments will be kept, and you can restore it
              later.
            </p>
          )}
          {mode === "restore" && (
            <p className="club-dialog-explanation">
              <strong>{club?.name}</strong> will return to your active clubs
              with its administrator assignments preserved.
            </p>
          )}
          {mode === "removeAdmin" && (
            <p className="club-dialog-explanation">
              Remove <strong>{target?.name || target?.email}</strong> as an
              administrator of <strong>{club?.name}</strong>? Their PFD account
              and access to other clubs will be kept.
            </p>
          )}
          {formError && (
            <p className="form-alert" role="alert">
              {formError}
            </p>
          )}
          <div className="club-form-actions">
            <button
              type="button"
              className="club-secondary"
              disabled={busy}
              onClick={() => dialog.current?.close()}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="button primary"
              disabled={
                busy || (mode === "assign" && (accountsLoading || !accounts))
              }
            >
              {busy
                ? "Saving…"
                : {
                    create: "Create club",
                    edit: "Save changes",
                    assign: "Assign administrator",
                    archive: "Archive club",
                    restore: "Restore club",
                    removeAdmin: "Remove access",
                  }[mode]}
            </button>
          </div>
        </form>
      </dialog>
    </div>
  );
}
