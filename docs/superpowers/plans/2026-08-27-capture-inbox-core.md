# Capture Inbox Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first Capture Inbox for text, URLs, and multiple files on the existing Home screen without embedding capture binaries in canvas documents.

**Architecture:** Introduce a first-class `CaptureItem` domain record and a `CaptureRepository` backed by local metadata plus a separate platform asset store. Riverpod exposes the repository to a Home-embedded Inbox panel; the existing `AssetService` supplies picker results, while URL validation reuses the current link policy.

**Tech Stack:** Flutter, Dart, Riverpod 2, SharedPreferences for bounded metadata, path_provider/path for native binary storage, the existing `web` IndexedDB bindings for Web binary storage, Forui primitives, Flutter widget tests.

**Spec:** `docs/superpowers/specs/2026-08-27-capture-inbox-design.md`

## Global Constraints

- Target platforms are Windows, Web, and Android; iOS is excluded from this MVP.
- A capture must be locally persisted before enrichment or cloud work.
- Binary assets must not be embedded in canvas JSON.
- A cancelled picker or empty input creates no item.
- Failed enrichment or future cloud sync must not delete a locally stored item.
- API keys, authorization headers, provider responses, credentials, and sensitive paths must not be logged or stored in capture records.
- Reuse existing dependencies and project UI primitives; do not add a dependency for this slice.
- No comments are added to application code.
- Run `flutter test`, `flutter analyze --no-pub`, `flutter build web --release`, and `flutter build windows --release` before claiming completion.

---

## Task 1: Capture domain model and normalization

**Files:**
- Create: `lib/features/capture/domain/capture_item.dart`
- Test: `test/features/capture/capture_item_test.dart`

**Interfaces:**
- Produces `CaptureKind`, `CaptureStatus`, `CaptureSyncState`, `CaptureOrigin`, `CaptureLinkMetadata`, `CaptureItem`, `CaptureInput`, and `CaptureFailure`.
- `CaptureInput.text(String value, {CaptureOrigin origin = CaptureOrigin.inApp, String? title})` creates text or link input after normalization.
- `CaptureInput.file({required String name, String? path, required Uint8List bytes, required String mimeType, String? title, CaptureOrigin origin = CaptureOrigin.inApp})` creates file input.
- `CaptureItem.toJson()` and `CaptureItem.fromJson(Map<String, dynamic>)` remain backward-compatible when optional fields are absent.

- [ ] **Step 1: Write failing model tests**

```dart
void main() {
  test('classifies an HTTPS value as a link', () {
    final input = CaptureInput.text('https://example.com/design');
    expect(input.kind, CaptureKind.link);
    expect(input.text, 'https://example.com/design');
  });

  test('keeps ordinary text as text', () {
    final input = CaptureInput.text('A loose idea for the next board');
    expect(input.kind, CaptureKind.text);
  });

  test('round trips optional fields and defaults missing fields', () {
    final item = CaptureItem(
      id: 'capture-1',
      kind: CaptureKind.text,
      createdAt: DateTime(2026, 8, 27, 10),
      updatedAt: DateTime(2026, 8, 27, 10),
      title: 'Idea',
      text: 'Build a visual journal',
      origin: CaptureOrigin.clipboard,
    );
    final restored = CaptureItem.fromJson(item.toJson());
    expect(restored.id, item.id);
    expect(restored.text, item.text);
    expect(restored.origin, CaptureOrigin.clipboard);

    final legacy = CaptureItem.fromJson({
      'id': 'legacy',
      'kind': 'text',
      'createdAt': '2026-08-27T10:00:00.000',
      'updatedAt': '2026-08-27T10:00:00.000',
    });
    expect(legacy.status, CaptureStatus.ready);
    expect(legacy.syncState, CaptureSyncState.localOnly);
    expect(legacy.isRead, isFalse);
    expect(legacy.isFavorite, isFalse);
  });

  test('rejects empty text and malformed HTTP input', () {
    expect(
      () => CaptureInput.text('  '),
      throwsA(isA<CaptureFailure>()),
    );
    expect(
      () => CaptureInput.text('https://'),
      throwsA(isA<CaptureFailure>()),
    );
  });
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/features/capture/capture_item_test.dart`

Expected: FAIL because the capture domain types do not exist.

- [ ] **Step 3: Implement the minimum model**

