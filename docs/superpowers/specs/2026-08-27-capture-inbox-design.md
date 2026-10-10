# Capture Inbox: Capture-first, Local-first Design

## Status
Approved direction; implementation not started.

## Date
2026-08-27

## Goal

Make Creative Canvas Studio the fastest place to capture ideas and references for general users. Text, files, images, screenshots, and links can be captured from Windows, Web, and Android, stored locally first, and optionally synchronized after the user creates an account.

The first-use experience is an Inbox, not a blank canvas. Captures are safe before they are organized. Users can later move captures to a canvas, collection, or project without losing the original item.

## Product principles

- Capture before classification: saving an item must not require a project, tag, title, or AI decision.
- Local-first: a successful local write is the success boundary; cloud sync is secondary.
- One inbox: every supported capture source lands in the same ordered list.
- Progressive enrichment: thumbnails, link previews, OCR, metadata, and AI enrichment run after persistence.
- Portable references: local files remain device-local unless the user explicitly uploads or exports them.
- Recoverable actions: retries, sync failures, and enrichment failures never delete a captured item.
- Platform parity: Windows, Web, and Android share the capture model and user flow, while platform adapters handle ingestion differences.
- Simple by default: advanced organization appears when it helps, not during first capture.

## Scope

### MVP

- Capture Inbox available from the home screen and while a canvas is open.
- Text entry and paste.
- URL detection and link capture.
- PNG/image clipboard capture where the platform exposes image clipboard data.
- Single and multiple file capture.
- Windows and Web drag-and-drop for files; Android file selection.
- Windows global quick-capture hotkey.
- Android share receiver for text, URLs, images, and files.
- Web installable/PWA share target where supported by the browser and hosting configuration.
- Offline local persistence and restart-safe pending sync outbox.
- Item status, retry, delete, restore, and open-on-source actions.
- Thumbnail and basic metadata extraction where existing platform services support it.
- Send or drag an item into an existing canvas as a new compatible node.
- Optional guest-to-account cloud sync with explicit sign-in entry point.

### After MVP

- OCR for images and scanned PDFs.
- Search across title, text, URL metadata, extracted text, and file metadata.
- Manual tags, favorites, collections, and smart collections.
- Duplicate detection and merge/keep-both flow.
- AI summarization, tagging, clustering, and board generation.
- Capture templates, presentation mode, and richer export.
- Collaboration permissions, shared inboxes, and version history.
- Integrations such as browser extension, email forwarding, and automation webhooks.

### Out of scope for the first implementation

- Real-time CRDT editing of the Inbox.
- Mandatory authentication.
- Automatic AI organization before the item is locally saved.
- Uploading every local file to cloud storage by default.
- iOS support.
- A new desktop database dependency before measuring the existing storage path and defining the migration boundary.

## Current project context

Creative Canvas Studio is a Flutter application with an infinite canvas, drawing studio, document editor, media cards, link previews, AI generation, Supabase synchronization, and local project persistence.

Reusable capabilities include:

- `AssetService` for file selection and asset metadata.
- `desktop_drop` handling canvas file drops.
- `LinkPreviewService` and URL policy code for link validation and previews.
- `LocalStorageService` for local project metadata and document persistence.
- `AutosaveController` for local-first saves and cloud retry behavior.
- `SearchService` for searchable node content.
- Existing polymorphic `CanvasNode` and `NodePayload` models for materializing Inbox items onto a canvas.

The current local persistence uses `SharedPreferences` and has a 4 MB document-size limit with degraded-save behavior. An Inbox must not put unbounded binary data into canvas JSON or rely on that document limit for its primary storage.

## Architecture

### Core boundary: `CaptureItem`, not `CanvasNode`

A capture is a first-class local record. It is not created as a canvas node until the user places it on a board. This prevents an unopened project from being required, keeps the Inbox independent from canvas layout, and avoids treating every raw capture as a permanent visual object.

The persisted `CaptureItem` should contain only durable, non-secret data:

