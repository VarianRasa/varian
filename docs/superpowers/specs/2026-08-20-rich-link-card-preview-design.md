# Design Spec: Rich Link Card Preview

## 1. Goal

Turn Link Card from a static bookmark into an editable rich web preview. A user creates an empty card, enters its URL directly on the selected card, and receives a persistent Open Graph preview containing a thumbnail, favicon, title, domain, and description.

## 2. User Experience

### 2.1 Creation and Inline Editing

Selecting the Link Card tool and clicking the canvas creates an empty `320 × 220` card. The selected card displays a URL prompt. Double-clicking the URL area enters inline edit mode.

- `Enter` validates and saves the URL.
- `Escape` cancels the edit and restores the previous value.
- Losing focus saves a valid changed value and otherwise keeps the editor open with validation feedback.
- Only one card URL editor is active at a time.

A valid changed URL immediately starts metadata retrieval. Existing cards remain readable and editable.

### 2.2 Canvas Preview

A populated card renders:

1. A large `og:image` thumbnail when available.
2. The site favicon, title, and hostname.
3. A short description when space permits.
4. A refresh action.
5. An external-browser action.

The layout responds to generic canvas resizing, with a Link Card minimum size that keeps controls usable. Small cards prioritize hostname and title; larger cards reveal thumbnail and description.

### 2.3 Opening Links

Double-clicking a populated card outside the URL editor or action buttons opens the URL in the existing in-app WebView. The external-browser button opens the same validated URL through `url_launcher` using `LaunchMode.externalApplication`.

## 3. Data Model

Extend `LinkPayload` with persisted preview metadata:

```dart
class LinkPayload extends NodePayload {
  final String title;
  final String url;
  final String? description;
  final String? faviconUrl;
  final String? imageUrl;
  final String? siteName;
  final DateTime? fetchedAt;
  final LinkPreviewStatus previewStatus;
  final String? previewError;
}
```

`LinkPreviewStatus` supports `idle`, `loading`, `ready`, and `error`. A `copyWith` method preserves unchanged fields during inline and Inspector edits.

JSON loading defaults missing fields for backward compatibility. Runtime loading states are persisted as `idle` so interrupted retrieval does not leave a document permanently loading. Metadata text and remote image URLs are stored in the document; image bytes are not copied into project storage.

## 4. Metadata Retrieval

Add one focused Link Preview service using the existing `http` dependency. No new package is required.

For a validated URL, the service:

1. Sends a bounded HTTP GET with an HTML-oriented `Accept` header and a short timeout.
2. Follows only a small number of redirects, validating every destination.
3. Rejects non-success responses, non-HTML content, and oversized bodies.
4. Parses `<title>`, Open Graph fields, Twitter image fallback, icon links, and canonical relative URLs.
5. Resolves relative metadata URLs against the final page URL.
6. Returns a plain immutable metadata result; it does not mutate providers.

Metadata precedence:

- Title: `og:title`, then `<title>`, then hostname.
- Description: `og:description`, then standard meta description.
- Image: `og:image`, then `twitter:image`.
- Site name: `og:site_name`, then hostname.
- Favicon: declared icon link, then `/favicon.ico` fallback.

Changing the URL clears stale preview metadata before retrieval. Refresh explicitly retrieves the current URL again. Concurrent requests are keyed by node and URL; stale responses are discarded when the card URL changes or a newer refresh starts.

## 5. URL and Network Safety

A shared URL policy is used by metadata retrieval, WebView opening, and external launch.

- Accept only absolute `http` and `https` URLs.
- Reject embedded username/password credentials.
- Reject empty or malformed hosts.
- Reject localhost, loopback, link-local, unspecified, multicast, and private IPv4/IPv6 destinations.
- Revalidate redirect destinations.
- Apply timeout, response-size, and redirect limits.
- Never execute fetched HTML or JavaScript during metadata parsing.

