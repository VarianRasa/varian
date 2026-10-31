import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  attachmentMaxBytes,
  attachmentPath,
  attachmentSignatureMatches,
  detectAttachmentMimeType,
  isAuthorizedWorkerRequest,
  resolveAllowedOrigin,
  sha256Hex,
} from "./helpers.ts";

const bucket = "workspace-note-assets";
const maxJobsPerRequest = 10;

type RehomeJob = {
  id: string;
  job_kind: "note_scope_change" | "project_delete";
  note_id: string | null;
  source_project_id: string | null;
  target_project_id: string | null;
  target_owner_user_id: string;
  requested_by: string;
  status: "copying" | "cleanup";
  lease_token: string;
};

type RehomeItem = {
  attachment_id: string;
  source_path: string;
  target_path: string;
  expected_sha256: string;
  mime_type: string;
  size_bytes: number | string;
};

class RehomeError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

if (import.meta.main) Deno.serve(async (request) => {
  const origin = request.headers.get('origin');
  const allowedOrigin = resolveAllowedOrigin(
    origin,
    Deno.env.get('ALLOWED_ORIGINS'),
  );
  if (origin !== null && allowedOrigin === null) {
    return jsonResponse({ error: 'ORIGIN_NOT_ALLOWED' }, 403, request);
  }
  if (request.method === "OPTIONS") return jsonResponse(null, 204, request);
  if (request.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED" }, 405, request);
  }

  try {
    const body = await readJson(request);
    if (body.action === "process_rehome_jobs") {
      if (!isAuthorizedWorkerRequest(
        request,
        Deno.env.get("NOTES_ATTACHMENT_WORKER_SECRET") ?? "",
      )) {
        return jsonResponse({ error: "UNAUTHORIZED" }, 401, request);
      }
      const result = await processAvailableJobs(createServiceClient());
      return jsonResponse(result, 200, request);
    }
    if (body.action === "finalize_upload") {
      const token = bearerToken(request.headers.get("authorization"));
      if (token === null || typeof body.attachmentId !== "string") {
        return jsonResponse({ error: "UNAUTHORIZED" }, 401, request);
      }
      const actorId = await authenticatedUserId(token);
      const result = await finalizeUpload(
        createServiceClient(),
        actorId,
        body.attachmentId,
      );
      return jsonResponse(result, 200, request);
    }
    return jsonResponse({ error: "INVALID_ACTION" }, 400, request);
  } catch (error) {
    const status = error instanceof RehomeError && error.code === "UNAUTHORIZED"
      ? 401
      : error instanceof RehomeError && error.code === "INVALID_REQUEST"
      ? 400
      : 502;
    return jsonResponse({ error: "ATTACHMENT_OPERATION_FAILED" }, status, request);
  }
});

async function finalizeUpload(
  client: SupabaseClient,
  actorId: string,
  attachmentId: string,
): Promise<{ attachmentId: string; mimeType: string; sizeBytes: number }> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(attachmentId)) {
    throw new RehomeError("INVALID_REQUEST");
  }
  const { data, error } = await client.rpc(
    "get_workspace_note_attachment_pending_upload",
    { p_attachment_id: attachmentId },
  );
  if (error !== null) throw new RehomeError("PENDING_READ_FAILED");
  const row = Array.isArray(data) ? data[0] : data;
  if (typeof row !== "object" || row === null ||
      typeof row.owner_user_id !== "string" ||
      (row.project_id !== null && typeof row.project_id !== "string") ||
      typeof row.storage_path !== "string") {
    throw new RehomeError("PENDING_UPLOAD_MISSING");
  }
  const expectedPath = attachmentPath(
    row.owner_user_id,
    row.project_id,
    attachmentId,
  );
  if (row.storage_path !== expectedPath) throw new RehomeError("OBJECT_PATH_INVALID");

  const bytes = await downloadBytes(client, expectedPath, "UPLOAD_READ_FAILED");
  const mimeType = detectAttachmentMimeType(bytes);
  if (mimeType === null) throw new RehomeError("OBJECT_SIGNATURE_INVALID");
  const digest = await sha256Hex(bytes);
  const { error: finalizeError } = await client.rpc(
    "finalize_workspace_note_attachment_upload",
    {
      p_attachment_id: attachmentId,
      p_actor_id: actorId,
      p_mime_type: mimeType,
      p_size_bytes: bytes.length,
      p_sha256: digest,
    },
  );
  if (finalizeError !== null) throw new RehomeError("UPLOAD_FINALIZE_FAILED");
  return { attachmentId, mimeType, sizeBytes: bytes.length };
}

function bearerToken(value: string | null): string | null {
  if (value === null || !value.startsWith("Bearer ")) return null;
  const token = value.slice(7).trim();
  return token.length > 0 && token.length <= 8192 ? token : null;
}

