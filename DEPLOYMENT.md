# PFD: GitHub, Vercel and your own domain

## Agreed environment direction

Keep the CURRENT PFD Supabase project tzdgdjvxtckkrbbplpzf and existing Resend
sender as PRODUCTION. Existing accounts, owner access, clubs, reports, private
uploads and working email configuration stay intact. No database recreation,
account migration or new Owner grant is needed for this move.

GitHub stores the code. Vercel builds and hosts the website. Your domain points
to Vercel. Supabase and Resend remain the already-running backend/email services.
Afterwards we will connect the ChatGPT copy to a NEW SEPARATE test backend.
Until that switch, both frontends connect to production: avoid test mutations.

Keep the old site connected until the new deployment passes checks on its
Vercel URL. Record old website DNS/domain assignments so they can be restored.

## 1. Put the source on GitHub

1. Extract pfd-platform-live-source.zip. Open its pfd-platform-live-source folder
   in Cursor. The source files must sit at the repository root, not a nested app.
2. In GitHub create a NEW PRIVATE repository named pfd-platform-live, with no
   README, licence or initial .gitignore. Your existing repo remains untouched.
3. In Cursor's terminal, inside the extracted source folder, run:

```
git init -b main
git add .
git commit -m "Import PFD MVP"
git remote add origin https://github.com/danyelhamra/pfd-platform-live.git
git push -u origin main
```

Use the URL GitHub actually shows if the owner/name differs. Authenticate with
GitHub when prompted, keeping tokens/passwords out of chat. The provided
.gitignore excludes .env.local, node_modules, .next and out. No secret values
should be committed. Public Supabase URL/publishable credentials are safe to
include; database access remains governed by Auth and RLS.

## 2. Deploy a new Vercel project on its temporary URL

1. Sign into Vercel with your GitHub account. Add New Project and import the NEW
   danyelhamra/pfd-platform-live repository. Keep the old Vercel project intact.
2. Use the settings declared in vercel.json:

| Setting | Value |
| --- | --- |
| Framework preset | Other |
| Root directory | Repository root |
| Build command | npm run build |
| Output directory | out |
| Install command | npm ci |
| Node.js | 24.x |

This app uses Next.js to export static files and Supabase for server operations.
Selecting Other serves the exact out/ HTML, including the generated CSP.
3. Add these environment variables using the SAME CURRENT Supabase values from
   the included .env.example / current project's dashboard:

```
NEXT_PUBLIC_SUPABASE_URL=https://tzdgdjvxtckkrbbplpzf.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<current project's publishable key>
```

There is no need for a database password, Supabase secret/service key or Resend
API key in Vercel. Authenticated server operations stay in Supabase Functions.
Changing public build variables requires rebuilding/redeploying the frontend.
4. Deploy. Retain the exact stable project address ending in .vercel.app.
   The website will load, but protected API requests need the next step before
   the dashboard works from this new origin.

## 3. Allow the new host in the EXISTING backend

No database setup SQL or initial migrations should be run on production.
The needed backend change is the allowed frontend origin and Auth redirects.

1. Add the exact temporary Vercel origin (https://...vercel.app, no path or ending
   slash) to the origins Set in index.ts for these five included functions:
   pfd-owner-dashboard, pfd-owner-clubs, pfd-club-teams, pfd-memberships,
   pfd-club-workspace. The root domain, www domain, ChatGPT Site and localhost
   addresses are already included in the exported source. Do not allow all
   *.vercel.app sites. Use the exact stable URL Vercel gives you.
2. Deploy the updated functions to the CURRENT project. In Cursor:

```
npx --yes supabase login
npx --yes supabase functions deploy --remote=tzdgdjvxtckkrbbplpzf --use-api
```

The included config.toml retains each function's JWT setting. The five active
functions do their own Auth getUser plus verified/active-session checks before
using service credentials. Never remove those checks. The old registration
function is intentionally retired (410); signup goes through normal Supabase Auth.
Supabase supplies managed server credentials. There is nothing to copy into Git.
3. In CURRENT Supabase > Authentication > URL Configuration, add this exact
   Redirect URL using Vercel's actual address:

```
https://YOUR-EXACT-VERCEL-HOST.vercel.app/auth/callback/
```

