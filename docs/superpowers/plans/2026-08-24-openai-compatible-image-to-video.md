# OpenAI-Compatible Image-to-Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Supabase/Hugging Face image-to-video path with a user-configured OpenAI-compatible Videos API adapter that materializes MP4 output in the canvas and supports download on Windows, Web, and Android.

**Architecture:** Keep the existing `AIService` video job flow and `{action: create|poll}` invoker boundary, but wire it to a direct client-side provider adapter. The adapter submits multipart image-to-video requests, polls the provider, downloads and validates MP4 bytes, then returns a short-lived artifact reference; canvas nodes use a local path on native platforms and a Web object URL on Web. The existing text/image provider flow remains unchanged.

**Tech Stack:** Flutter/Dart, Riverpod, `http`, `file_picker`, `path_provider`, `video_player`, `media_kit`, `shared_preferences`; add `flutter_secure_storage` only for native API-key storage and use its Web session-storage option if the package implementation is accepted by tests.

**Spec:** `docs/superpowers/specs/2026-08-24-openai-compatible-image-to-video-design.md`

## Global Constraints

- Support image-to-video only in this iteration.
- Use `POST {baseUrl}/videos`, `GET {baseUrl}/videos/{id}`, and `GET {baseUrl}/videos/{id}/content`.
- Use a 30-second timeout per HTTP request, a 2-second poll interval, and a five-minute maximum polling window.
- Do not retry a timed-out or failed create request automatically.
- Windows and Android store API keys in platform secure storage; Web keeps video credentials in memory for the current session only.
- Never write API keys to Web `localStorage`, Supabase, canvas JSON, job history, logs, errors, or node metadata.
- Validate image input, provider response shapes, MP4 content type/bytes/size, and all user configuration at boundaries.
- Do not add comments unless required by an existing convention; do not add new dependencies when existing packages solve the need.
- Do not change text-to-image, image-to-image, chat, Supabase sync, or unrelated canvas behavior.
- Do not commit changes unless explicitly requested.

---

## File Map

- Create: `lib/features/ai/data/video_provider.dart` — provider mode, normalized errors, request/response parsing, and testable video API protocol.
- Create: `lib/features/ai/data/video_artifact_store.dart` — native cache and Web object URL seams for validated MP4 artifacts.
- Create: `lib/features/ai/data/video_download_service.dart` — platform download action for cached/provider video artifacts.
- Modify: `lib/data/remote/backend_config.dart` — video provider configuration, fallback resolution, and session-only Web credentials.
- Modify: `lib/features/home/presentation/widgets/backend_settings_dialog.dart` — video settings and non-generating test action.
- Modify: `lib/features/ai/data/ai_service.dart` — direct video adapter integration, bounded polling, and local artifact materialization.
- Modify: `lib/features/ai/state/ai_provider.dart` — inject direct video invoker and artifact store instead of Supabase video invocation.
- Modify: `lib/domain/models/ai_job.dart` — carry a native artifact path/Web reference without serializing secrets.
- Modify: `lib/domain/models/node_payload.dart` — preserve generated local path and Web URL semantics through video payloads.
- Modify: `lib/features/canvas/presentation/canvas_screen.dart` — pass download action and open player with artifact references.
- Modify: `lib/features/media/inline_video_card_widget.dart` — add an accessible download action to video-card controls.
- Modify: `lib/features/media/video_player_screen.dart` — add a download button for native/Web sources.
- Modify: `lib/features/video_card/data/video_source_policy.dart` — allow only app-owned local artifacts and approved provider/Web URLs without allowing arbitrary LAN/private network playback.
- Modify: `pubspec.yaml` — add `flutter_secure_storage` only if secure storage is not already transitively available and direct import is required.
- Modify: `README.md` — replace hosted HF setup with provider configuration, API-key warning, supported contract, and testing commands.
- Create: `test/features/ai/video_provider_test.dart` — HTTP contract and error mapping tests.
- Create: `test/features/ai/video_artifact_store_test.dart` — artifact validation and storage tests.
- Modify: `test/features/ai/ai_service_video_test.dart` — direct provider polling and artifact result tests.
- Create: `test/features/ai/backend_video_config_test.dart` — configuration fallback and Web session behavior.
- Create: `test/features/media/video_download_service_test.dart` — download behavior through injected platform seams.
- Modify: `test/features/ai/supabase_ai_video_invoker_test.dart` or delete only after confirming no remaining production references — obsolete hosted-video tests must not constrain the new path.