- `id` — stable UUID.
- `kind` — `text`, `image`, `file`, `link`, `screenshot`, or `audio` when supported by an existing source.
- `createdAt` and `updatedAt`.
- `title` — optional user or derived title.
- `text` — optional captured text or note.
- `sourceUri` — optional validated local path or HTTPS URL reference.
- `assetId` — optional local asset reference or explicitly uploaded cloud asset reference.
- `mimeType`, `extension`, `byteSize` — optional validated metadata.
- `thumbnailRef` — optional local thumbnail reference.
- `extractedText` — optional bounded text from supported parsers or OCR.
- `linkMetadata` — optional title, description, site name, image reference, and media type.
- `status` — `ready`, `enriching`, `syncPending`, `synced`, `error`, or `deleted`.
- `syncState` — local/cloud state and the last safe error code.
- `origin` — `inApp`, `clipboard`, `drop`, `share`, `hotkey`, or `pwaShareTarget`.
- `canvasPlacements` — optional references to materialized node IDs, without embedding the asset bytes.

API keys, authorization headers, provider responses, raw response bodies, and credentials must never be stored in a `CaptureItem`.

### Storage layers

Use separate storage responsibilities:

1. **Capture metadata store** — structured records and indexes.
2. **Local asset store** — binary files/blobs, thumbnails, and extracted artifacts.
3. **Outbox** — durable mutations awaiting cloud synchronization.
4. **Cloud sync adapter** — optional Supabase records and storage assets after account setup.

The first implementation may use the existing local storage primitives behind a narrow capture repository, but binary assets must not be placed inside canvas JSON. If Inbox volume or Web quota makes the current browser storage insufficient, migrate the capture metadata and binary layers to an IndexedDB-backed implementation without changing the `CaptureRepository` contract.

### Repository interface

Keep one small application-facing boundary:

- `createCapture(input)` validates and writes a local item and its local asset atomically enough that an item never points to a missing required asset.
- `listCaptures(query)` returns newest-first items with pagination or bounded windows.
- `getCapture(id)` returns one item.
- `updateCapture(id, patch)` updates user-editable metadata and lifecycle state.
- `deleteCapture(id)` soft-deletes first; permanent purge is a separate explicit operation.
- `restoreCapture(id)` restores a soft-deleted item.
- `materializeToCanvas(id, projectId, placement)` creates a compatible node from the item.
- `flushOutbox()` retries durable cloud mutations when credentials and connectivity are available.

The repository owns validation and storage consistency. UI providers own presentation state, filters, and pending actions.

### Ingestion adapters

All sources normalize into one `CaptureInput`:

- `TextCaptureSource` — typed text and plain-text clipboard.
- `LinkCaptureSource` — validated URLs from text, clipboard, drop, or share payloads.
- `FileCaptureSource` — picker and drag/drop files, including multiple files.
- `ImageClipboardSource` — PNG/image bytes when available.
- `ScreenshotCaptureSource` — platform screenshot bytes or a user-selected image; global screen capture is optional and must not block MVP.
- `ShareCaptureSource` — Android share receiver and Web share target payloads.
- `HotkeyCaptureSource` — Windows global shortcut that opens the compact capture surface.

An adapter only gathers source data. Normalization, validation, persistence, enrichment, and sync remain centralized so the same rules apply across platforms.

## User flows

### First launch

1. Home opens on the Capture Inbox with a clear capture field and source actions.
2. The user can continue as a guest without authentication.
3. A short explanation states that captures are saved on this device first.
4. Sign-in is available for cross-device sync but never blocks local capture.

### Quick capture

1. The user opens the capture surface from Home, Canvas, Windows hotkey, Android share, or Web share target.
2. The app previews the detected source type and derived title.
3. The user may add an optional note, but title/project/tag fields remain optional.
4. Local persistence completes before preview enrichment or cloud upload.
5. The app confirms the item in Inbox and reports enrichment or sync separately.

### Inbox organization

- Default order is newest first.
- Tabs or filters are limited to `All`, `Unread`, `Favorites`, and `Trash` initially.
- Each item exposes source, timestamp, status, retry, favorite, delete, and `Add to canvas` actions.
- Selection supports batch delete, tag, and materialize actions after the basic flow is stable.
- Opening an item uses the existing preview/player/editor surface where possible.

### Materialize to canvas

The item is converted using existing node types:

- Text → text or sticky-note node.
- Image/screenshot → image node.
- Link → link-card node.
- Video → video-card node.
- Audio → audio-card node.
- Supported document/file → file-card node.

