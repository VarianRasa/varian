# Creative Canvas Studio — Product Requirements Document (PRD)

**Document Version:** 1.0
**Status:** Draft
**Product Type:** Cross-platform Creative Canvas Studio
**Target Platforms:** Windows, macOS, Linux, Web, Android, iOS/iPadOS
**Primary UI Stack:** Flutter
**Core/Performance Layer:** Rust
**Backend Foundation:** Supabase / PostgreSQL
**Last Updated:** 2026-08-15

---

## 1. Product Overview

Creative Canvas Studio adalah aplikasi creative workspace berbasis infinite canvas yang menggabungkan kemampuan:

- visual planning dan moodboarding ala Milanote,
- vector/interface design ala Figma,
- diagramming ala draw.io,
- raster drawing/painting ala ibisPaint dan Procreate,
- AI-assisted creation ala Gendo,
- collaborative whiteboard,
- local-first editing,
- project and asset management,
- export dan sharing lintas platform.

Aplikasi dirancang bukan sebagai kumpulan fitur yang terpisah, melainkan sebagai **canvas runtime** yang dapat menampung berbagai tipe node dan creative capability di dalam satu workspace.

---

## 2. Product Vision

> Menjadi creative operating system berbasis canvas yang memungkinkan pengguna berpikir, menggambar, mendesain, menyusun diagram, mengatur referensi, berkolaborasi, dan menggunakan AI dari satu workspace yang konsisten.

Creative Canvas Studio harus dapat berkembang dari aplikasi individual/offline menjadi platform kolaborasi kreatif multi-user tanpa membutuhkan rewrite arsitektur besar.

---

## 3. Product Goals

### 3.1 Primary Goals

1. Menyediakan infinite canvas yang cepat, responsif, dan lintas platform.
2. Menggabungkan beberapa workflow kreatif dalam satu document model.
3. Mendukung local-first editing dan autosave.
4. Menyediakan fondasi untuk real-time collaboration.
5. Menyediakan fondasi AI tools yang modular dan provider-agnostic.
6. Menjaga pengalaman pengguna konsisten di desktop, web, tablet, dan mobile.
7. Memiliki arsitektur yang mampu tumbuh dari MVP kecil ke aplikasi berskala besar.

### 3.2 Secondary Goals

- Mendukung plugin/capability baru tanpa mengubah canvas runtime secara besar.
- Mendukung versioning dokumen.
- Mendukung import/export berbagai format.
- Mendukung template dan reusable creative blocks.
- Mendukung multi-workspace dan team collaboration.

---

## 4. Non-Goals for Initial Release

Fitur berikut bukan target MVP pertama:

- full Figma-compatible editor,
- advanced vector boolean engine,
- full Photoshop/Procreate-grade raster engine,
- video editor,
- 3D editor,
- advanced animation timeline,
- marketplace plugin,
- enterprise SSO,
- organization billing,
- real-time multiplayer production-grade,
- offline conflict resolution tingkat lanjut,
- native PSD editing penuh,
- AI video generation.

---

## 5. Target Users

### 5.1 Primary Users

#### Creative Generalist
Pengguna yang sering berpindah antara:
- moodboard,
- note,
- wireframe,
- diagram,
- ide visual,
- drawing,
- AI generation.

#### UI/UX Designer
Membutuhkan:
- frame,
- text,
- shape,
- image,
- layout,
- reusable component,
- visual reference.

#### Student / Researcher
Membutuhkan:
- note,
- image,
- link,
- diagram,
- brainstorming,
- mind map,
- project board.

#### Illustrator / Concept Artist
Membutuhkan:
- raster layer,
- brush,
- reference board,
- AI image generation,
- image annotation.

#### Developer / System Designer
Membutuhkan:
- flowchart,
- UML-like diagram,
- architecture diagram,
- notes,
- code references.

### 5.2 Secondary Users

- product manager,
- content creator,
- game designer,
- architect,
- educator,
- startup team,
- creative agency.

---

## 6. Core Product Principles

### 6.1 Canvas First

Semua creative work terjadi di atas satu canvas runtime.

### 6.2 Local First

Edit harus tetap terasa cepat walaupun koneksi lambat atau tidak tersedia.

### 6.3 Modular Capability

Drawing, diagramming, AI, note, vector, dan media adalah capability yang dipasang di atas canvas runtime.

