# OpenAI-Compatible Image-to-Video Design

## Goal

Replace the hosted Hugging Face image-to-video path with a user-configured OpenAI-compatible video provider. Windows, Web, and Android call the provider directly using the user's API credentials, display the downloaded MP4 on the canvas, and expose a download action.

The application does not run a local diffusion model, launch CUDA, or use a Supabase video proxy in this design.

## Scope

- Add a standard OpenAI-compatible `Videos API` adapter.
- Reuse the existing AI provider configuration by default, with optional video-specific base URL, API key, and model overrides.
- Support image-to-video only in this iteration.
- Preserve the existing `AIService` create/poll job flow at its Flutter boundary.
- Download completed video content into a platform-appropriate artifact.
- Materialize the artifact as a video canvas node.
- Add a video-card download action.
- Keep deterministic FFmpeg pan/zoom as a separate fallback mode only where a platform runtime is available; it is not part of the provider adapter.
- Remove Hugging Face/Gradio from the active image-to-video path.

## Decision

Use direct client-to-provider calls with a standard asynchronous video contract:

1. `POST {baseUrl}/videos` creates a job.
2. `GET {baseUrl}/videos/{id}` polls the job.
3. `GET {baseUrl}/videos/{id}/content` downloads the completed MP4.

The client must not automatically retry a failed request with another endpoint shape. A provider that advertises OpenAI compatibility but does not implement this video contract receives a clear unsupported-provider error instead of risking duplicate paid requests.

The existing Supabase Edge Function and `ai_video_jobs` table are not used for this provider path. They remain unrelated infrastructure until explicitly removed in a later cleanup.

## Provider Configuration

Extend `BackendConfig` with:

- `videoApiBaseUrl`: optional; empty means `openAiBaseUrl`.
- `videoApiKey`: optional; empty means `openAiApiKey`.
- `videoModel`: required for API mode; no hard-coded provider-specific default.
- `videoProviderMode`: `openAiVideos` or `ffmpeg`.

Existing text and image configuration remains compatible. The video override allows a user to use a separate provider without changing the text/image provider.

The settings UI adds a Video Generation section containing:

- Provider mode.
- Video API key.
- Video API base URL.
- Video model identifier.
- Test Video API action.

An empty video key or base URL falls back to the existing general AI key or base URL. The UI must make that fallback explicit.

## Secret Handling

- Windows and Android store API keys in platform secure storage.
- Web keeps entered video credentials in memory for the current session only.
- API keys are never written to Web `localStorage`, Supabase, canvas JSON, job history, logs, error messages, or generated node metadata.
- Native secure-storage migration removes the existing provider key from `SharedPreferences` after a successful read/write migration.
- Provider requests use `Authorization: Bearer <key>` over HTTPS. HTTP is allowed only for explicit local development endpoints.
- Error messages expose status and a safe provider message, never request headers, API keys, or full response bodies.

Web API keys are visible to the browser session and network stack by design. The settings UI must warn that a same-origin authenticated proxy is required when the key must remain server-side.

## Request Contract

The adapter converts the selected image source to validated bytes before submission. It does not send arbitrary user-provided image URLs to a provider unless the provider-specific adapter explicitly requires it.

Default create request:

```http
POST {baseUrl}/videos
Authorization: Bearer {apiKey}
Content-Type: multipart/form-data
```

Multipart fields:

- `model`: configured video model.
- `prompt`: user prompt, required by the provider contract.
- `input_reference`: selected image file.
- `seconds`: supported value derived from the current video settings.
- `size`: supported value derived from the current aspect ratio and low-resolution default.

The adapter validates image MIME type, byte size, model name, prompt length, duration, and aspect ratio before sending. It sends one image and one generation request per user action.

Create response fields:

```json
{
  "id": "video_job_id",
  "status": "queued"
}
```

The parser accepts the standard terminal status vocabulary `queued`, `in_progress`, `completed`, `failed`, and `canceled`. Unknown statuses are failures, not indefinite pending states.

Poll request:

```http
GET {baseUrl}/videos/{id}
Authorization: Bearer {apiKey}
```

Completed content request:

```http
GET {baseUrl}/videos/{id}/content
Authorization: Bearer {apiKey}
Accept: video/mp4
```

The content response must be a bounded MP4 or a provider response containing a validated HTTPS content URL. If a URL is returned, the client downloads it with the same authorization policy only when the provider contract documents that behavior; credentials must not be appended to the URL.

## Job Lifecycle

`AIService` keeps the existing `create` and `poll` invoker boundary so UI and job history remain stable. The new invoker owns provider HTTP details and content download.

