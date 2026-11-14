import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { publicProject } from "./project-config";

export const projectUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL || publicProject.url;
const publishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  publicProject.publishableKey;
let client: SupabaseClient | undefined;
export function getSupabase() {
  if (!client) {
    let storage: Storage | undefined;
    let storageKey = "pfd-platform-tab-v2";
    // Discard the previous remembered login on this browser after upgrading.
    // Storage may be blocked in private browsing; login must still work.
    if (typeof window !== "undefined") {
      try {
        window.localStorage.removeItem("pfd-platform-auth-v1");
        window.localStorage.removeItem("pfd-platform-auth-v1-code-verifier");
      } catch {}
      try {
        const tabIdKey = "pfd-platform-tab-id-v2";
        const tabId = window.sessionStorage.getItem(tabIdKey) || crypto.randomUUID();
        window.sessionStorage.setItem(tabIdKey, tabId);
        storage = window.sessionStorage;
        // Separate keys also isolate Supabase's cross-tab broadcast channel.
        storageKey += ":" + tabId;
      } catch {
        // If browser storage is blocked, fall back to memory for this page.
      }
    }
    client = createClient(projectUrl, publishableKey, {
      auth: {
        // Tab session storage survives refresh without a shared localStorage login.
        persistSession: !!storage,
        storage,
        autoRefreshToken: true,
        detectSessionInUrl: false,
        storageKey,
      },
    });
  }
  return client;
}

// Keep redirects on the current app origin; never accept a user-supplied next URL.
export function authCallbackUrl() {
  return new URL("/auth/callback/", window.location.origin).href;
}

export async function registerAccount(name: string, email: string, password: string) {
  const { error } = await getSupabase().auth.signUp({
    email, password,
    options: { data: { full_name: name }, emailRedirectTo: authCallbackUrl() },
  });
  if (error) throw error;
}
