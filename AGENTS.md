# Agent Guide

## Project map
- [`lib/`](lib/): Flutter application, organized by app, data, domain, and feature areas.
- [`test/`](test/): Flutter unit/widget tests and mocked integration/contract tests.
- [`supabase/migrations/`](supabase/migrations/) and [`supabase/functions/`](supabase/functions/): database policies/schema and Edge Functions. Treat migrations, RLS, auth, and RPC contracts as security boundaries.
- [`tool/ai_3d_worker/`](tool/ai_3d_worker/): independent FastAPI worker. The `demo` provider creates deterministic test artifacts; production model providers require separate setup.

## Setup and run
For reproducible local validation, use Flutter 3.44.8 and Python 3.12, matching the versions pinned in the Quality workflow.

From the repository root, install Flutter dependencies and launch the web app against the local Supabase stack for interactive QA:

```powershell
flutter pub get --enforce-lockfile
.\tool\run_flutter_local_qa.ps1
```

The script starts (or reuses) the local Supabase stack without resetting its database, verifies the API URL is loopback, and serves Flutter at `http://127.0.0.1:20131` with the local publishable key only. Open that URL in an isolated Chrome profile. In the app, use Sign up with a disposable local email/password, confirm the message in Mailpit at `http://127.0.0.1:54333`, return to the app, sign in, and create a sample workspace/project. This exercises the real local Auth flow; it does not bypass authentication or connect to the production Supabase project. Stop the app with Ctrl+C and stop the local stack with `supabase stop` when finished. Do not use production credentials or put private keys in `--dart-define`, assets, logs, or commits.

The Windows app can still be launched with `flutter run -d windows` on a configured Windows desktop host. Its default checked-in Supabase URL and publishable key are public client values, not service-role credentials.

For the isolated worker API test path, create a Python environment, install the committed worker test lock, then run the unittest suite with its coverage gate (including the ASGI demo-provider job/artifact lifecycle):

```sh
python -m venv .venv
# Activate .venv using the command for your shell.
python -m pip install -r tool/ai_3d_worker/requirements.lock
python -m coverage run --source=tool.ai_3d_worker -m unittest tool.ai_3d_worker.test_worker
python -m coverage report --fail-under=60
```

Regenerate the lock only when intentionally updating worker dependencies: `uv pip compile tool/ai_3d_worker/requirements-test.in --python-version 3.12 --output-file tool/ai_3d_worker/requirements.lock`.

The worker suite uses an in-process ASGI transport, temporary artifact storage, and the `demo` provider. It does not contact Supabase or external AI providers. To run the worker interactively instead, see `tool/ai_3d_worker/README.md`; bind it to loopback and use `demo`, never production provider credentials, for smoke checks.

## Validation commands

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test --no-pub --coverage
python -m coverage run --source=tool.ai_3d_worker -m unittest tool.ai_3d_worker.test_worker
python -m coverage report --fail-under=60
python tool/check_markdown_links.py AGENTS.md
python -m unittest tool.test_check_markdown_links
```

CI runs these documented quality commands and checks local links in this guide. The [local QA launcher](tool/run_flutter_local_qa.ps1) and [worker runbook](tool/ai_3d_worker/README.md) provide the interactive run paths.

`flutter test --list-tests` is not supported by the Flutter CLI in this project environment. Run actual tests as above; do not interpret a failed test-list invocation as test execution or successful test collection. The repository's Flutter tests use fakes/mocks for services and do not require a production Supabase account. Tests named as live/backend integration checks may require explicitly configured local or disposable services; inspect their guards before running them.

## Local Git hooks

Install `pre-commit` and `ruff` in the development environment, then enable the checked-in hooks:

```sh
python -m pip install pre-commit ruff==0.17.1
pre-commit install
```

The hooks check staged Dart/Python formatting, lint the Python worker, and reject newly added files larger than 1 MiB. CI independently runs Flutter analysis, Ruff checks, formatting, tests, and Gitleaks.

## Conventions
- Follow the existing feature/data/domain boundaries and use the repository's Riverpod and routing patterns. Search for an existing helper/provider before adding another.
- Keep public behavior and typed contracts explicit. Validate untrusted HTTP/provider data at boundaries; do not swallow unexpected errors.
- Use Dart formatting and the recommended `flutter_lints` rules. Name Dart files `snake_case.dart`, types `UpperCamelCase`, members/variables `lowerCamelCase`, and constants following surrounding Dart conventions.
- Add focused tests for behavior changes. Keep network, Supabase, and provider calls behind injectable clients or test doubles where the existing API supports it.

## Safety constraints
- Do not deploy functions, run shared/production migrations, modify remote Supabase/Vercel resources, or use production credentials for tests without explicit authorization.
- Do not weaken RLS, auth checks, collaboration authorization, worker bearer-token checks, source URL validation, or artifact token checks to make QA easier.
- Never commit real `.env` files, service-role keys, access tokens, model credentials, or private user data. Use only public publishable client configuration or disposable local test fixtures.
- Preserve user changes. Before editing, inspect `git status`; do not overwrite unrelated modified or untracked files.
