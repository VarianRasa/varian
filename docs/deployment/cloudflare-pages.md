# Cloudflare Pages

Cloudflare Pages serves the Flutter Web frontend. Supabase remains the app's
backend for authentication and cloud-synced project data; local storage remains
available for offline use.

## First-time setup

1. Create a Cloudflare API token with only `Cloudflare Pages: Edit`, scoped to
   the account that will host the site. Do not use `wrangler login`; its OAuth
   flow is not granular.
2. Copy `.env.cloudflare.example` to `.env.cloudflare`, then set
   `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` in the local copy. Never
   commit or share that file.
3. Create a Pages Direct Upload project named `varian-creative-canvas` with
   production branch `main` using
   `npx --yes wrangler@4 --env-file .env.cloudflare pages project create varian-creative-canvas --production-branch main`.
4. Deploy with
   `powershell -ExecutionPolicy Bypass -File .\\scripts\\deploy-cloudflare-pages.ps1`.

For a different project name or production branch, pass `-ProjectName` and
`-Branch` to the PowerShell script. The Pages project must be created with the
same production branch.

After the first deploy, add the site's `pages.dev` origin to the Supabase Auth
Site URL and Redirect URLs. The web app uses the current origin as its auth
redirect URL.

Direct Upload is used so deployment only needs the local Flutter build and
Wrangler; no Git remote is required. Direct Upload projects cannot later be
converted to Git integration; automatic Git deployments require a separate
Pages project.
## Predeploy release gates

The deployment script is fail-closed. Before checking `.env.cloudflare` or
building, it requires locked Flutter dependency resolution, `flutter analyze`,
the full serial Flutter test suite, a supported Dart dependency advisory audit,
locked Deno Edge Function tests, and a disposable local Supabase database reset
plus pgTAP tests. The current script deliberately blocks at the Dart audit gate
because the installed Dart SDK does not support `dart pub audit`; configure a
supported advisory scanner before deployment. Install Flutter/Dart, Deno,
Supabase CLI, and Docker before running it. The local reset is destructive to
the local Supabase database: use only a disposable local instance, never a
linked or production database. A missing prerequisite, tool, lockfile, or
failed command stops the script without deploying.


The script does not yet assert remote migration/policy state, Cloudflare rate
controls, preview-host response headers, browser CSP behavior, or operator
approval. Record those checks separately before production promotion; their
absence is not a pass. Keep production promotion as a deliberate operator
action and retain the previous Pages deployment for rollback.

For a safe gate-path check, run
`powershell -ExecutionPolicy Bypass -File .\scripts\deploy-cloudflare-pages.ps1 -TestMode`.
This test mode runs only the prerequisite gates, then exits before reading
deployment credentials, building the release artifact, or invoking Wrangler.
It does not make any staging or production deployment claim.
