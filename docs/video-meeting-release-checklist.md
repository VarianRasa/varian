# Video meeting release checklist

Use this checklist for the Flutter Web/Windows LiveKit meeting release. Record the
operator, UTC date, build revision, target versions, and evidence paths for every
run. A unit test or local provider smoke test does not replace the two-client
matrix.

## 1. Configuration and no-secret review

- [ ] Confirm the meeting feature is disabled by default: omit
      `VIDEO_MEETING_ENABLED`, or set it to `false`.
- [ ] Confirm the client-safe defines are the only meeting defines in a Flutter
      build:
  - `VIDEO_MEETING_ENABLED` (default `false`)
  - `LIVEKIT_URL` (public provider endpoint; default empty)
  - `VIDEO_MEETING_MAX_PARTICIPANTS` (default `8`, accepted range `2..8`)
- [ ] Confirm the client bundle, `--dart-define` arguments, assets, URLs, logs,
      and source control contain no `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`,
      Supabase service-role key, TURN credential, provider token, SDP, or ICE
      candidate.
- [ ] Confirm both meeting Edge Functions read these deployment-only names from
      their function environments:
  - `meeting-token`
  - `meeting-remove-participant`
  - `LIVEKIT_URL`
  - `LIVEKIT_API_KEY`
  - `LIVEKIT_API_SECRET`
  - `ALLOWED_ORIGINS`
- [ ] Confirm `ALLOWED_ORIGINS` contains exact browser origins only; no wildcard,
      path, or credential is committed. Missing `Origin` is reserved for the
      authenticated native Windows path; browser origins must be explicitly
      allowlisted.
- [ ] Confirm `supabase/config.toml` retains both function entries with
      `verify_jwt = false`; each function validates the Bearer token itself.
- [ ] Manually verify Bearer authentication for `meeting-remove-participant`
      during release testing.
- [ ] Review command output and release artifacts for secret values. Report
      only variable names and redacted paths; never paste environment values into
      this checklist or an evidence artifact.

The repository gate is safe to run before provider credentials exist. It checks
both function files, shared contract names, and the disabled-by-default setting,
then runs the focused meeting suite, analyzer, Web release build, and Windows
release build in order. It never prints environment values:

```powershell
powershell -ExecutionPolicy Bypass -File tool/video_meeting_platform_matrix.ps1
```

After the deployment environment has been populated, require the server names
and their non-empty process values without printing those values:

```powershell
powershell -ExecutionPolicy Bypass -File tool/video_meeting_platform_matrix.ps1 `
  -RequireServerConfiguration
```

Keep `VIDEO_MEETING_ENABLED` off while collecting the manual evidence below.

## 2. Server deployment

- [ ] Link the intended Supabase project and apply the meeting migration.
- [ ] Deploy exactly `meeting-token` and `meeting-remove-participant`, both with
      `verify_jwt = false`.
- [ ] Set the four shared deployment-only names in both Supabase Edge Function
      environments. The removal function requires server LiveKit credentials to
      call the LiveKit room service. Use a secret manager or already-exported
      process environment; do not put literal values in shell history, source
      control, Flutter defines, or this document.
- [ ] Verify the token function accepts authenticated `POST` and `OPTIONS`,
      rejects other methods, checks the exact origin allowlist, and returns no
      token when configuration, authentication, membership, meeting status, or
      provider capacity checks fail.
- [ ] Verify the removal function accepts authenticated `POST` and `OPTIONS`,
      rejects other methods, validates host authorization and UUID identities,
      and returns exactly `{ "removed": true }` or `{ "removed": false }`.
- [ ] Treat `{ "removed": false }` as an idempotent successful no-op; malformed
      success payloads are unavailable errors.
- [ ] Verify neither function exposes API keys, API secrets, service-role keys,
      raw provider errors, or other credential details.

Deployment commands (the placeholders are names/placeholders only; do not
replace them with committed credentials):

```powershell
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --linked --yes
supabase functions deploy meeting-token --use-api
supabase functions deploy meeting-remove-participant --use-api
supabase secrets set `
  LIVEKIT_URL=$env:LIVEKIT_URL `
  LIVEKIT_API_KEY=$env:LIVEKIT_API_KEY `
  LIVEKIT_API_SECRET=$env:LIVEKIT_API_SECRET `
  ALLOWED_ORIGINS=$env:ALLOWED_ORIGINS
