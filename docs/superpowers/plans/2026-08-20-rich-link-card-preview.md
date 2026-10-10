# Rich Link Card Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an editable Link Card that automatically persists and renders Open Graph metadata, opens inside the app by default, and offers explicit external-browser and refresh actions.

**Architecture:** Keep persisted preview data in `LinkPayload`, isolate URL safety and HTML parsing in pure utilities, and coordinate bounded HTTP requests through one Riverpod controller that rejects stale results. Render Link Cards as positioned Flutter widgets above the painter so text editing and buttons remain interactive while existing canvas transforms, selection, and persistence remain authoritative.

**Tech Stack:** Flutter, Dart, Riverpod, existing `http`, `webview_flutter`, and `url_launcher` dependencies.

**Spec:** `docs/superpowers/specs/2026-08-20-rich-link-card-preview-design.md`

## Global Constraints

- Use existing dependencies; do not add a package for HTML metadata parsing.
- Accept only absolute `http` and `https` URLs without embedded credentials.
- Reject localhost and prohibited IPv4/IPv6 destinations before requests and after redirects.
- Apply request timeout, redirect limit, HTML content-type check, and response-size limit.
- Persist metadata text and remote image URLs, never remote image bytes.
- Treat persisted `loading` as `idle` when deserializing.
- Keep existing Link Card JSON backward compatible.
- Do not create undo entries for every inline-editor keystroke.
- Full-page screenshots, JavaScript execution, authentication, cookies, and periodic refresh are out of scope.

---

### Task 1: Persisted Link Preview Model

**Files:**
- Modify: `lib/domain/models/node_payload.dart:1668-1703`
- Create: `test/features/link_card/link_payload_test.dart`

**Interfaces:**
- Produces: `enum LinkPreviewStatus { idle, loading, ready, error }`
- Produces: `LinkPayload.copyWith({String? title, String? url, String? description, String? faviconUrl, String? imageUrl, String? siteName, DateTime? fetchedAt, LinkPreviewStatus? previewStatus, String? previewError, bool clearDescription = false, bool clearFaviconUrl = false, bool clearImageUrl = false, bool clearSiteName = false, bool clearFetchedAt = false, bool clearPreviewError = false})`
- Produces: `LinkPayload.clearPreview({required String url})`

- [ ] **Step 1: Write failing model tests**

Create tests that construct a payload with all metadata fields, round-trip through `toJson`/`LinkPayload.fromJson`, verify `clone`, and verify `copyWith(title: 'Manual')` preserves every preview field. Add legacy JSON without preview keys and JSON containing `previewStatus: 'loading'`; expect `idle` for both missing and persisted loading status.