### 6.4 Non-Destructive Editing

Aksi pengguna sebisa mungkin dapat di-undo, redo, atau dikembalikan melalui version history.

### 6.5 Cross-Platform Consistency

Project yang dibuat di desktop harus dapat dibuka di web/mobile tanpa konversi manual.

### 6.6 Progressive Complexity

Pemula dapat memakai aplikasi secara sederhana, sedangkan power user mendapat fitur lebih dalam.

---

## 7. Product Architecture Concept

```text
Creative Canvas Studio
│
├── Canvas Runtime
│   ├── Camera / Viewport
│   ├── Pan / Zoom
│   ├── Selection
│   ├── Transform
│   ├── Snapping
│   ├── Layering
│   ├── Undo / Redo
│   └── Input System
│
├── Document Model
│   ├── Vector Nodes
│   ├── Raster Nodes
│   ├── Diagram Nodes
│   ├── Content Nodes
│   ├── AI Nodes
│   └── Container Nodes
│
├── Capabilities
│   ├── Notes / Moodboard
│   ├── Vector Design
│   ├── Diagramming
│   ├── Raster Painting
│   ├── AI Tools
│   └── Collaboration
│
├── Persistence
│   ├── Local SQLite / Drift
│   ├── Project Serialization
│   ├── Autosave
│   └── Cloud Sync
│
└── Backend
    ├── Authentication
    ├── PostgreSQL
    ├── Storage
    ├── Realtime
    ├── Collaboration
    └── AI Job System
```

---

## 8. Recommended Technology Stack

### 8.1 Client

- Flutter
- Dart
- Riverpod
- go_router
- Drift
- SQLite
- CustomPainter
- Flutter Canvas
- Impeller
- Fragment shaders where needed

### 8.2 Performance Core

- Rust
- FFI for desktop/mobile
- WASM-compatible core where practical for web

Potential responsibilities:
- geometry,
- serialization,
- CRDT,
- image processing,
- complex canvas operations,
- document validation,
- import/export.

### 8.3 Backend

- Rust API services
- Supabase PostgreSQL
- Supabase Auth
- Supabase Storage for MVP
- Supabase Realtime for presence/basic events
- Custom WebSocket collaboration service when needed

### 8.4 Later Infrastructure

- S3-compatible object storage
- Automerge or equivalent CRDT
- NATS JetStream
- Temporal
- Python AI workers
- pgvector

---

## 9. Core Domain Model

```text
User
└── Workspace
    ├── WorkspaceMember
    └── Project
        ├── Canvas
        │   ├── CanvasNode
        │   ├── CanvasEdge
        │   ├── Layer
        │   ├── Comment
        │   └── Snapshot
        │
        ├── Asset
        ├── ProjectVersion
        └── AIJob
```

---

## 10. Canvas Node Model

### 10.1 Base Node

```text
CanvasNode
- id
- canvasId
- type
- x
- y
- width
- height
- rotation
- opacity
- visible
- locked
- zIndex
- parentId
- metadata
- createdAt
- updatedAt
```

### 10.2 Initial Node Types

#### Content
- text,
- sticky note,
- image,
- link card,
- file card.

#### Shape
- rectangle,
- ellipse,
- line,
- arrow.

#### Container
- frame,
- group,
- board.

#### Diagram
- diagram shape,
- connector.

#### Future
- vector path,
- raster layer,
- AI generation,
- embedded web content,
- table,
- component,
- prototype hotspot.

---

## 11. Major Functional Areas

## 11.1 Infinite Canvas

### Requirements

- Infinite-style workspace.
- Smooth pan and zoom.
- Zoom to selection.
- Fit canvas.
- Multi-select.
- Drag selection.
- Node transform.
- Node resize.
- Node rotation.
- Layer ordering.
- Copy/paste.
- Duplicate.
- Delete.
- Lock/unlock.
- Group/ungroup.
- Undo/redo.
- Keyboard shortcuts.
- Mouse, touch, and stylus input abstraction.

### Performance Target

- 60 FPS target on supported modern hardware.
- Canvas remains usable with at least 1,000 lightweight nodes.
- Viewport culling required.
- Heavy node rendering should be lazy or cached.

---

## 11.2 Notes and Moodboard

Initial functionality:

- sticky notes,
- rich/plain text,
- image placement,
- links,
- image captions,
- simple board/frame grouping,
- drag-and-drop assets.

