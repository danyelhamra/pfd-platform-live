import { getSupabase } from "./supabase";
export type TeamPermissions = {
  manage: boolean;
  members: boolean;
  coaches: boolean;
  players: boolean;
};
export type ClubTeam = {
  id: string;
  club_id: string;
  name: string;
  age_group: string;
  season: string;
  description: string;
  status: "active" | "archived";
  created_at: string;
  updated_at: string;
  coach_count: number;
  player_count: number;
  permissions?: TeamPermissions;
};
export type TeamMember = {
  user_id: string;
  name: string;
  email: string;
  role_key: "coach" | "player";
  created_at: string;
};
export type Candidate = { id: string; name: string; email: string };
export type TeamPage<T> = { items: T[]; total: number; page: number };
export type TeamList = TeamPage<ClubTeam> & {
  permissions: TeamPermissions;
  seasons: string[];
};
export type TeamStats = { teams: number; coaches: number; players: number };
export async function clubTeamRequest<T>(
  clubId: string,
  action: string,
  payload: Record<string, unknown> = {},
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);
  try {
    const result = await getSupabase().functions.invoke("pfd-club-teams", {
      body: { club_id: clubId, action, payload },
      signal: controller.signal,
    });
    if (result.error) {
      let message = "Unable to complete this team request. Please try again.";
      if (result.error.context instanceof Response) {
        try {
          message = (await result.error.context.json()).error || message;
        } catch {}
      }
      throw new Error(message);
    }
    if (result.data?.error) throw new Error(result.data.error);
    return result.data as T;
  } finally {
    clearTimeout(timeout);
  }
}