---

### Task 1: Define video provider contract and error model

**Files:**
- Create: `lib/features/ai/data/video_provider.dart`
- Test: `test/features/ai/video_provider_test.dart`

**Interfaces:**
- Produces `enum VideoProviderMode { openAiVideos, ffmpeg }`.
- Produces `class VideoProviderException implements Exception` with `code`, `message`, and optional `statusCode`.
- Produces `class VideoProviderJob` with `requestId`, `status`, optional `progress`, optional `videoUrl`.
- Produces `abstract interface class VideoProviderClient` with:
  ```dart
  Future<VideoProviderJob> createImageToVideo({
    required Uint8List imageBytes,
    required String imageMimeType,
    required String prompt,
    required String model,
    required String baseUrl,
    required String apiKey,
    required String duration,
    required String aspectRatio,
  });

  Future<VideoProviderJob> poll(String requestId);

  Future<Uint8List> downloadContent(String requestId);

  Future<(bool, String?)> testConnection();
  ```
- Produces `OpenAiVideosProviderClient` with injected `http.Client`, request timeout, and bounded response sizes.

- [ ] **Step 1: Write failing tests for request parsing and statuses**

```dart
test('parses queued create response', () {
  final job = VideoProviderJob.fromJson({'id': 'v1', 'status': 'queued'});
  expect(job.requestId, 'v1');
  expect(job.status, 'queued');
});

test('rejects an unknown provider status', () {
  expect(
    () => VideoProviderJob.fromJson({'id': 'v1', 'status': 'waiting'}),
    throwsA(isA<VideoProviderException>()),
  );
});
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/features/ai/video_provider_test.dart`
Expected: FAIL because the provider types do not exist.

- [ ] **Step 3: Implement the minimum contract and HTTP adapter**

Use `http.MultipartRequest` for `POST {baseUrl}/videos` with fields `model`, `prompt`, `seconds`, and `size`, plus one `input_reference` multipart file. Normalize `{baseUrl}` by trimming trailing slashes and preserving the configured `/v1` path. Map status codes 401/403 to `VIDEO_AUTH_ERROR`, 429 to `VIDEO_RATE_LIMITED`, 404/405 to `VIDEO_UNSUPPORTED_PROVIDER`, malformed JSON to `VIDEO_UNSUPPORTED_PROVIDER`, and other non-2xx responses to `VIDEO_GENERATION_FAILED` without including full response bodies. Require an ID for create/poll responses and accept only `queued`, `in_progress`, `completed`, `failed`, and `canceled`.

Use `http.Request` for poll and content calls with `Authorization`, `Accept`, and a 30-second timeout. Limit JSON response body size to 256 KiB and MP4 response bytes to 100 MiB. Require an MP4 signature (`ftyp` within the first 16 bytes) and reject empty/oversized content.

- [ ] **Step 4: Run focused tests and verify they pass**

Run: `flutter test test/features/ai/video_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Run formatting**

Run: `dart format lib/features/ai/data/video_provider.dart test/features/ai/video_provider_test.dart`
Expected: formatted files with no failure.

---

### Task 2: Add secure provider configuration

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/data/remote/backend_config.dart`
- Create: `test/features/ai/backend_video_config_test.dart`

**Interfaces:**
- `BackendConfig` adds `videoApiBaseUrl`, `videoApiKey`, `videoModel`, and `videoProviderMode`.
- `BackendConfig.effectiveVideoBaseUrl`, `effectiveVideoApiKey`, and `isVideoConfigured` expose normalized fallback values.
- `BackendConfigNotifier.loadConfig` loads native secure key values and Web session-only values.
- `BackendConfigNotifier.saveConfig` writes native key values to secure storage and never persists the Web video key beyond the current process/session.

