import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  buildGradioInput,
  type CreateInput,
  gradioApiUrl,
  GradioStreamError,
  isSupportedVideoCapability,
  type JsonObject,
  normalizeSpaceUrl,
  parseGradioEventStream,
} from "./helpers.ts";

const DEFAULT_SPACE_URL = "https://multimodalart-wan2-1-fast.hf.space";
const MAX_REQUEST_JSON_BYTES = 16 * 1024;
const MAX_SOURCE_BYTES = 8 * 1024 * 1024;
const MAX_REQUEST_BYTES = MAX_REQUEST_JSON_BYTES + MAX_SOURCE_BYTES;
const MAX_RESPONSE_BYTES = 256 * 1024;
const MAX_URL_CHARS = 2048;
const MAX_PROMPT_CHARS = 2000;
const MAX_OPTIONAL_TEXT_CHARS = 1000;
const SUBMIT_TIMEOUT_MS = 15_000;
const POLL_TIMEOUT_MS = 120_000;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 5;
const MAX_RATE_BUCKETS = 10_000;
const CORS_METHODS = "POST, OPTIONS";
const CORS_HEADERS =
  "Authorization, apikey, Content-Type, X-Client-Info, Accept";
const SAFE_SOURCE_URL_MESSAGE = "imageUrl must be a safe HTTPS URL.";

const REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/;
const IMAGE_DATA_PATTERN =
  /^data:image\/[A-Za-z0-9.+-]+;base64,([A-Za-z0-9+/]+={0,2})$/i;

type ErrorCode =
  | "VALIDATION_ERROR"
  | "UNAUTHORIZED"
  | "RATE_LIMITED"
  | "UPSTREAM_ERROR"
  | "NOT_FOUND"
  | "INVALID_RESPONSE";

type JobRecord = {
  request_id: string;
  model: string;
  owner_subject: string;
  status: string;
  progress: number | null;
  video_url: string | null;
};

type RateBucket = {
  startedAt: number;
  count: number;
};

const rateBuckets = new Map<string, RateBucket>();

class HttpError extends Error {
  readonly status: number;
  readonly code: ErrorCode;