The original `CaptureItem` remains intact. The placement stores a reference to the capture or asset rather than duplicating binary content.

### Account and sync

- Guest data remains local.
- Creating or signing into an account offers an explicit import/sync step.
- Local mutations are appended to a durable outbox.
- Sync is idempotent using capture IDs and mutation IDs.
- Cloud failures show `sync pending` or a safe error while the Inbox remains usable.
- Local paths are not treated as portable cloud assets; an upload is required before another device can open the binary.

## Validation and error handling

Normalize failures into user-safe categories:

- `CAPTURE_EMPTY` — no usable text, URL, file, or bytes.
- `CAPTURE_UNSUPPORTED_SOURCE` — source type or platform is unsupported.
- `CAPTURE_SOURCE_UNAVAILABLE` — local path, clipboard data, or share payload cannot be read.
- `CAPTURE_SIZE_LIMIT` — source exceeds the configured bounded size.
- `CAPTURE_INVALID_URL` — URL is malformed or blocked by the existing URL policy.
- `CAPTURE_STORAGE_ERROR` — local metadata or asset write failed.
- `CAPTURE_ENRICHMENT_ERROR` — preview, thumbnail, parser, or OCR failed; the item remains usable.
- `CAPTURE_SYNC_AUTH_REQUIRED` — account or credentials are needed for cloud sync.
- `CAPTURE_SYNC_ERROR` — retryable or permanent cloud mutation failure.

Rules:

- A cancelled picker or empty share payload creates no item.
- A failed enrichment never rolls back a successfully stored capture.
- A failed cloud upload never deletes the local asset.
- Retry uses the existing retry/backoff pattern but persists the outbox before returning.
- Errors must not expose API keys, authorization headers, private response bodies, or sensitive local paths in logs or UI.
- User-facing errors use short actionable text and preserve the source/prompt for retry.

## Platform behavior

### Windows

- Home and Canvas quick-capture surfaces share the same repository.
- Global hotkey opens a compact capture window or brings the app forward.
- File picker and drag/drop use existing services.
- Clipboard text and image capture use platform-safe adapters.
- Local binaries use an app data/cache directory with cleanup policy.
- Cloud sync runs when configured; local capture never waits for it.

### Web

- Use browser-supported clipboard and file APIs through Flutter platform adapters.
- Use drag/drop and a PWA share target where browser/hosting support exists.
- Keep session-only credentials out of capture data.
- Use IndexedDB or another browser-appropriate asset layer when `SharedPreferences` quota is insufficient.
- Object URLs and temporary artifacts are revoked when no longer needed.
- Link enrichment uses the existing same-origin/Supabase proxy path and URL policy.

### Android

- Home and Canvas use the same capture repository.
- Receive shared text, URLs, images, and files through a native share adapter.
- File picker and local app storage remain available offline.
- Background sync is best-effort and must not be required for the local success path.
- Back navigation and software keyboard behavior must preserve an in-progress capture where possible.

### iOS

Excluded from this MVP and must not shape the core model or block the Windows/Web/Android implementation.

## Search, enrichment, and AI phases

Enrichment is an asynchronous pipeline after the local write:

1. Validate and persist the source.
2. Generate a thumbnail or basic metadata if available.
3. Fetch link preview or parse supported documents.
4. Index bounded searchable text.
5. Optionally run OCR.
6. Optionally run AI summary/tagging/clustering.

Each stage updates the item independently and can be retried. Search must work without AI. AI output is an enhancement, never the source of truth for the capture.

## Security and privacy

- Validate URLs with the existing SSRF/private-host policy before network access.
- Bound source size, preview response size, redirect count, and parser work.
- Do not upload local assets without explicit sync/account behavior and a clear user-facing state.
- Keep provider keys in the existing secure-storage/session paths; never include them in Inbox records, sync payloads, logs, or filenames.
- Use authenticated, narrow cloud policies before production multi-user sync.
- Separate device-local references from portable cloud asset IDs.
- Provide purge controls for metadata, binaries, thumbnails, and cloud copies.

## Testing strategy

### Domain and repository tests

