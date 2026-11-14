import { validateClubFields, ClubValidationError } from "./validation.ts";
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
    if (raw.length > 180000) return reply({ error: "Request too large." }, 413);
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
    if (body.action === "settings_save")
      body.payload = {
        ...body.payload,
        ...validateClubFields(body.payload || {}),
      };
    const originalAction = body.action;
    const rpcAction =
      originalAction === "prepare_homework_upload"
        ? "homework_upload_access"
        : originalAction === "prepare_resource_upload"
          ? "resource_upload_access"
          : originalAction;
    const result = await service.rpc(
      originalAction.startsWith("player_")
        ? "pfd_player_workspace"
        : "pfd_club_workspace",
      {
        actor_id: identity.data.user.id,
        target_club: body.club_id,
        action: rpcAction,
        payload: body.payload || {},
      },
    );
    if (result.error) {
      const code = result.error.code;
      const status =
        code === "42501"
          ? 403
          : code === "P0002"
            ? 404
            : ["40001", "23505"].includes(code)
              ? 409
              : ["22023", "22007", "22P02", "23502", "23514"].includes(code)
                ? 400
                : 503;
      const message =
        code === "23505"
          ? "This record already exists. Refresh before retrying."
          : ["23502", "23514"].includes(code)
            ? "Check the required fields, dates and values."
            : status === 503
              ? "Unable to complete this club request. Please try again."
              : result.error.message;
      return reply({ error: message }, status);
    }
    if (
      [
        "resource_file_access",
        "file_access",
        "player_resource_file_access",
        "player_homework_file_access",
      ].includes(originalAction)
    ) {
      const file = await service.storage
        .from(result.data.bucket)
        .createSignedUrl(result.data.path, 600);
      if (file.error)
        return reply({ error: "Unable to open this private file." }, 503);
      return reply({ url: file.data.signedUrl });
    }
    if (
      ["prepare_homework_upload", "prepare_resource_upload"].includes(
        originalAction,
      )
    ) {
      const mime = body.payload?.mime;
      const size = body.payload?.size;
      const extensions: Record<string, string> = {
        "video/mp4": "mp4",
        "video/webm": "webm",
        "video/quicktime": "mov",
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/webp": "webp",
        "application/pdf": "pdf",
      };
      if (
        typeof mime !== "string" ||
        !Object.hasOwn(extensions, mime) ||
        typeof size !== "number" ||
        !Number.isSafeInteger(size) ||
        size <= 0 ||
        size > 52428800
      )
        return reply(
          { error: "Use a supported video, image or PDF up to 50 MB." },
          400,
        );
      const path =
        result.data.prefix + crypto.randomUUID() + "." + extensions[mime];
      const upload = await service.storage
        .from(result.data.bucket)
        .createSignedUploadUrl(path, { upsert: false });
      if (upload.error)
        return reply({ error: "Unable to prepare the private upload." }, 503);
      return reply({
        bucket: result.data.bucket,
        path,
        token: upload.data.token,
      });
    }
    return reply(result.data, body.action === "create" ? 201 : 200);
  } catch (error) {
    if (error instanceof ClubValidationError)
      return reply({ error: error.message }, 400);
    return reply(
      {
        error:
          "Unable to complete this club workspace request. Please try again.",
      },
      500,
    );
  }
});