  constructor(status: number, code: ErrorCode, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

Deno.serve(handleRequest);

async function handleRequest(request: Request): Promise<Response> {
  let corsOrigin: string | null = null;
  try {
    corsOrigin = resolveCorsOrigin(request.headers.get("origin"));
    if (request.method === "OPTIONS") {
      return jsonResponse(null, 204, corsOrigin);
    }
    if (request.method !== "POST") {
      throw new HttpError(
        405,
        "VALIDATION_ERROR",
        "Only POST requests are supported.",
      );
    }

    const token = readBearerToken(request);
    const supabase = createServiceClient();
    const ownerSubject = await authenticate(token, supabase);
    const body = await readJsonObject(request);
    const action = body.action;

    if (action === "create") {
      enforceCreateRateLimit(ownerSubject);
      return await createVideoJob(
        supabase,
        ownerSubject,
        await validateCreateInput(body),
        corsOrigin,
      );
    }
    if (action === "poll") {
      return await pollVideoJob(
        supabase,
        ownerSubject,
        validateRequestId(body.requestId),
        corsOrigin,
      );
    }

    throw new HttpError(
      400,
      "VALIDATION_ERROR",
      "Action must be create or poll.",
    );
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse(
        {
          error: { code: error.code, message: error.message },
        },
        error.status,
        corsOrigin,
      );
    }
    return jsonResponse(
      {
        error: {
          code: "UPSTREAM_ERROR",
          message: "Video service is unavailable.",
        },
      },
      500,
      corsOrigin,
    );
  }
}

function resolveCorsOrigin(originHeader: string | null): string | null {
  const origin = originHeader?.trim() ?? "";
  if (origin.length === 0) return null;
  const configured = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (origin === "*" || configured.includes("*")) {
    throw new HttpError(403, "VALIDATION_ERROR", "Origin is not allowed.");
  }
  if (!configured.includes(origin)) {
    throw new HttpError(403, "VALIDATION_ERROR", "Origin is not allowed.");
  }
  return origin;
}

function readBearerToken(request: Request): string {
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (match === null) {
    throw new HttpError(401, "UNAUTHORIZED", "Authentication is required.");
  }
  return match[1];
}

function createServiceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ??
    Deno.env.get("SUPABASE_SECRET_KEY")?.trim();
  if (
    url === undefined || url.length === 0 || serviceKey === undefined ||
    serviceKey.length === 0
  ) {
    throw new HttpError(
      500,
      "UPSTREAM_ERROR",
      "Video service is not configured.",
    );
  }
  return createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function authenticate(
  token: string,
  supabase: SupabaseClient,
): Promise<string> {
  try {
    const { data, error } = await supabase.auth.getUser(token);
    if (
      error !== null || data.user === null || data.user.id.trim().length === 0
    ) {
      throw new Error();
    }
    return data.user.id;
  } catch (_) {
    throw new HttpError(401, "UNAUTHORIZED", "Authentication is required.");
  }
}

async function readJsonObject(request: Request): Promise<JsonObject> {
  const contentLength = request.headers.get("content-length");
  if (contentLength !== null) {
    const length = Number(contentLength);
    if (Number.isFinite(length) && length > MAX_REQUEST_BYTES) {
      throw new HttpError(
        413,
        "VALIDATION_ERROR",
        "Request body is too large.",
      );
    }
  }

  const bytes = await readLimitedBytes(
    request.body,
    MAX_REQUEST_BYTES,
    new HttpError(413, "VALIDATION_ERROR", "Request body is too large."),
  );
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch (_) {
    throw new HttpError(
      400,
      "VALIDATION_ERROR",
      "Request body must be valid JSON.",
    );
  }
  if (!isJsonObject(parsed)) {
    throw new HttpError(
      400,
      "VALIDATION_ERROR",
      "Request body must be a JSON object.",
    );
  }
  return parsed;
}

async function readLimitedBytes(
  body: ReadableStream<Uint8Array> | null,
  maxBytes: number,
  exceededError: HttpError,
): Promise<Uint8Array> {
  if (body === null) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      total += result.value.byteLength;
      if (total > maxBytes) {
        await reader.cancel();
        throw exceededError;
      }
      chunks.push(result.value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

async function validateCreateInput(body: JsonObject): Promise<CreateInput> {
  const capability = requiredText(body.capability, "capability", 100);
  if (!isSupportedVideoCapability(capability)) {
    throw new HttpError(
      400,
      "VALIDATION_ERROR",
      "Capability is not supported.",
    );
  }

  const prompt = requiredText(body.prompt, "prompt", MAX_PROMPT_CHARS);
  const duration = body.duration;
  if (duration !== "5" && duration !== "10") {
    throw new HttpError(400, "VALIDATION_ERROR", "Duration must be 5 or 10.");
  }
  const aspectRatio = body.aspectRatio;
  if (
    aspectRatio !== "16:9" && aspectRatio !== "9:16" && aspectRatio !== "1:1"
  ) {
    throw new HttpError(
      400,
      "VALIDATION_ERROR",
      "Aspect ratio is not supported.",
    );
  }

  const imageData = optionalText(body.imageData, "imageData", MAX_SOURCE_BYTES);
  const imageUrl = optionalText(body.imageUrl, "imageUrl", MAX_URL_CHARS);
  if ((imageData === undefined) === (imageUrl === undefined)) {
    throw new HttpError(
      400,
      "VALIDATION_ERROR",
      "Provide exactly one image source.",
    );
  }

  const source = imageData === undefined
    ? await validateHttpsUrl(imageUrl as string)
    : validateImageData(imageData);
  const negativePrompt = optionalText(
    body.negativePrompt,
    "negativePrompt",
    MAX_OPTIONAL_TEXT_CHARS,
  );
  const cameraMotion = optionalText(
    body.cameraMotion,
    "cameraMotion",
    MAX_OPTIONAL_TEXT_CHARS,
  );

  return {
    capability,
    prompt,
    source,
    duration,
    aspectRatio,
    ...(negativePrompt === undefined ? {} : { negativePrompt }),
    ...(cameraMotion === undefined ? {} : { cameraMotion }),
  };
}

function requiredText(value: unknown, field: string, maxChars: number): string {
  if (typeof value !== "string") {
    throw new HttpError(400, "VALIDATION_ERROR", `${field} is required.`);
  }
  const text = value.trim();
  if (text.length === 0 || text.length > maxChars) {
    throw new HttpError(400, "VALIDATION_ERROR", `${field} is invalid.`);
  }
  return text;
}

function optionalText(
  value: unknown,
  field: string,
  maxChars: number,
): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new HttpError(400, "VALIDATION_ERROR", `${field} is invalid.`);
  }
  const text = value.trim();
  if (text.length === 0) return undefined;
  if (text.length > maxChars) {
    throw new HttpError(400, "VALIDATION_ERROR", `${field} is too long.`);
  }
  return text;
}

function validateImageData(value: string): string {
  if (new TextEncoder().encode(value).byteLength > MAX_SOURCE_BYTES) {
    throw new HttpError(413, "VALIDATION_ERROR", "Image data is too large.");
  }
  const match = IMAGE_DATA_PATTERN.exec(value);
  if (match === null || match[1].length % 4 === 1) {
    throw new HttpError(
      400,
      "VALIDATION_ERROR",
      "Image data must be a valid image data URI.",
    );
  }
  return value;
}

async function validateHttpsUrl(value: string): Promise<string> {
  if (value.length > MAX_URL_CHARS) {
    throw new HttpError(400, "VALIDATION_ERROR", SAFE_SOURCE_URL_MESSAGE);
  }
  let url: URL;
  try {
    url = new URL(value);
  } catch (_) {
    throw new HttpError(400, "VALIDATION_ERROR", SAFE_SOURCE_URL_MESSAGE);
  }
  const hostname = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (
    url.protocol !== "https:" || hostname.length === 0 || url.username ||
    url.password || isUnsafeHostname(hostname)
  ) {
    throw new HttpError(400, "VALIDATION_ERROR", SAFE_SOURCE_URL_MESSAGE);
  }

  if (parseIpv4(hostname) !== null || hostname.includes(":")) {
    if (isPrivateOrReservedIp(hostname)) {
      throw new HttpError(400, "VALIDATION_ERROR", SAFE_SOURCE_URL_MESSAGE);
    }
    return url.toString();
  }

  const addresses: string[] = [];
  let hasSuccessfulRecord = false;
  for (const recordType of ["A", "AAAA"] as const) {
    try {
      const records = await Deno.resolveDns(hostname, recordType);
      if (records.length > 0) hasSuccessfulRecord = true;
      addresses.push(...records);
    } catch (_) {
      continue;
    }
  }
  if (
    !hasSuccessfulRecord ||
    addresses.some((address) => isPrivateOrReservedIp(address))
  ) {
    throw new HttpError(400, "VALIDATION_ERROR", SAFE_SOURCE_URL_MESSAGE);
  }
  return url.toString();
}

function isUnsafeHostname(hostname: string): boolean {
  return hostname === "localhost" || hostname.endsWith(".localhost") ||
    hostname === "local" || hostname.endsWith(".local") ||
    hostname === "ip6-localhost";
}

function parseIpv4(value: string): number[] | null {
  const parts = value.split(".");
  if (parts.length !== 4) return null;
  if (!parts.every((part) => /^\d{1,3}$/.test(part))) return null;
  const octets = parts.map(Number);
  return octets.every((octet) => octet <= 255) ? octets : null;
}

function parseIpv6(value: string): bigint | null {
  if (value.includes("%")) return null;
  let normalized = value;
  if (normalized.includes(".")) {
    const separator = normalized.lastIndexOf(":");
    if (separator < 0) return null;
    const octets = parseIpv4(normalized.slice(separator + 1));
    if (octets === null) return null;
    const high = ((octets[0] << 8) | octets[1]).toString(16);
    const low = ((octets[2] << 8) | octets[3]).toString(16);
    normalized = `${normalized.slice(0, separator)}${high}:${low}`;
  }

  const halves = normalized.split("::");
  if (halves.length > 2) return null;
  const left = halves[0] === "" ? [] : halves[0].split(":");
  const right = halves.length === 2 && halves[1] !== ""
    ? halves[1].split(":")
    : [];
  const groups = [...left, ...right];
  if (!groups.every((group) => /^[0-9a-f]{1,4}$/i.test(group))) return null;
  const missing = 8 - groups.length;
  if (halves.length === 1 ? missing !== 0 : missing < 1) return null;
  const expanded = [
    ...left,
    ...Array.from({ length: missing }, () => "0"),
    ...right,
  ];
  return expanded.reduce(
    (result, group) => (result << 16n) | BigInt(parseInt(group, 16)),
    0n,
  );
}

function isPrivateOrReservedIp(value: string): boolean {
  const normalized = value.toLowerCase().replace(/^\[|\]$/g, "");
  const ipv4 = parseIpv4(normalized);
  if (ipv4 !== null) return isPrivateOrReservedIpv4(ipv4);
  const ipv6 = parseIpv6(normalized);
  if (ipv6 === null) return true;
  return isPrivateOrReservedIpv6(ipv6);
}

function isPrivateOrReservedIpv4([first, second, third]: number[]): boolean {
  return first === 0 || first === 10 || first === 127 ||
    (first === 100 && second >= 64 && second <= 127) ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 0) ||
    (first === 192 && second === 88 && third === 99) ||
    (first === 192 && second === 168) ||
    (first === 198 && (second === 18 || second === 19)) ||
    (first === 198 && second === 51 && third === 100) ||
    (first === 203 && second === 0 && third === 113) ||
    first >= 224;
}

