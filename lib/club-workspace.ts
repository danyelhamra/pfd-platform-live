import { getSupabase } from "./supabase";
import type { Options, AccountRow, WorkspaceClient } from "./workspace-api";
export type ClubWorkspaceOptions = Options & {
  workspace_role?: string;
  people: AccountRow[];
  permissions: string[];
};
export function clubWorkspaceClient(clubId: string): WorkspaceClient {
  return async <T>(action: string, payload: Record<string, unknown> = {}) => {
    const result = await getSupabase().functions.invoke("pfd-club-workspace", {
      body: { club_id: clubId, action, payload },
    });
    if (result.error) {
      let message = "Unable to complete this club request. Please try again.";
      if (result.error.context instanceof Response) {
        try {
          message = (await result.error.context.json()).error || message;
        } catch {}
      }
      throw new Error(message);
    }
    if (result.data?.error) throw new Error(result.data.error);
    return result.data as T;
  };
}
export function calendarDownload(event: {
  id: string;
  title: string;
  starts_at: string;
  ends_at: string;
  location: string;
  notes: string;
  status: string;
}) {
  const escape = (s: string) =>
    s
      .replace(/\\/g, "\\\\")
      .replace(/\r?\n/g, "\\n")
      .replace(/,/g, "\\,")
      .replace(/;/g, "\\;");
  const stamp = (s: string) =>
    new Date(s)
      .toISOString()
      .replace(/[-:]/g, "")
      .replace(/\.\d{3}/, "");
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//PFD//Club Calendar//EN",
    "BEGIN:VEVENT",
    `UID:${event.id}@pfd`,
    `DTSTAMP:${stamp(new Date().toISOString())}`,
    `DTSTART:${stamp(event.starts_at)}`,
    `DTEND:${stamp(event.ends_at)}`,
    `SUMMARY:${escape(event.title)}`,
    `LOCATION:${escape(event.location)}`,
    `DESCRIPTION:${escape(event.notes)}`,
    `STATUS:${event.status === "cancelled" ? "CANCELLED" : "CONFIRMED"}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  const url = URL.createObjectURL(
    new Blob([lines.join("\r\n")], { type: "text/calendar;charset=utf-8" }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = "pfd-event.ics";
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
