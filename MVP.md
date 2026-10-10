# Creative Canvas Studio — Minimum Viable Product (MVP)

**Version:** 1.0
**Status:** Proposed MVP
**Target:** Functional cross-platform creative canvas
**Primary Stack:** Flutter + Drift/SQLite + Supabase
**Optional Performance Layer:** Rust
**Last Updated:** 2026-08-15

---

## 1. MVP Objective

Tujuan MVP adalah membuktikan bahwa pengguna dapat menggunakan satu aplikasi lintas platform untuk:

- membuat project,
- menaruh berbagai jenis content di infinite canvas,
- mengatur content secara visual,
- menyimpan project secara lokal,
- melakukan cloud sync,
- membuka project kembali,
- mengekspor hasil.

MVP **tidak** bertujuan langsung menyaingi Figma, Procreate, Milanote, draw.io, dan Gendo sekaligus.

MVP harus membuktikan fondasi canvas dan document model terlebih dahulu.

---

## 2. MVP Product Promise

> "Satu canvas untuk mencatat ide, menyusun referensi, menggambar struktur visual, menambahkan gambar, dan mengorganisasi project secara bebas."

---

## 3. MVP Scope

## 3.1 P0 — Must Have

### Account

- Sign up.
- Sign in.
- Sign out.
- Password reset.
- Session persistence.

### Home

- Recent projects.
- Create project.
- Rename project.
- Duplicate project.
- Delete/archive project.
- Project thumbnail.
- Last edited date.

### Canvas

- Infinite pan.
- Zoom.
- Fit view.
- Grid background.
- Selection.
- Multi-selection.
- Drag.
- Resize.
- Delete.
- Duplicate.
- Copy/paste.
- Layer ordering.
- Undo.
- Redo.

### Node Types

MVP node types:

1. Text
2. Sticky Note
3. Rectangle
4. Ellipse
5. Line
6. Arrow
7. Image
8. Frame

### Inspector

Selected node inspector:

- position,
- width,
- height,
- rotation,
- opacity,
- fill color,
- border color,
- border width,
- text size where applicable,
- lock/unlock.

### Layers

- list nodes,
- rename layer,
- toggle visibility,
- lock layer,
- reorder layer.

### Local Persistence

- Drift/SQLite.
- Autosave.
- Crash-safe project restoration.
- Reopen previous project.
- Local project cache.

### Cloud

- Supabase authentication.
- Project metadata sync.
- Canvas snapshot sync.
- Asset metadata.
- Image storage.

### Assets

- Import PNG/JPEG/WebP.
- Drag image into canvas.
- Basic thumbnail.
- Remove asset from project.

### Export

- Export visible canvas/frame to PNG.
- Export native project JSON.

### Basic Settings

- theme,
- autosave status,
- account,
- app version.

---

## 3.2 P1 — Should Have

- Snap to grid.
- Alignment guides.
- Group/ungroup.
- Zoom to selection.
- Keyboard shortcuts.
- Drag-and-drop from OS.
- Project search.
- Project pin/favorite.
- Link card.
- Simple connector.
- Basic comments.
- Read-only project sharing.
- Offline indicator.
- Sync status.

---

## 3.3 P2 — Could Have

- Basic AI image generation.
- Background removal.
- Diagram templates.
- Mind-map template.
- Public share link.
- Export SVG.
- Markdown note.
- PDF import preview.
- Simple component/reusable block.
- Shared cursor prototype.

---

## 4. Explicitly Out of MVP

The following should not delay MVP:

- full brush engine,
- pressure-sensitive painting,
- advanced vector paths,
- bezier editing,
- components/instances,
- auto-layout,
- advanced constraints,
- plugin marketplace,
- multiplayer CRDT editing,
- version-history browser,
- video editor,
- animation timeline,
- 3D,
- PSD import/export,
- AI agent capable of manipulating entire project,
- enterprise roles,
- payments/subscription.

---

## 5. MVP User Flow

```text
Launch App
   ↓
Authentication
   ↓
Home
   ↓
Create Project
   ↓
Open Canvas
   ↓
Add Content
   ├── Text
   ├── Note
   ├── Shape
   ├── Image
   └── Frame
   ↓
Move / Resize / Style
   ↓
Autosave
   ↓
Cloud Sync
   ↓
Export / Close
   ↓
Reopen Project
```

---

## 6. MVP Screens

### 6.1 Authentication Screen

Contains:
- logo,
- email,
- password,
- sign in,
- sign up,
- forgot password.

### 6.2 Home Screen

Contains:
- recent projects,
- create project,
- search,
- profile/settings.

### 6.3 Canvas Editor

