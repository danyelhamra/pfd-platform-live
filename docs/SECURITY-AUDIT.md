# PFD MVP security and bug audit — 13 November 2026

Engineering audit and regression checks completed for the changes below.
This is not a certification, independent penetration test, or approval to launch.
Email confirmation and recovery were subsequently tested successfully by the owner.
CAPTCHA is explicitly deferred for this release; physical iPhone testing remains open.

## Fixed and deployed backend controls

- Retired the administrative signup endpoint (HTTP 410). It previously used
  `email_confirm:true` and bypassed the project's email confirmation setting.
  Signup now uses the normal Supabase Auth API and requires email confirmation.
- All five protected Edge endpoints verify the token with Auth, then check its
  canonical user/session against the database before accessing application data.
- Restrictive RLS on all 28 PFD tables and both PFD storage buckets requires a
  confirmed, non-deleted, non-banned user and an existing unexpired Auth session.
  It ANDs with the existing role/club/team/player policies and grants no new rows.
- Verified MFA factors require both an AAL2 JWT and AAL2 database session.
- Only service_role can supply another actor/session to the session-check RPC.
  Clients can check their own session only. Private definers have an empty
  search_path and narrowly scoped grants. No public security-definer function.
- Upload MIME allowlisting now rejects inherited object keys and fractional sizes.
  Buckets stay private, limited to 50 MB and the existing allowed formats.

## Native Auth settings verified in dashboard

- Email confirmation ON. Anonymous signup and manual linking OFF.
- Password minimum 8 characters, changed at the owner’s request and confirmed saved by the owner. Secure email/password changes ON.
- Email confirmation/recovery link expiration 900 seconds, OTP length 8 digits.
- Signup/signin rate configured at 10 requests per 5 minutes per IP, reduced from
  30. This is a token-bucket rate, not a strict 10-attempt account lockout;
  bursts and distributed IP attacks remain possible. IP forwarding remains OFF.
- Refresh limits unchanged at 150/5 min; verification 30/5 min.
- Default Site URL corrected from localhost to the PFD test Site. Exact callback
  URL allowlisted; no wildcard or arbitrary user-controlled redirect.
- TOTP authenticator support is enabled. No existing user's MFA was enrolled,
  password changed or account reset by this audit.

## Application controls

- Confirmation callback removes URL credentials immediately, verifies the email
  link's identity, and asks the user to continue with the displayed account.
  No arbitrary next URL or redirect is accepted.
- Resend confirmation and password reset flows; generic eligible-email messages.
- Password recovery uses 8-character passwords and signs out all sessions on
  success. AuthProvider checks confirmed email, MFA and active session status.
- Account security page offers optional authenticator enrollment and global
  sign-out. Verified authenticator challenges gate protected application access.
  QR secrets stay in the user's UI, never PFD tables or logs. Users should back up
  their authenticator securely before enabling it. Lost-factor recovery requires
  a separately verified support process; do not bypass MFA using password reset.
- Existing per-tab sessionStorage behavior is preserved: refresh retains login,
  while separate tabs use separate storage/broadcast keys.
- Static export adds CSP with hashes for Next's inline bootstrap scripts; no
  unsafe-inline JavaScript, external script hosts, objects or embedded frames.
  Inline CSS is allowed for existing React styles. No frame-ancestors restriction
  is imposed because the ChatGPT Site can be embedded by its host.
- CSP/referrer meta tags work in the static HTML. `_headers` and `vercel.json`
  supply CSP, nosniff, HSTS, referrer and permissions headers on hosts supporting
  those formats. Host-level header delivery must be checked on the final host;
  a successful build alone does not prove every HTTP header is served by Sites.

## Verification evidence

- All 11 SQL suites PASS in isolated PGlite and against the Supabase test backend
  in rollback-only transactions: player dashboard, coach homework, coach library,
  club workspace, teams, membership admission, club shell, owner workspace,
  library/match reports, permissions, and the new session security suite.
- Live session suite proves confirmed active access, immediate revoked-token
  denial, foreign-session denial, ban/expiry denial, MFA AAL enforcement and
  editable-metadata role spoofing rejection. No production authorization bypass
  was added to make test fixtures pass.