Hostname resolution and address checks happen before each native metadata request. If a hostname resolves to any prohibited destination, retrieval fails. Launching remains limited to valid HTTP(S) URLs; it does not accept custom schemes.

## 6. State and Data Flow

1. Canvas creates an empty `LinkPayload`.
2. Inline editor or Inspector submits a URL.
3. The URL policy normalizes and validates it.
4. The node is updated to the normalized URL, cleared metadata, and `loading` status.
5. The preview service retrieves and parses metadata.
6. The latest matching response updates the node to `ready` or `error` through `documentNodesProvider`.
7. Existing autosave persists the complete node after its normal debounce.
8. The canvas repaints from the persisted payload and remote image cache.

Automatic metadata completion creates one document update. Transient typing remains local to the editor until submission, avoiding an undo entry for every keystroke.

## 7. Rendering Architecture

The current synchronous `NodePainter` cannot own text input, buttons, loading state, or asynchronous network images. Link Cards therefore receive a dedicated positioned Flutter widget in the canvas node layer, while selection handles and transforms continue using the existing node system.

The widget owns only presentation and inline-edit state. Persisted data remains in `LinkPayload`; metadata retrieval remains in the service/controller. It uses the existing canvas image cache after that cache enforces timeout, content-type, and response-size limits for remote preview images.

Rendering states:

- `idle`: URL entry prompt or compact URL-only card.
- `loading`: stable skeleton layout without shifting node bounds.
- `ready`: rich preview with available metadata.
- `error`: URL and concise error with refresh action; opening the valid URL remains available.

Missing thumbnail or favicon is a valid ready state and uses deterministic visual fallbacks.

## 8. Inspector

The Link Card Inspector exposes:

- URL field with validation feedback.
- Editable title and description.
- Read-only hostname and preview status.
- Refresh Preview.
- Open in App.
- Open in Browser.

All edits use `LinkPayload.copyWith` so preview fields are preserved. URL submission follows the same normalization, clearing, fetch, and stale-response rules as inline editing.

## 9. Error Handling

- Invalid URLs remain editable and do not start network access.
- Retrieval failure changes only preview status and error text; the valid URL remains usable.
- Missing metadata produces hostname-based fallback content, not an error.
- Failed thumbnail or favicon downloads fall back visually without changing metadata status.
- WebView or external launch failure surfaces a non-blocking message.
- Deleted nodes and stale requests cannot be recreated by late responses.
- Existing malformed Link Card payloads render a safe empty state instead of throwing.

## 10. Testing

### Unit Tests

- `LinkPayload` JSON round-trip, backward-compatible loading, clone, and `copyWith` preservation.
- URL normalization and rejection of malformed, credentialed, local, private, and unsupported URLs.
- Redirect destination validation.
- Open Graph parsing, HTML fallback fields, relative URL resolution, and missing metadata fallback.
- Timeout, oversized response, non-HTML response, and stale-result handling.

### Widget Tests

- Empty card displays an inline URL prompt.
- Double-click enters editing; Enter saves; Escape cancels.
- Valid submission shows loading then ready preview.
- Invalid submission shows feedback and makes no request.
- Thumbnail, fallback, loading, and error states render without overflow at supported minimum sizes.
- Refresh, in-app WebView, and external-browser actions route correctly.
- Inspector edits preserve unrelated metadata.

### Integration and Manual Verification

Run `dart format`, `flutter analyze`, `flutter test`, and Windows debug/release builds. Manually verify creation, inline editing, resize, undo/redo, save/reopen, metadata refresh, offline/error behavior, in-app WebView, and external-browser opening against representative sites.

## 11. Non-Goals

- Full-page screenshots or browser-rendered thumbnails.
- Persisting remote image bytes for offline preview.
- Executing page scripts to discover metadata.
- Authentication, cookies, or previews of private pages.
- Periodic background refresh.
- Rich provider-specific embeds such as YouTube players or social posts.
