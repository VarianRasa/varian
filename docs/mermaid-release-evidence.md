# Mermaid Native Canvas Release Evidence

Verification date: 2026-09-06

This record covers the complete local Mermaid conversion path. Mermaid source remains the canonical representation. Native conversion creates detached canvas objects; native edits are not reverse-serialized into Mermaid source.

## Shipped scope

- Local Mermaid JS `11.17.2` rendering on Web.
- Local Merman FFI `0.7.0` rendering on native targets where the package is bundled.
- All 11 bundled Mermaid themes (`default`, `base`, `dark`, `forest`, `neutral`, `neo`, `neo-dark`, `redux`, `redux-dark`, `redux-color`, and `redux-dark-color`) forwarded through the correct Web and native configuration schemas.
- Bounded Mermaid source validation, diagnostics, render configuration, SVG sanitization, and CSS normalization.
- Source-preview mode plus detached native conversion for the semantic flowchart subset and sanitized SVG output from every renderer-supported family.
- Editable rectangles, ellipses, lines, paths, text, markers, gradients, transforms, nested viewports, and connector routes where renderer metadata or unambiguous geometry identifies endpoints.
- Atomic convert, regenerate, revert, delete, undo, and redo lifecycle behavior, including async duplicate and stale-request guards.
- Local persistence of canonical source, native ownership metadata, and bounded preview cache metadata.
- Canonical `.mmd` export that excludes detached native objects.

The durable renderer matrix covers `flowchart`, `sequence`, `class`, `state`, `er`, `journey`, `gantt`, `gitGraph`, `mindmap`, `timeline`, `pie`, `quadrant`, `requirement`, `xychart`, `sankey`, `block`, `architecture`, `packet`, `kanban`, `radar`, `treemap`, `zenuml`, `C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, and `C4Deployment`. C4 renderer icons are accepted only as bounded local PNG data images and become editable image nodes. Future renderer families use the same sanitized SVG boundary; unsupported or unsafe SVG returns a diagnostic without mutating the document.

## Dependency and artifact provenance

| Item | Evidence |
| --- | --- |
| Mermaid JS | `11.17.2` marker found in `assets/mermaid/mermaid.min.js` |
| Mermaid JS asset | 3,572,661 bytes; SHA-256 `581ED7D74BD9048D0E3A91363927D72EF22942D7722546B27F7CC29E35390EB8` |
| Web cache identity | `mermaid-js-11.17.2` |
| Merman package | `merman: 0.7.0` in `pubspec.yaml` and `pubspec.lock` |
| Native cache identity | `merman-0.7.0` |
| Merman package lock hash | `ab54a092df9d39f4f1ff03a7ce0144293cac3badd867d958855ac6479d318a72` |
| Windows Merman DLL | 13,544,448 bytes; SHA-256 `D34A41BF068B499AA6A8A346E9A548D5D98708D0FDB74F9A3558A2C01117670B` |
| Windows artifact match | Release `merman_ffi.dll` hash matches the cached `merman-0.7.0/windows/merman_ffi.dll` hash |
| Merman license | Package `LICENSE` contains Apache-2.0 and MIT license text; package README describes dual licensing |
| Upstream notices | Package README links to upstream Mermaid notices, but the cached package has no top-level `THIRD_PARTY_NOTICES.md`; complete notice reconciliation remains open |

The package README lists Android arm64-v8a/x86_64, iOS device/simulator, macOS, Windows, and Linux artifacts. Only the Windows runtime was exercised on this host. Artifact presence is not runtime parity proof.

## Automated verification

Verification status for the current tree:

- `flutter test --no-pub test/features/mermaid`: passed, including the 27-family durable SVG matrix and malformed numeric-geometry regression.
- `flutter test --no-pub test/features/canvas`: passed.
- `flutter test --no-pub test/features/nested_board`: passed.
- `flutter test --no-pub`: passed.
- `flutter analyze --no-pub`: passed with no issues.
- `flutter build web --release --no-pub`: passed.
- `flutter build windows --release --no-pub`: passed and produced `build/windows/x64/runner/Release/varian.exe`.
- `dart --packages=.dart_tool/package_config.json run tool/mermaid_theme_probe.dart`: passed; flowchart and sequence output applied all 11 native themes through `site_config.theme`.
- Mermaid lifecycle, Inspector, persistence, context-menu, canvas, nested-board, theme, and full-suite regressions passed after the final conversion changes.
- `git diff --check` passed; the theme-specific files were reviewed without unrelated source changes.
- Final repository-wide validation on 2026-09-06 passed: `flutter test --no-pub` completed with 691 tests, `flutter analyze --no-pub` completed with no issues, and both release builds completed successfully.
- Focused compound-vector, SVG projection, marker, alias, text, export, connector-history, and routing regressions passed after the final parity changes.

The regression test for malformed numeric SVG geometry was added before the existing unsafe-SVG test. It fails closed with `SVG_NUMBER_INVALID` and returns no native objects.

## Web smoke evidence

The isolated headed browser session `mermaid-flowchart-headed-5f3d9b7b` verified:

An isolated browser session `mermaid-release-d4f6f6f8cd26` exercised the rebuilt Web app: it loaded the project library, opened a new local document, inserted a Mermaid node, displayed the local preview, saved the source, and converted it to two native nodes and one native edge. The browser console had no errors or warnings. The network log returned the bundled Mermaid asset from `127.0.0.1` with HTTP 200 and no remote Mermaid request. Expected non-Mermaid Flutter asset requests remained visible.

The exact final Web artifact was load-checked in isolated session `mermaid-release-final-3`. It returned the bundled Mermaid asset with HTTP 200, and the console contained no errors or warnings.

A fresh isolated headless Chrome smoke on the 2026-09-06 Web artifact loaded the Flutter app at `http://127.0.0.1:8765/`, produced a `flutter-view`, and reported no browser error output. A separate local bundled-Mermaid probe rendered `flowchart`, `sequence`, `classDiagram`, and `erDiagram`; all four returned SVG output, with `SVG_COUNT=4` and an empty browser error log. Chrome DevTools MCP was not configured in this environment, so this evidence uses the isolated Chrome process rather than DevTools MCP.

