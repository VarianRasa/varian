import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  isAuthorized,
  jsonResponse,
  maxBodyBytes,
  normalizeProjectId,
} from "./helpers.ts";

class HttpError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") return jsonResponse(null, 204);
    if (request.method !== "POST") {
      throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST requests are supported.");
    }

    const secret = Deno.env.get("RETENTION_JOB_SECRET")?.trim() ?? "";
    if (!isAuthorized(request, secret)) {
      throw new HttpError(401, "INVALID_SECRET", "Retention job secret is invalid.");
    }

    const body = await readJson(request);
    const projectId = normalizeProjectId(body.projectId);
    const supabase = createServiceClient();
    const { data, error } = await supabase.rpc("run_workspace_retention_maintenance", {
      p_project_id: projectId,
    });
    if (error !== null || typeof data !== "object" || data === null) {
      throw new HttpError(502, "BACKEND_ERROR", "Retention maintenance failed.");
    }
    return jsonResponse(data, 200);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: { code: error.code, message: error.message } }, error.status);
    }
    if (error instanceof Error && error.message.startsWith("Project ID")) {
      return jsonResponse({ error: { code: "INVALID_PAYLOAD", message: error.message } }, 400);
    }
    return jsonResponse(
      { error: { code: "INTERNAL_ERROR", message: "Retention maintenance is unavailable." } },
      500,
    );
  }
});

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const body = request.body;
  if (body === null) throw new HttpError(400, "INVALID_JSON", "Request body is required.");
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      total += result.value.byteLength;
      if (total > maxBodyBytes) {
        throw new HttpError(413, "PAYLOAD_TOO_LARGE", "Request body is too large.");
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
  try {
    const parsed = JSON.parse(new TextDecoder().decode(bytes));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      throw new Error("Request body must be an object.");
    }
    return parsed as Record<string, unknown>;
  } catch (_) {
    throw new HttpError(400, "INVALID_JSON", "Request body is invalid JSON.");
  }
}

function createServiceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")?.trim().replace(/\/+$/, "");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ??
    Deno.env.get("SUPABASE_SECRET_KEY")?.trim();
  if (!url || !key) {
    throw new HttpError(500, "CONFIGURATION_ERROR", "Retention backend is not configured.");
  }
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
