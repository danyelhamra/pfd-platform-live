import { getSupabase } from "./supabase";
export type WorkspaceClient = <T>(
  action: string,
  payload?: Record<string, unknown>,
) => Promise<T>;
export type ClubOption = { id: string; name: string; status: string };
export type TeamOption = {
  id: string;
  club_id: string;
  name: string;
  status: string;
  age_group: string;
  season: string;
};
export type ReportField = {
  key: string;
  label: string;
  type: "text" | "date" | "number";
  unit?: string;
  min?: number;
  max?: number;
  step?: number;
};
export type PlanBlock = {
  id: string;
  resource_id: string;
  title: string;
  kind: string;
  minutes: number;
  instructions?: string;
  video_url?: string;
  attachments?: Attachment[];
};
export type Template = {
  key: string;
  label: string;
  definition: {
    title: string;
    short: string;
    intro: string;
    desc: string;
    categories: Record<string, string[]>;
    notes: string[];
    behaviours: Record<string, string[]>;
    exercises: string[][];
    fields?: ReportField[];
    team_report?: boolean;
  };
};
export type Options = {
  workspace_role?: string;
  clubs: ClubOption[];
  teams: TeamOption[];
  templates: Template[];
};
export type Page<T> = {
  items: T[];
  total: number;
  page: number;
  total_accounts?: number;
  pending?: number;
  submitted?: number;
  published?: number;
};
export type AccountRow = {
  id: string;
  name: string;
  email: string;
  roles: string[];
  created_at: string;
  last_sign_in_at: string | null;
  report_count: number;
};
export type RequestRow = {
  id: string;
  user_id: string;
  name: string;
  email: string;
  club_id: string;
  club_name: string;
  team_id: string | null;
  team_name: string | null;
  role_key: string;
  status: string;
  message: string;
  reason: string;
  created_at: string;
  reviewed_at: string | null;
  reviewer_name: string | null;
};
export type ReportData = {
  info: Record<string, string>;
  ratings: Record<string, number>;
  progress: Record<string, number>;
  values: Record<string, boolean>;
  extra: Record<string, string>;
  notes: string[];
  prepared_by: string;
  reviewer: string;
  review_date: string;
  consent: boolean;
  entry_kind?: string;
  subject_kind?: "player" | "coach" | "team";
  metrics?: Record<string, number>;
  team_ratings?: Record<string, { name: string; rating: number }>;
};
export type Report = {
  entry_kind?: string;
  read_only?: boolean;
  created_by?: string;
  id: string;
  subject_id: string | null;
  club_id: string | null;
  team_id: string | null;
  template_key: string;
  template_snapshot: Template["definition"];
  report_date: string;
  status: string;
  data: ReportData;
  updated_at: string;
  subject_name?: string;
  subject_email?: string;
  club_name?: string;
  team_name?: string;
  author_name?: string;
};
export type Attachment = {
  bucket?: string;
  path: string;
  name: string;
  size: number;
  mime: string;
};
export type Resource = {
  team_id?: string | null;
  source_resource_id?: string | null;
  club_name?: string;
  team_name?: string;
  author_name?: string;
  read_only?: boolean;
  club_id?: string | null;
  id: string;
  title: string;
  kind: string;
  category: string;
  difficulty: string;
  instructions: string;
  video_url: string;
  attachments: Attachment[];
  audience: string;
  status: string;
  club_ids: string[];
  updated_at: string;
  duration_minutes?: number | null;
  plan_blocks?: PlanBlock[];
};
export async function workspaceRequest<T>(
  action: string,
  payload: Record<string, unknown> = {},
): Promise<T> {
  const sb = getSupabase();
  const { data: identity, error: identityError } = await sb.auth.getUser();
  if (identityError || !identity.user) throw new Error("Please log in again.");
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);
  try {
    const { data, error } = await sb
      .rpc("pfd_owner_workspace", { action, payload })
      .abortSignal(controller.signal);
    if (error)
      throw new Error(
        error.code === "23505"
          ? "This record already exists. Refresh before trying again."
          : error.message,
      );
    return data as T;
  } finally {
    clearTimeout(timeout);
  }
}
export const roleLabel = (value: string) =>
  ({
    owner: "PFD Owner",
    club_admin: "Club Admin",
    coach: "Coach",
    player: "Player",
    member: "Member",
  })[value] || value;
export function dateLabel(value: string | null, time = false) {
  return value
    ? new Intl.DateTimeFormat(
        "en-AU",
        time
          ? { dateStyle: "medium", timeStyle: "short" }
          : { dateStyle: "medium" },
      ).format(new Date(value.length === 10 ? value + "T12:00:00" : value))
    : "—";
}
export const localDate = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