```dart
final payload = LinkPayload(
  title: 'Example',
  url: 'https://example.com/article',
  description: 'Description',
  faviconUrl: 'https://example.com/favicon.ico',
  imageUrl: 'https://cdn.example.com/card.jpg',
  siteName: 'Example Site',
  fetchedAt: DateTime.utc(2026, 8, 20),
  previewStatus: LinkPreviewStatus.ready,
);
final restored = LinkPayload.fromJson(payload.toJson());
expect(restored.imageUrl, payload.imageUrl);
expect(restored.previewStatus, LinkPreviewStatus.ready);
expect(restored.copyWith(title: 'Manual').faviconUrl, payload.faviconUrl);
expect(
  LinkPayload.fromJson({'url': 'https://example.com', 'previewStatus': 'loading'}).previewStatus,
  LinkPreviewStatus.idle,
);
```

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_payload_test.dart`

Expected: compilation fails because the enum and preview fields do not exist.

- [ ] **Step 3: Implement the minimal backward-compatible model**

Add the enum and fields, serialize enum names and ISO-8601 timestamps, parse unknown statuses as `idle`, and map serialized `loading` to `idle`. Implement `copyWith`, explicit nullable-field clearing flags, `clone`, and `clearPreview` that preserves manual URL but resets fetched metadata and status.

- [ ] **Step 4: Run focused model tests**

Run: `flutter test --no-pub test/features/link_card/link_payload_test.dart`

Expected: PASS.

---

### Task 2: URL Policy and Open Graph Parser

**Files:**
- Create: `lib/features/link_card/domain/link_url_policy.dart`
- Create: `lib/features/link_card/data/link_preview_parser.dart`
- Create: `test/features/link_card/link_url_policy_test.dart`
- Create: `test/features/link_card/link_preview_parser_test.dart`

**Interfaces:**
- Produces: `class LinkUrlValidationException implements Exception`
- Produces: `Uri normalizeLinkUrl(String input)`
- Produces: `Future<void> ensurePublicDestination(Uri uri, {InternetAddressLookup lookup = InternetAddress.lookup})`
- Produces: `class LinkPreviewMetadata { final Uri finalUri; final String title; final String? description; final Uri? faviconUri; final Uri? imageUri; final String siteName; }`
- Produces: `LinkPreviewMetadata parseLinkPreviewHtml({required String html, required Uri finalUri})`

- [ ] **Step 1: Write failing URL policy tests**

Cover trimming and lower-case scheme normalization, rejection of relative URLs, unsupported schemes, credentials, empty hosts, `localhost`, loopback, private IPv4 blocks, link-local, unspecified, multicast, IPv6 loopback/link-local/private ranges, and DNS lookup returning a prohibited address. Inject lookup functions so tests never require network access.

```dart
expect(normalizeLinkUrl(' HTTPS://Example.COM/path ').toString(), 'https://example.com/path');
expect(() => normalizeLinkUrl('file:///tmp/a'), throwsA(isA<LinkUrlValidationException>()));
await expectLater(
  ensurePublicDestination(
    Uri.parse('https://internal.example'),
    lookup: (_) async => [InternetAddress('127.0.0.1')],
  ),
  throwsA(isA<LinkUrlValidationException>()),
);
```

- [ ] **Step 2: Run URL policy tests and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_url_policy_test.dart`

Expected: compilation fails because policy symbols do not exist.

- [ ] **Step 3: Implement URL normalization and public-address validation**

Use `Uri.tryParse`, explicit scheme checks, `uri.userInfo.isEmpty`, normalized host/scheme reconstruction, `InternetAddress.tryParse`, and byte-level IPv4/IPv6 range checks. Reject the hostname before DNS when it is `localhost` or ends with `.localhost`; reject the destination when any resolved address is prohibited.

- [ ] **Step 4: Run URL policy tests**

Run: `flutter test --no-pub test/features/link_card/link_url_policy_test.dart`

Expected: PASS.

- [ ] **Step 5: Write failing parser tests**

Cover case-insensitive attributes, single/double/unquoted attributes, arbitrary attribute order, HTML entities, `<base href>`, relative image/icon URLs, `og:title` precedence, `<title>` fallback, `og:description` then description fallback, `og:image` then Twitter image fallback, site name fallback, and malformed/missing tags.

```dart
final result = parseLinkPreviewHtml(
  html: '''
    <html><head>
      <meta content="OG Title" property="og:title">
      <meta property='og:image' content='/preview.jpg'>
      <link rel="icon" href="icons/site.png">
    </head></html>
  ''',
  finalUri: Uri.parse('https://example.com/articles/1'),
);
expect(result.title, 'OG Title');
expect(result.imageUri.toString(), 'https://example.com/preview.jpg');
```

