# Video Card Upload and Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make remote upload persistence and platform behavior explicit and verifiable.

**Architecture:** Reuse `AssetService` and Supabase integration. Store remote URL separately from local path, expose upload failure/progress where the current API permits, and verify registered video implementations before promising playback.

**Tech Stack:** Flutter, existing `file_picker`, `supabase_flutter`, `video_player`, platform build tooling.

**Spec:** `docs/superpowers/specs/2026-08-20-video-card-design.md`

## Global Constraints

- Add no unsupported platform dependency merely to hide a limitation.
- Web must use a URL/blob source, never `VideoPlayerController.file`.
- Preserve metadata/export functionality when playback is unavailable.
- Do not log credentials, signed URLs, or sensitive paths.

### Task 1: Normalize upload result persistence

**Files:**
- Modify: `lib/features/assets/data/asset_service.dart`
- Modify: `lib/features/canvas/presentation/canvas_screen.dart`
- Test: `test/features/assets/asset_service_test.dart` or focused Video Card asset test

- [ ] Test local-only, remote-only, and local-plus-remote results.
- [ ] Persist `videoPath` and `videoUrl` independently.
- [ ] Ensure upload failure does not produce a node with an unusable source.
- [ ] Preserve existing file-card behavior.
- [ ] Run focused asset tests.

### Task 2: Add upload progress/retry only where supported

**Files:**
- Modify: `lib/features/assets/data/asset_service.dart`
- Modify: relevant upload state/provider file
- Test: focused asset upload tests

- [ ] Test progress callbacks, retryable failure, and cancellation if the underlying upload API exposes safe cancellation.
- [ ] Add a minimal typed upload state rather than a broad upload framework.
- [ ] Display progress/failure in the Video Card creation flow without blocking existing local-only usage.
- [ ] Run focused tests and analyzer.

### Task 3: Verify platform registrations and behavior

**Files:**
- Inspect/modify only necessary platform registration/config files under `android/`, `ios/`, `macos/`, `windows/`, `linux/`, and `web/`
- Test: platform-specific smoke tests where available

- [ ] Inspect generated plugin registration and confirm actual `video_player` implementations.
- [ ] Run `flutter build web`, `flutter build windows` or available platform builds, and the relevant Android/iOS checks.
- [ ] Ensure unsupported desktop playback reaches the player’s explicit error state rather than throwing.
- [ ] Verify web CORS/range-request failures are presented as source errors.
- [ ] Run `flutter analyze --no-pub` and the full test suite.

### Task 4: Verify export/import and regression behavior

**Files:**
- Modify: `lib/features/export/export_service.dart` only if new persisted fields are omitted
- Test: export/import and full regression test locations

- [ ] Test Video Card JSON round-trip with local path, remote URL, metadata, poster, and error state.
- [ ] Ensure text export includes title and duration without binary embedding.
- [ ] Run the full test suite, analyzer, and available release/debug builds.
