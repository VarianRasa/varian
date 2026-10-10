import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  Ai3DError,
  configuredAi3dProviders,
  normalizeWorkerBaseUrl,
  optionalText,
  parseInteger,
  readBearerToken,
  requirePrompt,
  safeJobId,
  safeProjectId,
  safeSourceUrl,
  type JsonObject,
  validateCorsOrigin,
  validateGlb,
  validatePng,
} from "./helpers.ts";
import {
  cancelFalTrellis2Job,
  createFalTrellis2Job,
  falArtifactUrl,
  falTrellis2Configured,
  FAL_TRELLIS2_PROVIDER,
  pollFalTrellis2Job,
} from "./fal_trellis2.ts";

const MAX_REQUEST_BYTES = 12 * 1024 * 1024;
const MAX_SOURCE_BASE64_CHARS = 11 * 1024 * 1024;
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const MAX_ARTIFACT_BYTES = 64 * 1024 * 1024;
const MAX_PREVIEW_BYTES = 4 * 1024 * 1024;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 5;
const rateBuckets = new Map<string, { startedAt: number; count: number }>();

type AuthenticatedUser = { id: string };

type JobRow = {
  request_id: string;
  project_id: string;
  owner_subject: string;
  worker_job_id: string;
  capability: string;
  provider: string;
  status: string;
  progress: number | null;
  prompt: string;
  parameters: JsonObject;
  artifact: JsonObject | null;
  artifact_path: string | null;
  error_code: string | null;
  error_message: string | null;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
};

type CreateInput = {
  jobId: string;
  projectId: string;
  capability: "textTo3D" | "imageTo3D";
  prompt: string;
  negativePrompt?: string;
  sourceImageBase64?: string;
  sourceImageUrl?: string;
  sourceModelReference?: string;
  provider: string;
  meshQuality: "draft" | "balanced" | "high";
  textureMode: "none" | "vertex_color" | "pbr";
  triangleBudget: number;
  seed: number;
  generatePreview: boolean;
};

const app = Deno.serve(handleRequest);

async function handleRequest(request: Request): Promise<Response> {
  let origin: string | null = null;
  try {
    origin = resolveCorsOrigin(request.headers.get("origin"));
    if (request.method === "OPTIONS") return jsonResponse(null, 204, origin);

    const route = routeParts(request.url);
    if (request.method === "GET" && route[0] === "health") {
      return await health(request, origin);
    }

    const user = await authenticate(request);
    const admin = createServiceClient();
    if (request.method === "POST" && route[0] === "3d" && route[1] === "jobs" && route.length === 2) {
      enforceRateLimit(user.id);
      const input = await validateCreateInput(await readJson(request));
      await assertProjectEditor(admin, input.projectId, user.id);
      return await createJob(admin, input, user, origin);
    }
    if (request.method === "GET" && route[0] === "3d" && route[1] === "jobs" && route[2]) {
      return await pollJob(admin, route[2], user, origin);
    }
    if (request.method === "POST" && route[0] === "3d" && route[1] === "jobs" && route[2] && route[3] === "cancel") {
      return await cancelJob(admin, route[2], user, origin);
    }
    if (request.method === "POST" && route[0] === "3d" && route[1] === "jobs" && route[2] && route[3] === "retry") {
      enforceRateLimit(user.id);
      return await retryJob(admin, route[2], user, origin);
    }
    throw new Ai3DError(404, "NOT_FOUND", "3D route not found.");
  } catch (error) {
    if (error instanceof Ai3DError) {
      return jsonResponse({ error: { code: error.code, message: error.message } }, error.status, origin);
    }
    return jsonResponse(
      { error: { code: "UPSTREAM_ERROR", message: "3D service is unavailable." } },
      500,
      origin,
    );
  }
}

async function health(request: Request, origin: string | null): Promise<Response> {
  await authenticate(request);
  const response = await workerFetch("/health", { method: "GET" });
  const payload = await readResponseJson(response, "3D worker health");
  return jsonResponse({ status: "ok", worker: payload }, 200, origin);
}

