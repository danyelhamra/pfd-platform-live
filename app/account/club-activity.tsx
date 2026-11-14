"use client";
import { useEffect, useMemo, useState, type FormEvent } from "react";
import { openPrivateFile } from "../../lib/private-files";
import { getSupabase } from "../../lib/supabase";
import {
  clubWorkspaceClient,
  calendarDownload,
  type ClubWorkspaceOptions,
} from "../../lib/club-workspace";
import { type Attachment, type Page } from "../../lib/workspace-api";
import { useWorkspaceList } from "./owner-management";
import { ErrorNotice, Modal, Pagination, Badge } from "./workspace-controls";
import { ChatPanel } from "./club-workspace-panels";
type Item = {
  id: string;
  title: string;
  body: string;
  instructions: string;
  starts_at: string;
  ends_at: string;
  location: string;
  notes: string;
  due_at: string;
  status: string;
  resource_snapshot?: {
    title: string;
    instructions: string;
    video_url: string;
    attachments?: Attachment[];
  };
  my_submission?: {
    id: string;
    notes: string;
    attachments: Attachment[];
    updated_at: string;
    feedback: string;
    review_status: string;
  };
};
export default function ClubActivity({ clubId }: { clubId: string }) {
  const request = useMemo(() => clubWorkspaceClient(clubId), [clubId]);
  const [tab, setTab] = useState("my_calendar");
  const [permissions, setPermissions] = useState<string[] | null>(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    let live = true;
    request<{ permissions: string[] }>("my_context")
      .then((x) => {
        if (live) {
          setPermissions(x.permissions);
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
  const tabs = [
    ["my_calendar", "Calendar", "events.view"],
    ["my_announcements", "Announcements", "announcements.view"],
    ["my_homework", "Homework", "homework.view"],
    ["chats", "Chats", "chats.view"],
  ].filter((t) => permissions?.includes(t[2]));
  return (
    <section className="owner-panel membership-panel club-feature">
      <h3>Your club activity</h3>
      <ErrorNotice error={error} />
      {error && (
        <button onClick={() => setRevision((r) => r + 1)}>Retry</button>
      )}
      {permissions && (
        <>
          <nav className="club-actions" aria-label="Club activity">
            {tabs.map(([key, title]) => (
              <button
                aria-current={tab === key ? "page" : undefined}
                key={key}
                onClick={() => setTab(key)}
              >
                {title}
              </button>
            ))}
          </nav>
          {!tabs.some((t) => t[0] === tab) ? (
            <p>
              Select an available section above. Your club controls role
              permissions.
            </p>
          ) : tab === "chats" ? (
            <ChatPanel
              request={request}
              options={
                {
                  clubs: [],
                  teams: [],
                  templates: [],
                  people: [],
                  permissions: permissions.filter((p) => p === "chats.view"),
                } as ClubWorkspaceOptions
              }
            />
          ) : (
            <ActivityList
              key={tab}
              request={request}
              tab={tab}
              canSubmit={permissions.includes("homework.submit")}
            />
          )}
        </>
      )}
    </section>
  );
}
export function ActivityList({
  request,
  tab,
  canSubmit,
  kind,
}: {
  request: ReturnType<typeof clubWorkspaceClient>;
  tab: string;
  canSubmit: boolean;
  kind?: string;
}) {
  const [page, setPage] = useState(1);
  const list = useWorkspaceList<Item>(tab, { page, kind: kind || "" }, request);
  const [editing, setEditing] = useState<Item | null>(null);
  const [error, setError] = useState("");
  async function openFile(id: string, path: string) {
    setError("");
    try {
      await openPrivateFile(() =>
        request<{ url: string }>("file_access", { submission_id: id, path }),
      );
    } catch (e) {
      setError((e as Error).message);
    }
  }
  return (
    <>
      <ErrorNotice error={list.error || error} />
      {list.loading ? (
        <p role="status">Loading activity…</p>
      ) : (
        <div className="club-cards">
          {list.data?.items.map((item) => (
            <article className="club-card" key={item.id}>
              <Badge value={item.status} />
              <h3>{item.title}</h3>
              {tab === "my_calendar" ? (
                <>
                  <p>
                    {new Date(item.starts_at).toLocaleString()} ·{" "}
                    {item.location}
                  </p>
                  <p>{item.notes}</p>
                  <button onClick={() => calendarDownload(item)}>
                    Add to calendar
                  </button>
                </>
              ) : tab === "my_announcements" ? (
                <p className="club-preserve">{item.body}</p>
              ) : (
                <>
                  <p>Due {new Date(item.due_at).toLocaleString()}</p>
                  <p>{item.instructions}</p>
                  {item.resource_snapshot && (
                    <>
                      <h4>{item.resource_snapshot.title}</h4>
                      <p>{item.resource_snapshot.instructions}</p>
                      {/^https?:\/\//.test(
                        item.resource_snapshot.video_url || "",
                      ) && (
                        <a
                          href={item.resource_snapshot.video_url}
                          target="_blank"
                          rel="noopener noreferrer"
                        >
                          Watch drill video ↗
                        </a>
                      )}
                      {item.resource_snapshot.attachments?.map((a) => (
                        <button
                          key={a.path}
                          onClick={() => {
                            setError("");
                            void openPrivateFile(() =>
                              request<{ url: string }>(
                                "player_homework_file_access",
                                { homework_id: item.id, path: a.path },
                              ),
                            ).catch((e) => setError(e.message));
                          }}
                        >
                          Open {a.name} ↗
                        </button>
                      ))}
                    </>
                  )}
                  {item.my_submission && (
                    <>
                      <p>
                        Submission:{" "}
                        {item.my_submission.review_status.replace(/_/g, " ")}
                      </p>
                      <p>{item.my_submission.notes}</p>
                      <p>
                        Feedback:{" "}
                        {item.my_submission.feedback || "Awaiting review"}
                      </p>
                      {item.my_submission.attachments.map((a) => (
                        <button
                          key={a.path}
                          onClick={() =>
                            void openFile(item.my_submission!.id, a.path)
                          }
                        >
                          Open {a.name} ↗
                        </button>
                      ))}
                    </>
                  )}
                  {canSubmit && item.status === "active" && (
                    <button
                      className="button primary"
                      onClick={() => setEditing(item)}
                    >
                      {item.my_submission
                        ? "Update submission"
                        : "Submit practice video"}
                    </button>
                  )}
                </>
              )}
            </article>
          ))}
          {!list.data?.items.length && (
            <p>No activity assigned to you here yet.</p>
          )}
        </div>
      )}
      <Pagination
        page={page}
        total={list.data?.total || 0}
        loading={list.loading}
        change={setPage}
      />
      {editing && (
        <HomeworkSubmission
          item={editing}
          request={request}
          close={() => setEditing(null)}
          saved={() => {
            setEditing(null);
            list.reload();
          }}
        />
      )}
    </>
  );
}
function HomeworkSubmission({
  item,
  request,
  close,
  saved,
}: {
  item: Item;
  request: ReturnType<typeof clubWorkspaceClient>;
  close: () => void;
  saved: () => void;
}) {
  const [notes, setNotes] = useState(item.my_submission?.notes || "");
  const [files, setFiles] = useState<File[]>([]);
  const [attachments, setAttachments] = useState<Attachment[]>(
    item.my_submission?.attachments || [],
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const uploaded = [...attachments];
    let pending = [...files];
    try {
      if (uploaded.length + files.length > 3)
        throw Error("Use up to three files.");
      for (const file of files) {
        const access = await request<{
          bucket: string;
          path: string;
          token: string;
        }>("prepare_homework_upload", {
          homework_id: item.id,
          mime: file.type,
          size: file.size,
        });
        const result = await getSupabase()
          .storage.from(access.bucket)
          .uploadToSignedUrl(access.path, access.token, file, {
            contentType: file.type,
          });
        if (result.error) throw result.error;
        uploaded.push({
          name: file.name,
          path: access.path,
          mime: file.type,
          size: file.size,
        });
        pending = pending.slice(1);
      }
      setAttachments(uploaded);
      setFiles([]);
      await request("submit_homework", {
        id: item.my_submission?.id || crypto.randomUUID(),
        homework_id: item.id,
        updated_at: item.my_submission?.updated_at || null,
        notes,
        attachments: uploaded,
      });
      saved();
    } catch (e) {
      setAttachments(uploaded);
      setFiles(pending);
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <Modal title={item.title} close={close} busy={busy} eyebrow="MY HOMEWORK">
      <form onSubmit={save}>
        <fieldset disabled={busy} className="club-editor">
          <label>
            Practice notes
            <textarea
              rows={4}
              maxLength={6000}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </label>
          <label>
            Upload practice video or supporting file
            <input
              type="file"
              multiple
              accept="video/mp4,video/webm,video/quicktime,image/jpeg,image/png,image/webp,application/pdf"
              onChange={(e) => setFiles(Array.from(e.target.files || []))}
            />
          </label>
          <p>
            Up to three files, 50 MB each. MP4, MOV, WebM, JPG, PNG, WebP or
            PDF.
          </p>
          {files.length > 0 && (
            <p>Queued for upload: {files.map((f) => f.name).join(", ")}</p>
          )}
          {attachments.map((a) => (
            <p key={a.path}>
              {a.name}{" "}
              <button
                type="button"
                onClick={() =>
                  setAttachments(attachments.filter((x) => x.path !== a.path))
                }
              >
                Remove
              </button>
            </p>
          ))}
          <ErrorNotice error={error} />
          <button className="button primary">
            {busy ? "Uploading and saving…" : "Submit homework"}
          </button>
        </fieldset>
      </form>
    </Modal>
  );
}