const IPV6_BLOCKED_RANGES = [
  ["::", 128],
  ["::1", 128],
  ["::ffff:0:0", 96],
  ["100::", 64],
  ["2001::", 32],
  ["2001:1::", 32],
  ["2001:2::", 48],
  ["2001:10::", 28],
  ["2001:20::", 28],
  ["2001:db8::", 32],
  ["2002::", 16],
  ["3fff::", 20],
  ["5f00::", 16],
  ["64:ff9b::", 96],
  ["64:ff9b:1::", 48],
  ["fc00::", 7],
  ["fe80::", 10],
  ["fec0::", 10],
  ["ff00::", 8],
] as const;

function isPrivateOrReservedIpv6(value: bigint): boolean {
  const mappedIpv4 = (value >> 32n) === 0xffffn
    ? Number(value & 0xffffffffn)
    : null;
  if (mappedIpv4 !== null) {
    return true;
  }
  return IPV6_BLOCKED_RANGES.some(([prefix, bits]) =>
    isIpv6InCidr(value, prefix, bits)
  );
}

function isIpv6InCidr(value: bigint, prefix: string, bits: number): boolean {
  const parsed = parseIpv6(prefix);
  if (parsed === null) return true;
  const width = BigInt(bits);
  const hostBits = 128n - width;
  const mask = ((1n << width) - 1n) << hostBits;
  return (value & mask) === (parsed & mask);
}