A bundled-Mermaid browser probe on the rebuilt artifact rendered both a flowchart and a sequence diagram under all 11 themes. Every non-default theme produced style output different from the default theme; the console remained clean. The app adapter keeps this theme in the root Mermaid JS options object, while the native adapter places it under Merman `site_config.theme`.

1. `Diagrams` selected Mermaid directly. The category has one item, so no flyout is expected.
2. A Mermaid node was inserted on the canvas.
3. The source editor accepted a bounded flowchart and displayed a local preview:

   ```mermaid
   flowchart TD
     Start[Start] --> Check{Ready?}
     Check -->|Yes| Done[Done]
     Check -->|No| Retry[Retry]
   ```

4. Saving produced a local source node.
5. Conversion produced four native nodes and three native edges.
6. Editing the native `Start` node's X coordinate from `-16.5` to `50` changed the canvas position.
7. `Regenerate` restored the generated node's deterministic position.
8. `Revert to source` removed the detached native graph and restored the source-backed node.
9. Export Center saved `Untitled Doc-canvas.mmd`; its contents matched the canonical source above.
10. Reload returned to the project library, reopening the saved document restored the Mermaid source node, and the document remained `LOCAL SAVED`.

Observed local network evidence:

- `http://127.0.0.1:8765/assets/assets/mermaid/mermaid.min.js`: HTTP 200.
- No remote Mermaid script was requested.
- Existing non-Mermaid requests included the external Flutter ANGLE GL binding, Google CanvasKit, and Google-hosted fonts. Therefore this build must not be described as fully offline at the application level, even though Mermaid rendering itself uses the bundled local asset.
- After the final Web rebuild, a fresh isolated session loaded the app with no page errors observed and received the bundled Mermaid asset with HTTP 200.