async function createJob(
  admin: SupabaseClient,
  input: CreateInput,
  user: AuthenticatedUser,
  origin: string | null,
): Promise<Response> {
  const existing = await getOwnedJob(admin, input.jobId, user.id);
  if (existing !== null) {
    return jsonResponse(await publicJob(admin, existing), 200, origin);
  }

  const upstreamPayload: JsonObject = {
    jobId: input.jobId,
    projectId: input.projectId,
    capability: input.capability,
    prompt: input.prompt,
    negativePrompt: input.negativePrompt,
    sourceImageBase64: input.sourceImageBase64,
    sourceImageUrl: input.sourceImageUrl,
    sourceModelReference: input.sourceModelReference,
    provider: input.provider,
    meshQuality: input.meshQuality,
    textureMode: input.textureMode,
    targetFormat: "glb",
    triangleBudget: input.triangleBudget,
    seed: input.seed,
    generatePreview: input.generatePreview,
  };
  removeUndefined(upstreamPayload);
  const workerPayload = input.provider === FAL_TRELLIS2_PROVIDER
    ? await createHostedFalJob(input)
    : await createWorkerJob(upstreamPayload);
  const workerJobId = readString(workerPayload, ["jobId", "id"]);
  const provider = readString(workerPayload, ["provider"]) || input.provider;
  const row = await insertJob(admin, {
    request_id: input.jobId,
    project_id: input.projectId,
    owner_subject: user.id,
    worker_job_id: workerJobId,
    capability: input.capability,
    provider,
    status: normalizeStatus(workerPayload.status),
    progress: readNumber(workerPayload),
    prompt: input.prompt,
    parameters: {
      negativePrompt: input.negativePrompt,
      meshQuality: input.meshQuality,
      textureMode: input.textureMode,
      triangleBudget: input.triangleBudget,
      seed: input.seed,
      generatePreview: input.generatePreview,
      sourceModelReference: input.sourceModelReference,
      ...(input.sourceImageUrl === undefined ? {} : { sourceImageUrl: input.sourceImageUrl }),
    },
  });
  return jsonResponse(await publicJob(admin, row), 202, origin);
}

async function pollJob(
  admin: SupabaseClient,
  requestId: string,
  user: AuthenticatedUser,
  origin: string | null,
): Promise<Response> {
  const row = await getOwnedJob(admin, requestId, user.id);
  if (row === null) throw new Ai3DError(404, "NOT_FOUND", "3D job not found.");
  if (["completed", "failed", "canceled"].includes(row.status)) {
    return jsonResponse(await publicJob(admin, row), 200, origin);
  }

  const workerPayload = row.provider === FAL_TRELLIS2_PROVIDER
    ? await pollFalTrellis2Job(row.worker_job_id)
    : await pollWorkerJob(row.worker_job_id);
  const status = normalizeStatus(workerPayload.status);
  const progress = readNumber(workerPayload);
  if (status === "completed") {
    const artifact = row.provider === FAL_TRELLIS2_PROVIDER
      ? await persistFalArtifact(admin, row, workerPayload)
      : await persistArtifact(admin, row, workerPayload);
    const completed = await updateJob(admin, row.request_id, {
      status: "completed",
      progress: 100,
      artifact,
      artifact_path: artifact.reference?.toString() ?? null,
      error_code: null,
      error_message: null,
      completed_at: new Date().toISOString(),
    });
    return jsonResponse(await publicJob(admin, completed), 200, origin);
  }

  const error = readError(workerPayload);
  const updated = await updateJob(admin, row.request_id, {
    status,
    progress,
    error_code: error === null ? null : "GENERATION_FAILED",
    error_message: error,
  });
  return jsonResponse(await publicJob(admin, updated), 200, origin);
}

async function cancelJob(
  admin: SupabaseClient,
  requestId: string,
  user: AuthenticatedUser,
  origin: string | null,
): Promise<Response> {
  const row = await getOwnedJob(admin, requestId, user.id);
  if (row === null) throw new Ai3DError(404, "NOT_FOUND", "3D job not found.");
  if (["completed", "failed", "canceled"].includes(row.status)) {
    return jsonResponse(await publicJob(admin, row), 200, origin);
  }
  const workerPayload = row.provider === FAL_TRELLIS2_PROVIDER
    ? await cancelFalTrellis2Job(row.worker_job_id)
    : await cancelWorkerJob(row.worker_job_id);
  const updated = await updateJob(admin, requestId, {
    status: normalizeStatus(workerPayload.status) === "canceled" ? "canceled" : "processing",
    progress: readNumber(workerPayload),
  });
  return jsonResponse(await publicJob(admin, updated), 200, origin);
}