- [ ] **Step 1: Add failing tests for fallback and key scope**

```dart
test('video settings fall back to general provider values', () {
  const config = BackendConfig(
    openAiApiKey: 'general-key',
    openAiBaseUrl: 'https://provider.test/v1',
    videoModel: 'video-model',
  );
  expect(config.effectiveVideoApiKey, 'general-key');
  expect(config.effectiveVideoBaseUrl, 'https://provider.test/v1');
  expect(config.isVideoConfigured, isTrue);
});

test('video mode defaults to OpenAI videos', () {
  expect(const BackendConfig().videoProviderMode, VideoProviderMode.openAiVideos);
});
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/features/ai/backend_video_config_test.dart`
Expected: FAIL because the fields and mode do not exist.

- [ ] **Step 3: Add the configuration fields and secure storage seam**

Use `FlutterSecureStorage` for native keys. Configure Web storage with `WebOptions(useSessionStorage: true)` only if the package is used for Web; otherwise keep the Web video key in a notifier-owned memory field and do not serialize it. Migrate the existing `cfg_openai_key` from `SharedPreferences` to secure storage on native platforms, preserving existing image/text behavior through the normalized `openAiApiKey` value. Keep Supabase values in their existing storage.

Add URL validation using the existing `normalizeOpenAiBaseUrl`, reject query/fragment URLs, and require a non-empty video model for `openAiVideos`. Add `copyWith`, `normalized`, load, and save handling for all new fields. Keep the default provider mode `openAiVideos` and the default video model empty so users must configure one.

- [ ] **Step 4: Run focused tests and verify they pass**

Run: `flutter test test/features/ai/backend_video_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Run format and dependency resolution**

Run: `dart format lib/data/remote/backend_config.dart test/features/ai/backend_video_config_test.dart`
Run: `flutter pub get`
Expected: both commands succeed.

---

### Task 3: Add artifact storage and download service

**Files:**
- Create: `lib/features/ai/data/video_artifact_store.dart`
- Create: `lib/features/ai/data/video_download_service.dart`
- Test: `test/features/ai/video_artifact_store_test.dart`
- Test: `test/features/media/video_download_service_test.dart`

**Interfaces:**
- Produces `class VideoArtifact` with `path`, `url`, `bytes`, and `fileName` fields, where native uses `path` and Web uses `url`/`bytes`.
- Produces `abstract interface class VideoArtifactStore`:
  ```dart
  Future<VideoArtifact> save(Uint8List bytes, {String fileName});
  Future<bool> exists(VideoArtifact artifact);
  Future<Uint8List?> read(VideoArtifact artifact);
  Future<void> dispose(VideoArtifact artifact);
  ```
- Produces `abstract interface class VideoDownloadService`:
  ```dart
  Future<void> download(VideoArtifact artifact, {String? suggestedName});
  ```

- [ ] **Step 1: Write failing artifact validation tests**

```dart
test('rejects bytes without an MP4 signature', () async {
  final store = MemoryVideoArtifactStore();
  expect(
    () => store.save(Uint8List.fromList([1, 2, 3])),
    throwsA(isA<VideoProviderException>()),
  );
});