- `CaptureItem` serialization and backward-compatible defaults.
- Input normalization for text, URL, file, image, screenshot, and share payloads.
- Cancelled picker and empty payload behavior.
- URL and source-size validation.
- Atomic local metadata/asset behavior for success and failure.
- Soft delete, restore, purge, and ordering.
- Outbox idempotency, retry, restart recovery, and safe terminal failures.
- Materialization mapping to existing `NodeType` payloads without embedding binary data.

### Widget and integration tests

- Home opens Inbox and accepts text capture.
- Paste detects plain text versus URL.
- Batch file capture creates one valid item per file.
- Failed enrichment leaves a usable item.
- Sync-pending state and retry action are visible.
- Add-to-canvas preserves the original Inbox item.
- Guest flow does not require authentication.

### Platform verification

- Windows global hotkey, file picker, drag/drop, and clipboard.
- Web clipboard permissions, drag/drop, storage quota behavior, object URL cleanup, and PWA share target when hosted.
- Android share receiver for text, image, and file payloads, plus offline restart.
- Manual checks must use real files and real share actions; mocked tests are not enough for OS integration.

### Required project checks

```bash
flutter test
flutter analyze --no-pub
flutter build web --release
flutter build windows --release
```

Android build verification should be added when the Android share adapter is implemented.

## Phased delivery

### Phase 0: Foundation

- Define `CaptureItem`, `CaptureInput`, validation errors, and repository contract.
- Define local asset references and durable outbox records.
- Add serialization and repository tests before UI integration.

### Phase 1: Core Inbox

- Add Home Inbox screen and in-app quick capture.
- Support typed text, paste text/URL, single/multiple file selection, and existing link/file/image previews.
- Persist locally and support restart-safe list, delete, restore, and retry states.

### Phase 2: Platform capture

- Wire Windows global hotkey and clipboard image capture.
- Wire Web drag/drop, clipboard permissions, and PWA share target where available.
- Wire Android share receiver and validate offline restart behavior.

### Phase 3: Canvas bridge and organization

- Add materialization to canvas and drag/drop from Inbox.
- Add search, favorites, tags, collections, and duplicate handling.
- Add automatic project thumbnails only if the existing export path is sufficient.

### Phase 4: Cloud sync

- Add guest-to-account transition.
- Add capture metadata sync, explicit asset upload, durable outbox flush, conflict policy, and recovery UI.
- Add narrow authentication/RLS policies before shared production use.

### Phase 5: AI enrichment and collaboration

- Add OCR, summaries, smart tags, clustering, and board generation behind optional actions.
- Add shared inboxes, permissions, activity history, and version recovery only after local-first behavior is reliable.

## Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Browser storage quota is too small for raw assets | High | Keep binaries outside canvas JSON; use an asset repository and move Web storage to IndexedDB when required |
| Android share integration differs by OS version | High | Isolate a platform adapter and verify with real `ACTION_SEND` and `ACTION_SEND_MULTIPLE` payloads |
| Global Windows hotkey conflicts with another app | Medium | Make the shortcut configurable and handle registration failure without blocking in-app capture |
| Cloud sync duplicates or loses mutations | High | Durable outbox, stable IDs, idempotent upserts, and explicit retry state |
| AI/OCR makes capture feel slow | Medium | Persist first; run enrichment asynchronously and independently |
| Local file paths do not work on another device | Medium | Mark them device-local and require explicit upload for portability |
| Large scope delays the core value | High | Ship the Inbox and local capture path before search, AI, or collaboration |

## Open decisions for implementation

- Whether the first metadata store should remain a JSON-backed repository or move immediately to IndexedDB/SQLite per platform.
- The exact Windows global hotkey and conflict behavior.
- Maximum file size and retention/cleanup policy for local binaries.
- Whether Android background sync is required or best-effort in the first cloud-sync phase.
- Which authentication provider and guest-account migration flow should be used for production.

## Success criteria

- A user can capture text, a URL, an image, a screenshot, or a file on Windows, Web, or Android without first creating a project.
- The item is visible after a restart even when offline.
- Cancelled or invalid input creates no empty Inbox item.
- Enrichment and cloud failures do not destroy locally captured content.
- The user can place a capture on a canvas without losing the Inbox record.
- The implementation avoids putting large binary data into canvas JSON and does not require iOS support.
