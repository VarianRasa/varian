# Native Chart Release Evidence

## Scope

Charts use the existing canvas document model. Each chart is one `CanvasNode` with a bounded `ChartPayload`; charts do not introduce a second editor model.

Supported chart families:

- line
- bar / column
- pie
- doughnut
- scatter
- radar

Chart data includes bounded categories, series, values, scatter points, colors, titles, legends, grid/axis/value visibility, curved lines, dots, bar orientation, and doughnut hole ratio.

## Rendering and editing

- `fl_chart ^1.2.0` renders interactive chart widgets for the six supported families.
- `ChartCanvasPainter` renders the same families on native Canvas surfaces used by export, minimap, and non-widget layers.
- The toolbar and chart palette support click selection and drag-and-drop creation.
- The inspector edits chart type, title, categories, series, colors, display toggles, orientation, and doughnut ratio.
- Existing selection, resize, duplicate, clipboard clone, undo/redo, and history paths remain canonical.

## Persistence and interoperability

- Native JSON and `CanvasDocument` persistence round-trip chart nodes.
- Draw.io export writes bounded chart JSON into the `data-varian-chart` cell attribute and uses a rectangle style for external Draw.io compatibility.
- Import restores chart semantics when that attribute survives the external round trip. Malformed or oversized metadata falls back to an editable rectangle.
- SVG export emits native chart geometry. Markdown and plain text retain chart data tables; the existing lightweight PDF writer retains chart cards and chart title/type labels. PNG uses the native Canvas painter.

## Provenance and licensing

The direct widget dependency is `fl_chart` 1.2.0 from pub.dev. Its bundled license is MIT, copyright Flutter 4 Fun (2022). No Syncfusion, web-only chart editor, or second canvas/editor dependency was added.

## Security boundaries

Chart labels, titles, series, colors, values, points, metadata, and imported numbers are bounded at the model or codec boundary. Non-finite values become safe finite defaults. Draw.io metadata is base64-decoded only within a fixed byte limit and is parsed as local JSON; no remote content is resolved.

## Validation results

- Focused chart model, widget, native painter, palette, creation, inspector, history, persistence, Draw.io, and export tests pass.
- Real `CanvasToolbar` chart-category creation and typed Forui chart selector interactions pass.
- Full Flutter suite passes: 727 tests.
- `flutter analyze --no-pub` passes with no issues.
- `flutter build web --release --no-pub` passes.
- `flutter build windows --release --no-pub` passes.
- `flutter pub deps --style=compact --no-dev` confirms `fl_chart 1.2.0` and `equatable 2.1.0` as the added chart dependency chain.
- Browser/interactive runtime smoke remains blocked because Chrome DevTools MCP is not configured in the environment.

## Known limits

Draw.io chart semantics require the custom metadata attribute to survive external editing. PDF follows the existing lightweight PDF writer policy rather than embedding the full SVG chart renderer. Exact pixel parity between `fl_chart`, native Canvas, SVG, and PDF is not a target; the data and chart family remain consistent across paths.