function validateRequestId(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpError(400, "VALIDATION_ERROR", "Request ID is required.");
  }
  const requestId = value.trim();
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    throw new HttpError(400, "VALIDATION_ERROR", "Request ID is invalid.");
  }
  return requestId;
}

function enforceCreateRateLimit(ownerSubject: string): void {
  const now = Date.now();
  for (const [subject, bucket] of rateBuckets) {
    if (now - bucket.startedAt >= RATE_LIMIT_WINDOW_MS) {
      rateBuckets.delete(subject);
    }
  }
  if (!rateBuckets.has(ownerSubject) && rateBuckets.size >= MAX_RATE_BUCKETS) {
    const oldest = rateBuckets.keys().next().value;
    if (typeof oldest === "string") rateBuckets.delete(oldest);
  }
  const existing = rateBuckets.get(ownerSubject);
  if (
    existing === undefined || now - existing.startedAt >= RATE_LIMIT_WINDOW_MS
  ) {
    rateBuckets.set(ownerSubject, { startedAt: now, count: 1 });
    return;
  }
  if (existing.count >= RATE_LIMIT_MAX) {
    throw new HttpError(
      429,
      "RATE_LIMITED",
      "Too many video requests. Try again later.",
    );
  }
  existing.count += 1;
}

async function createVideoJob(
  supabase: SupabaseClient,
  ownerSubject: string,
  input: CreateInput,
  corsOrigin: string | null,
): Promise<Response> {
  const spaceUrl = readSpaceUrl();
  const providerResponse = await requestGradio(
    gradioApiUrl(spaceUrl, "/call/generate_video"),
    "POST",
    { data: buildGradioInput(input) },
    SUBMIT_TIMEOUT_MS,
  );
  const requestId = gradioEventId(providerResponse);
  const now = new Date().toISOString();
  const { error } = await supabase.from("ai_video_jobs").insert({
    request_id: requestId,
    model: spaceUrl,
    owner_subject: ownerSubject,
    status: "queued",
    progress: null,
    video_url: null,
    created_at: now,
    updated_at: now,
  });
  if (error !== null) {
    throw new HttpError(
      500,
      "UPSTREAM_ERROR",
      "Video job could not be stored.",
    );
  }
  return jsonResponse({ requestId, status: "queued" }, 200, corsOrigin);
}

