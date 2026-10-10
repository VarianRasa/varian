# Agent Guide

## Project map
- `lib/`: Flutter application, organized by app, data, domain, and feature areas.
- `test/`: Flutter unit/widget tests and mocked integration/contract tests.
- `supabase/migrations/` and `supabase/functions/`: database policies/schema and Edge Functions. Treat migrations, RLS, auth, and RPC contracts as security boundaries.
- `tool/ai_3d_worker/`: independent FastAPI worker. The `demo` provider creates deterministic test artifacts; production model providers require separate setup.

## Setup and run
From the repository root, install Flutter dependencies and launch the web app:

```sh
flutter pub get
flutter run -d chrome
```

The Windows app can be launched with `flutter run -d windows` on a configured Windows Flutter desktop host. The app's checked-in public Supabase URL and publishable key support local startup; they are public client values, not service-role credentials. Authentication uses the normal Supabase Auth flow. Do not add production auth bypasses or put private keys in `--dart-define`, assets, logs, or commits.

For the isolated worker API smoke path, create a Python environment, install the worker's bounded base requirements, and run its tests (including the ASGI demo-provider job/artifact lifecycle):

```sh
python -m venv .venv
# Activate .venv using the command for your shell.
python -m pip install -r tool/ai_3d_worker/requirements.txt
python -m unittest tool.ai_3d_worker.test_worker
```

The worker suite uses an in-process ASGI transport, temporary artifact storage, and the `demo` provider. It does not contact Supabase or external AI providers. To run the worker interactively instead, see `tool/ai_3d_worker/README.md`; bind it to loopback and use `demo`, never production provider credentials, for smoke checks.

## Validation commands

```sh
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test --no-pub --coverage
python -m unittest tool.ai_3d_worker.test_worker
```

`flutter test --list-tests` is not supported by the Flutter CLI in this project environment. Run actual tests as above; do not interpret a failed test-list invocation as test execution or successful test collection. The repository's Flutter tests use fakes/mocks for services and do not require a production Supabase account. Tests named as live/backend integration checks may require explicitly configured local or disposable services; inspect their guards before running them.

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