```

Bearer authentication for participant removal is a manual verification step;
the Supabase gateway does not enforce JWT validation because both function
entries deliberately use `verify_jwt = false`.


## 3. Rollout and client builds

- [ ] First deploy and smoke-test with the flag omitted or `false`; the app
      remains unavailable and does not request camera, microphone, or a token.
- [ ] For an authorized canary only, build Chrome and Windows with
      `VIDEO_MEETING_ENABLED=true` and the public `LIVEKIT_URL`. Never pass the
      API key or secret as a client define.
- [ ] Confirm the client requires both the true flag and a non-empty provider URL
      before it is available. Confirm server-issued `serverUrl` and token remain
      authoritative.
- [ ] Confirm capacity remains bounded at `2..8`, with `8` as the default.
- [ ] Confirm viewer grants subscribe access without publish access; owners,
      editors, and commenters receive only the publish capabilities allowed by
      the server contract.
- [x] Keep the rollout flag off until both manual matrix directions pass and the
      evidence is reviewed.

## 4. Manual dated Windows/Chrome matrix

For each direction, record an absolute UTC timestamp, app/build revision, Flutter
and browser/Windows versions, user roles, meeting ID redacted to a stable
reference, and a screenshot/log path that contains no token or secret. Use two
authorized users in an active project; do not use a personal browser profile in
release evidence.

### Windows host ↔ Chrome guest

- [ ] Host creates one active meeting; guest joins through the meeting route.
- [ ] Roster, identity labels, role state, mute/camera-off state, and active
      speaker state are correct on both clients.
- [ ] Windows camera and microphone publish; Chrome receives them.
- [ ] Chrome camera and microphone publish; Windows receives them.
- [ ] Windows screen share starts and stops from the browser/desktop capture
      boundary without affecting canvas screen tracking.
- [ ] Chrome screen share starts and stops; both clients recover when the picker
      is cancelled.
- [ ] Deny browser camera/microphone permission, verify a safe permission error,
      then grant permission and retry successfully.
- [ ] Deny Windows device permission, verify a safe permission error, then grant
      permission and retry successfully.
- [ ] Cause a temporary network interruption; capture `reconnecting`, recovery,
      and participant/media state after reconnect.
- [ ] Guest leaves; host remains connected and local guest media is stopped.
- [ ] Host removes the guest; the guest is disconnected, cannot refresh a token,
      and sees only the safe removed message.
- [ ] Host ends for everyone; both clients disconnect, leave the route cleanly,
      and the durable session is `ended`.
- [ ] Revoke the collaboration room/session; meeting access stops and a late
      provider event does not restore the route or media.

### Chrome host ↔ Windows guest

- [ ] Repeat every check above with host and guest reversed, including camera,
      microphone, screen share, picker cancellation, both permission-denial
      retries, temporary network interruption/reconnect, guest leave, host
      remove, host end, and collaboration-room revoke.
- [ ] Confirm host-only controls are unavailable to the Windows guest and viewer
      publish is denied in this direction as well.

Local safe-gate verification completed in this worktree: focused meeting tests,
`flutter analyze --no-pub`, `flutter build web --no-pub`, and
`flutter build windows --no-pub` passed with the feature disabled. Full repository
`flutter test --no-pub` remains blocked by unrelated existing failures outside the
meeting gate. No authenticated deployment or two-client manual matrix was run.

## 5. Cleanup and evidence review

- [ ] Route leave, route disposal, provider disconnect, ended session, remove,
      and revoke stop local audio/video/screen-share tracks, disconnect the
      provider, unsubscribe the meeting stream, clear participant state, and
      ignore late provider events.
- [ ] Confirm ordinary Leave disconnects only the local participant; End for
      everyone performs the durable Supabase transition.
- [ ] Confirm meeting cleanup does not stop or mutate the separate canvas
      collaboration screen-tracking session.
- [ ] Confirm token refresh obtains a new short-lived token through
      `meeting-token`; it never uses a client API secret or changes the meeting
      ID.
- [ ] Review screenshots, terminal logs, browser console/network captures, and
      build artifacts. Remove or redact authorization headers, token payloads,
      provider credentials, room names where sensitive, SDP, ICE candidates, and
      personal account data.
- [ ] Attach the focused contract-test result and the release-gate result with
      command, exit code, UTC timestamp, and redacted evidence path.
- [ ] Keep the rollout flag disabled if any provider, permission, reconnect,
      cleanup, authorization, or no-secret check is incomplete.