```text
┌──────────────────────────────────────────────────────┐
│ App Bar / Project Name / Undo / Redo / Export       │
├─────────┬──────────────────────────────┬─────────────┤
│ Toolbar │                              │ Inspector   │
│         │        Infinite Canvas       │             │
│ Select  │                              │ Properties  │
│ Text    │                              │             │
│ Note    │                              │             │
│ Shape   │                              │             │
│ Image   │                              │             │
│ Frame   │                              │             │
├─────────┴──────────────────────────────┴─────────────┤
│ Zoom / Save status / Sync status                     │
└──────────────────────────────────────────────────────┘
```

### 6.4 Project Settings

- rename,
- duplicate,
- delete,
- cloud status.

### 6.5 App Settings

- theme,
- account,
- storage,
- diagnostics.

---

## 7. MVP Canvas Interaction Model

### Mouse

- left click: select,
- drag: move node,
- wheel: zoom or pan depending modifier,
- middle click / space + drag: pan,
- shift + click: multi-select.

### Keyboard

Suggested:

```text
Ctrl/Cmd + Z       Undo
Ctrl/Cmd + Shift+Z Redo
Ctrl/Cmd + C       Copy
Ctrl/Cmd + V       Paste
Ctrl/Cmd + D       Duplicate
Delete             Delete
Ctrl/Cmd + A       Select all
Ctrl/Cmd + S       Force save
Space + Drag       Pan
```

### Touch

- one finger: select/edit,
- two fingers: pan/zoom,
- long press: context menu.

---

## 8. MVP Document Model

```text
ProjectDocument
- schemaVersion
- projectId
- canvasId
- nodes[]
- viewport
- metadata
- updatedAt
```

### Node

```text
CanvasNode
- id
- type
- x
- y
- width
- height
- rotation
- zIndex
- visible
- locked
- style
- payload
```

---

## 9. MVP Node Payloads

### Text

```text
text
fontSize
fontWeight
textAlign
color
```

### Sticky Note

```text
text
backgroundColor
textColor
```

### Shape

```text
shapeType
fill
stroke
strokeWidth
```

### Image

```text
assetId
fit
crop
```

### Frame

```text
name
background
clipContent
```

---

## 10. MVP Flutter Architecture

Recommended feature-first structure:

```text
lib/
│
├── app/
│   ├── app.dart
│   ├── router.dart
│   └── theme/
│
├── core/
│   ├── errors/
│   ├── utils/
│   ├── ids/
│   └── logging/
│
├── features/
│   ├── auth/
│   ├── home/
│   ├── project/
│   ├── canvas/
│   ├── layers/
│   ├── inspector/
│   ├── assets/
│   ├── export/
│   └── settings/
│
├── domain/
│   ├── project/
│   ├── canvas/
│   └── asset/
│
├── data/
│   ├── local/
│   ├── remote/
│   └── repositories/
│
└── shared/
    ├── widgets/
    └── design_system/
```

---

## 11. MVP Canvas Package Structure

```text
packages/canvas_runtime/
│
├── lib/
│   ├── camera/
│   ├── controller/
│   ├── input/
│   ├── selection/
│   ├── transform/
│   ├── rendering/
│   ├── snapping/
│   └── commands/
│
└── test/
```

Keep canvas runtime independent from project/cloud features.

---

## 12. State Management

Recommended:

- Riverpod.

Suggested state separation:

```text
ProjectState
CanvasDocumentState
SelectionState
ViewportState
ToolState
HistoryState
SyncState
AssetState
```

Avoid putting the entire app state in one provider.

---

## 13. Local Database

Use:
- SQLite,
- Drift.

Suggested tables:

```text
local_projects
local_documents
local_assets
sync_queue
app_settings
```

### local_projects

```text
id
name
thumbnail_path
last_opened_at
created_at
updated_at
sync_state
```

### local_documents

```text
project_id
schema_version
document_json
updated_at
```

---

## 14. Supabase MVP Schema

### profiles

```text
id
display_name
avatar_url
created_at
```

### projects

```text
id
owner_id
name
thumbnail_url
created_at
updated_at
```

### canvases

```text
id
project_id
name
snapshot_path
created_at
updated_at
```

### assets

```text
id
project_id
owner_id
storage_path
mime_type
size_bytes
width
height
created_at
```

---

## 15. MVP Sync Strategy

Keep synchronization simple.

### Local Edit

```text
User Action
   ↓
Update Local State
   ↓
Write SQLite
   ↓
Mark Project Dirty
```

### Cloud Sync

```text
Dirty Project
   ↓
Serialize Snapshot
   ↓
Upload Snapshot
   ↓
Update Supabase Metadata
   ↓
Mark Synced
```