- [ ] **Step 6: Run parser tests and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_preview_parser_test.dart`

Expected: compilation fails because parser symbols do not exist.

- [ ] **Step 7: Implement the minimal non-executing HTML parser**

Parse only the opening tags required for metadata using bounded regular expressions and a small attribute tokenizer. Decode named `amp`, `quot`, `apos`, `lt`, `gt`, and numeric entities; strip remaining tags and normalize whitespace. Resolve metadata URLs against valid `<base>` or the final response URI. Return hostname fallbacks when metadata is absent.

- [ ] **Step 8: Run policy and parser tests**

Run: `flutter test --no-pub test/features/link_card/link_url_policy_test.dart test/features/link_card/link_preview_parser_test.dart`

Expected: PASS.

---

### Task 3: Bounded Metadata Fetch and Stale-Result Coordinator

**Files:**
- Create: `lib/features/link_card/data/link_preview_service.dart`
- Create: `lib/features/link_card/state/link_preview_controller.dart`
- Create: `test/features/link_card/link_preview_service_test.dart`
- Create: `test/features/link_card/link_preview_controller_test.dart`

**Interfaces:**
- Consumes: `normalizeLinkUrl`, `ensurePublicDestination`, `parseLinkPreviewHtml`, `LinkPayload.copyWith`
- Produces: `class LinkPreviewException implements Exception { final String message; }`
- Produces: `class LinkPreviewService { Future<LinkPreviewMetadata> fetch(String input); }`
- Produces: `final linkPreviewServiceProvider = Provider<LinkPreviewService>(...)`
- Produces: `class LinkPreviewController extends AutoDisposeNotifier<Map<String, int>> { Future<void> refresh(CanvasNode node); void cancel(String nodeId); }`
- Produces: `final linkPreviewControllerProvider = AutoDisposeNotifierProvider<LinkPreviewController, Map<String, int>>(...)`

- [ ] **Step 1: Write failing service tests with a fake HTTP client**

Verify HTML success, relative metadata resolution against final redirect URI, rejection of non-2xx responses, non-HTML content, oversized declared `content-length`, oversized streamed body, redirect loops, more than three redirects, redirect to a prohibited destination, and timeout. Use injected `http.Client`, destination checker, timeout, and `maxBodyBytes`.

```dart
final service = LinkPreviewService(
  client: fakeClient,
  ensureDestination: (_) async {},
  timeout: const Duration(milliseconds: 50),
  maxBodyBytes: 1024,
  maxRedirects: 3,
);
final metadata = await service.fetch('https://example.com');
expect(metadata.title, 'Example');
```

- [ ] **Step 2: Run service tests and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_preview_service_test.dart`

Expected: compilation fails because `LinkPreviewService` does not exist.

- [ ] **Step 3: Implement bounded manual redirects and body streaming**

Send `http.Request('GET', uri)` with `followRedirects = false`, validate each URI before sending, accept only `text/html` or `application/xhtml+xml`, and accumulate response bytes only up to the configured cap. Decode using UTF-8 with malformed replacement, parse metadata, and translate network/timeout failures to concise `LinkPreviewException` messages.

- [ ] **Step 4: Run service tests**

Run: `flutter test --no-pub test/features/link_card/link_preview_service_test.dart`

Expected: PASS.

- [ ] **Step 5: Write failing controller tests**

Use `ProviderContainer` overrides for fake service results and `documentNodesProvider`. Verify refresh immediately writes cleared metadata plus `loading`, success writes `ready`, failure writes `error` without removing URL, the older of two requests cannot overwrite the newer URL, and deleting a node before completion does not recreate it.

- [ ] **Step 6: Run controller tests and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_preview_controller_test.dart`

Expected: compilation fails because the provider/controller does not exist.

- [ ] **Step 7: Implement generation-token coordination**

Increment a generation per node before each request. Before every completion update, re-read `documentNodesProvider`, locate the node, verify its current URL and generation, then update only that existing node. `cancel` invalidates the generation. Convert result URIs to strings and stamp `fetchedAt` in UTC.

- [ ] **Step 8: Run service and controller tests**

Run: `flutter test --no-pub test/features/link_card/link_preview_service_test.dart test/features/link_card/link_preview_controller_test.dart`

Expected: PASS.

---

### Task 4: Interactive Rich Link Card Widget

**Files:**
- Create: `lib/features/link_card/presentation/link_card_widget.dart`
- Create: `test/features/link_card/link_card_widget_test.dart`
- Modify: `lib/features/canvas/presentation/painters/node_painter.dart:88-89,2755-2794`

**Interfaces:**
- Consumes: `LinkPayload`, `normalizeLinkUrl`
- Produces: `class LinkCardWidget extends StatefulWidget`
- Constructor: `LinkCardWidget({required CanvasNode node, required bool selected, required ValueChanged<String> onSubmitUrl, required VoidCallback onRefresh, required VoidCallback onOpenInApp, required VoidCallback onOpenExternal})`

- [ ] **Step 1: Write failing widget tests**

Pump the card at `320 × 220` and minimum supported `220 × 120`. Verify empty prompt, double-click URL area entering a `TextField`, Enter submission, Escape cancellation, loading indicator, ready metadata text/image placeholder, error message, refresh callback, external callback, and no overflow exceptions.

```dart
await tester.pumpWidget(testApp(LinkCardWidget(
  node: emptyNode,
  selected: true,
  onSubmitUrl: submitted.add,
  onRefresh: () => refreshed++,
  onOpenInApp: () => openedInApp++,
  onOpenExternal: () => openedExternal++,
)));
await tester.tap(find.byKey(const Key('link-card-url')), buttons: kPrimaryButton);
await tester.tap(find.byKey(const Key('link-card-url')), buttons: kPrimaryButton);
await tester.enterText(find.byType(TextField), 'https://example.com');
await tester.testTextInput.receiveAction(TextInputAction.done);
expect(submitted.single, 'https://example.com');
```

- [ ] **Step 2: Run widget tests and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_card_widget_test.dart`