async function retryJob(
  admin: SupabaseClient,
  requestId: string,
  user: AuthenticatedUser,
  origin: string | null,
): Promise<Response> {
  const row = await getOwnedJob(admin, requestId, user.id);
  if (row === null) throw new Ai3DError(404, "NOT_FOUND", "3D job not found.");
  if (["completed", "queued", "processing"].includes(row.status)) {
    return jsonResponse(await publicJob(admin, row), 200, origin);
  }

  const workerPayload = row.provider === FAL_TRELLIS2_PROVIDER
    ? await createHostedFalJobFromRow(row)
    : await retryWorkerJob(row.worker_job_id);
  const retriedWorkerJobId = readString(workerPayload, ["jobId", "id"]);
  const status = normalizeStatus(workerPayload.status);
  const progress = readNumber(workerPayload);
  if (status === "completed") {
    const artifact = row.provider === FAL_TRELLIS2_PROVIDER
      ? await persistFalArtifact(admin, row, workerPayload)
      : await persistArtifact(admin, row, workerPayload);
    const completed = await updateJob(admin, requestId, {
      worker_job_id: retriedWorkerJobId,
      status: "completed",
      progress: 100,
      artifact,
      artifact_path: artifact.reference?.toString() ?? null,
      error_code: null,
      error_message: null,
      completed_at: new Date().toISOString(),
    });
    return jsonResponse(await publicJob(admin, completed), 200, origin);
  }

  const error = readError(workerPayload);
  const updated = await updateJob(admin, requestId, {
    worker_job_id: retriedWorkerJobId,
    status,
    progress,
    artifact: null,
    artifact_path: null,
    error_code: error === null ? null : "GENERATION_FAILED",
    error_message: error,
    completed_at: null,
  });
  return jsonResponse(await publicJob(admin, updated), status === "queued" || status === "processing" ? 202 : 200, origin);
}

async function persistArtifact(
  admin: SupabaseClient,
  row: JobRow,
  workerPayload: JsonObject,
): Promise<JsonObject> {
  const rawArtifact = workerPayload.artifact;
  if (!isObject(rawArtifact)) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "3D worker did not return an artifact.");
  }
  const sourceUrl = typeof rawArtifact.url === "string" ? rawArtifact.url : "";
  const safeUrl = validateWorkerArtifactUrl(sourceUrl);
  const response = await workerFetch(safeUrl, { method: "GET", artifact: true });
  if (!response.ok) {
    throw new Ai3DError(502, "ARTIFACT_DOWNLOAD_FAILED", "Generated GLB could not be downloaded.");
  }
  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (contentLength > MAX_ARTIFACT_BYTES) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB exceeds the 64 MB limit.");
  }
  const bytes = await readBoundedBytes(
    response.body,
    MAX_ARTIFACT_BYTES,
    () => new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB exceeds the 64 MB limit."),
  );
  const info = validateGlb(bytes, MAX_ARTIFACT_BYTES);
  return storeGlbArtifact(admin, row, rawArtifact, bytes, info, true);
}

async function persistFalArtifact(
  admin: SupabaseClient,
  row: JobRow,
  hostedPayload: JsonObject,
): Promise<JsonObject> {
  const rawArtifact = hostedPayload.artifact;
  if (!isObject(rawArtifact)) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Hosted TRELLIS.2 did not return an artifact.");
  }
  const sourceUrl = typeof rawArtifact.url === "string" ? rawArtifact.url : "";
  const safeUrl = falArtifactUrl(sourceUrl);
  let response: Response;
  try {
    response = await fetch(safeUrl, {
      method: "GET",
      headers: { Accept: "model/gltf-binary,application/octet-stream" },
      redirect: "error",
    });
  } catch (_) {
    throw new Ai3DError(502, "ARTIFACT_DOWNLOAD_FAILED", "Hosted TRELLIS.2 GLB could not be downloaded.");
  }
  if (!response.ok) {
    throw new Ai3DError(502, "ARTIFACT_DOWNLOAD_FAILED", "Hosted TRELLIS.2 GLB could not be downloaded.");
  }
  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (contentLength > MAX_ARTIFACT_BYTES) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Hosted TRELLIS.2 GLB exceeds the 64 MB limit.");
  }
  const bytes = await readBoundedBytes(
    response.body,
    MAX_ARTIFACT_BYTES,
    () => new Ai3DError(502, "INVALID_ARTIFACT", "Hosted TRELLIS.2 GLB exceeds the 64 MB limit."),
  );
  const info = validateGlb(bytes, MAX_ARTIFACT_BYTES);
  const triangleBudget = typeof row.parameters.triangleBudget === "number"
    ? row.parameters.triangleBudget
    : 100000;
  if (info.triangleCount > triangleBudget) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Hosted TRELLIS.2 GLB exceeds the requested triangle budget.");
  }
  return storeGlbArtifact(admin, row, rawArtifact, bytes, info, false);
}

