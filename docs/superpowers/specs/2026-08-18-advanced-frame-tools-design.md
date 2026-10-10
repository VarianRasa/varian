# Design Spec: Advanced Frame Tools (Presets, Clip Content & Styling, Auto-Layout, and Frame Quick Export)

## 1. Overview
Enhance the **Frame Container** in Varian canvas from a simple visual rectangle container into a powerful, Figma-grade frame system with:
1. **Device & Artboard Presets + Orientation Switcher** (Mobile, Tablet, Desktop, Presentation, Social, Paper).
2. **True Clip Content & Rich Styling** (Corner Radius, Border Stroke & Style, Background Color/Gradient, Drop Shadow, Canvas Clip).
3. **Auto-Layout & Resizing Constraints** (Direction: None/Horizontal/Vertical, Spacing/Gap, Padding, Alignments, and Child Constraint Scaling/Pinning).
4. **Quick Export per Frame** (Export specific frame and its children to PNG at 1x/2x/3x, SVG, or standalone single-page PDF).

---

## 2. Domain & Data Models

### 2.1 Model Updates: `FramePayload`
In `lib/domain/models/node_payload.dart`:
```dart
enum AutoLayoutDirection { none, horizontal, vertical }
enum AutoLayoutAlign { start, center, end, spaceBetween }
enum ConstraintHorizontal { left, right, leftRight, center, scale }
enum ConstraintVertical { top, bottom, topBottom, center, scale }

class FramePayload extends NodePayload {
  final String name;
  final Color background;
  final Color? backgroundGradientEnd; // Optional linear gradient
  final bool clipContent;
  final double cornerRadius;
  final Color borderColor;
  final double borderWidth;
  final bool isDashedBorder;
  final bool hasShadow;
  final double shadowBlur;
  final Color shadowColor;

  // Auto-Layout
  final AutoLayoutDirection layoutDirection;
  final double itemSpacing;
  final double paddingLeft;
  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final AutoLayoutAlign layoutAlign;
  final AutoLayoutAlign layoutDistribution;

  // Preset tracking
  final String? presetId;
  final bool isLandscape;
  ...
}
```

### 2.2 Child Constraint Extension
In `CanvasNode` or `NodePayload` (or via payload metadata):
Support horizontal and vertical constraints per child node for smart frame resizing:
- `constraintH`: `left`, `right`, `leftRight` (stretch), `center`, `scale`
- `constraintV`: `top`, `bottom`, `topBottom` (stretch), `center`, `scale`

---

## 3. Presets Catalog (`lib/features/canvas/utils/frame_presets.dart`)
Standard presets catalog:
- **Mobile**: iPhone 16 Pro (393 x 852), iPhone SE (375 x 667), Galaxy S24 (360 x 780), Pixel 8 (412 x 915).
- **Tablet**: iPad Pro 11" (834 x 1194), iPad Pro 12.9" (1024 x 1366).
- **Desktop / Web**: MacBook Pro 14" (1512 x 982), Desktop 1440p (1440 x 900), Full HD (1920 x 1080).
- **Presentation**: Slide 16:9 (1920 x 1080), Slide 4:3 (1024 x 768).
- **Social Media**: Instagram Post (1080 x 1080), Instagram Story (1080 x 1920), Dribbble Shot (1600 x 1200), Twitter Header (1500 x 500).
- **Paper**: A4 (595 x 842), US Letter (612 x 792).

Includes helper functions for:
- Orientations switch (portrait <-> landscape swap).
- Dialog widget (`FramePresetDialog`) to spawn or re-apply presets.

---

## 4. Layout Engine & Canvas Painter

### 4.1 Auto-Layout Calculation (`lib/features/canvas/utils/auto_layout_engine.dart`)
- Helper function `applyAutoLayout(CanvasNode frameNode, List<CanvasNode> children) -> List<CanvasNode>`
- Automatically recalculates child positions (x, y) and frame dimensions based on padding, spacing, layout direction, and align.
- Supports Auto-Layout reflow when nodes are added, reordered, or edited inside an auto-layout enabled frame.

### 4.2 Rendering & True Clip Content (`NodePainter` & `CanvasPainter`)
- `_paintFrame`:
  - Paints drop shadow if enabled.
  - Draws filled rectangle / rounded rectangle with corner radius and solid or gradient fill.
  - Draws frame stroke / border (solid or dashed).
  - Renders top-left frame label tag outside bounds.
- Canvas clip during multi-layer paint:
  - When iterating over children inside a frame where `clipContent == true`, apply `canvas.save()`, `canvas.clipRRect(...)`, paint children, `canvas.restore()`.

---

## 5. UI / UX Integration

### 5.1 Inspector Panel (`lib/features/canvas/presentation/widgets/inspector_panel.dart`)
When a `NodeType.frame` is selected:
1. **Frame Presets & Orientation**: Dropdown of presets + quick Portrait/Landscape toggle button.
2. **Styling Controls**:
   - Background Color & Gradient End Color.
   - Corner Radius slider/input.
   - Border Color, Stroke Width, and Border Style (Solid/Dashed).
   - Shadow toggle and blur.
   - Clip Content checkbox toggle.
3. **Auto-Layout Section**:
   - Direction toggle: `None` | `Row (H)` | `Column (V)`.
   - Spacing / Gap input.
   - Padding inputs (all / individual).
   - Alignment buttons (Start, Center, End, Space Between).
4. **Quick Export Frame Section**:
   - Buttons: `Export PNG (1x, 2x, 3x)`, `Export SVG`, `Export PDF (Single Slide)`.

### 5.2 Toolbar & Creation Workflow
- Selecting `Frame Container (F)` tool displays preset picker or allows click-to-preset & drag-to-draw.
- Context menu: "Change Frame Preset", "Export Frame...".

---

## 6. Verification Plan
1. Unit tests for `FramePayload` serialization / deserialization with all new properties.
2. Unit tests for `AutoLayoutEngine` (horizontal, vertical, padding, spacing).
3. Integration test for quick export per frame (PNG/SVG/PDF single frame generation).
4. Flutter widget / analyzer verification (`flutter analyze` / `flutter test`).
