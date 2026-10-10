# Image-to-Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the AI Creative Engine generate a real image-to-video result through a secure asynchronous fal.ai queue adapter and materialize the completed MP4 as a canvas video node.

**Architecture:** Flutter sends image-to-video jobs to a Supabase Edge Function named `ai-video`; the Edge Function verifies Supabase JWTs, keeps `FAL_KEY` server-side, submits and polls a configured fal.ai queue model, and returns only structured job status and a validated video URL. Flutter polls the function, maps the completed result to `AIJob`, and creates a `VideoPayload` only when a non-empty HTTPS video URL exists. Anonymous Supabase Auth is enabled automatically for users without a session so public usage has a user identity for rate limiting.

**Tech Stack:** Flutter/Dart 3.12.2, Riverpod, `http`, `supabase_flutter`, Supabase Edge Functions/Deno, fal.ai Queue REST API.

**Spec:** `docs/superpowers/specs/2026-08-17-ai-creative-engine-design.md`

## Global Constraints

- Do not send `FAL_KEY` or another provider secret to Flutter or the browser.
- Use `POST /v1/ai/generate` and `GET /v1/ai/jobs/{id}` semantics internally through the `ai-video` Edge Function actions `create` and `poll`.
- Accept only HTTPS public image URLs or bounded `data:image/*;base64,...` inputs at the Edge Function boundary.
- Do not create a canvas video node until the terminal response contains a validated HTTPS video URL.
- Reuse the existing `http` and `supabase_flutter` dependencies; add no provider SDK.
- Keep existing synchronous image-generation routes unchanged.
- No comments in production code.

---

### Task 1: Define the async video contract and regression tests

**Files:**
- Modify: `lib/domain/models/ai_job.dart:216-270`
- Test: `test/features/ai/ai_service_video_test.dart`

**Interfaces:**
- `AIService.executeJob` must route `imageToVideo` and `videoFromImage` to an async video operation instead of returning the old synchronous-endpoint error.
- `AIJob.category` must return `AICreativeCategory.videoAI` for `AICapability.imageToVideo`.

- [ ] **Step 1: Write failing tests**

Add tests that construct a video job with `sourceImageBase64`, inject a fake video function invoker returning one create response followed by `COMPLETED`, and assert that the result is completed, categorized as `videoAI`, and contains the returned MP4 URL. Add a failure test asserting a terminal provider failure becomes `AIJobStatus.failed` with the provider message.

- [ ] **Step 2: Run the focused test to verify RED**

Run: `flutter test test/features/ai/ai_service_video_test.dart`

Expected: FAIL because `imageToVideo` is currently categorized as generation and `AIService` has no video invoker or polling route.

- [ ] **Step 3: Make the smallest domain change**

Move `AICapability.imageToVideo` into the `videoAI` branch of `AIJob.category`; leave all other capability mappings unchanged.

- [ ] **Step 4: Run the focused test again**

Run: `flutter test test/features/ai/ai_service_video_test.dart`

Expected: The category assertion passes while async service assertions still fail.

---

### Task 2: Implement the tested Flutter async video adapter

**Files:**
- Modify: `lib/features/ai/data/ai_service.dart:15-105`
- Test: `test/features/ai/ai_service_video_test.dart`

**Interfaces:**
- Add a public type alias `AIVideoFunctionInvoker = Future<Map<String, dynamic>> Function(Map<String, dynamic> body);`.
- Extend `AIService` with an optional `AIVideoFunctionInvoker` while preserving existing positional constructor calls.
- Create requests with `{action: "create", prompt, imageUrl?, imageData?, duration: "5", aspectRatio: "16:9", negativePrompt?, cameraMotion?, capability}`.
- Poll with `{action: "poll", requestId}` until `queued`, `processing`, or `in_progress` becomes `completed`/`succeeded`, or `failed`/`canceled`/`cancelled`.
- Return a completed job only after a non-empty `videoUrl` is found; reject malformed or non-HTTPS result URLs.

- [ ] **Step 1: Extend the tests for request shape and polling**

The fake invoker must assert the first body has `action: create`, a `data:image/png;base64,` source, prompt, duration, aspect ratio, and camera motion. It must return `{requestId: "req-1", status: "queued"}` and then `{requestId: "req-1", status: "completed", videoUrl: "https://cdn.example/video.mp4"}`. Add a test for a missing invoker returning a clear Supabase configuration error.

