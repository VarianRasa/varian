# Video Card Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Provide reliable, accessible playback controls for valid Video Card sources.

**Architecture:** `VideoPlayerScreen` owns one controller and all runtime state. A source resolver selects network/blob or native file playback without demo fallback. UI renders explicit loading, ready, and error states.

**Tech Stack:** Flutter, Dart, existing `video_player` dependency.

**Spec:** `docs/superpowers/specs/2026-08-20-video-card-design.md`

## Global Constraints

- No demo-video fallback.
- Autoplay is not required for correctness.
- Dispose controllers on route close.
- Unsupported codecs/platforms show actionable errors.
- Controls require accessible labels and disabled states.

### Task 1: Add source resolution and error classification

**Files:**
- Create: `lib/features/media/video_source_resolver.dart`
- Test: `test/features/media/video_source_resolver_test.dart`

- [ ] Test local, network, blob/data, empty, malformed, and unsupported sources.
- [ ] Implement a typed resolver used by the player to select the correct controller constructor.
- [ ] Return stable error categories for missing source, invalid source, unsupported platform, and initialization failure.
- [ ] Run focused tests.

### Task 2: Replace fallback initialization

**Files:**
- Modify: `lib/features/media/video_player_screen.dart`
- Test: `test/features/media/video_player_screen_test.dart`

- [ ] Add widget tests for loading, missing source, initialization error, and retry action.
- [ ] Initialize only from the resolver result; remove the Flutter demo URL fallback.
- [ ] Ensure `dispose` always disposes the controller and listeners.
- [ ] Keep captions and current/duration display.
- [ ] Run focused tests and analyzer.

### Task 3: Add playback controls

**Files:**
- Modify: `lib/features/media/video_player_screen.dart`
- Test: `test/features/media/video_player_screen_test.dart`

- [ ] Add widget tests for play/pause, seek, mute/volume, loop, and speed selection using a controllable test abstraction where the platform plugin cannot initialize in unit tests.
- [ ] Implement controls with semantic labels, disabled states, and current controller values.
- [ ] Add fullscreen route/layout behavior using Flutter platform-independent UI; preserve orientation/platform guards.
- [ ] Prevent autoplay assumptions and ensure controls remain usable after errors.
- [ ] Run focused tests, analyzer, and existing media tests.

### Task 4: Handle runtime failures

**Files:**
- Modify: `lib/features/media/video_player_screen.dart`
- Modify: `lib/features/media/video_source_resolver.dart`
- Test: `test/features/media/video_player_screen_test.dart`

- [ ] Test retry after failed initialization and a readable unsupported-source message.
- [ ] Map controller errors to concise user-facing messages without exposing secrets or full local paths.
- [ ] Preserve retry/loading/error state transitions without duplicate controllers.
- [ ] Run focused tests and `flutter analyze --no-pub`.