Screenshots and the downloaded `.mmd` file are local smoke artifacts, not release inputs.

## Windows native smoke evidence

The final release executable at `build/windows/x64/runner/Release/varian.exe` was launched with its packaged `merman_ffi.dll`. The Windows app opened the task-owned `mermaid integration` document and visibly rendered the native Mermaid source preview as `Start` connected to `End`. Process module inspection confirmed `merman_ffi.dll` loaded from the release bundle after the preview rendered.

The UI action provider reported coordinate clicks as synthetic and unverified. The native render result itself was visually observed in the resulting screenshot, and no native runtime error was visible.

On 2026-09-06, `flutter run -d windows --release --no-pub` rebuilt and started the release app successfully. Process inspection observed `merman_plugin.dll` loaded from `build/windows/x64/runner/Release`; the smoke process was stopped after verification. The existing rendered-document evidence above remains the proof of an actual Mermaid conversion, while this run confirms the current release executable and plugin load path.

Available Flutter devices on this host were Windows, Chrome, and Edge. A Pixel 8 Pro Android emulator is configured but was not connected or launched. iOS, macOS, and Linux runtime targets were unavailable. Android, iOS, macOS, and Linux runtime parity therefore remains unverified.

## Bounds and security controls

- Source: 256 KiB, 4,000 lines, and 16 KiB per line.
- Cached/rendered SVG: 5 MiB.
- SVG elements: 20,000.
- CSS: 256 KiB, 2,048 rules, 512-byte selectors, 4,096-byte declarations, and 500,000 selector-match checks.
- Generated native objects: 2,000.
- Renderer-produced images are accepted only as local base64 PNG data and remain bounded by the SVG limit.
- Cached SVG requires matching source revision, render configuration hash, and renderer identity when the active adapter provides one.
- Web Mermaid operations are serialized because Mermaid configuration is global.
- Theme and `themeVariables` overrides remain bounded and allowlisted; native Merman receives them only inside `site_config`, and no remote renderer fallback is available.
- Browser degraded persistence removes Mermaid cached SVG and cache metadata when the 4 MiB document limit is exceeded.
- Renderer output is normalized and sanitized before Flutter display.
- The widget reports a ten-second render timeout. Native Merman calls are synchronous FFI calls, so the Dart `Future.timeout` cannot forcibly interrupt a call already executing on the UI isolate. This is documented behavior, not cancellation proof.

## Known limitations and follow-up

- Direct `.mmd` file-picker import is not implemented. Mermaid import is paste-based through the existing import dialog.
- `Export Mermaid` exports canonical source. The generic visual SVG exporter has no dedicated Mermaid renderer branch and is not a lossless Mermaid visual export.
- Native edits remain detached. They do not update Mermaid source.
- Renderer families outside the durable matrix are not hard-coded by the semantic parser. They use the sanitized SVG fallback when the active local renderer supports them; unsupported or unsafe SVG returns a diagnostic and leaves the document unchanged.
- Some renderer-produced connectors do not expose endpoint metadata. The converter keeps these as editable vector paths and emits an `EDGE_ENDPOINT_UNRESOLVED` warning when geometry is missing, distant, or ambiguous.
- The package notice, native artifact provenance, and authoritative dependency-audit reconciliation require a separate supply-chain review before a broad production release.
- The latest isolated browser axe audit reported one violation, the Flutter-generated `meta-viewport` `user-scalable=no` rule. Earlier audits also reported an unnamed Flutter canvas command (`aria-command-name`) and content outside landmarks (`region`), plus incomplete ARIA-attribute and color-contrast checks against Flutter semantics nodes. These findings are not Mermaid-specific and remain open.
- This work does not install ComfyUI, download models, or claim GPU generation support.