- Actual Edge handler tests PASS for verified actor identity, forged actor IDs,
  origins, permission denial, signed file scoping, MIME/size limits, and
  unverified/revoked/malformed sessions or database failures across all 5 Edges.
- Live HTTP checks: all 5 protected Edges return 401 without a user token;
  retired signup returns 410, and the service-only session RPC returns 401.
- Report provenance PASS: all 5 original templates and 75 questions preserved.
- Owner/Club workspace separation checks PASS.
- Production build and TypeScript PASS. All 8 generated HTML documents have
  hash-based CSP; exported text/JS contains no detected privileged key references,
  service-role JWTs, secret API keys or private-key headers.
- npm audit: zero known dependency vulnerabilities on this run.
- Supabase security advisor: one remaining warning, leaked password protection
  disabled. Dashboard confirms that feature requires Pro. No paid upgrade made.
- After rollback checks: 4 real accounts, 1 club, 1 report, 2 resources;
  zero leftover fixture accounts. Existing data preserved.
- Login rate-setting screenshot: audit-evidence/rate-limits.jpg.

## Outstanding setup and practical limits

1. Resend SMTP was configured by the owner after verifying
   auth.playerfocusseddevelopment.com. The owner confirmed successful real-mailbox
   signup verification and password recovery. The agent did not read SMTP keys,
   passwords or email tokens. Resend sending quotas still apply.
2. CAPTCHA is OFF, explicitly deferred by the owner for this release. Native
   server rate limits remain active. Do not claim CAPTCHA/bot challenges are
   enabled, or enable them without matching frontend support.
3. Leaked-password detection is not available on this project's Free plan.
   Consider an authorised Pro upgrade before public rollout. Not enabled here.
4. Final desktop Owner browser QA passed: overview, clubs, users, access requests,
   reports/template preview, library, settings/permissions, security page,
   sidebar, refresh persistence, separate-tab isolation and logout/protected-route
   denial. Only browser extension metadata errors were observed. No business
   records or permissions were saved during this walkthrough. The other roles
   retain automated workflow/permission coverage. Physical iPhone/Safari testing
   and a complete non-owner browser walkthrough are not claimed. Managed local
   preview still fails because its daemon appends Vite flags to Next.js; no
   infrastructure bypass or app workaround was introduced.
5. The original four MVP test accounts were automatically confirmed previously.
   Their confirmed timestamps are not proof of mailbox verification. Preserve
   their data here; create genuinely verified users in a separate live backend.
6. Already-issued signed download URLs remain usable until their 10-minute
   expiry; already-downloaded files cannot be recalled. Signed upload capability
   expiry is managed by Storage and does not equal immediate JWT revocation.
   Immediate session checks apply to new protected API/database operations.
7. Upload restrictions do not provide antivirus/content scanning. Do not claim
   malware scanning. No external penetration test, load test or email-delivery
   certification was performed.
8. Test/live need separate Supabase projects, keys, file buckets and redirect
   settings before deployment on the existing domain. Configure verified backup,
   restoration, monitoring and a lost-factor support process before real clubs.

## Repeatable local checks

```
npm run build
node tests/security-build.cjs
PFD_PGLITE_PACKAGE=/tmp/pfd-workspace-validation/node_modules/@electric-sql/pglite node tests/run-local-db.cjs
node tests/edge-session-security.cjs
node tests/club-workspace-edge.cjs
node tests/club-teams-edge.cjs
node tests/membership-edge.cjs
node tests/club-workspace-separation.cjs
node tests/report-template-provenance.cjs <original-report.html>
npm audit
```

## Final release pass

All 11 local SQL suites, Edge/session checks, original report provenance,
workspace separation, production build, CSP/export scan and dependency audit
passed again. No database code changed since the successful live rollback suites.
Live checks confirmed RLS on all 28 public tables and private 50 MB file buckets.
Two stale product messages were corrected without changing permissions or data.
Current user decisions and remaining limits are recorded in AUDIT-CHECKPOINT.md.
Desktop screenshots: audit-evidence/public-home.jpg and logged-out-account.jpg.