Future:

- web clipping,
- video embeds,
- PDF cards,
- markdown blocks,
- checklist blocks,
- database-like cards.

---

## 11.3 Diagramming

Initial:

- rectangle,
- ellipse,
- diamond,
- line,
- arrow,
- connector,
- label,
- basic snapping.

Future:

- flowchart library,
- UML library,
- ERD,
- auto-routing,
- auto-layout,
- Mermaid import/export,
- PlantUML import,
- architecture templates.

---

## 11.4 Vector Design

Future capability:

- pen tool,
- bezier path,
- fills/strokes,
- gradients,
- boolean operations,
- text styles,
- layout constraints,
- components,
- instances,
- design tokens.

---

## 11.5 Raster Painting

Future capability:

- raster layers,
- brush engine,
- pressure sensitivity,
- masks,
- eraser,
- blend modes,
- selection tools,
- transform,
- filters,
- tiled rendering.

Raster engine harus dipisahkan dari object/vector canvas engine.

---

## 11.6 AI Capability

AI harus diperlakukan sebagai modular tool system.

### Initial AI Tools

- text-to-image,
- image variation,
- background removal,
- image upscale,
- image description,
- summarize canvas notes,
- generate diagram from prompt.

### AI Job Lifecycle

```text
queued
→ processing
→ completed
→ failed
```

### AI Tool Registry

```text
AITool
- id
- name
- provider
- capability
- inputSchema
- outputSchema
- pricingMetadata
- enabled
```

Aplikasi tidak boleh bergantung langsung pada satu AI provider.

---

## 11.7 Asset Management

Supported asset categories:

- PNG,
- JPEG,
- WebP,
- SVG,
- PDF,
- video,
- audio,
- font,
- project export,
- AI output.

### Requirements

- metadata stored in PostgreSQL,
- binary stored in object storage,
- thumbnails generated asynchronously,
- content hash supported,
- project-level ownership,
- future deduplication support.

---

## 11.8 Project Management

User dapat:

- create project,
- rename project,
- duplicate project,
- delete/archive project,
- open recent project,
- pin project,
- view project thumbnail,
- organize project into workspace.

---

## 11.9 Autosave and Local Persistence

### Requirements

- local project state stored with Drift/SQLite,
- debounce-based autosave,
- crash-safe recovery,
- restore last session,
- dirty-state tracking,
- local version snapshot.

Future:
- offline cloud queue,
- merge after reconnect,
- conflict-safe collaboration.

---

## 11.10 Cloud Sync

Cloud sync is not required for the earliest prototype but is required for public MVP.

### Responsibilities

- project metadata,
- canvas snapshots,
- asset metadata,
- account settings,
- project ownership,
- synchronization status.

---

## 11.11 Collaboration

### Phase 1

- project sharing,
- read-only link,
- comment support.

### Phase 2

- presence,
- shared cursors,
- selected-node awareness.

### Phase 3

- real-time editing,
- CRDT document sync,
- offline conflict merge.

---

## 12. User Experience Structure

Desktop layout recommendation:

```text
┌──────────────────────────────────────────────────────────────┐
│ Top Bar                                                     │
├──────────────┬──────────────────────────────┬────────────────┤
│ Left Toolbar │                              │ Right Panel    │
│              │        Infinite Canvas       │                │
│ Tools        │                              │ Properties     │
│ Assets       │                              │ Layers         │
│ Components   │                              │ AI             │
│              │                              │ Inspector      │
├──────────────┴──────────────────────────────┴────────────────┤
│ Status / Zoom / Sync                                        │
└──────────────────────────────────────────────────────────────┘
```

### Desktop Priorities

- keyboard shortcuts,
- mouse precision,
- dockable inspector,
- multi-panel workflow.

### Tablet Priorities

- stylus input,
- radial/floating controls,
- gesture navigation,
- collapsible panels.

### Mobile Priorities

- viewer/editor hybrid,
- simplified editing,
- quick capture,
- sticky note,
- image upload,
- review/comment.

---

## 13. Navigation

Primary navigation:

```text
Home
├── Recent
├── Projects
├── Workspaces
├── Templates
└── Settings

Project
└── Canvas
    ├── Toolbar
    ├── Layers
    ├── Assets
    ├── Inspector
    └── AI
```

---

## 14. Authentication

MVP:

- email/password,
- session persistence,
- logout,
- password reset.