async function storeGlbArtifact(
  admin: SupabaseClient,
  row: JobRow,
  rawArtifact: JsonObject,
  bytes: Uint8Array,
  info: { byteLength: number; triangleCount: number },
  includePreview: boolean,
): Promise<JsonObject> {
  const bucket = Deno.env.get("AI_3D_BUCKET")?.trim() || "assets";
  const path = `${await storageSegment(row.project_id)}/ai-3d/${row.request_id}.glb`;
  const upload = await admin.storage.from(bucket).upload(path, bytes, {
    contentType: "model/gltf-binary",
    upsert: true,
  });
  if (upload.error) {
    throw new Ai3DError(502, "ARTIFACT_UPLOAD_FAILED", "Generated GLB could not be saved to storage.");
  }
  const signed = await admin.storage.from(bucket).createSignedUrl(
    path,
    Math.max(300, Number(Deno.env.get("AI_3D_SIGNED_URL_SECONDS") ?? "86400")),
  );
  if (signed.error || !signed.data?.signedUrl) {
    throw new Ai3DError(502, "ARTIFACT_URL_FAILED", "Generated GLB URL could not be created.");
  }
  const preview = includePreview ? await persistPreview(admin, row, rawArtifact) : null;
  return {
    kind: "model3d",
    url: signed.data.signedUrl,
    reference: `${bucket}/${path}`,
    fileName: typeof rawArtifact.fileName === "string" ? rawArtifact.fileName : `${row.request_id}.glb`,
    mimeType: "model/gltf-binary",
    byteLength: info.byteLength,
    provider: typeof rawArtifact.provider === "string" ? rawArtifact.provider : row.provider,
    triangleCount: info.triangleCount,
    ...(preview ?? {}),
  };
}

async function persistPreview(
  admin: SupabaseClient,
  row: JobRow,
  rawArtifact: JsonObject,
): Promise<JsonObject | null> {
  const sourceUrl = typeof rawArtifact.previewUrl === "string" ? rawArtifact.previewUrl : "";
  if (sourceUrl.length === 0) return null;
  const safeUrl = validateWorkerArtifactUrl(sourceUrl);
  const response = await workerFetch(safeUrl, { method: "GET", artifact: true });
  if (!response.ok) {
    throw new Ai3DError(502, "PREVIEW_DOWNLOAD_FAILED", "Generated preview could not be downloaded.");
  }
  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (contentLength > MAX_PREVIEW_BYTES) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview exceeds the 4 MB limit.");
  }
  const bytes = await readBoundedBytes(
    response.body,
    MAX_PREVIEW_BYTES,
    () => new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview exceeds the 4 MB limit."),
  );
  const info = validatePng(bytes, MAX_PREVIEW_BYTES);
  const bucket = Deno.env.get("AI_3D_BUCKET")?.trim() || "assets";
  const path = `${await storageSegment(row.project_id)}/ai-3d/${row.request_id}.png`;
  const upload = await admin.storage.from(bucket).upload(path, bytes, {
    contentType: "image/png",
    upsert: true,
  });
  if (upload.error) {
    throw new Ai3DError(502, "PREVIEW_UPLOAD_FAILED", "Generated preview could not be saved to storage.");
  }
  const signed = await admin.storage.from(bucket).createSignedUrl(
    path,
    Math.max(300, Number(Deno.env.get("AI_3D_SIGNED_URL_SECONDS") ?? "86400")),
  );
  if (signed.error || !signed.data?.signedUrl) {
    throw new Ai3DError(502, "PREVIEW_URL_FAILED", "Generated preview URL could not be created.");
  }
  return {
    previewUrl: signed.data.signedUrl,
    previewReference: `${bucket}/${path}`,
    previewFileName: typeof rawArtifact.previewFileName === "string" ? rawArtifact.previewFileName : `${row.request_id}.png`,
    previewMimeType: "image/png",
    previewByteLength: info.byteLength,
    previewWidth: info.width,
    previewHeight: info.height,
  };
}

