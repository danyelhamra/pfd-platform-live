import { clubWorkspaceClient } from "./club-workspace";
import type { Options, WorkspaceClient } from "./workspace-api";
export type PlayerOptions = Options & {
  workspace_role: "player";
  self: { id: string; name: string };
  permissions: string[];
  self_templates: string[];
};
export function playerWorkspaceClient(clubId: string): WorkspaceClient {
  const request = clubWorkspaceClient(clubId);
  const routes: Record<string, string> = {
    options: "player_options",
    stats: "player_stats",
    reports_list: "player_reports_list",
    report_get: "player_report_get",
    report_save: "player_report_save",
    resources_list: "player_resources_list",
    resource_file_access: "player_resource_file_access",
    my_calendar: "player_calendar",
    team_chat: "player_team_chat",
  };
  return <T>(action: string, payload: Record<string, unknown> = {}) =>
    request<T>(routes[action] || action, payload);
}
