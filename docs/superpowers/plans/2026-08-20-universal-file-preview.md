# Universal File Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make File Card accept and open any file type, with in-app previews for supported media/text formats and platform-safe external fallback for everything else.

**Architecture:** Add a pure file-type classifier and one preview router shared by Canvas and Inspector. The router opens existing `PdfViewerScreen` for PDF, a focused generic preview screen for images/text/audio/video, WebView/browser for HTML/URLs, and `open_file_plus` or browser download for unsupported formats.

**Tech Stack:** Flutter, Dart stdlib, `pdfrx`, `video_player`, `just_audio`, `webview_flutter`, `open_file_plus`, `url_launcher`.

**Spec:** Approved in-chat design dated 2026-08-20.

## Global Constraints

- Support Windows, macOS, Linux, Android, iOS, and Web.
- Add no dependency unless an existing dependency cannot provide the required behavior.
- Preserve `base64Data`, `localPath`, and `remoteUrl` source compatibility.
- Unsupported formats must remain downloadable/openable externally and must never crash the app.
- Validate remote URLs before launch and never execute file contents.

---

### Task 1: File Type Classification and Source Resolution

**Files:**
- Create: `lib/features/canvas/presentation/widgets/file_preview/file_preview_type.dart`
- Test: `test/features/file_card/file_preview_type_test.dart`

**Interfaces:**
- Consumes: `FilePayload`.
- Produces: `enum FilePreviewType { pdf, image, text, audio, video, html, external }`, `FilePreviewType classifyFilePreview(FilePayload payload)`, and `String normalizedFileExtension(FilePayload payload)`.

- [ ] **Step 1: Write failing classifier tests**

Cover PDF, PNG/JPEG/WebP/GIF, TXT/MD/JSON/XML/CSV/log/source files, MP3/WAV/M4A/AAC/OGG, MP4/WebM/MOV, HTML/HTM, Office/archive/unknown fallback, uppercase extensions, and extension inferred from `fileName`.

- [ ] **Step 2: Run classifier tests**

Run: `flutter test test/features/file_card/file_preview_type_test.dart`
Expected: FAIL because classifier symbols do not exist.

- [ ] **Step 3: Implement the pure classifier**

Use constant extension sets and default unknown or binary formats to `FilePreviewType.external`.

- [ ] **Step 4: Run classifier tests**

Run: `flutter test test/features/file_card/file_preview_type_test.dart`
Expected: PASS.

### Task 2: Generic In-App Preview Screen

**Files:**
- Create: `lib/features/canvas/presentation/widgets/file_preview/file_preview_screen.dart`
- Test: `test/features/file_card/file_preview_screen_test.dart`

**Interfaces:**
- Consumes: `FilePayload`, `FilePreviewType`.
- Produces: `FilePreviewScreen({required FilePayload payload, required FilePreviewType previewType})`.

- [ ] **Step 1: Write failing widget tests**

Test shared AppBar metadata, missing-source error state, image preview presence, UTF-8 text rendering/search/copy controls, and unsupported fallback action.

- [ ] **Step 2: Run widget tests**

Run: `flutter test test/features/file_card/file_preview_screen_test.dart`
Expected: FAIL because the screen does not exist.

- [ ] **Step 3: Implement source loading**

Resolve bytes in this order: `base64Data`, readable `localPath`, then `remoteUrl`. Decode textual formats with `utf8.decode(bytes, allowMalformed: true)` and cap rendered text to a safe maximum while preserving external-open access for large files.

- [ ] **Step 4: Implement image and text previews**

Use `InteractiveViewer` plus `Image.memory`/`Image.network` for images. Use searchable `SelectableText` for textual content with line wrapping and copy support.

- [ ] **Step 5: Implement audio and video previews**

Use existing `just_audio` and `video_player`; initialize from file or network where supported, expose play/pause, seek, duration, volume, loading, and error states, and dispose controllers.

- [ ] **Step 6: Implement HTML preview and external fallback**

Use `WebViewController` for valid remote HTTP(S) URLs. Local HTML and unsupported sources show metadata with Open externally/Download actions rather than injecting untrusted HTML into the app.

- [ ] **Step 7: Run widget tests**

Run: `flutter test test/features/file_card/file_preview_screen_test.dart`
Expected: PASS.

### Task 3: Shared Preview Router

**Files:**
- Create: `lib/features/canvas/presentation/widgets/file_preview/file_preview_router.dart`
- Modify: `lib/features/canvas/presentation/canvas_screen.dart:1847-1885`
- Modify: `lib/features/canvas/presentation/widgets/inspector_panel.dart:5908-5944`
- Test: `test/features/file_card/file_preview_router_test.dart`

**Interfaces:**
- Consumes: `BuildContext`, `FilePayload`, classifier and preview screens.
- Produces: `Future<void> openFilePreview(BuildContext context, FilePayload payload)`.

- [ ] **Step 1: Write failing router tests**

Verify PDF routes to `PdfViewerScreen`, supported generic types route to `FilePreviewScreen`, and unsupported formats invoke external fallback without attempting PDF rendering.

- [ ] **Step 2: Run router tests**

Run: `flutter test test/features/file_card/file_preview_router_test.dart`
Expected: FAIL because router does not exist.

- [ ] **Step 3: Implement platform-safe router**

Route PDF internally; route supported generic types internally; use `OpenFile.open` for non-Web local files; use validated `launchUrl` for remote HTTP(S); show a SnackBar when no usable source exists.

- [ ] **Step 4: Replace duplicate Canvas and Inspector routing**

Delete local PDF-only branching and call `openFilePreview(context, payload)` from both locations.

- [ ] **Step 5: Run router and existing File Card tests**

Run: `flutter test test/features/file_card/`
Expected: PASS.

### Task 4: File Picker and Metadata Hardening

**Files:**
- Modify: `lib/features/assets/data/asset_service.dart:53-168`
- Modify: `test/features/file_card/file_card_test.dart`

**Interfaces:**
- Consumes: `PlatformFile` metadata.
- Produces: correct MIME inference and `AssetPickerResult` for arbitrary files.

- [ ] **Step 1: Add failing MIME/extension tests**

Cover PDF, Office, OpenDocument, archives, text, HTML, images, audio, video, and unknown binary MIME fallback.

- [ ] **Step 2: Run tests**

Run: `flutter test test/features/file_card/file_card_test.dart`
Expected: FAIL for missing MIME mappings.

- [ ] **Step 3: Expand MIME inference**

Map common document/media extensions to standard MIME values and retain `application/octet-stream` for unknown formats.

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/file_card/file_card_test.dart`
Expected: PASS.

### Task 5: Final Verification

**Files:**
- Verify all changed files.

**Interfaces:**
- Consumes: completed universal preview implementation.
- Produces: analyzer-clean, test-passing application.

- [ ] **Step 1: Format changed Dart files**

Run: `dart format lib/features/canvas/presentation/widgets/file_preview test/features/file_card lib/features/assets/data/asset_service.dart lib/features/canvas/presentation/canvas_screen.dart lib/features/canvas/presentation/widgets/inspector_panel.dart`

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run full tests**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 4: Manual smoke-check matrix**

Open one PDF, image, TXT/JSON, MP3, MP4, HTML remote URL, DOCX, ZIP, unknown binary, missing local path, and invalid remote URL. Confirm each selects the expected in-app viewer or safe external fallback.