test('stores and reads a valid MP4 artifact', () async {
  final store = MemoryVideoArtifactStore();
  final artifact = await store.save(_minimalMp4(), fileName: 'generated.mp4');
  expect(await store.exists(artifact), isTrue);
  expect(await store.read(artifact), _minimalMp4());
});
```

- [ ] **Step 2: Run focused tests and verify they fail**

Run: `flutter test test/features/ai/video_artifact_store_test.dart test/features/media/video_download_service_test.dart`
Expected: FAIL because artifact and download types do not exist.

- [ ] **Step 3: Implement native cache, Web object URL seam, and download behavior**

Use `path_provider` and `dart:io` behind platform-specific files for native cache writes. Keep the Web implementation injectable so tests do not require browser APIs; create a Blob/object URL at runtime and revoke it after download when the platform supports it. Use `FilePicker.saveFile` for Windows/Android destination selection and write bytes to the selected path. Sanitize suggested names to a safe basename ending in `.mp4`. Do not use provider URL query parameters for credentials.

Implement a memory store for unit tests. Validate the MP4 signature and 100 MiB maximum before writing. Keep artifact paths under the app cache directory; do not accept arbitrary paths from provider responses.

- [ ] **Step 4: Run focused tests and verify they pass**

Run: `flutter test test/features/ai/video_artifact_store_test.dart test/features/media/video_download_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Run formatting**

Run: `dart format lib/features/ai/data/video_artifact_store.dart lib/features/ai/data/video_download_service.dart test/features/ai/video_artifact_store_test.dart test/features/media/video_download_service_test.dart`
Expected: formatted files with no failure.

---

### Task 4: Replace AIService video flow with direct provider polling

**Files:**
- Modify: `lib/features/ai/data/ai_service.dart`
- Modify: `lib/domain/models/ai_job.dart`
- Modify: `lib/domain/models/node_payload.dart`
- Modify: `test/features/ai/ai_service_video_test.dart`

**Interfaces:**
- `AIService` receives a `VideoProviderClient` and `VideoArtifactStore` through injectable constructor parameters.
- `_handleRemoteVideo` calls the provider client directly and returns an `AIJob` whose generated artifact is available through a path or Web URL.
- `AIJob` adds an optional non-serialized `VideoArtifact? resultVideoArtifact` or equivalent fields; API keys and provider headers are never part of the model.
- `spawnVideoNodeFromJob` creates `VideoPayload(videoPath: ...)` for native artifacts or `VideoPayload(videoUrl: ...)` for approved Web/provider URLs.

- [ ] **Step 1: Update tests to describe the direct provider contract**

Replace the Supabase invoker fixture with an injected fake provider that returns:

```dart
FakeVideoProvider(
  createResult: const VideoProviderJob(requestId: 'v1', status: 'queued'),
  pollResults: const [VideoProviderJob(requestId: 'v1', status: 'completed')],
  content: _minimalMp4(),
)
```

Assert that the result is completed, the artifact is stored, `resultAssetUrl` is not used for a local artifact, and the generated node contains `videoPath` on native tests. Add tests for provider auth, unknown status, timeout, and failed terminal status.

- [ ] **Step 2: Run the updated tests and verify they fail**

Run: `flutter test test/features/ai/ai_service_video_test.dart`
Expected: FAIL because `AIService` still requires the Supabase invoker and only accepts HTTPS URLs.

- [ ] **Step 3: Implement direct provider execution**

Change video capability handling to use the injected provider client. Validate `sourceImageBase64` or read a local image source before create; preserve existing source URL support only by downloading it through the existing bounded image downloader and validating the response MIME/size. Build `duration: '5'` and `aspectRatio: '16:9'` initially to preserve the current UI contract, then map them to provider multipart fields in the adapter.

Poll every two seconds for up to 150 attempts. On completion call `downloadContent`, save the bytes through `VideoArtifactStore`, and set a private artifact reference on the job. Map all `VideoProviderException` codes into the safe job error message. Remove the Supabase-specific missing-invoker message and do not call `invokeAIVideoFunction`.

Keep non-video routes exactly as they are. If the provider mode is `ffmpeg`, return a clear unsupported-mode result until the later optional FFmpeg task is explicitly implemented; do not silently simulate semantic motion.

- [ ] **Step 4: Update video node materialization**

Make `spawnVideoNodeFromJob` prefer a validated local artifact path, then a validated Web object URL, then a provider HTTPS URL. Reject all other values. Set only the selected source field and keep `videoPath`/`videoUrl` mutually exclusive for generated nodes.

