# PFD release checkpoint — 13 November 2026

Current Site: appgprj_6af6449a0af08191bcfe029e46e8f6c7
URL: https://pfd-development-build.dany-elhamra-8394.chatgpt.site
Audience: PUBLIC at the owner's explicit request. Preserve public access.
Supabase: tzdgdjvxtckkrbbplpzf. Do not use hrzsklvopeahtttajopp.
Preserve existing accounts, club, memberships, reports and resources.

## Current decisions and verified status

- CAPTCHA remains OFF, explicitly deferred by the owner for this release.
- Native rate limiting stays active. No paid plan or services were purchased.
- Signup and recovery use an 8-character minimum at the owner's request.
  The owner confirmed saving the matching Supabase minimum of 8.
- Resend domain auth.playerfocusseddevelopment.com verified by owner; custom SMTP
  configured by owner. Owner successfully tested actual email confirmation AND
  password recovery through a real mailbox and returned to the app successfully.
- Retired auto-confirm signup Edge remains 410; active-session checks and RLS
  remain deployed, including MFA enforcement for enrolled users.
- Optional authenticator setup and global logout remain available. No factor was
  enrolled and no password was entered or changed by the agent during QA.
- Future registration payments, subscriptions and clothing are INTERNAL ROADMAP
  ONLY. Do not add these features or mention them in the current product UI.

## Final checks

PASS: production build, TypeScript, secret/CSP export scan, actual Edge handler
security tests, workspace separation, original-template provenance (5 templates,
75 questions unchanged), all 11 isolated SQL workflow/security suites, npm audit
(0 known vulnerabilities). The same SQL suites passed live in the preceding
security audit; no database implementation changed in this final release pass.
Live read checks: all 28 public tables have RLS; both file buckets remain private
with 50 MB limits. Security advisor's only warning is the Free-plan limitation
on leaked-password protection. No test users or data were created by this pass.

PASS in actual desktop browser with canonical Owner login via secure prompt:
public homepage/account modal; Owner overview, clubs, users, access requests,
reports and original-template preview, development library, settings and
permission editor; sidebar hide/show; account security page; refresh retains
login; separately opened account tab stays signed out; logout locks account
route; homepage image and back-to-top navigation.
Only browser errors observed were extension metadata errors, not PFD errors.
No production report, club, resource, permission or profile was saved during QA.

Fixed two stale UI messages: onboarding requests were wrongly described as not
connected, and permission guidance wrongly described all controls as unfinished.

NOT claimed: physical iPhone/Safari testing, authenticated browser walkthroughs
of every non-owner role, malware scanning, independent pentest or load testing.
Other roles have automated database and Edge coverage. Managed local preview
still fails due to daemon-added Vite flags; do not bypass preview controls or
change valid Next.js app code to compensate.

## Publication and future deployment

Use the official Sites source helper to push/package, then save_site_version and
deploy_site_version for this PUBLIC audience. Do not use private deployment.
Refresh short-lived source credentials; never print or save them in files.
The user's own GitHub/custom-domain deployment and a separately isolated live
backend are separate work from this public ChatGPT-hosted release. Do not claim
that DNS, GitHub export or backend separation have happened.
