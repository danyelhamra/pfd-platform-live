"use client";
import Link from "next/link";
import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "../../auth-provider";
import AccountMenu from "../../account-menu";
import ClubAdminDashboard from "../club-admin-dashboard";
export default function ClubAdminPage() {
  const { user, ready, isOwner } = useAuth();
  const router = useRouter();
  useEffect(() => {
    if (ready && user && isOwner) router.replace("/account/");
  }, [ready, user?.id, isOwner, router]);
  if (!ready || (user && isOwner))
    return (
      <main className="container workspace-main">
        <p role="status">Opening your account…</p>
      </main>
    );
  if (user) return <ClubAdminDashboard key={user.id} user={user} />;
  return (
    <>
      <header className="site-header">
        <div className="container header-inner">
          <Link className="wordmark" href="/">
            PFD<span>.</span>
          </Link>
          <AccountMenu />
        </div>
      </header>
      <main className="container workspace-main">
        <p className="eyebrow">CLUB WORKSPACE</p>
        <h1 className="workspace-title">Welcome to PFD.</h1>
        <p className="workspace-description">
          Log in to open your assigned club workspace.
        </p>
        <Link className="text-link" href="/">
          ← Back to the platform
        </Link>
      </main>
    </>
  );
}