- [ ] **Step 5: Run focused tests and verify they pass**

Run: `flutter test test/features/ai/ai_service_video_test.dart test/features/ai/ai_image_source_test.dart`
Expected: PASS.

- [ ] **Step 6: Run format and analyze the touched Dart files**

Run: `dart format lib/features/ai/data/ai_service.dart lib/domain/models/ai_job.dart lib/domain/models/node_payload.dart test/features/ai/ai_service_video_test.dart`
Run: `flutter analyze lib/features/ai/data/ai_service.dart lib/domain/models/ai_job.dart lib/domain/models/node_payload.dart`
Expected: no formatting or analyzer errors.

---

### Task 5: Wire provider injection and settings UI

**Files:**
- Modify: `lib/features/ai/state/ai_provider.dart`
- Modify: `lib/features/home/presentation/widgets/backend_settings_dialog.dart`
- Create or modify: `test/features/ai/backend_settings_dialog_test.dart` only if existing widget-test conventions support this surface.

**Interfaces:**
- `aiServiceProvider` constructs a direct `OpenAiVideosProviderClient` from `BackendConfig` and injects the artifact store.
- Settings dialog displays provider mode, video key/base/model fields, fallback state, and `Test Video API`.

- [ ] **Step 1: Add the settings fields and test action fixture**

Add controllers for video key, base URL, and model plus a `VideoProviderMode` selector. Add `_runVideoTest` that calls a non-generating provider test. Assert no `/videos` POST is made by the test action when a widget test seam is available.

- [ ] **Step 2: Run the focused settings test and verify it fails**

Run: `flutter test test/features/ai/backend_settings_dialog_test.dart`
Expected: FAIL until the fields and action are wired.

- [ ] **Step 3: Implement settings persistence and provider wiring**

Pass the video configuration into `BackendConfig`, save it with the existing Save & Apply flow, and invalidate only the AI service provider after save. Keep the existing Supabase initialization flow. Display a warning that direct Web keys are visible to the browser and that an API provider must implement the standard Videos API.

- [ ] **Step 4: Run focused tests and verify they pass**

Run: `flutter test test/features/ai/backend_settings_dialog_test.dart test/features/ai/backend_video_config_test.dart`
Expected: PASS, or skip the widget test only if the existing dialog requires unavailable platform setup; retain unit coverage.

- [ ] **Step 5: Run analyzer on settings and provider wiring**

Run: `flutter analyze lib/features/ai/state/ai_provider.dart lib/features/home/presentation/widgets/backend_settings_dialog.dart`
Expected: no analyzer errors.

---

### Task 6: Add canvas and player download action

**Files:**
- Modify: `lib/features/canvas/presentation/canvas_screen.dart`
- Modify: `lib/features/media/inline_video_card_widget.dart`
- Modify: `lib/features/media/video_player_screen.dart`
- Modify: `lib/features/video_card/data/video_source_policy.dart`
- Test: `test/features/media/video_download_service_test.dart` and any focused widget tests already covering video player/card behavior.

**Interfaces:**
- `InlineVideoCardWidget` accepts `VoidCallback? onDownload`.
- `VideoPlayerScreen` accepts `VoidCallback? onDownload` and shows a download control after source validation.
- Canvas passes a callback using the injected `VideoDownloadService` and the node's artifact reference.

- [ ] **Step 1: Add failing tests for download callback and source policy**

Assert that a valid app cache path is accepted, arbitrary private network URLs remain rejected, and invoking the player/card download action reaches the injected service exactly once.

- [ ] **Step 2: Run focused tests and verify they fail**

Run: `flutter test test/features/media/video_download_service_test.dart`
Expected: FAIL until callback wiring exists.

- [ ] **Step 3: Implement the minimum callback wiring**

Add download controls to the existing compact Windows controls and player controls. Keep controls accessible with tooltips and avoid changing playback behavior. In `CanvasScreen`, build a `VideoArtifact` from the node's safe local path or Web URL and call `VideoDownloadService.download`. Show a short success/failure `SnackBar`; do not include provider credentials or raw response details.

