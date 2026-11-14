import { getSupabase } from "./supabase";

export type ShellClub = {
  id: string;
  name: string;
  city: string;
  state: string;
  country: string;
  sport: string;
  league: string;
};
export type ClubShellContext = {
  clubs: ShellClub[];
  hasAssignment: boolean;
  permissions: Record<string, boolean>;
};

// Every read uses the caller's JWT and existing database RLS. No service key.
export async function loadClubShell(): Promise<ClubShellContext> {
  const sb = getSupabase();
  const identity = await sb.auth.getUser();
  if (identity.error || !identity.data.user)
    throw new Error("Please log in again.");
  const userId = identity.data.user.id;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000);
  try {
    const owner = await sb
      .from("pfd_platform_owners")
      .select("user_id")
      .eq("user_id", userId)
      .abortSignal(controller.signal)
      .maybeSingle();
    if (owner.error)
      throw new Error(
        "Unable to verify your account access. Please try again.",
      );
    if (owner.data)
      throw new Error(
        "Use your separate Club Administrator account to open this workspace.",
      );
    const [assignments, clubs, permissions] = await Promise.all([
      sb
        .from("pfd_club_admins")
        .select("club_id")
        .eq("user_id", userId)
        .abortSignal(controller.signal),
      sb
        .from("pfd_clubs")
        .select("id,name,city,state,country,sport,league")
        .eq("status", "active")
        .order("name")
        .abortSignal(controller.signal),
      sb
        .from("pfd_role_permissions")
        .select("permission_key,enabled")
        .eq("role_key", "club_admin")
        .abortSignal(controller.signal),
    ]);
    if (assignments.error || clubs.error || permissions.error)
      throw new Error("Unable to verify your club access. Please try again.");
    const assigned = new Set(assignments.data.map((a) => a.club_id));
    return {
      hasAssignment: assigned.size > 0,
      clubs: clubs.data.filter((c) => assigned.has(c.id)) as ShellClub[],
      permissions: Object.fromEntries(
        permissions.data.map((p) => [p.permission_key, p.enabled]),
      ),
    };
  } finally {
    clearTimeout(timeout);
  }
}
