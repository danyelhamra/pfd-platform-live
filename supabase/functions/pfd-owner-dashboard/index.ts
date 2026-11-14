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
  const reply = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), { status, headers });
  if (origin && !origins.has(origin))
    return reply({ error: "This website is not permitted." }, 403);
  if (req.method === "OPTIONS")
    return new Response(null, { status: 204, headers });
  if (req.method !== "POST")
    return reply({ error: "Method not allowed." }, 405);
  try {
    const bearer = req.headers
      .get("authorization")
      ?.match(/^Bearer (.+)$/i)?.[1];
    if (!bearer) return reply({ error: "Please log in." }, 401);
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: identity, error: authError } =
      await admin.auth.getUser(bearer);
    if (authError || !identity.user)
      return reply({ error: "Please log in again." }, 401);
    // Decode only AFTER Auth verifies the token. Never authorize from editable metadata.
    let claims;
    try {
      claims = JSON.parse(atob(bearer.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    } catch { return reply({ error: "Please log in again." }, 401); }
    if (!identity.user.email_confirmed_at || typeof claims.session_id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(claims.session_id))
      return reply({ error: "Confirm your email and log in again." }, 401);
    const sessionCheck = await admin.rpc("pfd_check_session", {
      actor_id: identity.user.id, session_id: claims.session_id,
      assurance: typeof claims.aal === "string" ? claims.aal : "",
    });
    if (sessionCheck.error) return reply({ error: "Unable to verify your session. Please try again." }, 503);
    if (sessionCheck.data !== true) return reply({ error: "Your session ended or requires two-step verification. Log in again." }, 401);

    const { data: grant, error: grantError } = await admin
      .from("pfd_platform_owners")
      .select("user_id")
      .eq("user_id", identity.user.id)
      .maybeSingle();
    if (grantError)
      return reply(
        { error: "Unable to verify access. Please try again." },
        503,
      );
    if (!grant) return reply({ error: "PFD Owner access is required." }, 403);
    const raw = await req.text();
    if (raw.length > 1000) return reply({ error: "Request too large." }, 413);
    const body = raw ? JSON.parse(raw) : {};
    const page = Number(body.page ?? 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 100000)
      return reply({ error: "Invalid page." }, 400);
    const { data, error } = await admin.auth.admin.listUsers({
      page,
      perPage: 20,
    });
    if (error)
      return reply(
        { error: "Unable to load accounts. Please try again." },
        503,
      );
    const owners = await admin.from("pfd_platform_owners").select("user_id");
    if (owners.error)
      return reply({ error: "Unable to load owner access." }, 503);
    const ownerIds = new Set(owners.data.map((row) => row.user_id));
    const clubs = await admin
      .from("pfd_clubs")
      .select("id", { count: "exact", head: true });
    const assignments = await admin
      .from("pfd_club_admins")
      .select("user_id,pfd_clubs!inner(status)")
      .eq("pfd_clubs.status", "active");
    if (clubs.error || assignments.error)
      return reply({ error: "Unable to load club totals." }, 503);
    const administratorIds = new Set(
      assignments.data.map((row) => row.user_id),
    );
    const total = Math.max(
      data.total || 0,
      (page - 1) * 20 + data.users.length,
    );
    return reply({
      totalAccounts: total,
      totalOwners: ownerIds.size,
      totalClubs: clubs.count || 0,
      totalClubAdministrators: administratorIds.size,
      page,
      perPage: 20,
      hasNext: page * 20 < total,
      users: data.users.map((user) => ({
        id: user.id,
        email: user.email || "",
        name:
          typeof user.user_metadata?.full_name === "string"
            ? user.user_metadata.full_name
            : "",
        createdAt: user.created_at,
        lastSignInAt: user.last_sign_in_at || null,
        access: ownerIds.has(user.id)
          ? "PFD Owner"
          : administratorIds.has(user.id)
            ? "Club Administrator"
            : "Member",
      })),
    });
  } catch {
    return reply(
      { error: "Unable to load dashboard data. Please try again." },
      500,
    );
  }
});