async function publicJob(admin: SupabaseClient, row: JobRow): Promise<JsonObject> {
  let artifact = row.artifact;
  if (row.artifact_path !== null) {
    const parts = row.artifact_path.split("/");
    const bucket = parts.shift();
    const path = parts.join("/");
    if (bucket && path) {
      const signed = await admin.storage.from(bucket).createSignedUrl(
        path,
        Math.max(300, Number(Deno.env.get("AI_3D_SIGNED_URL_SECONDS") ?? "86400")),
      );
      if (!signed.error && signed.data?.signedUrl && artifact !== null) {
        artifact = { ...artifact, url: signed.data.signedUrl };
      }
    }
  }
  if (artifact !== null && typeof artifact.previewReference === "string") {
    const parts = artifact.previewReference.split("/");
    const bucket = parts.shift();
    const path = parts.join("/");
    if (bucket && path) {
      const signed = await admin.storage.from(bucket).createSignedUrl(
        path,
        Math.max(300, Number(Deno.env.get("AI_3D_SIGNED_URL_SECONDS") ?? "86400")),
      );
      if (!signed.error && signed.data?.signedUrl) {
        artifact = { ...artifact, previewUrl: signed.data.signedUrl };
      }
    }
  }
  const payload: JsonObject = {
    jobId: row.request_id,
    status: row.status,
    progress: row.progress,
    provider: row.provider,
  };
  if (artifact !== null) payload.artifact = artifact;
  if (row.error_message !== null) {
    payload.error = { code: row.error_code ?? "GENERATION_FAILED", message: row.error_message };
    payload.message = row.error_message;
  }
  return payload;
}

async function insertJob(admin: SupabaseClient, values: Record<string, unknown>): Promise<JobRow> {
  const result = await admin.from("ai_3d_jobs").insert(values).select("*").single();
  if (result.error || !result.data) {
    if (result.error?.code === "23505") {
      const existing = await getOwnedJob(admin, String(values.request_id), String(values.owner_subject));
      if (existing !== null) return existing;
    }
    throw new Ai3DError(500, "DATABASE_ERROR", "3D job could not be saved.");
  }
  return result.data as JobRow;
}

async function updateJob(admin: SupabaseClient, requestId: string, values: Record<string, unknown>): Promise<JobRow> {
  const result = await admin.from("ai_3d_jobs").update(values).eq("request_id", requestId).select("*").single();
  if (result.error || !result.data) throw new Ai3DError(500, "DATABASE_ERROR", "3D job could not be updated.");
  return result.data as JobRow;
}

async function getOwnedJob(admin: SupabaseClient, requestId: string, userId: string): Promise<JobRow | null> {
  const result = await admin.from("ai_3d_jobs").select("*").eq("request_id", requestId).eq("owner_subject", userId).maybeSingle();
  if (result.error) throw new Ai3DError(500, "DATABASE_ERROR", "3D job could not be read.");
  return result.data as JobRow | null;
}

async function assertProjectEditor(admin: SupabaseClient, projectId: string, userId: string): Promise<void> {
  const project = await admin.from("projects").select("owner_id").eq("id", projectId).maybeSingle();
  if (project.error) throw new Ai3DError(500, "DATABASE_ERROR", "Project authorization could not be checked.");
  if (!project.data) throw new Ai3DError(403, "FORBIDDEN", "Project does not exist.");
  if (project.data.owner_id === userId) return;
  const member = await admin.from("workspace_members").select("role").eq("project_id", projectId).eq("user_id", userId).maybeSingle();
  if (member.error || !member.data || !["owner", "editor"].includes(member.data.role)) {
    throw new Ai3DError(403, "FORBIDDEN", "Project edit access is required for 3D generation.");
  }
}

async function createWorkerJob(payload: JsonObject): Promise<JsonObject> {
  const upstream = await workerFetch("/3d/jobs", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return readResponseJson(upstream, "3D job creation");
}

async function pollWorkerJob(jobId: string): Promise<JsonObject> {
  const upstream = await workerFetch(`/3d/jobs/${encodeURIComponent(jobId)}`, { method: "GET" });
  return readResponseJson(upstream, "3D job polling");
}

async function cancelWorkerJob(jobId: string): Promise<JsonObject> {
  const upstream = await workerFetch(`/3d/jobs/${encodeURIComponent(jobId)}/cancel`, { method: "POST" });
  return readResponseJson(upstream, "3D job cancellation");
}

async function retryWorkerJob(jobId: string): Promise<JsonObject> {
  const upstream = await workerFetch(`/3d/jobs/${encodeURIComponent(jobId)}/retry`, { method: "POST" });
  return readResponseJson(upstream, "3D job retry");
}

async function createHostedFalJob(input: CreateInput): Promise<JsonObject> {
  if (!falTrellis2Configured()) {
    throw new Ai3DError(503, "CONFIGURATION_ERROR", "Hosted TRELLIS.2 is not configured.");
  }
  if (input.capability === "textTo3D" && input.sourceImageBase64 === undefined && input.sourceImageUrl === undefined) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "Hosted TRELLIS.2 requires a reference image.");
  }
  return createFalTrellis2Job({
    imageUrl: falImageInput(input),
    meshQuality: input.meshQuality,
    textureMode: input.textureMode,
    triangleBudget: input.triangleBudget,
    seed: input.seed,
  });
}