async function authenticatedUserId(token: string): Promise<string> {
  const url = Deno.env.get("SUPABASE_URL")?.trim().replace(/\/+$/, "");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  if (url === undefined || anonKey === undefined) throw new RehomeError("CONFIGURATION_ERROR");
  const userClient = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await userClient.auth.getUser(token);
  if (error !== null || data.user === null || data.user.is_anonymous) {
    throw new RehomeError("UNAUTHORIZED");
  }
  return data.user.id;
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  if (request.body === null) throw new RehomeError("INVALID_REQUEST");
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      total += result.value.byteLength;
      if (total > 8192) throw new RehomeError("INVALID_REQUEST");
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
  try {
    const value = JSON.parse(new TextDecoder().decode(bytes));
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new RehomeError("INVALID_REQUEST");
    }
    return value as Record<string, unknown>;
  } catch (error) {
    if (error instanceof RehomeError) throw error;
    throw new RehomeError("INVALID_REQUEST");
  }
}

export async function processAvailableJobs(
  client: SupabaseClient,
): Promise<{ claimed: number; completed: number; retried: number }> {
  const { data, error } = await client.rpc(
    "claim_workspace_note_attachment_rehome_jobs",
    { p_limit: maxJobsPerRequest },
  );
  if (error !== null) throw new RehomeError("CLAIM_FAILED");
  const jobs = parseJobs(data);
  let completed = 0;
  let retried = 0;
  for (const job of jobs) {
    try {
      await processJob(client, job);
      completed += 1;
    } catch (error) {
      const code = error instanceof RehomeError ? error.code : "REHOME_FAILED";
      const { error: recordError } = await client.rpc(
        "record_workspace_note_attachment_rehome_failure",
        {
          p_job_id: job.id,
          p_lease_token: job.lease_token,
          p_error_code: code,
        },
      );
      if (recordError !== null) {
        console.error("Notes attachment rehome failure could not be recorded.");
      }
      retried += 1;
    }
  }
  return { claimed: jobs.length, completed, retried };
}

async function processJob(client: SupabaseClient, job: RehomeJob): Promise<void> {
  const { data, error } = await client.rpc(
    "get_workspace_note_attachment_rehome_items",
    { p_job_id: job.id, p_lease_token: job.lease_token },
  );
  if (error !== null) throw new RehomeError("ITEMS_READ_FAILED");
  const items = parseItems(data, job);

  if (job.status === "copying") {
    for (const item of items) {
      const source = await downloadBytes(client, item.source_path, "SOURCE_READ_FAILED");
      await verifyPayload(source, item);
      const { error: uploadError } = await client.storage
        .from(bucket)
        .upload(item.target_path, source, {
          upsert: true,
          contentType: item.mime_type,
          metadata: {
            size: String(item.size_bytes),
            mimetype: item.mime_type,
          },
        });
      if (uploadError !== null) throw new RehomeError("TARGET_WRITE_FAILED");
      const target = await downloadBytes(client, item.target_path, "TARGET_READ_FAILED");
      await verifyPayload(target, item);
      const { error: verifyError } = await client.rpc(
        "mark_workspace_note_attachment_rehome_item_verified",
        {
          p_job_id: job.id,
          p_lease_token: job.lease_token,
          p_attachment_id: item.attachment_id,
          p_copied_sha256: item.expected_sha256,
        },
      );
      if (verifyError !== null) throw new RehomeError("TARGET_VERIFY_RECORD_FAILED");
    }

    const { error: commitError } = await client.rpc(
      "commit_workspace_note_attachment_rehome",
      { p_job_id: job.id, p_lease_token: job.lease_token },
    );
    if (commitError !== null) throw new RehomeError("METADATA_SWITCH_FAILED");
  }

  for (const item of items) {
    const target = await downloadBytes(client, item.target_path, "TARGET_READ_FAILED");
    await verifyPayload(target, item);
    const { error: removeError } = await client.storage
      .from(bucket)
      .remove([item.source_path]);
    if (removeError !== null) throw new RehomeError("SOURCE_CLEANUP_FAILED");
    const { error: markError } = await client.rpc(
      "mark_workspace_note_attachment_rehome_source_removed",
      {
        p_job_id: job.id,
        p_lease_token: job.lease_token,
        p_attachment_id: item.attachment_id,
      },
    );
    if (markError !== null) throw new RehomeError("SOURCE_CLEANUP_RECORD_FAILED");
  }

  const { error: completeError } = await client.rpc(
    "complete_workspace_note_attachment_rehome_cleanup",
    { p_job_id: job.id, p_lease_token: job.lease_token },
  );
  if (completeError !== null) throw new RehomeError("REHOME_FINALIZE_FAILED");
}

