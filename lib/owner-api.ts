import { getSupabase } from "./supabase";

export async function ownerRequest<T>(
  name: "pfd-owner-clubs" | "pfd-owner-dashboard",
  body: Record<string, unknown>,
): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);
  try {
    const result = await getSupabase().functions.invoke(name, {
      body,
      signal: controller.signal,
    });
    if (result.error) {
      let message = "Unable to complete this request. Please try again.";
      if (result.error.context instanceof Response) {
        try {
          message = (await result.error.context.json()).error || message;
        } catch {}
      }
      throw new Error(message);
    }
    if (result.data?.error) throw new Error(result.data.error);
    return result.data as T;
  } finally {
    clearTimeout(timeout);
  }
}