async function createHostedFalJobFromRow(row: JobRow): Promise<JsonObject> {
  const parameters = row.parameters;
  const sourceImageUrl = typeof parameters.sourceImageUrl === "string" ? parameters.sourceImageUrl : undefined;
  if (sourceImageUrl === undefined) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "Hosted TRELLIS.2 retry requires a reusable image URL.");
  }
  const meshQuality = parameters.meshQuality === "draft" || parameters.meshQuality === "high"
    ? parameters.meshQuality
    : "balanced";
  const textureMode = parameters.textureMode === "none" || parameters.textureMode === "vertex_color"
    ? parameters.textureMode
    : "pbr";
  const triangleBudget = typeof parameters.triangleBudget === "number" ? parameters.triangleBudget : 100000;
  const seed = typeof parameters.seed === "number" ? parameters.seed : -1;
  return createFalTrellis2Job({
    imageUrl: sourceImageUrl,
    meshQuality,
    textureMode,
    triangleBudget,
    seed,
  });
}

function falImageInput(input: CreateInput): string {
  if (input.sourceImageUrl !== undefined) return input.sourceImageUrl;
  const raw = input.sourceImageBase64?.trim() ?? "";
  if (raw.length === 0) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "Hosted TRELLIS.2 requires a reference image.");
  }
  if (raw.startsWith("data:")) {
    if (!/^data:image\/(?:png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$/i.test(raw)) {
      throw new Ai3DError(400, "VALIDATION_ERROR", "sourceImageBase64 must be a PNG, JPEG, or WebP data URI.");
    }
    return raw;
  }
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(raw)) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "sourceImageBase64 is invalid.");
  }
  return `data:image/png;base64,${raw}`;
}

async function validateCreateInput(body: JsonObject): Promise<CreateInput> {
  const projectId = safeProjectId(body.projectId);
  const capability = body.capability === "textTo3D" || body.capability === "imageTo3D" ? body.capability : null;
  if (capability === null) throw new Ai3DError(400, "VALIDATION_ERROR", "capability must be textTo3D or imageTo3D.");
  const provider = (optionalText(body.provider, "provider", 40) ?? Deno.env.get("AI_3D_DEFAULT_PROVIDER")?.trim() ?? "triposr").toLowerCase();
  const hunyuanGateApproved =
    Deno.env.get("AI_3D_ENABLE_HUNYUAN") === "true" &&
    Deno.env.get("AI_3D_HUNYUAN_LEGAL_APPROVED") === "true" &&
    Deno.env.get("AI_3D_HUNYUAN_TERRITORY_CONFIRMED") === "true" &&
    Deno.env.get("AI_3D_HUNYUAN_AUP_CONFIRMED") === "true";
  const allowedProviders = configuredAi3dProviders(
    Deno.env.get("AI_3D_ALLOWED_PROVIDERS"),
    Deno.env.get("AI_3D_ALLOW_DEMO") === "true",
    Deno.env.get("AI_3D_ENABLE_HUNYUAN") === "true",
    hunyuanGateApproved,
    Deno.env.get("AI_3D_ENABLE_TRELLIS2") === "true",
    Deno.env.get("AI_3D_TRELLIS2_LEGAL_APPROVED") === "true",
    Deno.env.get("AI_3D_TRELLIS2_DEPENDENCY_REVIEWED") === "true",
    Deno.env.get("AI_3D_ENABLE_FAL_TRELLIS2") === "true" && falTrellis2Configured(),
  );
  if (!allowedProviders.has(provider)) throw new Ai3DError(400, "VALIDATION_ERROR", "provider is not allowed.");
  const sourceImageBase64 = optionalText(body.sourceImageBase64, "sourceImageBase64", MAX_SOURCE_BASE64_CHARS);
  const sourceImageUrlValue = optionalText(body.sourceImageUrl, "sourceImageUrl", 2048);
  const sourceImageUrl = sourceImageUrlValue === undefined ? undefined : safeSourceUrl(sourceImageUrlValue, allowedSourceHosts());
  if (capability === "imageTo3D" && sourceImageBase64 === undefined && sourceImageUrl === undefined) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "imageTo3D requires an image source.");
  }
  if (provider === FAL_TRELLIS2_PROVIDER && sourceImageBase64 === undefined && sourceImageUrl === undefined) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "Hosted TRELLIS.2 requires an image source.");
  }
  const triangleBudget = parseInteger(body.triangleBudget, "triangleBudget", 100000, 1000, 500000);
  const meshQuality = optionalText(body.meshQuality, "meshQuality", 20) ?? "balanced";
  const textureMode = optionalText(body.textureMode, "textureMode", 20) ?? "pbr";
  if (!["draft", "balanced", "high"].includes(meshQuality)) throw new Ai3DError(400, "VALIDATION_ERROR", "meshQuality is invalid.");
  if (!["none", "vertex_color", "pbr"].includes(textureMode)) throw new Ai3DError(400, "VALIDATION_ERROR", "textureMode is invalid.");
  const generatePreview = body.generatePreview === undefined ? true : body.generatePreview;
  if (typeof generatePreview !== "boolean") throw new Ai3DError(400, "VALIDATION_ERROR", "generatePreview is invalid.");
  return {
    jobId: safeJobId(body.jobId),
    projectId,
    capability,
    prompt: requirePrompt(body.prompt),
    negativePrompt: optionalText(body.negativePrompt, "negativePrompt", 1000),
    sourceImageBase64,
    sourceImageUrl,
    sourceModelReference: optionalText(body.sourceModelReference, "sourceModelReference", 1000),
    provider,
    meshQuality: meshQuality as CreateInput["meshQuality"],
    textureMode: textureMode as CreateInput["textureMode"],
    triangleBudget,
    seed: parseInteger(body.seed, "seed", -1, -1, 2**31 - 1),
    generatePreview,
  };
}

