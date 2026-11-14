import {
  ClubValidationError as InputError,
  validateClubFields as fields,
  isCompleteClub,
} from "./validation.ts";
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
const uuid = (value: unknown) =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
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
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const identity = await admin.auth.getUser(token);
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
    const sessionCheck = await admin.rpc("pfd_check_session", {
      actor_id: identity.data.user.id, session_id: claims.session_id,
      assurance: typeof claims.aal === "string" ? claims.aal : "",
    });
    if (sessionCheck.error) return reply({ error: "Unable to verify your session. Please try again." }, 503);
    if (sessionCheck.data !== true) return reply({ error: "Your session ended or requires two-step verification. Log in again." }, 401);

    const owner = await admin
      .from("pfd_platform_owners")
      .select("user_id")
      .eq("user_id", identity.data.user.id)
      .maybeSingle();
    if (owner.error) return reply({ error: "Unable to verify access." }, 503);
    if (!owner.data)
      return reply({ error: "PFD Owner access is required." }, 403);
    const raw = await req.text();
    if (raw.length > 10000) return reply({ error: "Request too large." }, 413);
    const body = raw ? JSON.parse(raw) : {};
    if (!body || typeof body !== "object" || Array.isArray(body))
      return reply({ error: "Invalid request." }, 400);
    const actor = identity.data.user.id;
    if (body.action === "list") {
      const page = Number(body.page ?? 1),
        status = body.status ?? "active",
        query = body.query ?? "";
      if (
        !Number.isSafeInteger(page) ||
        page < 1 ||
        page > 100000 ||
        !["active", "archived", "all"].includes(status) ||
        typeof query !== "string" ||
        query.length > 120
      )
        return reply({ error: "Invalid search or page." }, 400);
      let request = admin
        .from("pfd_clubs")
        .select("*", { count: "exact" })
        .order("created_at", { ascending: false })
        .order("id", { ascending: false });
      if (status !== "all") request = request.eq("status", status);
      if (query.trim())
        request = request.ilike("name", "%" + query.trim() + "%");
      const clubs = await request.range((page - 1) * 12, page * 12 - 1);
      if (clubs.error) return reply({ error: "Unable to load clubs." }, 503);
      const ids = clubs.data.map((club) => club.id);
      const assignments = ids.length
        ? await admin
            .from("pfd_club_admins")
            .select("club_id")
            .in("club_id", ids)
        : { data: [], error: null };
      if (assignments.error)
        return reply({ error: "Unable to load administrator counts." }, 503);
      const counts = new Map<string, number>();
      for (const row of assignments.data || [])
        counts.set(row.club_id, (counts.get(row.club_id) || 0) + 1);
      return reply({
        clubs: clubs.data.map((club) => ({
          ...club,
          administratorCount: counts.get(club.id) || 0,
        })),
        total: clubs.count ?? 0,
        page,
        perPage: 12,
        hasNext: page * 12 < (clubs.count ?? 0),
      });
    }
    if (body.action === "create") {
      const values = fields(body);
      if (!uuid(body.id))
        return reply({ error: "Invalid club identifier." }, 400);
      const club = await admin
        .from("pfd_clubs")
        .insert({ ...values, id: body.id, created_by: actor })
        .select()
        .single();
      if (club.error)
        return reply(
          {
            error:
              club.error.code === "23505"
                ? "This club has already been saved. Refresh the list."
                : "Unable to create the club.",
          },
          club.error.code === "23505" ? 409 : 503,
        );
      return reply({ club: club.data }, 201);
    }
    if (!uuid(body.clubId)) return reply({ error: "Invalid club." }, 400);
    const club = await admin
      .from("pfd_clubs")
      .select("*")
      .eq("id", body.clubId)
      .maybeSingle();
    if (club.error) return reply({ error: "Unable to load this club." }, 503);
    if (!club.data) return reply({ error: "Club not found." }, 404);
    if (
      ["assign_admin", "set_status"].includes(body.action) &&
      !isCompleteClub(club.data)
    ) {
      return reply(
        {
          error:
            "Complete this club's required details before assigning administrators or changing its status.",
        },
        409,
      );
    }
    if (body.action === "get") {
      const memberships = await admin
        .from("pfd_club_admins")
        .select("user_id,created_at")
        .eq("club_id", body.clubId)
        .order("created_at");
      if (memberships.error)
        return reply({ error: "Unable to load administrators." }, 503);
      const administrators = await Promise.all(
        memberships.data.map(async (row) => {
          const result = await admin.auth.admin.getUserById(row.user_id);
          const user = result.data.user;
          return {
            userId: row.user_id,
            grantedAt: row.created_at,
            name:
              typeof user?.user_metadata?.full_name === "string"
                ? user.user_metadata.full_name
                : "",
            email: user?.email || "Account unavailable",
          };
        }),
      );
      return reply({ club: club.data, administrators });
    }
    if (body.action === "update" || body.action === "set_status") {
      if (
        typeof body.updatedAt !== "string" ||
        Number.isNaN(Date.parse(body.updatedAt))
      )
        return reply({ error: "Refresh this club before saving." }, 400);
      let values: Record<string, unknown>;
      if (body.action === "update") values = fields(body);
      else {
        if (!["active", "archived"].includes(body.status))
          return reply({ error: "Invalid club status." }, 400);
        values = { status: body.status };
      }
      const changed = await admin
        .from("pfd_clubs")
        .update({ ...values, updated_at: new Date().toISOString() })
        .eq("id", body.clubId)
        .eq("updated_at", body.updatedAt)
        .select()
        .maybeSingle();
      if (changed.error)
        return reply({ error: "Unable to save this club." }, 503);
      if (!changed.data)
        return reply(
          {
            error:
              "This club changed since you opened it. Refresh and try again.",
          },
          409,
        );
      return reply({ club: changed.data });
    }
    if (body.action === "assign_admin") {
      if (club.data.status !== "active")
        return reply(
          { error: "Restore this club before assigning an administrator." },
          409,
        );
      if (!uuid(body.userId))
        return reply({ error: "Choose an existing PFD account." }, 400);
      const account = await admin.auth.admin.getUserById(body.userId);
      if (account.error || !account.data.user)
        return reply(
          { error: "Account not found. Ask this person to sign up first." },
          404,
        );
      const added = await admin.from("pfd_club_admins").insert({
        club_id: body.clubId,
        user_id: body.userId,
        granted_by: actor,
      });
      if (added.error)
        return reply(
          {
            error:
              added.error.code === "23505"
                ? "This account is already a club administrator."
                : "Unable to assign the administrator.",
          },
          added.error.code === "23505" ? 409 : 503,
        );
      return reply({ ok: true }, 201);
    }
    if (body.action === "remove_admin") {
      if (!uuid(body.userId))
        return reply({ error: "Invalid administrator." }, 400);
      const removed = await admin
        .from("pfd_club_admins")
        .delete()
        .eq("club_id", body.clubId)
        .eq("user_id", body.userId);
      if (removed.error)
        return reply({ error: "Unable to remove this administrator." }, 503);
      return reply({ ok: true });
    }
    return reply({ error: "Unknown club action." }, 400);
  } catch (error) {
    return reply(
      {
        error:
          error instanceof InputError
            ? error.message
            : "Unable to complete this request. Please try again.",
      },
      error instanceof InputError ? 400 : 500,
    );
  }
});