Implement these exact persisted fields on `CaptureItem`: `id`, `kind`, `createdAt`, `updatedAt`, nullable `title`, nullable `text`, nullable `sourceUri`, nullable `assetId`, nullable `mimeType`, nullable `extension`, nullable `byteSize`, nullable `thumbnailRef`, nullable `extractedText`, nullable `linkMetadata`, `status`, `syncState`, `origin`, `isRead`, `isFavorite`, and nullable `syncErrorCode`.

Use `normalizeLinkUrl` from `lib/features/link_card/domain/link_url_policy.dart` for values beginning with `http://` or `https://`. Keep arbitrary text unchanged after trimming. Reject empty file names, empty bytes, and byte counts greater than `50 * 1024 * 1024` with `CaptureFailure` codes `CAPTURE_EMPTY` or `CAPTURE_SIZE_LIMIT`.

- [ ] **Step 4: Run the focused test and verify it passes**

Run: `flutter test test/features/capture/capture_item_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit the completed task**

```bash
git add lib/features/capture/domain/capture_item.dart test/features/capture/capture_item_test.dart
git commit -m "feat: add capture inbox domain model"
```

---

## Task 2: Separate local asset storage and capture repository

**Files:**
- Create: `lib/features/capture/data/capture_asset_store.dart`
- Create: `lib/features/capture/data/capture_asset_store_io.dart`
- Create: `lib/features/capture/data/capture_asset_store_web.dart`
- Create: `lib/features/capture/data/capture_repository.dart`
- Test: `test/features/capture/capture_repository_test.dart`

**Interfaces:**
- `CaptureAssetStore` exposes `save(Uint8List bytes, {required String fileName, required String mimeType})`, `read(String reference)`, `exists(String reference)`, and `delete(String reference)`.
- `createCaptureAssetStore()` returns the native filesystem implementation on Windows/Android and the IndexedDB implementation on Web.
- `CaptureRepository` exposes `createCapture(CaptureInput input)`, `listCaptures({CaptureQuery query = const CaptureQuery()})`, `getCapture(String id)`, `setRead(String id, bool value)`, `setFavorite(String id, bool value)`, `deleteCapture(String id)`, `restoreCapture(String id)`, and `purgeCapture(String id)`.
- `LocalCaptureRepository` accepts `SharedPreferences? preferences`, `CaptureAssetStore? assetStore`, and `Uuid? uuid` for deterministic tests and production defaults.

- [ ] **Step 1: Write failing repository tests with an in-memory asset store**

```dart
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('creates, reloads, sorts, and updates capture metadata', () async {
    final repository = LocalCaptureRepository(assetStore: MemoryCaptureAssetStore());
    final created = await repository.createCapture(
      CaptureInput.text('https://example.com', origin: CaptureOrigin.clipboard),
    );
    expect(created.kind, CaptureKind.link);
    expect((await repository.listCaptures()).single.id, created.id);

    await repository.setRead(created.id, true);
    await repository.setFavorite(created.id, true);
    final reloaded = (await LocalCaptureRepository(
      assetStore: MemoryCaptureAssetStore(),
    ).listCaptures()).single;
    expect(reloaded.isRead, isTrue);
    expect(reloaded.isFavorite, isTrue);
  });

  test('stores file bytes outside metadata and removes them on purge', () async {
    final assets = MemoryCaptureAssetStore();
    final repository = LocalCaptureRepository(assetStore: assets);
    final item = await repository.createCapture(
      CaptureInput.file(
        name: 'reference.png',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
      ),
    );
    expect(item.assetId, isNotNull);
    expect(await assets.exists(item.assetId!), isTrue);
    final raw = (await SharedPreferences.getInstance()).getString('ccs_capture_items_v1');
    expect(raw, isNot(contains('AQID')));

    await repository.purgeCapture(item.id);
    expect(await assets.exists(item.assetId!), isFalse);
    expect(await repository.getCapture(item.id), isNull);
  });

  test('cancel-like empty input creates no record', () async {
    final repository = LocalCaptureRepository(assetStore: MemoryCaptureAssetStore());
    expect(() => repository.createCapture(CaptureInput.text('')), throwsA(isA<CaptureFailure>()));
    expect(await repository.listCaptures(), isEmpty);
  });

  test('delete and restore preserve the capture', () async {
    final repository = LocalCaptureRepository(assetStore: MemoryCaptureAssetStore());
    final item = await repository.createCapture(CaptureInput.text('Keep this'));
    await repository.deleteCapture(item.id);
    expect((await repository.listCaptures()).single.status, CaptureStatus.deleted);
    expect((await repository.listCaptures(query: const CaptureQuery(includeDeleted: false))), isEmpty);
    await repository.restoreCapture(item.id);
    expect((await repository.listCaptures()).single.status, CaptureStatus.ready);
  });
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/features/capture/capture_repository_test.dart`

Expected: FAIL because the repository and asset store do not exist.

- [ ] **Step 3: Implement the asset-store seam**

Use a conditional export/import so `dart:io` is never compiled for Web. The native implementation copies bytes into an application-support `varian-captures` directory and sanitizes the filename. The Web implementation stores `ArrayBuffer` values in an IndexedDB object store named `captures` in database `varian-capture-assets`, keyed by a generated `capture-asset://` reference. Both implementations reject empty or oversized bytes and never put bytes in metadata JSON.