- Network request timeout: 30 seconds per request.
- Poll interval: 2 seconds.
- Maximum polling window: 5 minutes.
- Terminal success requires a valid downloaded MP4 artifact.
- Terminal failure returns a safe normalized error.
- Timeout returns a distinct timeout error and stops polling.
- A provider queue is surfaced to the user as provider progress; the client never polls indefinitely.
- No automatic duplicate create after timeout. The user explicitly starts a new job if needed.

## Artifact and Canvas Integration

`VideoPayload` already supports `videoUrl` and `videoPath`. The adapter produces:

- Windows: an app-cache MP4 path.
- Android: an app-cache MP4 path.
- Web: an in-memory object URL or provider HTTPS URL that remains valid for the current session.

The generated node uses the existing `videoCard` type and stores no API key. Native canvas persistence may retain a local path only as a device-local reference; cloud synchronization must not treat that path as a portable asset.

The canvas displays the artifact immediately after successful generation. If the artifact is no longer available, the node shows its existing source-error state instead of crashing.

## Download Action

Add a download action to the video-card/player surface:

- Windows and Android copy the cached MP4 to a user-selected destination using the existing file-picker capability.
- Web downloads the in-memory object URL or provider content through a browser download action.
- The filename is sanitized and uses an `.mp4` extension.
- Download failures are recoverable and do not remove the canvas node.
- Download does not expose the provider API key in a URL or filename.

## Error Semantics

Normalize provider errors into:

- `VIDEO_CONFIGURATION_ERROR`: missing or invalid base URL, key, or model.
- `VIDEO_UNSUPPORTED_PROVIDER`: endpoint or response shape is not supported.
- `VIDEO_SOURCE_ERROR`: selected image cannot be read or exceeds limits.
- `VIDEO_AUTH_ERROR`: provider rejected the credential.
- `VIDEO_RATE_LIMITED`: provider returned a rate limit.
- `VIDEO_GENERATION_FAILED`: provider reached a failed terminal state.
- `VIDEO_TIMEOUT`: polling exceeded the client deadline.
- `VIDEO_DOWNLOAD_ERROR`: completed content could not be downloaded or validated.

The UI shows a short message and retains the selected source and prompt for retry.

## Provider Test

`Test Video API` performs a non-generating capability check where possible:

1. Validate the configured base URL and model.
2. Request `GET /models` only if the provider exposes it.
3. If `/models` is unavailable, report that configuration validation passed but a generation request is required to verify video support.

The test must never create a paid video job.

## FFmpeg Fallback

FFmpeg is a separate deterministic fallback that creates a video from a still image using pan, zoom, crop, or fade. It is not presented as semantic AI animation and does not use the provider API key.

The fallback is enabled only when an approved platform runtime is available. It must not block the OpenAI-compatible adapter or require a bundled CUDA model. A future implementation may expose it as `videoProviderMode = ffmpeg`.

## Removed Active Path

The active image-to-video flow no longer depends on:

- Hugging Face Space URLs.
- Gradio event IDs or SSE parsing.
- Supabase anonymous authentication for video generation.
- `HF_VIDEO_SPACE_URL` or `ALLOWED_ORIGINS` for video requests.
- Hosted provider job ownership in `ai_video_jobs`.

Existing helper tests for Gradio remain only until the obsolete implementation is deleted; they must not constrain the new provider adapter.

## Testing

Add tests for:

- Video configuration fallback and normalization.
- Secure-key loading behavior on native and session-only behavior on Web.
- Multipart create request fields and image bytes.
- Create response parsing and request ID extraction.
- Poll status parsing for pending, success, failure, canceled, and unknown statuses.
- Per-request timeout and five-minute polling deadline.
- Provider auth, rate-limit, malformed-response, and unsupported-endpoint mapping.
- MP4 content-type, size, and byte validation.
- Native cache artifact and Web object-URL materialization through injected platform seams.
- Video node creation from a local artifact and recovery when the artifact is missing.
- Windows, Android, and Web download actions.
- Settings save, fallback display, and non-generating video connection test.
- Existing image-generation and text-generation behavior remains unchanged.

No live provider call belongs in the test suite. Use injected HTTP clients and deterministic fake responses.

## Non-goals

- Running LTX, CogVideoX, FramePack, CUDA, or Python locally.
- Proxying user credentials through Supabase.
- Automatically discovering arbitrary provider-specific video APIs.
- Supporting every custom provider response shape in the default adapter.
- Persisting provider keys in cloud data.
- Making a provider's paid API free.
- Sharing local cached video paths between devices.