Update `VideoSourcePolicy` to distinguish app-owned cache paths from arbitrary paths and preserve the current rejection of localhost/private network URLs. Allow Web object URLs only when they were created by the artifact store, not arbitrary `blob:` values supplied by document JSON.

- [ ] **Step 4: Run focused tests and verify they pass**

Run: `flutter test test/features/media/video_download_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Run formatting and analyzer**

Run: `dart format lib/features/canvas/presentation/canvas_screen.dart lib/features/media/inline_video_card_widget.dart lib/features/media/video_player_screen.dart lib/features/video_card/data/video_source_policy.dart`
Run: `flutter analyze lib/features/canvas/presentation/canvas_screen.dart lib/features/media/inline_video_card_widget.dart lib/features/media/video_player_screen.dart lib/features/video_card/data/video_source_policy.dart`
Expected: no errors.

---

### Task 7: Remove obsolete hosted-video wiring and update documentation

**Files:**
- Modify: `README.md`
- Modify/delete only production-referenced portions of `supabase/functions/ai-video/index.ts`, `supabase/functions/ai-video/helpers.ts`, and `supabase/config.toml` after repository-wide reference search.
- Modify: `test/features/ai/supabase_ai_video_invoker_test.dart` only if no other production path uses it.

**Interfaces:**
- README documents the direct Videos API contract, key-storage warning, provider requirements, supported platforms, and local test commands.
- No active Flutter production dependency remains on `invokeAIVideoFunction` for image-to-video.

- [ ] **Step 1: Search for obsolete production references**

Run: `rg "invokeAIVideoFunction|ai-video|HF_VIDEO_SPACE_URL|gradio_api|VideoFunctionInvoker" lib test supabase README.md`
Expected: identify only the old implementation, tests, and documentation before removal.

- [ ] **Step 2: Update README and remove only dead hosted-video code**

Replace the hosted HF section with provider configuration examples using `{baseUrl}/videos`, polling, and content download. Document that API billing/quotas belong to the user's provider, that compatibility is not guaranteed by the label alone, and that direct Web keys are visible in the browser. Remove dead Supabase video code only when no live references remain; retain Supabase sync/link-preview features.

- [ ] **Step 3: Run regression tests**

Run: `flutter test test/features/ai test/features/backend_sync_test.dart`
Expected: all relevant AI/backend tests pass; unrelated pre-existing failures are recorded separately rather than hidden.

- [ ] **Step 4: Run format, analyzer, and builds**

Run: `dart format --output=none --set-exit-if-changed lib test`
Run: `flutter analyze`
Run: `flutter build web --release`
Run: `flutter build windows --release`
Expected: formatting, analysis, and both builds pass.

---

### Task 8: Final verification and handoff

**Files:**
- No new production files; update focused tests if verification exposes defects.

- [ ] **Step 1: Run the full relevant test matrix**

Run:

```powershell
flutter test test/features/ai test/features/backend_sync_test.dart
flutter analyze
flutter build web --release
flutter build windows --release
```

Expected: all newly affected tests pass, analyzer is clean, and Web/Windows builds complete.

- [ ] **Step 2: Verify security properties**

Search the changed files for key names and logging:

```powershell
rg "debugPrint|print|openAiApiKey|videoApiKey|Authorization|Bearer" lib/features/ai lib/data/remote lib/features/home
```

Expected: no API key value is logged, serialized into canvas/job payloads, or appended to URLs.

- [ ] **Step 3: Manual provider smoke test**

Configure a test provider with a non-production key and model, run `Test Video API`, create one image-to-video job, wait for completion, verify the video card appears, open the player, and download the MP4. Do not repeat create requests after timeout unless the provider confirms the first job did not run.

- [ ] **Step 4: Report exact verification results**

Record passed commands, any pre-existing unrelated test failures, provider compatibility limitations, and the absence of automatic local CUDA/FFmpeg runtime in this iteration.
