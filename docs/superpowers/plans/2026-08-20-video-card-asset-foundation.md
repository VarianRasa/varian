# Video Card Asset Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Video Card creation and persisted source data safe and explicit.

**Architecture:** Keep `VideoPayload` as the persistence boundary and `AssetService` as the picker boundary. Reject cancelled or unusable selections before creating a canvas node; preserve backward-compatible JSON defaults.

**Tech Stack:** Flutter, Dart, `file_picker`, existing `AssetService`, Flutter test.

**Spec:** `docs/superpowers/specs/2026-08-20-video-card-design.md`

## Global Constraints

- Do not add a dependency unless existing project dependencies cannot provide the capability.
- Do not create a node after picker cancellation or when no usable source exists.
- Do not log sensitive local paths or credentials.
- Keep existing JSON documents readable.

### Task 1: Harden VideoPayload serialization

**Files:**
- Modify: `lib/domain/models/node_payload.dart`
- Test: `test/domain/models/node_payload_test.dart` or the existing payload test location

- [ ] Add tests for local path, remote URL, caption, duration metadata, and missing-field backward compatibility.
- [ ] Add only the durable fields required by the current player/preview: numeric duration when available, video dimensions when available, poster source when available, and source error text.
- [ ] Implement `toJson`, `fromJson`, `copyWith`, and `clone` with safe defaults and no runtime controller state.
- [ ] Run the focused payload tests, then `flutter analyze --no-pub`.

### Task 2: Validate video sources

**Files:**
- Create: `lib/features/video_card/data/video_source_policy.dart`
- Test: `test/features/video_card/video_source_policy_test.dart`

- [ ] Add tests for empty input, valid local paths, valid `http`/`https` URLs, malformed URLs, unsupported schemes, and credentials in URLs.
- [ ] Implement a small pure policy returning a typed valid/invalid result and user-facing error category.
- [ ] Reuse the project’s existing URL security conventions instead of duplicating weaker checks.
- [ ] Run the focused policy tests.

### Task 3: Stop cancelled or invalid node creation

**Files:**
- Modify: `lib/features/canvas/presentation/canvas_screen.dart`
- Modify: `lib/features/assets/data/asset_service.dart` only if result normalization is required
- Test: existing canvas creation test location or `test/features/canvas/video_card_creation_test.dart`

- [ ] Add a test proving a cancelled picker creates no node.
- [ ] Add a test proving a picker result with neither usable path nor URL creates no node and reports an error.
- [ ] Normalize `videoPath` and `videoUrl` separately from `AssetPickerResult`.
- [ ] Remove the placeholder title/source behavior for cancelled selection.
- [ ] Run focused tests and analyzer.

### Task 4: Derive safe metadata

**Files:**
- Create: `lib/features/video_card/data/video_metadata_service.dart`
- Test: `test/features/video_card/video_metadata_service_test.dart`
- Modify: `lib/features/canvas/presentation/canvas_screen.dart`

- [ ] Add pure tests for duration formatting and fallback when metadata is unavailable.
- [ ] Implement metadata extraction through already available APIs where supported; do not introduce FFmpeg or transcoding.
- [ ] Populate actual duration when available and retain a safe fallback label otherwise.
- [ ] Run focused tests, analyzer, and the existing canvas tests.
