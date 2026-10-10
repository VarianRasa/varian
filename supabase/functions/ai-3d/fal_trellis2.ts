import { Ai3DError, type JsonObject } from "./helpers.ts";

export const FAL_TRELLIS2_PROVIDER = "fal-trellis2";
export const DEFAULT_FAL_TRELLIS2_MODEL = "fal-ai/trellis-2";

const FAL_QUEUE_ORIGIN = "https://queue.fal.run";
const MODEL_PATTERN = /^fal-ai\/trellis-2$/;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,255}$/;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

export type FalTrellis2Input = {
  imageUrl: string;
  meshQuality: "draft" | "balanced" | "high";
  textureMode: "none" | "vertex_color" | "pbr";
  triangleBudget: number;
  seed: number;
};

export function falTrellis2Model(): string {
  const model = (Deno.env.get("FAL_3D_MODEL") ?? DEFAULT_FAL_TRELLIS2_MODEL).trim();
  if (!MODEL_PATTERN.test(model)) {
    throw new Ai3DError(500, "CONFIGURATION_ERROR", "FAL_3D_MODEL must be fal-ai/trellis-2.");
  }
  return model;
}

export function falTrellis2Configured(): boolean {
  return (Deno.env.get("FAL_KEY") ?? "").trim().length > 0;
}

export function buildFalTrellis2Payload(input: FalTrellis2Input): JsonObject {
  const resolution = input.meshQuality === "draft" ? 512 : input.meshQuality === "high" ? 1536 : 1024;
  const textureSize = input.textureMode === "none" ? 1024 : input.meshQuality === "high" ? 4096 : 2048;
  const decimationTarget = Math.max(5000, Math.min(2_000_000, Math.floor(input.triangleBudget)));
  return {
    image_url: input.imageUrl,
    seed: input.seed >= 0 ? input.seed : null,
    resolution,
    decimation_target: decimationTarget,
    texture_size: textureSize,
    remesh: true,
  };
}

export function falJobId(requestId: string): string {
  return `${FAL_TRELLIS2_PROVIDER}:${safeFalRequestId(requestId)}`;
}

export function falRequestId(jobId: string): string {
  const prefix = `${FAL_TRELLIS2_PROVIDER}:`;
  if (!jobId.startsWith(prefix)) {
    throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 job ID is invalid.");
  }
  return safeFalRequestId(jobId.slice(prefix.length));
}

export function falArtifactUrl(value: string): string {
  let url: URL;
  try {
    url = new URL(value);
  } catch (_) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Hosted TRELLIS.2 returned an invalid artifact URL.");
  }
  const hostname = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.hash ||
    (hostname !== "fal.media" && !hostname.endsWith(".fal.media")) ||
    !url.pathname.toLowerCase().endsWith(".glb")
  ) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Hosted TRELLIS.2 returned an untrusted artifact URL.");
  }
  return url.toString();
}

export async function createFalTrellis2Job(input: FalTrellis2Input): Promise<JsonObject> {
  const payload = await falJsonRequest(falQueueUrl(), {
    method: "POST",
    body: JSON.stringify(buildFalTrellis2Payload(input)),
  });
  const requestId = readRequestId(payload);
  return {
    jobId: falJobId(requestId),
    provider: FAL_TRELLIS2_PROVIDER,
    status: "queued",
    progress: 0,
  };
}

export async function pollFalTrellis2Job(jobId: string): Promise<JsonObject> {
  const requestId = falRequestId(jobId);
  const model = falTrellis2Model();
  const statusPayload = await falJsonRequest(
    `${FAL_QUEUE_ORIGIN}/${model}/requests/${encodeURIComponent(requestId)}/status`,
  );
  const status = normalizeFalStatus(statusPayload.status);
  if (status === "queued" || status === "processing") {
    return {
      jobId,
      provider: FAL_TRELLIS2_PROVIDER,
      status,
      progress: status === "queued" ? 5 : 60,
    };
  }
  if (status === "canceled") {
    return { jobId, provider: FAL_TRELLIS2_PROVIDER, status, progress: 0 };
  }
  if (status === "failed") {
    return {
      jobId,
      provider: FAL_TRELLIS2_PROVIDER,
      status,
      progress: 0,
      error: "Hosted TRELLIS.2 generation failed.",
    };
  }

  const result = await falJsonRequest(
    `${FAL_QUEUE_ORIGIN}/${model}/requests/${encodeURIComponent(requestId)}`,
  );
  const rawArtifact = isObject(result.model_glb) ? result.model_glb : null;
  const url = rawArtifact !== null && typeof rawArtifact.url === "string"
    ? falArtifactUrl(rawArtifact.url)
    : null;
  if (url === null) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Hosted TRELLIS.2 did not return a GLB artifact.");
  }
  return {
    jobId,
    provider: FAL_TRELLIS2_PROVIDER,
    status: "completed",
    progress: 100,
    artifact: {
      kind: "model3d",
      url,
      fileName: "generated-trellis2.glb",
      mimeType: "model/gltf-binary",
      provider: FAL_TRELLIS2_PROVIDER,
    },
  };
}