async function pollVideoJob(
  supabase: SupabaseClient,
  ownerSubject: string,
  requestId: string,
  corsOrigin: string | null,
): Promise<Response> {
  const { data, error } = await supabase
    .from("ai_video_jobs")
    .select("request_id, model, owner_subject, status, progress, video_url")
    .eq("request_id", requestId)
    .eq("owner_subject", ownerSubject)
    .maybeSingle();
  if (error !== null) {
    throw new HttpError(500, "UPSTREAM_ERROR", "Video job could not be read.");
  }
  if (!isJobRecord(data)) {
    throw new HttpError(404, "NOT_FOUND", "Video job was not found.");
  }

  const spaceUrl = validateStoredModel(data.model);
  if (data.status === "completed") {
    if (data.video_url === null) {
      throw new HttpError(
        502,
        "INVALID_RESPONSE",
        "Video provider returned an invalid result.",
      );
    }
    const videoUrl = validateFinalVideoUrl(data.video_url, spaceUrl);
    return jsonResponse(
      { requestId, status: "completed", videoUrl },
      200,
      corsOrigin,
    );
  }
  if (data.status === "failed") {
    return failedVideoResponse(requestId, corsOrigin);
  }
  if (data.status !== "queued" && data.status !== "processing") {
    throw new HttpError(
      502,
      "INVALID_RESPONSE",
      "Video job status is invalid.",
    );
  }

  const stream = await requestGradioStream(
    gradioApiUrl(
      spaceUrl,
      `/call/generate_video/${encodeURIComponent(requestId)}`,
    ),
    POLL_TIMEOUT_MS,
  );
  let videoUrl: string;
  try {
    videoUrl = parseGradioEventStream(stream, spaceUrl);
  } catch (error) {
    await markJobFailed(supabase, ownerSubject, requestId);
    if (error instanceof GradioStreamError && error.kind === "provider") {
      return failedVideoResponse(requestId, corsOrigin);
    }
    throw new HttpError(
      502,
      "INVALID_RESPONSE",
      "Video provider returned an invalid result.",
    );
  }
  const now = new Date().toISOString();
  await updateJob(supabase, ownerSubject, requestId, {
    status: "completed",
    progress: 100,
    video_url: videoUrl,
    updated_at: now,
    completed_at: now,
  });
  return jsonResponse(
    { requestId, status: "completed", videoUrl },
    200,
    corsOrigin,
  );
}

async function markJobFailed(
  supabase: SupabaseClient,
  ownerSubject: string,
  requestId: string,
): Promise<void> {
  await updateJob(supabase, ownerSubject, requestId, {
    status: "failed",
    progress: null,
    video_url: null,
    updated_at: new Date().toISOString(),
  });
}

async function updateJob(
  supabase: SupabaseClient,
  ownerSubject: string,
  requestId: string,
  values: JsonObject,
): Promise<void> {
  const { error } = await supabase
    .from("ai_video_jobs")
    .update(values)
    .eq("request_id", requestId)
    .eq("owner_subject", ownerSubject);
  if (error !== null) {
    throw new HttpError(
      500,
      "UPSTREAM_ERROR",
      "Video job could not be updated.",
    );
  }
}

function failedVideoResponse(
  requestId: string,
  corsOrigin: string | null,
): Response {
  return jsonResponse(
    {
      requestId,
      status: "failed",
      error: { code: "UPSTREAM_ERROR", message: "Video generation failed." },
    },
    200,
    corsOrigin,
  );
}

function readSpaceUrl(): string {
  try {
    return normalizeSpaceUrl(
      Deno.env.get("HF_VIDEO_SPACE_URL") ?? DEFAULT_SPACE_URL,
    );
  } catch (_) {
    throw new HttpError(
      500,
      "UPSTREAM_ERROR",
      "Video provider Space is not configured correctly.",
    );
  }
}

function validateStoredModel(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpError(502, "INVALID_RESPONSE", "Video job model is invalid.");
  }
  try {
    return normalizeSpaceUrl(value);
  } catch (_) {
    throw new HttpError(502, "INVALID_RESPONSE", "Video job model is invalid.");
  }
}

