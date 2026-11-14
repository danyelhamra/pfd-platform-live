// Retired: registration now goes through Supabase Auth's verified-email flow.
// Fail closed for old clients. Never recreate the administrative auto-confirm path.
Deno.serve(() => new Response(JSON.stringify({
  error: "Please refresh the website and use Sign up to verify your email.",
}), { status: 410, headers: {
  "Content-Type": "application/json", "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "https://pfd-development-build.dany-elhamra-8394.chatgpt.site",
} }));
