"use client";

import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import MfaChallenge from "./mfa-challenge";
import type { User, Session } from "@supabase/supabase-js";
import { getSupabase } from "../lib/supabase";

const AuthContext = createContext<{
  user: User | null;
  ready: boolean;
  isOwner: boolean;
}>({ user: null, ready: false, isOwner: false });
export const useAuth = () => useContext(AuthContext);

export default function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);
  const [isOwner, setIsOwner] = useState(false);
  const [factorId, setFactorId] = useState<string | null>(null);
  useEffect(() => {
    const sb = getSupabase();
    let active = true;
    let revision = 0;
    let verifiedId: string | null = null;
    function verify(session: Session | null) {
      const current = ++revision;
      if (!session) {
        setFactorId(null);
        verifiedId = null;
        setUser(null);
        setIsOwner(false);
        setReady(true);
        return;
      }
      if (session.user.id !== verifiedId) {
        setReady(false);
        setIsOwner(false);
      }
      // Keep auth callbacks synchronous. Verify identity and read the protected grant afterwards.
      setTimeout(async () => {
        try {
          const { data, error } = await sb.auth.getUser();
          let verifiedUser = error || !data.user?.email_confirmed_at ? null : data.user;
          let owner = false;
          let pendingFactor: string | null = null;
          if (verifiedUser) {
            const factors = await sb.auth.mfa.listFactors();
            const level = await sb.auth.mfa.getAuthenticatorAssuranceLevel();
            if (factors.error || level.error) throw new Error("Unable to verify account security.");
            const enrolled = factors.data.totp[0];
            if (enrolled && level.data.currentLevel !== "aal2") {
              pendingFactor = enrolled.id;
              verifiedUser = null;
            } else {
              const check = await sb.rpc("pfd_session_status");
              if (check.error || check.data !== true) throw new Error("Session ended.");
            }
          }
          if (verifiedUser) {
            const grant = await sb
              .from("pfd_platform_owners")
              .select("user_id")
              .eq("user_id", verifiedUser.id)
              .maybeSingle();
            owner = !grant.error && !!grant.data;
          }
          if (active && current === revision) {
            setFactorId(pendingFactor);
            verifiedId = verifiedUser?.id || null;
            setUser(verifiedUser);
            setIsOwner(owner);
            setReady(true);
          }
        } catch {
          if (active && current === revision) {
            setFactorId(null);
            setUser(null);
            setIsOwner(false);
            setReady(true);
          }
        }
      }, 0);
    }
    const {
      data: { subscription },
    } = sb.auth.onAuthStateChange((_event, session) => {
      if (active) verify(session);
    });
    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, []);
  return (
    <AuthContext.Provider value={{ user, ready, isOwner }}>
      {factorId && <MfaChallenge factorId={factorId} />}
      <div hidden={!!factorId}>{children}</div>
    </AuthContext.Provider>
  );
}