- [ ] **Step 2: Run the focused test to verify RED**

Run: `flutter test test/features/ai/ai_service_video_test.dart`

Expected: FAIL because the invoker type and video route do not exist.

- [ ] **Step 3: Implement the minimum adapter**

Add the invoker field, route video capabilities before the unsupported switch branch, build a bounded data URI from raw base64, call the invoker, validate response maps and statuses, poll with an injectable zero-or-more delay for tests and a two-second production interval, cap polling at 90 attempts, and convert all terminal failures to `AIJobStatus.failed`.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run: `flutter test test/features/ai/ai_service_video_test.dart`

Expected: PASS with request-shape, polling, success, malformed-result, and failure assertions.

- [ ] **Step 5: Run existing AI tests**

Run: `flutter test test/features/ai/ai_service_web_test.dart test/features/ai/ai_service_responses_fallback_test.dart test/features/ai/ai_image_source_test.dart`

Expected: PASS; synchronous image behavior remains unchanged.

---

### Task 3: Add Supabase anonymous session and Edge Function invocation boundary

**Files:**
- Modify: `lib/data/remote/supabase_service.dart:1-70`
- Modify: `lib/features/ai/state/ai_provider.dart:10-14`
- Test: `test/features/backend_sync_test.dart`

**Interfaces:**
- Add `Future<void> ensureAnonymousSupabaseSession(SupabaseClient client)` that preserves an existing session and calls `signInAnonymously()` only when no session exists.
- Add `Future<Map<String, dynamic>> invokeAIVideoFunction(SupabaseClient client, Map<String, dynamic> body)` that ensures the session, invokes `ai-video`, converts a map response, and throws a user-safe `SyncException` for non-2xx or malformed responses.
- `aiServiceProvider` supplies the invoker when a Supabase client exists and leaves it null when Supabase is not configured.

- [ ] **Step 1: Add boundary tests**

Cover the no-client error through the AI service and the response-map conversion using the existing injectable AI invoker seam. Keep the Supabase SDK boundary thin; do not mock global SDK state in unit tests.

- [ ] **Step 2: Run focused tests to verify RED**

Run: `flutter test test/features/backend_sync_test.dart test/features/ai/ai_service_video_test.dart`

Expected: The new invocation behavior is absent while existing tests continue to identify the current implementation.

- [ ] **Step 3: Implement the Supabase boundary**

Use the official `SupabaseClient.auth.currentSession`, `signInAnonymously`, and `client.functions.invoke('ai-video', body: body)` APIs. Extract `FunctionsHttpException.details` without exposing keys or stack traces. Update `aiServiceProvider` to pass a closure around the current client.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run: `flutter test test/features/backend_sync_test.dart test/features/ai/ai_service_video_test.dart`

Expected: PASS.

---

### Task 4: Implement the secure fal.ai Edge Function

**Files:**
- Create: `supabase/functions/ai-video/index.ts`
- Modify: `supabase/config.toml:5-6`
- Create: `supabase/migrations/20260824010000_create_ai_video_jobs.sql` only if durable job ownership is required by the final function implementation
- Test: `supabase/functions/ai-video/index.test.ts` if a Deno test harness is available; otherwise use the deployed HTTP smoke script in Task 6

**Interfaces:**
- `POST /functions/v1/ai-video` with `action: "create"` returns `{requestId, status}`.
- `POST /functions/v1/ai-video` with `action: "poll"` and `requestId` returns `{requestId, status, progress?}` while queued/processing and `{requestId, status: "completed", videoUrl}` when done.
- Every error returns `{error: {code, message}}` with a 4xx/5xx status and no provider key or upstream body dump.

- [ ] **Step 1: Define the function contract fixture**

Use a local fixture describing create, queued, processing, completed, failed, malformed, unauthorized, oversized, and private-image cases. The fixture must assert that `FAL_KEY` is read only from `Deno.env` and that outbound authorization uses `Authorization: Key ...`.

- [ ] **Step 2: Run the function check to verify RED**

Run: `npx --yes deno check supabase/functions/ai-video/index.ts`