Later:

- Google,
- Apple,
- GitHub,
- passkeys,
- enterprise SSO.

---

## 15. Permissions

Future access roles:

```text
Owner
Editor
Commenter
Viewer
```

Project-level policies should be enforced in both:
- backend business logic,
- PostgreSQL/Supabase RLS where appropriate.

---

## 16. Database Baseline

Suggested MVP tables:

```text
profiles
workspaces
workspace_members
projects
canvases
canvas_snapshots
assets
project_members
comments
ai_jobs
```

Potential later tables:

```text
project_versions
templates
components
design_tokens
subscriptions
notifications
activity_logs
plugins
plugin_installations
```

---

## 17. Document Persistence Strategy

Do not store one database row per cursor movement.

Recommended approach:

### PostgreSQL

Store:
- project metadata,
- ownership,
- snapshot references,
- assets,
- users,
- comments.

### Local Database

Store:
- active document state,
- local operations,
- undo history metadata,
- unsynced changes.

### Object Storage

Store:
- images,
- videos,
- PDFs,
- large document snapshots,
- generated outputs.

### Collaboration Layer

Store/stream:
- CRDT operations,
- ephemeral presence,
- shared cursor events.

---

## 18. Undo / Redo

All mutable canvas commands should follow command-based history.

Example:

```text
AddNodeCommand
DeleteNodeCommand
MoveNodeCommand
ResizeNodeCommand
UpdateStyleCommand
GroupNodesCommand
```

Requirement:
- minimum 100 recent actions per active session for MVP where memory permits.

---

## 19. Performance Requirements

### Canvas

- smooth interaction under common workloads,
- viewport culling,
- avoid rebuilding entire widget tree on pointer movement,
- cache expensive rendered content,
- node-level invalidation where practical.

### Database

- local write should not block interaction,
- cloud sync must run asynchronously.

### Assets

- lazy loading,
- thumbnails before full-resolution assets,
- progressive loading where practical.

---

## 20. Reliability Requirements

- autosave enabled by default,
- crash recovery,
- corrupted project detection,
- validation before destructive project migration,
- failed upload retry support,
- failed AI job retry support.

---

## 21. Security Requirements

- secure authentication,
- short-lived signed asset URLs where needed,
- RLS for user-owned records,
- server-side authorization checks,
- no AI provider secret keys in Flutter client,
- no trusted business logic exclusively in client,
- upload MIME/type validation,
- file size limits,
- rate limiting on expensive endpoints.

---

## 22. Privacy Requirements

- private project by default,
- clear sharing state,
- ability to delete account data,
- explicit handling of uploaded assets,
- transparent AI provider usage when AI features are enabled.

---

## 23. Offline Requirements

MVP:
- project can open from local cache,
- canvas edits save locally,
- temporary offline state indicator.

Later:
- full offline creation,
- queued cloud sync,
- CRDT reconciliation.

---

## 24. Export Requirements

MVP:
- PNG export,
- project JSON/native format.

Later:
- SVG,
- PDF,
- JPEG,
- WebP,
- Mermaid,
- draw.io compatible export where feasible,
- layered project package.

---

## 25. Import Requirements

MVP:
- image import,
- project JSON/native import.

Later:
- SVG,
- PDF,
- Mermaid,
- draw.io,
- Figma-compatible partial imports where technically/legal appropriate,
- PSD partial import.

---

## 26. AI Architecture

```text
Flutter
  ↓
Backend API
  ↓
AI Job
  ↓
Queue
  ↓
Python Worker
  ↓
Provider Adapter
  ↓
AI Provider
  ↓
Object Storage
  ↓
Job Completed Event
  ↓
Flutter
```

Potential provider adapters:

```text
ImageProvider
LLMProvider
EmbeddingProvider
UpscaleProvider
BackgroundRemovalProvider
```

---

## 27. Collaboration Architecture

```text
Client A
   │
Client B
   ├── WebSocket Collaboration Service
Client C
   │
   ↓
CRDT Document
   ↓
Snapshot Service
   ↓
PostgreSQL/Object Storage
```

Ephemeral data:
- cursor,
- viewport,
- selected node,
- online status.

Persistent data:
- node creation,
- node deletion,
- content edit,
- transform,
- style changes.

---

## 28. Product Analytics

Not required for earliest internal MVP.

Later events:

```text
project_created
project_opened
node_created
asset_uploaded
export_completed
ai_job_started
ai_job_completed
collaboration_session_started
```

Analytics must not interfere with canvas rendering.

---

## 29. Monetization Possibilities

Not part of MVP implementation, but architecture should allow:

### Free

- local projects,
- limited cloud storage,
- basic canvas tools.

### Pro

- more cloud storage,
- advanced export,
- AI credits,
- version history,
- advanced drawing/vector tools.

### Team

- shared workspace,
- permissions,
- team asset library,
- collaborative editing.

---

## 30. Plugin Architecture — Future

Potential capability contract:

```text
CanvasCapability
- registerNodeTypes()
- registerTools()
- registerInspectorPanels()
- registerCommands()
- registerShortcuts()
- registerImporters()
- registerExporters()
```

Potential plugins:

- UML,
- mind map,
- pixel art,
- presentation,
- storyboard,
- architecture,
- game design,
- AI image toolkit.

---

## 31. Development Principles

1. Build canvas runtime before advanced features.
2. Profile before moving code to Rust.
3. Keep domain model independent from Flutter widgets.
4. Separate local persistence from cloud persistence.
5. Separate raster engine from vector/object engine.
6. Treat AI as asynchronous jobs.
7. Keep backend modular, but avoid premature microservices.
8. Do not introduce NATS/Temporal before operational need exists.
9. Maintain testable serialization format.
10. Keep project file format versioned from day one.

---

## 32. Suggested Repository Structure

```text
creative_canvas_studio/
│
├── apps/
│   └── studio_flutter/
│
├── crates/
│   ├── creative_core/
│   ├── creative_geometry/
│   ├── creative_document/
│   └── creative_sync/
│
├── services/
│   ├── api/
│   └── ai_worker/
│
├── packages/
│   ├── canvas_runtime/
│   ├── document_model/
│   ├── editor_commands/
│   ├── local_storage/
│   └── design_system/
│
├── infra/
│   ├── supabase/
│   └── docker/
│
└── docs/
    ├── PRD.md
    ├── MVP.md
    └── architecture/
```

---

## 33. Product Milestones

### Milestone 0 — Technical Prototype
- infinite canvas,
- pan/zoom,
- shape rendering,
- selection,
- drag.

### Milestone 1 — Local Editor
- project system,
- notes,
- text,
- images,
- layers,
- undo/redo,
- autosave.

### Milestone 2 — Public MVP
- authentication,
- Supabase project sync,
- asset upload,
- export,
- basic sharing.

### Milestone 3 — Diagram Studio
- connectors,
- diagram shapes,
- snapping,
- flowchart templates.

### Milestone 4 — AI Studio
- AI panel,
- asynchronous generation,
- image result inserted into canvas.

### Milestone 5 — Collaboration
- presence,
- cursor,
- comments,
- multiplayer editing.

### Milestone 6 — Advanced Creative Engine
- vector path editing,
- raster painting,
- components,
- design system capability.

---

## 34. MVP Success Criteria

MVP dianggap berhasil apabila pengguna dapat:

1. membuat akun,
2. membuat project,
3. membuka infinite canvas,
4. menambahkan text/note/shape/image,
5. memindahkan dan mengubah ukuran object,
6. melakukan undo/redo,
7. menutup aplikasi tanpa kehilangan project,
8. membuka project kembali,
9. menyimpan project ke cloud,
10. membuka project yang sama di platform lain,
11. mengekspor canvas ke PNG,
12. menggunakan aplikasi tanpa lag berat untuk canvas ukuran normal.

---

## 35. Long-Term Differentiator

Pembeda utama Creative Canvas Studio bukan sekadar jumlah fitur.

Pembeda yang dituju adalah:

> Semua creative capabilities hidup di atas satu shared canvas, satu shared document model, satu asset system, dan satu AI context.

Contoh future workflow:

```text
Moodboard
   ↓
AI concept generation
   ↓
Vector UI layout
   ↓
Flow diagram
   ↓
Raster annotation
   ↓
Prototype
   ↓
Export/share
```

Semua dilakukan tanpa pindah aplikasi.

---

## 36. Product Statement

**Creative Canvas Studio adalah cross-platform, local-first, modular creative workspace yang menyatukan ide, visual design, diagram, drawing, assets, collaboration, dan AI dalam satu infinite canvas.**