Keep the existing ChatGPT callback during transition. Site URL can remain the
current Site until domain cutover, because the app requests its exact callback.
4. Commit and push these source changes to GitHub too so the repository remains
   the record of what is deployed. A GitHub push does NOT deploy Supabase by itself.
5. Test the Vercel URL using your EXISTING PFD account. Confirm Owner access,
   club/team data, reports, file downloads and the signup/recovery email flows.
   Also test on a real iPhone. Existing data is shared, so avoid disposable writes
   in real clubs. Do not change working SMTP, minimum-password or email-confirmation
   settings merely to move the frontend. Your existing Resend domain stays verified.

## 4. Move playerfocusseddevelopment.com from the old website

1. After the Vercel deployment passes, open the NEW project's Settings > Domains.
   Add playerfocusseddevelopment.com and www.playerfocusseddevelopment.com.
   Use https://playerfocusseddevelopment.com as canonical and redirect www to it.
2. If Vercel says the domain belongs to an old Vercel project, move its assignment
   only when the new project is ready. Routing may switch immediately even if
   DNS records do not need to change. Keep the old deployment for rollback.
3. Record old values. In Namecheap > Domain List > Manage > Advanced DNS, change
   ONLY the website records for @ and www to the EXACT A/CNAME values Vercel shows.
   Vercel can supply project-specific targets; never guess an IP or generic CNAME.
   Resolve conflicting website records only for those exact hosts. If DNS is
   hosted elsewhere, edit that provider; do not switch nameservers unnecessarily.
4. PRESERVE the existing email records, including resend._domainkey.auth,
   rsend.auth and send.auth, plus any other mail MX/TXT records. They keep the
   verified auth.playerfocusseddevelopment.com sender working. Website routing
   and email verification records serve different purposes.
5. In the CURRENT Supabase > Authentication > URL Configuration set Site URL to:

```
https://playerfocusseddevelopment.com
```

Add exact additional Redirect URLs:

```
https://playerfocusseddevelopment.com/auth/callback/
https://www.playerfocusseddevelopment.com/auth/callback/
```

Keep the temporary Vercel/ChatGPT callbacks during cutover as needed; remove
unneeded production origins/callbacks only after the test environment is separate.
6. Confirm Vercel shows valid domain configuration and HTTPS. Test root, www,
   direct /account/ loading, login/logout/refresh, verification email links,
   password recovery, dashboards and private uploads on the real domain.
   DNS caches can delay the switch. Keep old hosting until this is confirmed.
   If needed, restore the saved old DNS/domain assignment to roll back the website;
   no database migration is involved, so existing data remains in the same place.

## 5. Make the separate ChatGPT test environment afterwards

1. Create a new Supabase TEST project and review any quoted plan/cost before
   confirming. Production remains tzdgdjvxtckkrbbplpzf; never reset or rebuild it.
2. Run supabase/setup-empty-test-database.sql once in the NEW EMPTY test project
   only. It contains the ordered schema/migration chain and rejects existing PFD
   tables. This is OPTIONAL future test setup, never a production migration.
3. Deploy the included functions to that test project, configure its Auth/SMTP
   independently, and connect ONLY the ChatGPT frontend to its public keys.
   Set its Site URL/callback to the ChatGPT test Site. Verify both frontends'
   project references so test data cannot affect the real database.
4. The duplicate schema does not copy Auth accounts, live data, player videos or
   SMTP secrets. Use synthetic test accounts/data. A real-data copy needs a
   separately planned database/Auth/Storage migration with appropriate privacy.
5. Use separate email credentials/settings for test where practical. Once test
   separation is verified, remove the ChatGPT origin/callback from PRODUCTION.

## Ongoing updates

Git push to main triggers Vercel frontend deployments. Test/review code before
publishing. Database changes and Edge Function changes need a separate reviewed
Supabase deployment; GitHub pushes alone do not apply them. Monitor quotas,
errors and backups/restoration before broad club rollout.

## Verification of this export

Base source: cf6873d545274bb19051056dba7873af203b8f89.
Export-only changes are listed in README.md. The build was checked with the
current project's public browser credentials. The guarded empty-backend bundle
passed all 11 existing isolated SQL suites. No live schema, data, SMTP, GitHub,
Vercel or DNS settings were changed while preparing the export.