Expected: FAIL because the function file does not exist.

- [ ] **Step 3: Implement create and poll**

Use `Deno.serve`, require JWT verification through Supabase function configuration, enforce `POST`, parse a bounded body, cap prompt and source sizes, validate public HTTPS URLs/data URIs, map the request to the configured model (default `fal-ai/kling-video/v2.1/standard/image-to-video`), submit to `https://queue.fal.run/{model}`, poll `.../requests/{id}/status`, fetch `.../requests/{id}` only after completion, extract `video.url`, and apply a small per-subject in-memory create rate limit.

- [ ] **Step 4: Run the function check to verify GREEN**

Run: `npx --yes deno check supabase/functions/ai-video/index.ts`

Expected: PASS.

---

### Task 5: Wire the UI and result materialization

**Files:**
- Modify: `lib/features/ai/state/ai_provider.dart:197-300`
- Modify: `lib/features/ai/presentation/ai_panel.dart:438-447, 481-488, 796-819`
- Modify: `lib/features/ai/data/ai_service.dart:880-898`
- Test: `test/features/ai/ai_image_source_test.dart` or a new focused provider test

**Interfaces:**
- Selecting `Image → Video (Motion)` from Generation must use the video route and produce a `NodeType.videoCard`.
- A missing source image must fail before network invocation with a readable message.
- A completed video node must contain the returned URL and never an empty URL.

- [ ] **Step 1: Add the node-materialization regression test**

Construct a completed `AIJob` with `AICapability.imageToVideo` and an MP4 URL, call `spawnVideoNodeFromJob`, and assert `VideoPayload.videoUrl` equals the URL. Add an assertion that an empty URL is rejected by the service path rather than materialized.

- [ ] **Step 2: Run the focused test to verify RED**

Run: `flutter test test/features/ai/ai_image_source_test.dart`

Expected: The category/materialization assertions fail until the route and validation are wired.

- [ ] **Step 3: Wire the provider and UI**

Keep the existing source-image picker, ensure `imageToVideo` is treated like the video-AI capabilities for controls and result dispatch, and show the camera-motion control for the Generation image-to-video selection without duplicating the entire panel. Do not create a video node for failed or malformed jobs.

- [ ] **Step 4: Run focused tests and analyzer**

Run: `flutter test test/features/ai/ai_image_source_test.dart test/features/ai/ai_service_video_test.dart && flutter analyze`

Expected: PASS with no analyzer errors.

---

### Task 6: Deploy and verify the complete path

**Files:**
- Modify: `README.md:5-35`
- Modify: `supabase/config.toml` if deployment configuration needs adjustment

- [ ] **Step 1: Check local Dart and Deno contracts**

Run: `flutter test test/features/ai/ai_service_video_test.dart test/features/backend_sync_test.dart`; `npx --yes deno check supabase/functions/ai-video/index.ts`

Expected: PASS.

- [ ] **Step 2: Deploy the function and configure the provider secret**

Run:

```powershell
npx supabase secrets set FAL_KEY=<provider-key>
npx supabase secrets set FAL_VIDEO_MODEL=fal-ai/kling-video/v2.1/standard/image-to-video
npx supabase functions deploy ai-video --use-api
```

Do not print or commit the provider key.

- [ ] **Step 3: Ensure anonymous Auth is enabled in the Supabase dashboard**

Enable Anonymous sign-ins, then run the app with configured Supabase URL and publishable/anon key. No provider key is required in the Web client for image-to-video.

- [ ] **Step 4: Run an authenticated smoke test**

Use the app UI: select a readable image node, choose `Image → Video (Motion)`, enter a prompt, execute, wait through queued/processing, and verify a playable MP4 appears as a `VideoPayload` node. Capture only status codes and redacted error messages.

- [ ] **Step 5: Run release verification**

Run: `flutter analyze`; `flutter build web --release`; `flutter build windows --release`

Expected: all commands exit 0. Existing unrelated full-suite failures must be reported separately rather than hidden.

- [ ] **Step 6: Update deployment documentation**

Document `FAL_KEY`, optional `FAL_VIDEO_MODEL`, Anonymous Auth, function deployment, expected cost, rate limits, and the fact that hosted video generation is metered rather than unlimited-free. Do not document or include real secrets.
