# Page-Anchored PDF Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist sticky notes, page-bound drawing, and multi-page text comments on their actual PDF pages.

**Architecture:** Store normalized page-local annotation data in `FilePayload`. Use `pdfrx` document-coordinate hit testing and `pageOverlaysBuilder` so annotations inherit page scroll/zoom transforms. Route annotation mutations back to the owning File Card provider and clear them on replacement.

**Tech Stack:** Flutter 3.44.8, Dart 3.12.2, pdfrx 1.3.5.

**Spec:** `docs/superpowers/specs/2026-08-20-page-anchored-pdf-annotations-design.md`

## Global Constraints

- PDF bytes are never modified.
- Stored coordinates are normalized against the unrotated owning page.
- Existing project JSON without annotations remains compatible.
- Text comments spanning pages remain one thread.
- Replace clears all annotations.
- Workspace is not a Git repository; omit commit steps.

---

### Task 1: Serializable Annotation Domain

**Files:**
- Modify: `lib/features/canvas/presentation/widgets/pdf/pdf_annotation_layer.dart`
- Modify: `lib/domain/models/node_payload.dart`
- Test: `test/features/file_card/pdf_viewer_screen_test.dart`
- Test: `test/features/file_card/file_card_test.dart`

**Interfaces:**
- Produces `PdfAnnotationData`, `PdfPageAnchor`, `PdfTextComment`, page-bound `PdfStroke`, JSON round-trip, and `FilePayload.pdfAnnotations`.

- [ ] Write failing JSON/copy tests for sticky notes, page-bound strokes, multi-page comments, empty backward-compatible payload, and replace reset semantics.
- [ ] Run focused tests and confirm failure for missing models/fields.
- [ ] Implement immutable models, JSON conversion, coordinate clamping, and `FilePayload` integration.
- [ ] Run focused tests and confirm pass.

### Task 2: Pure Page Coordinate Mapping

**Files:**
- Create: `lib/features/canvas/presentation/widgets/pdf/pdf_annotation_coordinates.dart`
- Test: `test/features/file_card/pdf_annotation_coordinates_test.dart`

**Interfaces:**
- Produces `PdfPagePlacement? locatePdfPage(Offset documentPoint, List<Rect> pageRects)` and conversion helpers between normalized/page-local coordinates.

- [ ] Write failing tests for page 1, page 2, gap rejection, clamping, and coordinate round-trip.
- [ ] Run test and confirm missing symbols.
- [ ] Implement pure mapping functions.
- [ ] Run test and confirm pass.

### Task 3: Page-Native Sticky Notes and Strokes

**Files:**
- Modify: `lib/features/canvas/presentation/widgets/pdf_viewer_screen.dart`
- Modify: `lib/features/canvas/presentation/widgets/pdf/pdf_annotation_layer.dart`
- Test: `test/features/file_card/pdf_viewer_screen_test.dart`

**Interfaces:**
- `PdfViewerScreen` consumes `FilePayload.pdfAnnotations` and optional `ValueChanged<PdfAnnotationData> onAnnotationsChanged`.
- `pageOverlaysBuilder` renders only annotations matching `page.pageNumber`.

- [ ] Add failing tests that page 1 annotations do not render under page 2 and placement captures clicked page independent of current page.
- [ ] Remove viewport-global annotation rendering.
- [ ] Use `globalToDocument`, `pageLayouts`, and page-local normalized coordinates for creation.
- [ ] Render sticky notes and strokes from `pageOverlaysBuilder`.
- [ ] Emit immutable annotation updates after add/delete.
- [ ] Run focused tests and confirm pass.

### Task 4: Persistent Text Highlight Comments

**Files:**
- Modify: `lib/features/canvas/presentation/widgets/pdf_viewer_screen.dart`
- Modify: `lib/features/canvas/presentation/widgets/pdf/pdf_sidebar.dart`
- Test: `test/features/file_card/pdf_viewer_screen_test.dart`

**Interfaces:**
- Consumes `PdfViewerParams.onTextSelectionChange` and controller selection range.
- Produces one `PdfTextComment` with one or more `PdfPageAnchor` entries and persistent page overlay highlights.

- [ ] Add failing widget/model tests for Add Comment availability, one multi-page thread, persistent highlights, sidebar display, navigation, and deletion.
- [ ] Capture selection quote/range and page geometry.
- [ ] Add contextual Add Comment action and dialog.
- [ ] Render persistent highlight rectangles per page and connect all anchors to one thread.
- [ ] Merge sticky/text comments in sidebar and emit deletions.
- [ ] Run focused tests and confirm pass.

### Task 5: File Card Persistence and Replace Reset

**Files:**
- Modify: `lib/features/canvas/presentation/widgets/file_preview/file_preview_router.dart`
- Modify: `lib/features/canvas/presentation/canvas_screen.dart`
- Modify: `lib/features/canvas/presentation/widgets/inspector_panel.dart`
- Modify: `lib/features/canvas/presentation/widgets/document_conversion/document_conversion_screen.dart`
- Test: `test/features/file_card/file_card_test.dart`
- Test: `test/features/file_card/file_preview_router_test.dart`

**Interfaces:**
- Router accepts an annotation mutation callback and forwards it through PDF/document conversion routes.
- File Card owners update `documentNodesProvider`; Replace assigns empty `PdfAnnotationData`.

- [ ] Write failing tests for callback forwarding, reopen persistence, Office conversion preservation, and Replace reset.
- [ ] Add router/conversion callback plumbing.
- [ ] Update Canvas and Inspector call sites to persist annotation changes on the selected node.
- [ ] Clear annotations in Replace payload creation.
- [ ] Run File Card tests and confirm pass.

### Task 6: Final Verification

- [ ] Run `dart format lib/domain/models/node_payload.dart lib/features/canvas/presentation/widgets/pdf lib/features/canvas/presentation/widgets/pdf_viewer_screen.dart lib/features/canvas/presentation/widgets/file_preview lib/features/canvas/presentation/widgets/document_conversion test/features/file_card`.
- [ ] Run `flutter analyze --no-pub` and require no issues.
- [ ] Run `flutter test --no-pub` and require all tests pass.
- [ ] Run `flutter build windows --debug --no-pub`.
- [ ] Manually verify sticky notes under scroll, zoom, rotation, single/continuous mode, close/reopen, Office conversion, and Replace reset.
