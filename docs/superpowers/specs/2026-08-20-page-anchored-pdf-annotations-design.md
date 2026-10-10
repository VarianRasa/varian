# Design Spec: Page-Anchored PDF Annotations and Comments

## 1. Goal

Make PDF annotations behave like document annotations rather than viewport overlays. Sticky notes, freehand pen strokes, freehand highlights, and text-selection comments remain attached to their original PDF pages while scrolling, zooming, rotating, changing view mode, closing, and reopening the viewer.

## 2. Supported Annotation Types

### 2.1 Free Sticky Note

A user selects the sticky-note tool and clicks a PDF page. The note stores one page-local anchor and opens a comment dialog. It appears only on its owning page and moves with that page.

### 2.2 Freehand Pen and Highlighter

Each stroke stores its owning page and page-relative points. Drawing starts only when the pointer is inside a page. Crossing page gaps ends or rejects the stroke. Pen and highlighter strokes remain page-bound under all viewer transforms.

### 2.3 Text Highlight Comment

In selection mode, a user selects PDF text and creates a comment. One comment thread may span multiple pages. It stores:

- Selected quote text.
- Character-range identity where available.
- One or more page anchors describing highlight rectangles in PDF/page coordinates.
- Comment text and timestamps.

The highlight remains visible after selection clears. Clicking any highlight segment opens the same comment thread.

## 3. Data Model

Add serializable PDF annotation models owned by `FilePayload`:

```dart
class PdfAnnotationData {
  final List<PdfStickyNote> stickyNotes;
  final List<PdfStroke> strokes;
  final List<PdfTextComment> textComments;
}

class PdfPageAnchor {
  final int pageNumber;
  final List<Rect> relativeRects;
}

class PdfStickyNote {
  final String id;
  final int pageNumber;
  final Offset relativePosition;
  final String text;
  final Color color;
  final DateTime createdAt;
}

class PdfStroke {
  final String id;
  final int pageNumber;
  final List<Offset> relativePoints;
  final Color color;
  final double width;
  final bool isHighlighter;
}

class PdfTextComment {
  final String id;
  final String quote;
  final String comment;
  final List<PdfPageAnchor> anchors;
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

Coordinates are normalized relative to the unrotated page. Every model supports JSON round-trip, cloning, and immutable updates.

`FilePayload` gains `PdfAnnotationData pdfAnnotations`, defaulting to empty for backward compatibility. Replacing a File Card creates a new payload with empty annotations. Converting Office/ODF to a cached PDF keeps annotations on the original File Card; the PDF viewer receives the same annotation data and reports mutations back to the original payload owner.

## 4. Coordinate and Rendering Architecture

Use `pdfrx` page-native APIs:

- `PdfViewerController.globalToDocument` converts pointer coordinates into document coordinates.
- `controller.layout.pageLayouts` identifies the page under the pointer.
- Page-local positions are normalized against that page rectangle.
- `PdfViewerParams.pageOverlaysBuilder` renders annotations inside their owning page overlay.

No annotation is positioned using viewer `LayoutBuilder` width or height. Continuous mode never ignores `pageNumber`.

Page overlay rendering converts normalized coordinates to the current `pageRect.size`. Because the overlay belongs to the page, scrolling, zooming, layout mode, and viewport resizing are inherited from `pdfrx`.

Rotation uses the same unrotated page coordinate convention for storage. Rendering applies the viewer/page transformation once; stored coordinates are not rewritten when rotation changes.

## 5. Interaction Flow

### 5.1 Sticky Note

1. Sticky-note mode installs a `PdfOverlayInteractionRegion` through `viewerOverlayBuilder`.
2. A click is transformed to document coordinates.
3. The owning page is found from `pageLayouts`; clicks in margins/gaps are ignored.
4. Page number and normalized page position are captured before opening the dialog.
5. Saving creates the note with the captured placement, never the mutable current-page value.

### 5.2 Freehand Drawing

1. Pointer-down resolves an owning page.
2. Pointer movement converts document points into normalized points for that same page.
3. Points outside the owning page are clipped or ignored.
4. Pointer-up stores one page-bound stroke.

### 5.3 Text Comment

1. Selection mode enables `pdfrx` text selection.
2. `onTextSelectionChange` and `controller.textSelection.textSelectionPointRange` capture selected text and character range.
3. Selection geometry is grouped by page into `PdfPageAnchor` entries.
4. A contextual **Add Comment** action opens the comment dialog.
5. Saving persists one `PdfTextComment`, even when anchors span multiple pages.
6. Persistent page overlays paint highlight rectangles and open the shared thread when clicked.

If the installed `pdfrx` version does not expose selection rectangles directly, geometry is derived from page text fragments and character indices. No viewport screenshot or approximate global rectangle is persisted.

## 6. Persistence and Ownership

`PdfViewerScreen` receives an optional mutation callback:

```dart
final ValueChanged<PdfAnnotationData>? onAnnotationsChanged;
```

Every add, edit, and delete operation updates local viewer state and calls the callback. Canvas and Inspector routing pass a callback that updates the corresponding File Card through `documentNodesProvider`.

Direct viewer tests and contexts without an owner may omit the callback; annotations then remain session-local. Normal File Card usage always supplies the callback.

Office/ODF conversion must retain the original node identity and callback while displaying the converted PDF. Cache invalidation does not delete annotations. File replacement explicitly resets annotations because page identity may change.

## 7. Sidebar and Navigation

The Notes sidebar combines sticky notes and text comments, sorted by page then creation time. Text comments spanning pages show the first page and a page range. Selecting an item:

1. Navigates to its first anchor page.
2. Focuses or briefly emphasizes the annotation overlay.
3. Opens its thread/details dialog.

Delete removes the annotation from viewer state and persisted `FilePayload`.

## 8. Error and Compatibility Rules

- Invalid page numbers or malformed coordinates are ignored during rendering, not allowed to crash the viewer.
- Relative coordinates are clamped to `0..1` when loading legacy/project JSON.
- Existing projects without `pdfAnnotations` deserialize to an empty collection.
- Legacy in-memory annotation classes are migrated or replaced without changing unrelated PDF viewer behavior.
- Search highlights remain separate from persistent text-comment highlights.
- PDF contents are never rewritten; annotations live in project data.

## 9. Tests

### Unit Tests

- Pointer-to-page hit testing for page 1, page 2, and page gaps.
- Page-relative coordinate round-trip under scroll and zoom transforms.
- JSON round-trip for sticky notes, strokes, multi-page text comments, and annotation collections.
- Invalid coordinate/page compatibility handling.
- Replace resets annotations.

### Widget Tests

- Page 1 sticky note is rendered only under page 1 overlay.
- Continuous scrolling moves the note with page 1 and does not project it onto page 2.
- Sticky note placement uses the clicked page rather than `_currentPage`.
- Pen/highlighter strokes remain page-bound.
- Text selection exposes **Add Comment** and saves one multi-page thread.
- Selecting sidebar items navigates to the correct page/thread.
- Closing and reopening through File Card restores annotations.

### Verification

Run `dart format`, `flutter analyze`, `flutter test`, and Windows debug/release builds. Manually smoke-check sticky notes and text comments across zoom, rotation, single-page mode, continuous mode, close/reopen, Office conversion, and File Card replacement.

## 10. Non-Goals

- Writing annotations into the PDF binary.
- Collaborative real-time comment threads.
- Replies, mentions, assignments, or resolution workflows.
- OCR-based selection for scanned PDFs without a text layer.
