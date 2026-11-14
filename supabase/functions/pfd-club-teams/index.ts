import { createClient } from "npm:@supabase/supabase-js@2.119.0";
const origins = new Set([
  "https://pfd-development-build.dany-elhamra-8394.chatgpt.site",
  "https://playerfocusseddevelopment.com",
  "https://www.playerfocusseddevelopment.com",
  "http://localhost:4173",
  "http://127.0.0.1:4173",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
]);
Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin") || "";
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    Vary: "Origin",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
  };
  if (origins.has(origin)) headers["Access-Control-Allow-Origin"] = origin;
  const reply = (value: unknown, status = 200) =>
    new Response(JSON.stringify(value), { status, headers });
  if (origin && !origins.has(origin))
    return reply({ error: "This website is not permitted." }, 403);
  if (req.method === "OPTIONS")
    return new Response(null, { status: 204, headers });
  if (req.method !== "POST")
    return reply({ error: "Method not allowed." }, 405);
  try {
    const token = req.headers
      .get("authorization")
      ?.match(/^Bearer (.+)$/i)?.[1];
    if (!token) return reply({ error: "Please log in." }, 401);
    const service = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const identity = await service.auth.getUser(token);
    if (identity.error || !identity.data.user)
      return reply({ error: "Please log in again." }, 401);
    // Decode only AFTER Auth verifies the token. Never authorize from editable metadata.
    let claims;
    try {
      claims = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    } catch { return reply({ error: "Please log in again." }, 401); }
    if (!identity.data.user.email_confirmed_at || typeof claims.session_id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(claims.session_id))
      return reply({ error: "Confirm your email and log in again." }, 401);
    const sessionCheck = await service.rpc("pfd_check_session", {
      actor_id: identity.data.user.id, session_id: claims.session_id,
      assurance: typeof claims.aal === "string" ? claims.aal : "",
    });
    if (sessionCheck.error) return reply({ error: "Unable to verify your session. Please try again." }, 503);
    if (sessionCheck.data !== true) return reply({ error: "Your session ended or requires two-step verification. Log in again." }, 401);

    const raw = await req.text();
    if (raw.length > 14000) return reply({ error: "Request too large." }, 413);
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return reply({ error: "Invalid request." }, 400);
    }
    if (
      !body ||
      typeof body !== "object" ||
      Array.isArray(body) ||
      typeof body.action !== "string" ||
      typeof body.club_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        body.club_id,
      )
    )
      return reply({ error: "Choose a valid club." }, 400);
    const result = await service.rpc("pfd_club_teams", {
      actor_id: identity.data.user.id,
      target_club: body.club_id,
      action: body.action,
      payload: body.payload || {},
    });
    if (result.error) {
      const code = result.error.code;
      const status =
        code === "42501"
          ? 403
          : code === "P0002"
            ? 404
            : ["40001", "23505"].includes(code)
              ? 409
              : ["22023", "22P02", "23502", "23514"].includes(code)
                ? 400
                : 503;
      const message =
        code === "23505"
          ? body.action === "add_member"
            ? "This account already has that role in this team."
            : "A team with this name and season already exists in this club. Check archived teams too."
          : ["23502", "23514"].includes(code)
            ? "Complete the team name, age group and season, within the displayed limits."
            : status === 503
              ? "Unable to complete this team request. Please try again."
              : result.error.message;
      return reply({ error: message }, status);
    }
    return reply(result.data, body.action === "create" ? 201 : 200);
  } catch {
    return reply(
      { error: "Unable to complete this team request. Please try again." },
      500,
    );
  }
});
