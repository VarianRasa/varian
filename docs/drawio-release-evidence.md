# Native Diagram Library Release Evidence

## Scope

Diagrams now has a native, editable shape library with bounded Draw.io/mxGraph XML interoperability. Mermaid source remains a separate tool. The implementation does not embed the Draw.io editor and does not copy Draw.io stencil or icon assets.

## Native editor coverage

- Shape catalog spans basic, flowchart, UML, BPMN, network, database, people, container, notes, and arrow families.
- Palette supports search, category filtering, previews, accessible labels, and native shape selection.
- Known shapes render through the native catalog. Unknown or custom shape IDs use an editable rectangle fallback while retaining `diagramShapeId`, raw style, raw cell XML, and bounded custom attributes for export.
- Native creation supports click, canvas drag, and palette drag-and-drop paths. The canvas shows a drop-zone highlight and rejects drops in read-only mode. Existing canvas editing supplies selection, inline labels, resize, rotation, fill/stroke/gradient/dash/shadow styles, connectors, markers, waypoints, grouping, layers, duplication, and undo/redo.
- Draw.io export is available as an export preset and from the canvas export menu.

## XML interoperability

`DrawioXmlCodec` uses `package:xml` and supports bounded `mxGraphModel` documents containing:

- vertices, edges, labels, hierarchy, groups, and root-level layers;
- parent-relative geometry on export and restored absolute geometry on import;
- editable node and edge style values merged with retained unknown Draw.io style tokens;
- rotation, opacity, font properties, shadows, fills, strokes, dash styles, routing, markers, and waypoints;
- bounded raw non-reserved cell attributes for custom metadata preservation.

The codec reconstructs supported geometry rather than promising byte-for-byte XML reproduction. It does not preserve every original child element verbatim.

## Provenance and licensing

The native registry and codec do not vendor Draw.io editor source, JavaScript bundles, stencil files, or icon assets. They use the existing `xml` dependency and interoperate with documented `mxGraphModel`/Draw.io XML conventions and shape aliases. Any future bundled Draw.io assets or editor code must receive a separate upstream license and notice review before redistribution.

## Security boundaries

- XML input is limited to 2 MiB and 12,000 cells.
- Labels and styles are limited to 16 KiB each; waypoints use the existing bounded edge limit.
- Malformed XML, `DOCTYPE`, CDATA, scripts, external references, invalid numeric values, recursive hierarchies, and over-limit geometry are rejected before document mutation.
- No remote stencil, image, entity, or script reference is resolved.

## Validation results

- Focused diagrams, canvas, grouping, connector, import/export, and history regressions passed.
- Full Flutter suite passed: 710 tests, including palette drag-and-drop and click-only native creation regressions.
- Full `flutter analyze --no-pub` passed.
- `flutter build web --release --no-pub` passed.
- `flutter build windows --release --no-pub` passed.
- Browser smoke is blocked because Chrome DevTools MCP is not configured in the environment. No user browser profile was attached.
- Windows release startup/plugin smoke passed. The executable stayed responsive and loaded `flutter_windows.dll`, `file_selector_windows_plugin.dll`, `merman_plugin.dll`, `media_kit_video_plugin.dll`, `url_launcher_windows_plugin.dll`, and `window_manager_plugin.dll`.
- Windows UI smoke reached the editor, opened the native palette, selected Hexagon, created and labeled a native shape, showed `Export Draw.io XML`, and then undid the smoke edits. The non-interactive runtime check had empty stderr; Orca-driven interaction emitted Flutter accessibility bridge warnings in stderr, so those harness warnings remain noted.

## Known limits

- Exact all-stencil Draw.io visual parity is not a goal of the native registry. Unknown shapes remain editable fallbacks with lossless bounded metadata.
- Export reconstructs geometry and selected metadata instead of reproducing all original XML child elements verbatim.
- Nested edge-parent semantics, full layer behavior, font alignment, detailed opacity/gradient parameters, curved routing, marker variants, rounded-corner parameters, and additional `mxgraph.*` aliases remain candidates for fixture-driven expansion.