Expected: compilation fails because `LinkCardWidget` does not exist.

- [ ] **Step 3: Implement idle, loading, ready, and error layouts**

Use `LayoutBuilder` and stable keyed controls. Keep text editing local until submit. Normalize/validate before invoking `onSubmitUrl`; show inline validation errors without mutating the node. Use `Image.network` with `errorBuilder` for remote image/favicons and deterministic icon/color fallbacks. Hide description and then thumbnail as dimensions shrink.

- [ ] **Step 4: Make the painter skip Link Cards**

Remove `_paintLinkCard` invocation for `NodeType.linkCard` so the widget is the sole card renderer. Preserve painter behavior for malformed or export-only contexts by drawing a simple noninteractive fallback only when the widget layer is unavailable, selected through an explicit `paintLinkCards` parameter on `CanvasPainter`/`NodePainter` rather than double-painting normal canvas cards.

- [ ] **Step 5: Run widget and painter smoke tests**

Run: `flutter test --no-pub test/features/link_card/link_card_widget_test.dart test/features/infinite_board_suite_test.dart`

Expected: PASS and no Flutter overflow exceptions.

---

### Task 5: Canvas Overlay, Automatic Refresh, and Link Opening

**Files:**
- Modify: `lib/features/canvas/presentation/canvas_screen.dart:757-890,2529-2568,2951-2961,4000-4013`
- Modify: `lib/features/media/embed_webview_screen.dart:21-102`
- Create: `test/features/link_card/link_card_canvas_actions_test.dart`

**Interfaces:**
- Consumes: `LinkCardWidget`, `linkPreviewControllerProvider`, `normalizeLinkUrl`, `EmbedWebviewScreen`
- Produces: canvas helper `_submitLinkUrl(CanvasNode node, String input)`
- Produces: canvas helper `_openLinkInApp(CanvasNode node)`
- Produces: canvas helper `_openLinkExternal(CanvasNode node)`

- [ ] **Step 1: Write failing canvas-action tests**

Extract action decisions into testable callbacks or a small widget harness. Verify a valid changed URL updates once then invokes refresh, unchanged normalized URL does not clear metadata, card-body double-click opens `EmbedWebviewScreen`, and external action calls an injected launcher with `LaunchMode.externalApplication`. Verify invalid URLs show a SnackBar and invoke neither navigation nor launch.