Do **not** implement per-operation CRDT sync in MVP.

Use snapshot-based sync first.

---

## 16. Conflict Strategy for MVP

MVP recommendation:

- single active editing session assumed,
- latest successful explicit sync wins,
- warn when remote project version is newer,
- create safety local backup before overwrite.

Future:
- CRDT-based merge.

---

## 17. Autosave

Recommended:

- local save after 500–1500 ms inactivity,
- immediate save after major operations where practical,
- periodic backup snapshot,
- force save when app backgrounds/closes.

Autosave must never block canvas interaction.

---

## 18. Undo/Redo

Implement command pattern.

```text
EditorCommand
├── execute()
├── undo()
└── mergeWith()
```

Initial commands:

```text
CreateNodeCommand
DeleteNodeCommand
MoveNodeCommand
ResizeNodeCommand
UpdateStyleCommand
UpdateTextCommand
ReorderNodeCommand
```

---

## 19. MVP Export

### PNG

Requirements:
- selected frame export,
- transparent background option,
- standard background option.

### Native JSON

Requirements:
- schemaVersion,
- project metadata,
- node data,
- asset references.

Example:

```json
{
  "schemaVersion": 1,
  "projectId": "project_123",
  "nodes": []
}
```

---

## 20. MVP File Format

Recommended extension later:

```text
.ccs
```

Possible package structure:

```text
project.ccs
├── manifest.json
├── document.json
├── assets/
└── thumbnail.png
```

For first MVP implementation, plain JSON + asset files is acceptable.

---

## 21. MVP Rust Usage

Rust is optional for initial milestone.

Do not move code into Rust until profiling proves it is needed.

Early Rust candidates:

- geometry calculations,
- hit-testing at high node counts,
- serialization,
- document validation,
- image transforms.

Flutter/Dart remains responsible for:
- UI,
- tool state,
- layout,
- application navigation.

---

## 22. MVP Performance Budget

Target:

- 60 FPS during normal canvas navigation,
- first project open under ~2 seconds for small local projects,
- 500–1,000 lightweight nodes usable without major input lag,
- image thumbnails used before full-resolution decoding,
- viewport culling enabled.

These are engineering goals rather than hard contractual SLAs.

---

## 23. MVP Error Handling

Required user-facing states:

- save failed,
- sync failed,
- image upload failed,
- unsupported file,
- project corrupted,
- authentication expired,
- offline mode,
- export failed.

Never silently discard user edits.

---

## 24. MVP Security

Required:

- Supabase Auth.
- Row Level Security.
- User can only access owned/shared projects.
- Storage path authorization.
- No backend/admin secrets in Flutter binary.
- File MIME validation.
- Upload size limitation.
- Server-side ownership checks.

---

## 25. MVP Testing Strategy

### Unit Tests

- document serialization,
- node transformations,
- command undo/redo,
- repository behavior,
- sync state logic.

### Widget Tests

- toolbar,
- inspector,
- layers panel,
- project cards.

### Integration Tests

- create project,
- add node,
- autosave,
- reopen project,
- export,
- login + cloud sync.

### Performance Tests

- 100 nodes,
- 500 nodes,
- 1,000 nodes,
- multiple images,
- repeated zoom/pan.

---

## 26. MVP Acceptance Criteria

### Authentication

- [ ] User can create an account.
- [ ] User can sign in.
- [ ] Session persists after restart.
- [ ] User can sign out.

### Projects

- [ ] User can create a project.
- [ ] User can rename a project.
- [ ] User can duplicate a project.
- [ ] User can delete/archive a project.
- [ ] Recent project list works.

### Canvas

- [ ] User can pan.
- [ ] User can zoom.
- [ ] User can select an object.
- [ ] User can multi-select.
- [ ] User can move an object.
- [ ] User can resize an object.
- [ ] User can delete an object.
- [ ] User can duplicate an object.

### Content

- [ ] User can create text.
- [ ] User can create sticky note.
- [ ] User can create rectangle.
- [ ] User can create ellipse.
- [ ] User can create line.
- [ ] User can create arrow.
- [ ] User can import image.
- [ ] User can create frame.

### Editing

- [ ] Undo works.
- [ ] Redo works.
- [ ] Layer order works.
- [ ] Inspector can modify core properties.

### Persistence

- [ ] Project autosaves locally.
- [ ] Project survives app restart.
- [ ] Project can sync to cloud.
- [ ] Cloud project can reopen on another supported client.

### Export

- [ ] PNG export works.
- [ ] Native JSON export works.

---

## 27. MVP Development Milestones

## Milestone 0 — Project Foundation

Deliverables:

- Flutter workspace.
- Riverpod.
- go_router.
- design system.
- testing setup.
- Drift database setup.

