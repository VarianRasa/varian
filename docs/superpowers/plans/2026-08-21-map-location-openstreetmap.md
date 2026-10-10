# Map Location OpenStreetMap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reliable OpenStreetMap/Nominatim Map Location editor with searchable locations, reverse geocoding, complete inspector controls, and persisted map metadata.

**Architecture:** Keep `MapPayload` as the immutable node boundary. Add a focused HTTP-backed geocoding service and result model, inject it into the map editor, and keep the canvas preview as a lightweight painter. Reuse existing Riverpod node updates and Flutter Map APIs rather than adding a state-management or map SDK dependency.

**Tech Stack:** Flutter, Dart, `flutter_map: ^8.3.1`, `latlong2: ^0.10.1`, existing `http: ^1.2.0`, OpenStreetMap tiles, Nominatim API.

**Spec:** `docs/superpowers/specs/2026-08-21-map-location-openstreetmap-design.md`

## Global Constraints

- Use free OpenStreetMap tiles and Nominatim; do not add Google Maps or Mapbox.
- Use the existing `http` dependency; do not add a geocoding dependency.
- Validate latitude `-90..90`, longitude `-180..180`, and zoom `1..19`.
- Do not issue autocomplete requests on every keystroke.
- Show OpenStreetMap and Nominatim attribution.
- Keep interactive tiles out of the canvas `CustomPainter` preview.
- Device GPS, offline tile caching, and API keys are out of scope.
- Do not add comments unless required by an external API contract.

---

### Task 1: Harden MapPayload

**Files:**
- Modify: `lib/domain/models/node_payload.dart` around `MapPayload`.
- Test: `test/features/infinite_board_suite_test.dart` or a focused map payload test following repository conventions.

**Interfaces:**
- Produces validated `MapPayload` construction/deserialization while preserving existing JSON field names and defaults.

- [ ] **Step 1: Write failing tests** for valid round-trip, clone preservation, invalid latitude/longitude/zoom fallback, and non-finite values.
- [ ] **Step 2: Run the focused test and confirm the invalid-value assertions fail.**
- [ ] **Step 3: Implement shared range checks in `MapPayload`, keeping existing constructor and JSON compatibility.**
- [ ] **Step 4: Run the focused map payload tests and confirm pass.**
- [ ] **Step 5: Run `dart format` on changed Dart files.**

### Task 2: Add Nominatim Service

**Files:**
- Create: `lib/features/media/map_location_service.dart`.
- Test: `test/features/map_location_service_test.dart`.

**Interfaces:**
- `class MapLocationResult { final String displayName; final double latitude; final double longitude; }`
- `class MapLocationService { Future<List<MapLocationResult>> search(String query); Future<MapLocationResult?> reverse(double latitude, double longitude); }`
- Constructor accepts an injectable `http.Client`, base URI defaulting to `https://nominatim.openstreetmap.org`, and an application user-agent string.

- [ ] **Step 1: Write HTTP fixture tests** for query encoding, `format=jsonv2`, `limit`, `accept-language`, User-Agent, result parsing, empty results, malformed JSON, HTTP errors, and timeout mapping.
- [ ] **Step 2: Run `flutter test test/features/map_location_service_test.dart` and confirm failure before implementation.**
- [ ] **Step 3: Implement requests with `http.Client`, `Uri` query parameters, timeout, status validation, finite coordinate parsing, and typed recoverable exceptions/results.**
- [ ] **Step 4: Run the service tests and confirm pass.**
- [ ] **Step 5: Run `dart format` on service and tests.**

### Task 3: Upgrade MapViewerScreen

**Files:**
- Modify: `lib/features/media/map_viewer_screen.dart`.
- Test: `test/features/map_viewer_screen_test.dart`.

**Interfaces:**
- `MapViewerScreen` continues accepting `MapPayload` and `ValueChanged<MapPayload> onSave`.
- It consumes `MapLocationService` through an optional constructor parameter, defaulting to the real service.

