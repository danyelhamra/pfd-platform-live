import { getSupabase } from "./supabase";
export type JoinedClub = {
  id: string;
  name: string;
  city: string;
  state: string;
  country: string;
  sport: string;
  league: string;
  status: string;
  joined_at: string;
};
export type JoinRequest = {
  id: string;
  club_id: string;
  club_name?: string;
  team_id: string | null;
  team_name: string | null;
  role_key: string;
  status: string;
  message: string;
  reason: string;
  created_at: string;
  reviewed_at: string | null;
  user_id?: string;
  name?: string;
  email?: string;
  reviewer_name?: string;
};
export type MyAccess = {
  clubs: JoinedClub[];
  teams: {
    id: string;
    name: string;
    club_id: string;
    age_group: string;
    season: string;
    status: string;
    role_key: string;
  }[];
  requests: JoinRequest[];
};
export type ClubChoice = {
  id: string;
  name: string;
  city: string;
  state: string;
  country: string;
  sport: string;
  league: string;
  joined: boolean;
  pending: boolean;
};
export type TeamChoice = {
  id: string;
  name: string;
  age_group: string;
  season: string;
  roles: string[];
  pending_roles: string[];
};
export async function membershipRequest<T>(
  action: string,
  payload: Record<string, unknown> = {},
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25000);
  try {
    const r = await getSupabase().functions.invoke("pfd-memberships", {
      body: { action, payload },
      signal: controller.signal,
    });
    if (r.error) {
      let message =
        "Unable to complete this membership request. Please try again.";
      if (r.error.context instanceof Response) {
        try {
          message = (await r.error.context.json()).error || message;
        } catch {}
      }
      throw new Error(message);
    }
    if (r.data?.error) throw new Error(r.data.error);
    return r.data as T;
  } finally {
    clearTimeout(timeout);
  }
}
export const accessLabel = (role: string) =>
  ({
    member: "Club membership",
    club_admin: "Club Administrator",
    coach: "Coach team access",
    player: "Player team access",
  })[role] || role;