async function authenticate(request: Request): Promise<AuthenticatedUser> {
  const token = readBearerToken(request.headers.get("authorization"));
  const admin = createServiceClient();
  const result = await admin.auth.getUser(token);
  if (result.error || !result.data.user) throw new Ai3DError(401, "UNAUTHORIZED", "Authentication is required.");
  return { id: result.data.user.id };
}

function createServiceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? Deno.env.get("SUPABASE_SECRET_KEY")?.trim();
  if (!url || !key) throw new Ai3DError(500, "CONFIGURATION_ERROR", "Supabase service is not configured.");
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

async function workerFetch(pathOrUrl: string, init: RequestInit & { artifact?: boolean } = {}): Promise<Response> {
  const { artifact, ...requestInit } = init;
  const base = normalizeWorkerBaseUrl(Deno.env.get("AI_3D_WORKER_BASE_URL") ?? "");
  const target = pathOrUrl.startsWith("http") ? pathOrUrl : `${base}${pathOrUrl}`;
  const headers = new Headers(requestInit.headers);
  const token = Deno.env.get("AI_3D_WORKER_TOKEN")?.trim();
  if (token && !artifact) headers.set("Authorization", `Bearer ${token}`);
  headers.set("Accept", artifact ? "model/gltf-binary,application/octet-stream" : "application/json");
  try {
    return await fetch(target, { ...requestInit, headers, redirect: "error" });
  } catch (error) {
    throw new Ai3DError(502, "WORKER_UNREACHABLE", "3D worker is unreachable.");
  }
}

async function readResponseJson(response: Response, operation: string): Promise<JsonObject> {
  const length = Number(response.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > MAX_RESPONSE_BYTES) {
    throw new Ai3DError(502, "INVALID_RESPONSE", `${operation} response is too large.`);
  }
  const bytes = await readBoundedBytes(
    response.body,
    MAX_RESPONSE_BYTES,
    () => new Ai3DError(502, "INVALID_RESPONSE", `${operation} response is too large.`),
  );
  let payload: unknown;
  try {
    payload = JSON.parse(new TextDecoder().decode(bytes));
  } catch (_) {
    throw new Ai3DError(502, "INVALID_RESPONSE", `${operation} returned invalid JSON.`);
  }
  if (!response.ok) {
    const message = isObject(payload) && isObject(payload.error) && typeof payload.error.message === "string"
      ? payload.error.message
      : `${operation} failed (HTTP ${response.status}).`;
    throw new Ai3DError(502, "WORKER_ERROR", message);
  }
  if (!isObject(payload)) throw new Ai3DError(502, "INVALID_RESPONSE", `${operation} returned an invalid object.`);
  return payload;
}