Keep `MemoryCaptureAssetStore` in the shared file for repository tests. It must copy byte lists on write and read so tests catch accidental mutation.

- [ ] **Step 4: Implement the local repository**

Store only a JSON list of `CaptureItem.toJson()` values under `ccs_capture_items_v1`. Serialize writes through a private future queue, sort results newest first, filter deleted items according to `CaptureQuery`, and support `all`, `unread`, and `favorites` filters through query fields. On file creation, save the asset first, write metadata second, and delete the new asset if metadata persistence fails. Use `Uuid` for IDs and never log source paths or input content.

- [ ] **Step 5: Run focused tests and verify they pass**

Run: `flutter test test/features/capture/capture_item_test.dart test/features/capture/capture_repository_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the completed task**

```bash
git add lib/features/capture/data test/features/capture/capture_repository_test.dart
git commit -m "feat: persist capture items and local assets"
```

---

## Task 3: Riverpod capture state and file-picker batch support

**Files:**
- Modify: `lib/features/assets/data/asset_service.dart`
- Create: `lib/features/capture/state/capture_provider.dart`
- Test: `test/features/capture/capture_provider_test.dart`
- Modify: `test/features/file_card/file_card_test.dart` only if the existing asset-service expectations need a shared helper update

**Interfaces:**
- `captureRepositoryProvider` returns `LocalCaptureRepository` with the default platform asset store.
- `captureFilterProvider` stores `CaptureFilter.all`, `CaptureFilter.unread`, `CaptureFilter.favorites`, or `CaptureFilter.trash`.
- `captureItemsProvider` exposes `AsyncValue<List<CaptureItem>>`.
- `CaptureNotifier.captureText(String value)`, `CaptureNotifier.captureFiles(List<AssetPickerResult> files)`, `CaptureNotifier.setRead(String id, bool value)`, `CaptureNotifier.setFavorite(String id, bool value)`, `CaptureNotifier.delete(String id)`, `CaptureNotifier.restore(String id)`, and `CaptureNotifier.purge(String id)` update the repository and refresh the visible list.
- `AssetService.pickAnyFiles({String? projectId})` returns every selected file and does not upload automatically when no sync service is supplied.

- [ ] **Step 1: Write failing provider tests**

Test that an overridden repository loads items, `captureText` creates a record, the filter changes the list, and `captureFiles` creates one item per picker result while ignoring an empty result list.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `flutter test test/features/capture/capture_provider_test.dart`

Expected: FAIL because the provider and batch picker method do not exist.

- [ ] **Step 3: Add multi-file selection to `AssetService`**

Reuse the existing `_pickFiles`, `_extractBytes`, `_size`, `_extension`, and `_result` helpers. Add a method that returns `[]` for cancellation, maps every selected `PlatformFile`, and does not silently choose `.first`. Preserve the existing single-file methods unchanged.

- [ ] **Step 4: Implement the notifier**

Use the existing Riverpod `StateNotifierProvider` style. Refresh after every successful mutation. Keep repository errors as `AsyncValue.error` for initial loading and expose mutation failures to the caller so the UI can show a short toast. Apply the selected filter in the provider query rather than filtering only in widgets.

- [ ] **Step 5: Run focused tests and verify they pass**

Run: `flutter test test/features/capture/capture_provider_test.dart test/features/file_card/file_card_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the completed task**

```bash
git add lib/features/assets/data/asset_service.dart lib/features/capture/state/capture_provider.dart test/features/capture/capture_provider_test.dart test/features/file_card/file_card_test.dart
git commit -m "feat: expose capture inbox state"
```

---

## Task 4: Home Capture Inbox UI

**Files:**
- Create: `lib/features/capture/presentation/capture_inbox_panel.dart`
- Modify: `lib/features/home/presentation/home_screen.dart`
- Test: `test/features/capture/capture_inbox_panel_test.dart`

