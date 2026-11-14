import { getSupabase } from "./supabase";
import defaults from "./permission-defaults.json";

export type EditableRole = "club_admin" | "coach" | "player";
export type Role = "owner" | EditableRole;
export const roles: { key: Role; label: string; scope: string }[] = [
  { key: "owner", label: "PFD Owner", scope: "Full platform access. Protected and always enabled." },
  { key: "club_admin", label: "Club Admin", scope: "Assigned clubs only. These defaults apply to all club administrators." },
  { key: "coach", label: "Coach", scope: "Assigned teams only. These defaults apply to all coaches." },
  { key: "player", label: "Player", scope: "Own information and joined teams only. These defaults apply to all players." },
];
export type Permission = { key: string; category: string; label: string; description: string; available: boolean; owner_only: boolean; sort_order: number };
export type Grant = { role_key: EditableRole; permission_key: string; enabled: boolean };
export type PermissionSnapshot = {
  permissions: Permission[];
  grants: Grant[];
  settings: { revision: number; updated_at: string; updated_by: string | null };
  history: { id: string; revision: number; created_at: string; change_count: number }[];
};
export const grantKey = (role: EditableRole, permission: string) => role + ":" + permission;
export function defaultEnabled(role: EditableRole, permission: string) {
  return defaults.find((p) => p.key === permission)?.defaults.includes(role) ?? false;
}
async function verifyIdentity() {
  const { data, error } = await getSupabase().auth.getUser();
  if (error || !data.user) throw new Error("Please log in again.");
}
export async function loadPermissions(): Promise<PermissionSnapshot> {
  await verifyIdentity();
  const { data, error } = await getSupabase().rpc("pfd_get_role_permissions");
  if (error) throw new Error(error.message);
  if (!data?.settings || !Array.isArray(data.permissions) || !Array.isArray(data.grants))
    throw new Error("Unable to load role permissions.");
  return data as PermissionSnapshot;
}
export async function savePermissions(revision: number, changes: Grant[]) {
  await verifyIdentity();
  const { data, error } = await getSupabase().rpc("pfd_save_role_permissions", { expected_revision: revision, changes });
  if (error) throw new Error(error.message);
  return data as { revision: number; updated_at: string };
}