Exit criteria:
- application boots on desktop and web.

---

## Milestone 1 — Canvas Technical Prototype

Deliverables:

- canvas viewport,
- pan,
- zoom,
- camera,
- rectangle node,
- selection,
- drag.

Exit criteria:
- 500 rectangles can be navigated acceptably on development hardware.

---

## Milestone 2 — Editor Core

Deliverables:

- node model,
- text,
- note,
- shapes,
- image,
- frame,
- selection,
- transform,
- layers,
- inspector,
- command history.

Exit criteria:
- user can make a basic moodboard completely offline.

---

## Milestone 3 — Local Persistence

Deliverables:

- Drift repositories,
- autosave,
- project home,
- recent projects,
- reopen session.

Exit criteria:
- closing/restarting app does not lose project.

---

## Milestone 4 — Cloud Foundation

Deliverables:

- Supabase,
- auth,
- profiles,
- projects,
- snapshot sync,
- asset upload.

Exit criteria:
- authenticated user can sync a project.

---

## Milestone 5 — Export and Polish

Deliverables:

- PNG export,
- native JSON export,
- keyboard shortcuts,
- context menu,
- loading/error states,
- responsive desktop/tablet layout.

Exit criteria:
- application is usable for small real creative projects.

---

## Milestone 6 — MVP Release

Deliverables:

- Windows build,
- Web build,
- Android build,
- release notes,
- crash reporting optional,
- onboarding,
- example template.

Exit criteria:
- external testers can create, edit, save, reopen, and export projects.

---

## 28. Recommended MVP Platform Priority

Development order:

```text
1. Windows/Desktop
2. Web
3. Android Tablet
4. macOS
5. iPadOS
6. Linux
7. Mobile phone optimization
```

Reason:
Desktop provides the best environment for building and validating complex canvas interactions first.

---

## 29. MVP Design Priority

Focus on:

1. canvas responsiveness,
2. predictable selection,
3. reliable autosave,
4. clean toolbar,
5. readable inspector,
6. low visual clutter.

Do not spend early cycles on:
- heavy animation,
- complex branding,
- large template library,
- dozens of tools.

---

## 30. Suggested MVP Toolbar

```text
Select
Hand
Text
Note
Rectangle
Ellipse
Line
Arrow
Image
Frame
```

Later additions:

```text
Pen
Brush
Connector
Comment
AI
Component
Prototype
```

---

## 31. Suggested Definition of Done

A feature is done when:

- implementation works,
- empty/loading/error states exist,
- keyboard/touch impact reviewed,
- persistence behavior defined,
- undo/redo behavior defined,
- basic tests exist,
- no obvious canvas performance regression,
- serialization schema remains compatible.

---

## 32. Post-MVP Roadmap

### V0.2 — Diagram Studio

- connectors,
- diagram shape library,
- snapping,
- alignment,
- flowcharts.

### V0.3 — AI Studio

- AI sidebar,
- image generation,
- background removal,
- AI node type,
- asynchronous job state.

### V0.4 — Collaboration

- project sharing,
- comments,
- presence,
- shared cursors.

### V0.5 — Vector Studio

- pen tool,
- paths,
- advanced styles,
- components.

### V0.6 — Paint Studio

- raster layer,
- brush,
- pressure,
- mask,
- blend mode.

### V1.0

Target identity:

> A unified collaborative creative canvas for ideation, visual design, diagramming, drawing, and AI-assisted creation.

---

## 33. MVP Technical Stack Summary

```text
Frontend
- Flutter
- Dart
- Riverpod
- go_router

Canvas
- CustomPainter
- Canvas
- Impeller

Local
- Drift
- SQLite

Cloud
- Supabase Auth
- PostgreSQL
- Supabase Storage

Backend
- Start with Supabase + minimal custom API
- Add Rust backend as business logic grows

Performance
- Rust only when profiling proves necessary

AI
- Not required for core MVP
- Add Python workers after canvas foundation is stable
```

---

## 34. MVP Rule

**Jangan menambahkan fitur yang tidak membantu membuktikan canvas runtime, document model, persistence, atau basic cloud workflow sebelum MVP stabil.**

Jika ada pilihan antara:

```text
10 fitur setengah jadi
```

dan:

```text
4 fitur yang terasa sangat solid
```

pilih opsi kedua.

---

## 35. MVP Completion Statement

MVP selesai ketika seorang pengguna dapat membuka Creative Canvas Studio, membuat project baru, menyusun text/note/shape/image di infinite canvas, menutup aplikasi, membuka project kembali tanpa kehilangan data, menyinkronkan project ke cloud, dan mengekspor hasilnya.