function validateWorkerArtifactUrl(value: string): string {
  let artifact: URL;
  try {
    artifact = new URL(value);
  } catch (_) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "3D worker artifact URL is invalid.");
  }
  const worker = new URL(normalizeWorkerBaseUrl(Deno.env.get("AI_3D_WORKER_BASE_URL") ?? ""));
  const isLocalHttp = artifact.protocol === "http:" &&
    ["localhost", "127.0.0.1", "::1"].includes(artifact.hostname.toLowerCase());
  if (artifact.origin !== worker.origin || (artifact.protocol !== "https:" && !isLocalHttp)) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "3D worker artifact URL is not trusted.");
  }
  return artifact.toString();
}

function allowedSourceHosts(): Set<string> {
  const configured = (Deno.env.get("AI_3D_ALLOWED_SOURCE_HOSTS") ?? "").split(",").map((value) => value.trim().toLowerCase()).filter(Boolean);
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  if (supabaseUrl) {
    try {
      configured.push(new URL(supabaseUrl).hostname.toLowerCase());
    } catch (_) {
      return new Set(configured);
    }
  }
  return new Set(configured);
}

function resolveCorsOrigin(value: string | null): string | null {
  const configured = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((item) => item.trim()).filter(Boolean);
  return validateCorsOrigin(value, new Set(configured));
}

function jsonResponse(payload: unknown, status: number, origin: string | null): Response {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (origin !== null) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Headers", "Authorization, apikey, Content-Type, Accept");
    headers.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    headers.set("Vary", "Origin");
  }
  return new Response(payload === null ? null : JSON.stringify(payload), { status, headers });
}

function routeParts(value: string): string[] {
  const parts = new URL(value).pathname.split("/").filter(Boolean);
  const index = parts.lastIndexOf("ai-3d");
  return index < 0 ? [] : parts.slice(index + 1);
}

async function readJson(request: Request): Promise<JsonObject> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > MAX_REQUEST_BYTES) {
    throw new Ai3DError(413, "REQUEST_TOO_LARGE", "Request is too large.");
  }
  const bytes = await readBoundedBytes(
    request.body,
    MAX_REQUEST_BYTES,
    () => new Ai3DError(413, "REQUEST_TOO_LARGE", "Request is too large."),
  );
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (!isObject(value)) throw new Error("not object");
    return value;
  } catch (_) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "Request body must be a JSON object.");
  }
}

async function readBoundedBytes(
  body: ReadableStream<Uint8Array> | null,
  maxBytes: number,
  tooLarge: () => Ai3DError,
): Promise<Uint8Array> {
  if (body === null) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value === undefined) continue;
      total += value.byteLength;
      if (total > maxBytes) {
        try {
          await reader.cancel();
        } catch (_) {}
        throw tooLarge();
      }
      chunks.push(value);
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

function enforceRateLimit(userId: string): void {
  const now = Date.now();
  const bucket = rateBuckets.get(userId);
  if (!bucket || now - bucket.startedAt >= RATE_LIMIT_WINDOW_MS) {
    rateBuckets.set(userId, { startedAt: now, count: 1 });
    if (rateBuckets.size > 10000) rateBuckets.delete(rateBuckets.keys().next().value as string);
    return;
  }
  if (bucket.count >= RATE_LIMIT_MAX) throw new Ai3DError(429, "RATE_LIMITED", "3D generation rate limit exceeded.");
  bucket.count += 1;
}

function normalizeStatus(value: unknown): string {
  const status = String(value ?? "queued").trim().toLowerCase();
  return status === "cancelled" ? "canceled" : ["queued", "processing", "completed", "failed", "canceled"].includes(status) ? status : "processing";
}

function readString(payload: JsonObject, keys: string[]): string {
  for (const key of keys) {
    const value = payload[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  throw new Ai3DError(502, "INVALID_RESPONSE", "3D worker did not return a job ID.");
}

function readNumber(payload: JsonObject, key: string = "progress"): number | null {
  const value = payload[key];
  return typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.min(100, value)) : null;
}

function readError(payload: JsonObject): string | null {
  const value = payload.error ?? payload.message;
  if (isObject(value) && typeof value.message === "string") return value.message;
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function removeUndefined(value: JsonObject): void {
  for (const key of Object.keys(value)) if (value[key] === undefined) delete value[key];
}

async function storageSegment(value: string): Promise<string> {
  if (/^[A-Za-z0-9._-]{1,120}$/.test(value)) return value;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