async function downloadBytes(
  client: SupabaseClient,
  path: string,
  errorCode: string,
): Promise<Uint8Array> {
  const { data, error } = await client.storage.from(bucket).download(path);
  if (error !== null || data === null) throw new RehomeError(errorCode);
  const bytes = new Uint8Array(await data.arrayBuffer());
  if (bytes.length > attachmentMaxBytes) throw new RehomeError("OBJECT_TOO_LARGE");
  return bytes;
}

async function verifyPayload(bytes: Uint8Array, item: RehomeItem): Promise<void> {
  const size = Number(item.size_bytes);
  if (!Number.isSafeInteger(size) || size < 1 || size > attachmentMaxBytes ||
      bytes.length !== size ||
      !attachmentSignatureMatches(bytes, item.mime_type) ||
      await sha256Hex(bytes) !== item.expected_sha256) {
    throw new RehomeError("OBJECT_VERIFICATION_FAILED");
  }
}

function parseJobs(value: unknown): RehomeJob[] {
  if (!Array.isArray(value)) throw new RehomeError("CLAIM_RESPONSE_INVALID");
  return value.map((candidate) => {
    if (typeof candidate !== "object" || candidate === null) {
      throw new RehomeError("CLAIM_RESPONSE_INVALID");
    }
    const row = candidate as Record<string, unknown>;
    if (typeof row.id !== "string" || typeof row.job_kind !== "string" ||
        typeof row.target_owner_user_id !== "string" ||
        typeof row.requested_by !== "string" ||
        typeof row.status !== "string" ||
        typeof row.lease_token !== "string" ||
        !["copying", "cleanup"].includes(row.status)) {
      throw new RehomeError("CLAIM_RESPONSE_INVALID");
    }
    return {
      id: row.id,
      job_kind: row.job_kind as RehomeJob["job_kind"],
      note_id: typeof row.note_id === "string" ? row.note_id : null,
      source_project_id: typeof row.source_project_id === "string"
        ? row.source_project_id
        : null,
      target_project_id: typeof row.target_project_id === "string"
        ? row.target_project_id
        : null,
      target_owner_user_id: row.target_owner_user_id,
      requested_by: row.requested_by,
      status: row.status as RehomeJob["status"],
      lease_token: row.lease_token,
    };
  });
}

function parseItems(value: unknown, job: RehomeJob): RehomeItem[] {
  if (!Array.isArray(value)) throw new RehomeError("ITEMS_RESPONSE_INVALID");
  return value.map((candidate) => {
    if (typeof candidate !== "object" || candidate === null) {
      throw new RehomeError("ITEMS_RESPONSE_INVALID");
    }
    const row = candidate as Record<string, unknown>;
    if (typeof row.attachment_id !== "string" ||
        typeof row.source_path !== "string" ||
        typeof row.target_path !== "string" ||
        typeof row.expected_sha256 !== "string" ||
        typeof row.mime_type !== "string" ||
        (typeof row.size_bytes !== "number" && typeof row.size_bytes !== "string")) {
      throw new RehomeError("ITEMS_RESPONSE_INVALID");
    }
    const expectedSource = attachmentPath(
      job.target_owner_user_id,
      job.source_project_id,
      row.attachment_id,
    );
    const expectedTarget = attachmentPath(
      job.target_owner_user_id,
      job.target_project_id,
      row.attachment_id,
    );
    if (row.source_path !== expectedSource || row.target_path !== expectedTarget) {
      throw new RehomeError("OBJECT_PATH_INVALID");
    }
    return {
      attachment_id: row.attachment_id,
      source_path: row.source_path,
      target_path: row.target_path,
      expected_sha256: row.expected_sha256,
      mime_type: row.mime_type,
      size_bytes: row.size_bytes,
    };
  });
}

function createServiceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")?.trim().replace(/\/+$/, "");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ??
    Deno.env.get("SUPABASE_SECRET_KEY")?.trim();
  if (url === undefined || url.length === 0 || key === undefined || key.length === 0) {
    throw new RehomeError("CONFIGURATION_ERROR");
  }
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function jsonResponse(
  payload: unknown,
  status: number,
  request: Request,
): Response {
  const origin = resolveAllowedOrigin(
    request.headers.get('origin'),
    Deno.env.get('ALLOWED_ORIGINS'),
  );
  const headers = new Headers({
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers":
      "authorization, apikey, content-type, x-client-info, x-notes-attachment-worker-secret",
  });
  if (origin !== null) {
    headers.set("access-control-allow-origin", origin);
    headers.set("vary", "Origin");
  }
  return new Response(payload === null ? null : JSON.stringify(payload), {
    status,
    headers,
  });
}