async function requestGradio(
  url: string,
  method: "POST",
  payload: JsonObject,
  timeoutMs: number,
): Promise<JsonObject> {
  const body = JSON.stringify(payload);
  if (new TextEncoder().encode(body).byteLength > MAX_REQUEST_BYTES) {
    throw new HttpError(
      413,
      "VALIDATION_ERROR",
      "Video provider request is too large.",
    );
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method,
      headers: {
        accept: "application/json",
        "content-type": "application/json",
      },
      body,
      signal: controller.signal,
    });
    const bytes = await readLimitedBytes(
      response.body,
      MAX_RESPONSE_BYTES,
      new HttpError(
        502,
        "UPSTREAM_ERROR",
        "Video provider response is too large.",
      ),
    );
    if (!response.ok) {
      throw new HttpError(
        502,
        "UPSTREAM_ERROR",
        `Video provider request failed (HTTP ${response.status}).`,
      );
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(new TextDecoder().decode(bytes));
    } catch (_) {
      throw new HttpError(
        502,
        "INVALID_RESPONSE",
        "Video provider returned invalid JSON.",
      );
    }
    if (!isJsonObject(parsed)) {
      throw new HttpError(
        502,
        "INVALID_RESPONSE",
        "Video provider returned an invalid response.",
      );
    }
    return parsed;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(
      502,
      "UPSTREAM_ERROR",
      "Video provider is unavailable.",
    );
  } finally {
    clearTimeout(timeout);
  }
}

async function requestGradioStream(
  url: string,
  timeoutMs: number,
): Promise<string> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: "GET",
      headers: { accept: "text/event-stream" },
      signal: controller.signal,
    });
    const bytes = await readLimitedBytes(
      response.body,
      MAX_RESPONSE_BYTES,
      new HttpError(
        502,
        "UPSTREAM_ERROR",
        "Video provider response is too large.",
      ),
    );
    if (!response.ok) {
      throw new HttpError(
        502,
        "UPSTREAM_ERROR",
        `Video provider request failed (HTTP ${response.status}).`,
      );
    }
    return new TextDecoder().decode(bytes);
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError(
      502,
      "UPSTREAM_ERROR",
      "Video provider is unavailable.",
    );
  } finally {
    clearTimeout(timeout);
  }
}

function gradioEventId(body: JsonObject): string {
  const eventId = body.event_id;
  if (typeof eventId !== "string" || !REQUEST_ID_PATTERN.test(eventId)) {
    throw new HttpError(
      502,
      "INVALID_RESPONSE",
      "Video provider returned an invalid request ID.",
    );
  }
  return eventId;
}

function validateFinalVideoUrl(value: string, spaceUrl: string): string {
  if (value.length === 0 || value.length > MAX_URL_CHARS) {
    throw new HttpError(
      502,
      "INVALID_RESPONSE",
      "Video provider returned an invalid result.",
    );
  }
  let url: URL;
  let space: URL;
  try {
    url = new URL(value);
    space = new URL(spaceUrl);
  } catch (_) {
    throw new HttpError(
      502,
      "INVALID_RESPONSE",
      "Video provider returned an invalid result.",
    );
  }
  if (
    url.protocol !== "https:" || url.hostname.length === 0 || url.username ||
    url.password ||
    url.hostname.toLowerCase() !== space.hostname.toLowerCase() ||
    url.port !== space.port
  ) {
    throw new HttpError(
      502,
      "INVALID_RESPONSE",
      "Video provider returned an invalid result.",
    );
  }
  return url.toString();
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isJobRecord(value: unknown): value is JobRecord {
  if (!isJsonObject(value)) return false;
  return (
    typeof value.request_id === "string" &&
    typeof value.model === "string" &&
    typeof value.owner_subject === "string" &&
    typeof value.status === "string" &&
    (value.progress === null || typeof value.progress === "number") &&
    (value.video_url === null || typeof value.video_url === "string")
  );
}

function jsonResponse(
  payload: unknown,
  status = 200,
  origin: string | null = null,
): Response {
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
  });
  headers.set("access-control-allow-methods", CORS_METHODS);
  headers.set("access-control-allow-headers", CORS_HEADERS);
  if (origin !== null) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
  }
  return new Response(status === 204 ? null : JSON.stringify(payload), {
    status,
    headers,
  });
}
