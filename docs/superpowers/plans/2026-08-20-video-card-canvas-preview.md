# Video Card Canvas Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve the canvas card preview without embedding a controller per node.

**Architecture:** Keep `CustomPainter` as the default renderer. Draw a persisted poster when available, otherwise show deterministic loading/error/static states. The existing tap opens the dedicated player.

**Tech Stack:** Flutter CustomPainter, existing node painter, existing VideoPayload.

**Spec:** `docs/superpowers/specs/2026-08-20-video-card-design.md`

## Global Constraints

- Do not create a `VideoPlayerController` for every canvas node.
- Preserve drag, selection, resize, context menu, lock, visibility, and inspector behavior.
- Keep the existing visual language.

### Task 1: Add preview state model

**Files:**
- Modify: `lib/domain/models/node_payload.dart`
- Test: `test/domain/models/node_payload_test.dart`

- [ ] Test poster source, preview status, and error serialization with old JSON defaults.
- [ ] Add the smallest durable fields needed by the painter.
- [ ] Keep runtime playback state out of persisted payload.
- [ ] Run focused model tests.

### Task 2: Render poster and fallback states

**Files:**
- Modify: `lib/features/canvas/presentation/painters/node_painter.dart`
- Test: `test/features/infinite_board_suite_test.dart` or a focused painter test

- [ ] Add painter tests for poster, loading, source error, and no-poster fallback.
- [ ] Render poster only when it is a valid local/remote image source already supported by the project; otherwise render deterministic placeholder state.
- [ ] Preserve title, duration, opacity, rotation, and card bounds.
- [ ] Run painter tests and analyzer.

### Task 3: Wire preview updates

**Files:**
- Modify: `lib/features/canvas/presentation/canvas_screen.dart`
- Modify: relevant Video Card state/controller file if one exists
- Test: focused canvas preview test

- [ ] Update the node payload after metadata/poster resolution without overwriting newer user edits.
- [ ] Keep preview failures local to the node and visible through the painter.
- [ ] Verify click opens player and drag still moves the node.
- [ ] Run focused canvas tests and the full existing canvas suite.