export async function cancelFalTrellis2Job(jobId: string): Promise<JsonObject> {
  const requestId = falRequestId(jobId);
  const model = falTrellis2Model();
  await falJsonRequest(
    `${FAL_QUEUE_ORIGIN}/${model}/requests/${encodeURIComponent(requestId)}/cancel`,
    { method: "PUT" },
    true,
  );
  return {
    jobId,
    provider: FAL_TRELLIS2_PROVIDER,
    status: "canceled",
    progress: 0,
  };
}

function falQueueUrl(): string {
  return `${FAL_QUEUE_ORIGIN}/${falTrellis2Model()}`;
}

async function falJsonRequest(url: string, init: RequestInit = {}, allowEmpty = false): Promise<JsonObject> {
  const key = (Deno.env.get("FAL_KEY") ?? "").trim();
  if (key.length === 0) {
    throw new Ai3DError(503, "CONFIGURATION_ERROR", "Hosted TRELLIS.2 is not configured.");
  }
  const headers = new Headers(init.headers);
  headers.set("Authorization", `Key ${key}`);
  headers.set("Accept", "application/json");
  if (init.body !== undefined) headers.set("Content-Type", "application/json");
  let response: Response;
  try {
    response = await fetch(url, { ...init, headers, redirect: "error" });
  } catch (_) {
    throw new Ai3DError(502, "UPSTREAM_ERROR", "Hosted TRELLIS.2 is unreachable.");
  }
  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_RESPONSE_BYTES) {
    throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 response is too large.");
  }
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new Ai3DError(
        502,
        "UPSTREAM_AUTH_ERROR",
        "Hosted TRELLIS.2 authorization was rejected; rotate FAL_KEY and verify account/model access.",
      );
    }
    if (response.status === 429) {
      throw new Ai3DError(
        429,
        "UPSTREAM_RATE_LIMITED",
        "Hosted TRELLIS.2 rate limit or quota was reached; try again later.",
      );
    }
    throw new Ai3DError(502, "UPSTREAM_ERROR", `Hosted TRELLIS.2 request failed (HTTP ${response.status}).`);
  }
  const text = await response.text();
  if (allowEmpty && text.trim().length === 0) return {};
  if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) {
    throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 response is too large.");
  }
  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch (_) {
    throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 returned invalid JSON.");
  }
  if (!isObject(payload)) {
    throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 returned an invalid response.");
  }
  return payload;
}

function readRequestId(payload: JsonObject): string {
  const value = payload.request_id ?? payload.requestId;
  if (typeof value !== "string") {
    throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 did not return a request ID.");
  }
  return safeFalRequestId(value);
}

function safeFalRequestId(value: string): string {
  const requestId = value.trim();
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 returned an invalid request ID.");
  }
  return requestId;
}

function normalizeFalStatus(value: unknown): "queued" | "processing" | "completed" | "failed" | "canceled" {
  switch (String(value ?? "").trim().toUpperCase()) {
    case "IN_QUEUE":
    case "QUEUED":
      return "queued";
    case "IN_PROGRESS":
    case "PROCESSING":
      return "processing";
    case "COMPLETED":
    case "DONE":
      return "completed";
    case "CANCELED":
    case "CANCELLED":
      return "canceled";
    case "FAILED":
    case "ERROR":
      return "failed";
    default:
      throw new Ai3DError(502, "INVALID_RESPONSE", "Hosted TRELLIS.2 returned an invalid job status.");
  }
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