- [ ] **Step 1: Add widget tests** for initial fields, submitting a search, selecting a result, tapping/dragging marker, reverse-geocoding updates, zoom persistence, save payload, attribution, empty results, and service errors using a fake service.
- [ ] **Step 2: Run focused widget tests and confirm failure.**
- [ ] **Step 3: Move controllers to `initState` and dispose them; add search state, results, loading/error states, and fake-service injection.**
- [ ] **Step 4: Wire `flutter_map` camera events and marker interactions so latitude, longitude, and zoom update together.**
- [ ] **Step 5: Trigger reverse geocoding only after a settled point change, preserve title edits, and update address from successful results.**
- [ ] **Step 6: Add attribution and save-time validation; preserve current callback navigation.**
- [ ] **Step 7: Run focused widget tests and confirm pass.**

### Task 4: Expand Inspector Map Controls

**Files:**
- Modify: `lib/features/canvas/presentation/widgets/inspector_panel.dart` around the Map Location section.
- Modify: `lib/features/canvas/presentation/canvas_screen.dart` where `MapViewerScreen` is opened.
- Test: existing inspector/widget test location or `test/features/map_inspector_test.dart`.

**Interfaces:**
- Inspector updates the selected node through the existing `documentNodesProvider.notifier.updateNode` path.
- Reverse-geocode action uses the same `MapLocationService` and updates only address/coordinates on success.

- [ ] **Step 1: Add tests** for latitude, longitude, zoom edits, invalid numeric input preservation, reverse-geocode action, and Open Map Editor navigation.
- [ ] **Step 2: Run focused tests and confirm failure.**
- [ ] **Step 3: Add controlled numeric fields with inline validation and immutable `MapPayload` updates.**
- [ ] **Step 4: Add reverse-geocode and open-editor actions while preserving selected-node state.**
- [ ] **Step 5: Run focused tests and confirm pass.**

### Task 5: Complete Export and Search Metadata

**Files:**
- Modify: `lib/features/export/export_service.dart` map export sections.
- Modify: `lib/features/search/search_service.dart` map indexing sections.
- Test: existing import/export/search tests or focused additions.

**Interfaces:**
- Exported Map Location metadata includes title, address, latitude, longitude, and zoom.
- Search matches both `locationTitle` and `address`.

- [ ] **Step 1: Add failing assertions for all five exported fields and address search matches.**
- [ ] **Step 2: Run focused tests and confirm failure.**
- [ ] **Step 3: Add metadata using existing output/index conventions without changing unrelated node formats.**
- [ ] **Step 4: Run export, import, and search tests and confirm pass.**

### Task 6: Improve Canvas Preview and Defaults

**Files:**
- Modify: `lib/features/canvas/presentation/painters/node_painter.dart` map painter.
- Modify: `lib/features/canvas/presentation/canvas_screen.dart` map node spawn defaults if needed.
- Test: `test/features/infinite_board_suite_test.dart` or canvas painter tests.

**Interfaces:**
- Canvas remains a lightweight `CustomPainter` preview.
- Preview uses current payload title/address and coordinates where space permits; no network tile loading occurs.

- [ ] **Step 1: Add/adjust a painter test** confirming current map payload values render without throwing and invalid data does not crash.
- [ ] **Step 2: Implement compact address/coordinate display while preserving existing dark visual style and node sizing.**
- [ ] **Step 3: Run focused painter tests.**

### Task 7: Full Verification

**Files:**
- No source changes unless verification exposes an issue.

- [ ] **Step 1: Run `dart format` on all changed Dart files.**
- [ ] **Step 2: Run `flutter analyze --no-pub`.**
- [ ] **Step 3: Run `flutter test --no-pub`.**
- [ ] **Step 4: Review the diff for unrelated changes, API keys, secrets, missing attribution, and accidental network calls from canvas painting.**

## Self-Review

- Spec coverage: Tasks 1-2 cover data and service; Task 3 covers viewer/search/reverse geocoding/zoom/errors/attribution; Task 4 covers inspector; Tasks 5-6 cover integrations and canvas; Task 7 covers verification.
- Placeholder scan: No TBD/TODO or unspecified implementation step remains.
- Type consistency: `MapLocationResult` and `MapLocationService` are defined in Task 2 and consumed by Tasks 3-4; `MapPayload` field names remain unchanged.
- Scope: Device location, offline caching, provider SDKs, and canvas tile rendering are explicitly excluded.
