# PFD — Player Focused Development

Portable source for the public MVP released 13 November 2026, based on source
commit cf6873d545274bb19051056dba7873af203b8f89.

Read DEPLOYMENT.md before connecting the domain. The CURRENT Supabase project,
accounts, clubs, reports, private files and Resend email setup become production.
They remain hosted where they are. This source contains public browser keys;
it contains no service-role keys, Resend secrets, passwords, database rows,
uploaded player videos or Git credentials. A separate ChatGPT test backend will
be configured afterwards. Until then both frontends share the same database.

## Local development

Use Node.js 24 LTS:

```
npm ci
npm run dev
```

Open http://localhost:4173. Public connection defaults point to the current PFD
backend tzdgdjvxtckkrbbplpzf, now designated production by the owner. Be aware
that local edits/data operations therefore affect real data unless overridden.
An optional .env.local can supply the two public values shown in .env.example.
Never put Supabase service-role/secret keys or Resend API keys in NEXT_PUBLIC
variables. Those belong only in the appropriate backend/provider settings.

Build with npm run build. The static export is out/. On Vercel use Framework
Preset Other, Build npm run build, Output out, Install npm ci, Node.js 24.x.
vercel.json supplies this configuration. No Node server is needed at runtime.

## Export-specific changes

- ChatGPT Site identity and Git metadata omitted.
- Existing public Supabase configuration preserved, as requested by the owner.
- Root and www live domains added to protected Edge CORS allowlists; current
  ChatGPT and local origins retained during the transition.
- Header generation loads .env.local using Next's environment loader.
- Vercel serves the exact static out/ output. Build-specific CSP hashes stay in
  HTML meta tags, because Vercel reads configuration before running the build;
  old build hashes must not become a conflicting response-header policy.
- Optional guarded setup-empty-test-database.sql provided ONLY for a future NEW
  EMPTY test backend. Do not run it, or any initial schema scripts, on production.

All product features and original report questions remain unchanged.
The original ChatGPT Site/backend have not been modified while preparing this
package. No GitHub push, Vercel deployment or domain change has happened yet.

app/: pages and dashboards. lib/: clients/permissions/report models.
public/: static assets. scripts/: build policy generation.
supabase/: schema, migrations and Edge Functions. tests/: regression checks.
docs/: report provenance and historical audit notes. DEPLOYMENT.md is the
current handoff plan and supersedes older deployment notes.
