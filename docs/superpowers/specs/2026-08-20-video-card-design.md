# Video Card Feature Design

## Goal

Make Video Card reliable for local and remote videos across the existing canvas workflow, while preserving canvas performance by keeping the canvas representation lightweight and opening full playback in a dedicated player route.

## Scope

Implementation is staged:

1. Asset foundation: safe picker cancellation, source validation, metadata extraction where supported, explicit local/remote source handling, and useful error states.
2. Player: play/pause, seek, volume, mute, loop, playback speed, fullscreen, captions, retry, and source errors without demo-video fallback.
3. Canvas preview: poster/thumbnail when available, loading/error states, and preserved static rendering for nodes that are not actively opened.
4. Upload/platform hardening: upload progress, retry/cancel where the existing asset service supports it, remote URL persistence, and platform verification/fallbacks.

Trim, transcoding, subtitle-track editing, and live playback for every canvas node are out of scope. New dependencies are added only when existing Flutter and project dependencies cannot provide the required capability.

## Architecture

`VideoPayload` remains the persisted boundary for Video Card data. It will distinguish source URL/path and store durable metadata needed for display and playback. Runtime controller state remains in the player screen/controller and is not persisted as playback state unless explicitly represented as a user preference.

The canvas continues to use `CustomPainter` for the default card. It may draw a stored or generated poster image, but it will not keep a `VideoPlayerController` for every node. A node tap opens `VideoPlayerScreen`, which owns controller creation, lifecycle, controls, and error handling.

Asset selection continues through `AssetService`. The creation flow must not create a node when selection is cancelled or when no usable source is returned. Local files use native file playback; web requires a URL/blob source; remote sources use validated network URLs.

## Data and validation

- Preserve title, caption, local path, remote URL, duration display, and playback preferences needed by the UI.
- Add machine-readable duration and media dimensions only where the available platform API can provide them safely; retain display fallbacks for unavailable metadata.
- Validate supported source schemes and reject empty, malformed, inaccessible, or unsupported sources with user-visible errors.
- Do not substitute a demo video when a source is missing.
- Keep serialization backward-compatible with existing documents; missing new fields use safe defaults.
- Keep security checks for remote URLs and avoid logging sensitive local paths or credentials.

## Player behavior

The player initializes only from a valid source and shows loading, ready, and error states. It provides:

- play/pause;
- progress display and scrubbing;
- volume and mute;
- loop toggle;
- playback speed selection;
- fullscreen;
- caption display;
- retry after initialization or playback failure;
- accessible labels and disabled states while unavailable.

Autoplay must not be required for correctness, especially on web. Controller disposal is guaranteed when the route closes. Unsupported codecs and platform limitations produce actionable errors rather than uncaught exceptions.

## Canvas preview behavior

The card keeps the existing visual language and node interactions. It displays title, duration, and one of:

- poster/thumbnail;
- loading placeholder;
- source/error placeholder;
- existing static play preview when no poster exists.

Clicking the card opens the player. Dragging, selection, resize, context menu, inspector editing, z-order, visibility, locking, and persistence continue to use the existing canvas mechanisms.

## Upload and platform behavior

When the existing asset upload flow is active, Video Card stores the resulting remote URL separately from the local source and reports upload failure without silently creating an unusable node. Progress and cancellation are added only where the underlying API supports safe cancellation. Web uses remote/blob URLs and never attempts `VideoPlayerController.file`.

Android, iOS, macOS, Web, Windows, and Linux behavior must be verified against the actual registered video-player implementations. If a platform lacks a working implementation, the UI states that playback is unavailable on that platform while preserving metadata and export functionality; no unsupported dependency is introduced merely to mask the limitation.

## Testing

Add focused tests for:

- `VideoPayload` serialization and backward-compatible defaults;
- source validation and source selection;
- cancelled picker behavior;
- metadata formatting and fallback behavior;
- player loading, controls, retry, error, and disposal paths where testable;
- inspector updates;
- canvas preview states;
- export/import round-trip.

Run the relevant Video Card tests, the full test suite when practical, `flutter analyze --no-pub`, and available platform builds. Manual verification is required for real local playback, remote playback, fullscreen, and platform-specific codec behavior.

## Completion criteria

Video Card never creates an empty node after picker cancellation, never silently plays a demo source, persists valid local/remote source information, displays useful metadata or explicit fallbacks, provides the specified player controls and errors, preserves canvas performance and existing node actions, and passes automated checks without introducing unnecessary dependencies.