- [ ] **Step 2: Run canvas-action tests and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_card_canvas_actions_test.dart`

Expected: tests fail because Link Cards have no overlay/actions.

- [ ] **Step 3: Add transformed Link Card overlays above `CustomPaint`**

For every visible Link Card, convert world position using `viewportProvider`, multiply width/height by zoom, and place a transformed `LinkCardWidget` in the existing canvas `Stack`. Keep selection and drag hit testing owned by the canvas; interactive child regions consume only editor/action gestures. Pass current selection state and provider-backed callbacks.

- [ ] **Step 4: Change creation defaults**

Create Link Cards at `320 × 220` with empty URL/title metadata and `idle` status. Clamp Link Card resize to `220 × 120` in the existing generic resize path while preserving other node minimum rules.

- [ ] **Step 5: Wire URL submission and automatic metadata retrieval**

Normalize input, update the existing node once with cleared metadata/loading through the controller, and let the controller fetch immediately. Do not write draft keystrokes to `documentNodesProvider`.

- [ ] **Step 6: Wire in-app and external opening**

Validate before opening. Push `EmbedWebviewScreen` for body double-click/Open in App. Call `launchUrl(uri, mode: LaunchMode.externalApplication)` for external action and show a non-blocking SnackBar when launch returns false or throws. Update `EmbedWebviewScreen` to accept only prevalidated HTTP(S) URLs and handle controller/load errors without throwing.

- [ ] **Step 7: Run canvas/action and existing interaction tests**

Run: `flutter test --no-pub test/features/link_card/link_card_canvas_actions_test.dart test/features/canvas/hit_test_test.dart test/features/canvas/resize_handles_test.dart test/features/canvas/command_history_test.dart`

Expected: PASS.

---

### Task 6: Inspector Controls and End-to-End Verification

**Files:**
- Create: `lib/features/link_card/presentation/link_card_inspector.dart`
- Modify: `lib/features/canvas/presentation/widgets/inspector_panel.dart:5052-5117`
- Create: `test/features/link_card/link_card_inspector_test.dart`
- Modify: `test/features/infinite_board_suite_test.dart:26-39,109-131`

**Interfaces:**
- Consumes: `LinkPayload.copyWith`, `linkPreviewControllerProvider`, `normalizeLinkUrl`
- Produces: `LinkCardInspector({required CanvasNode node, required ValueChanged<String> onSubmitUrl, required ValueChanged<String> onTitleChanged, required ValueChanged<String> onDescriptionChanged, required VoidCallback onRefresh, required VoidCallback onOpenInApp, required VoidCallback onOpenExternal})`

- [ ] **Step 1: Write failing Inspector tests**

Verify URL submission happens on Enter/focus completion rather than each keystroke, validation feedback appears, title/description changes preserve favicon/image/site/status, hostname/status display correctly, and Refresh/Open in App/Open in Browser invoke their callbacks. Pump a narrow Inspector width and assert no overflow.

- [ ] **Step 2: Run Inspector tests and confirm failure**

Run: `flutter test --no-pub test/features/link_card/link_card_inspector_test.dart`

Expected: compilation fails because `LinkCardInspector` does not exist.

- [ ] **Step 3: Implement the focused Inspector widget**

Move the Link Card branch UI into `LinkCardInspector`. Keep URL draft state local; expose validation feedback; submit only normalized changes. Use `copyWith` for title and description updates. Render status as `Idle`, `Loading`, `Ready`, or the concise persisted error.

- [ ] **Step 4: Replace the old Inspector branch and preserve provider ownership**

Instantiate `LinkCardInspector` from `InspectorPanel`, pass callbacks that update the current node or invoke `linkPreviewControllerProvider`, and reuse the same validated open helpers as canvas actions. Delete manual `LinkPayload(...)` reconstruction that drops favicon data.

- [ ] **Step 5: Expand suite serialization and painter expectations**

Update `infinite_board_suite_test.dart` to assert URL, description, favicon, image, site name, fetched timestamp, and status round-trip. Keep painter smoke coverage for export/fallback rendering without requiring network access.

- [ ] **Step 6: Run all Link Card tests**

Run: `flutter test --no-pub test/features/link_card test/features/infinite_board_suite_test.dart`

Expected: PASS.

- [ ] **Step 7: Format and run static verification**

Run: `dart format lib/domain/models/node_payload.dart lib/features/link_card lib/features/canvas/presentation/canvas_screen.dart lib/features/canvas/presentation/painters/node_painter.dart lib/features/canvas/presentation/widgets/inspector_panel.dart lib/features/media/embed_webview_screen.dart test/features/link_card test/features/infinite_board_suite_test.dart`

Run: `flutter analyze --no-pub`

Expected: `No issues found!`

- [ ] **Step 8: Run the complete test suite**

Run: `flutter test --no-pub`

Expected: all tests pass.

- [ ] **Step 9: Build Windows debug and release**

Run: `flutter build windows --debug --no-pub`

Run: `flutter build windows --release --no-pub`

Expected: both builds produce `varian.exe`. If the linker reports `LNK1168`, stop only the running local `varian.exe` process and rerun the failed build.

- [ ] **Step 10: Perform manual smoke verification**

Create an empty Link Card; edit URL by double-click; verify automatic loading and preview; resize to minimum and large sizes; undo/redo; save/reopen; refresh online and offline; open in app; open externally; test invalid/private URLs; delete a card during a pending request; confirm no stale node returns.