**Interfaces:**
- `CaptureInboxPanel` is a `ConsumerStatefulWidget` that renders the capture input, source actions, filters, and item list.
- The panel uses `CaptureNotifier` rather than writing to `LocalCaptureRepository` directly.

- [ ] **Step 1: Write failing widget tests**

```dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures typed text and displays it in the inbox', (tester) async {
    final repository = FakeCaptureRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [captureRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: FTheme(data: AppTheme.darkForui, child: const CaptureInboxPanel())),
      ),
    );
    await tester.enterText(find.bySemanticsLabel('Capture text or paste a link'), 'New reference');
    await tester.tap(find.text('CAPTURE'));
    await tester.pumpAndSettle();
    expect(find.text('New reference'), findsOneWidget);
  });

  testWidgets('shows an empty state without creating an item', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [captureRepositoryProvider.overrideWithValue(FakeCaptureRepository())],
        child: MaterialApp(home: FTheme(data: AppTheme.darkForui, child: const CaptureInboxPanel())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NOTHING CAPTURED'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the focused widget test and verify it fails**

Run: `flutter test test/features/capture/capture_inbox_panel_test.dart`

Expected: FAIL because the panel does not exist.

- [ ] **Step 3: Build the panel with existing Forui primitives**

Use `UiSurface`, `UiSectionHeader`, `UiTextField`, `UiButton`, `UiIconButton`, `UiBadge`, `UiEmptyState`, `UiLoadingState`, and `showUiToast`. The capture field accepts multiline text and classifies valid HTTP/HTTPS input as a link. The `FILES` action invokes `AssetService.pickAnyFiles()` and creates one item for each selected file. The UI must do nothing for cancellation.

Render each item with a type icon, derived title, safe text preview, relative timestamp, unread/favorite state, and actions for mark read/unread, favorite, delete, restore, and permanent purge in Trash. Do not display full local paths. Keep controls keyboard-focusable and provide semantics labels for capture, file selection, favorite, delete, restore, and purge.

- [ ] **Step 4: Embed the panel as the first Home section**

Modify the Home data branch so the Inbox is visible before project archives for both empty and non-empty project lists. Keep existing project creation, archive, search, settings, and template actions intact. Use a bounded responsive height for the panel so the project grid remains usable on desktop and the panel can scroll internally on narrow windows.

- [ ] **Step 5: Run focused widget tests and verify they pass**

Run: `flutter test test/features/capture/capture_inbox_panel_test.dart test/features/home/project_card_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit the completed task**

```bash
git add lib/features/capture/presentation/capture_inbox_panel.dart lib/features/home/presentation/home_screen.dart test/features/capture/capture_inbox_panel_test.dart
git commit -m "feat: add capture inbox to home"
```

---

## Checkpoint: Core Inbox

- [ ] `flutter test test/features/capture test/features/home/project_card_test.dart`
- [ ] `flutter analyze --no-pub`
- [ ] Windows: type text, paste a URL, select multiple files, restart, filter, favorite, delete, restore, and purge.
- [ ] Web: type text, paste a URL, select multiple files, restart, and verify file metadata remains while binary data is stored outside capture JSON.
- [ ] Android: type text, select a file, rotate/back out of the capture field, and confirm local persistence.

---

## Deferred follow-up slices

These are intentionally not part of this execution slice:

1. Materialize a `CaptureItem` onto a canvas node and drag from Inbox to Canvas.
2. Windows global hotkey.
3. Android share receiver and Web PWA share target.
4. OCR, search indexing, tags, collections, duplicate detection, and AI enrichment.
5. Guest-to-account authentication, cloud capture sync, durable cloud outbox flush, and conflict policy.
6. Screenshot-specific OS capture beyond selecting an image file.

Each follow-up should be implemented as a separate plan after the Core Inbox checkpoint passes.

## Plan self-review

- Spec coverage for the first vertical slice is explicit: local-first persistence, text/URL/file capture, separate binary storage, cancellation safety, lifecycle controls, and Windows/Web/Android verification.
- No unresolved placeholders or unbounded implementation instructions remain in the tasks.
- Names used by later tasks are defined before use: `CaptureItem`, `CaptureInput`, `CaptureRepository`, `CaptureAssetStore`, `CaptureFilter`, `CaptureNotifier`, and `CaptureInboxPanel`.
- The cloud, OS-level, OCR, and canvas-materialization systems are deferred instead of being mixed into this slice.
