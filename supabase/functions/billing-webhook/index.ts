import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import {
  normalizeBillingWebhook,
  verifyWebhookSignature,
} from "./helpers.ts";

const maxBodyBytes = 256 * 1024;

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
    if (request.method === "OPTIONS") {
      return jsonResponse(null, 204);
    }
    if (request.method !== "POST") {
      throw new HttpError(405, "METHOD_NOT_ALLOWED", "Only POST requests are supported.");
    }

    const secret = Deno.env.get("BILLING_WEBHOOK_SECRET")?.trim() ?? "";
    if (secret.length < 16) {
      throw new HttpError(500, "CONFIGURATION_ERROR", "Billing webhook is not configured.");
    }
    const bodyBytes = await readLimitedBody(request.body, maxBodyBytes);
    const rawBody = new TextDecoder().decode(bodyBytes);
    const verified = await verifyWebhookSignature({
      secret,
      timestamp: request.headers.get("x-billing-timestamp"),
      rawBody,
      signatureHeader: request.headers.get("x-billing-signature"),
    });
    if (!verified) {
      throw new HttpError(401, "INVALID_SIGNATURE", "Billing webhook signature is invalid.");
    }

    let body: unknown;
    try {
      body = JSON.parse(rawBody);
    } catch (_) {
      throw new HttpError(400, "INVALID_JSON", "Billing webhook payload is invalid.");
    }
    const event = normalizeBillingWebhook(
      body,
      Deno.env.get("BILLING_PROVIDER")?.trim() || "generic",
    );
    const supabase = createServiceClient();
    const { data, error } = await supabase.rpc("apply_workspace_billing_webhook", {
      p_provider: event.provider,
      p_event_id: event.eventId,
      p_event_type: event.eventType,
      p_project_id: event.projectId,
      p_plan_id: event.planId,
      p_status: event.status,
      p_revision: event.revision,
      p_limits: event.limits,
      p_overage_policy: event.overagePolicy,
      p_grace_until: event.graceUntil,
      p_external_customer_id: event.externalCustomerId,
      p_external_subscription_id: event.externalSubscriptionId,
      p_payload: event.payload,
      p_signature_hash: await signatureDigest(
        request.headers.get("x-billing-signature"),
      ),
    });
    if (error !== null || typeof data !== "object" || data === null) {
      throw new HttpError(502, "BACKEND_ERROR", "Billing entitlement update failed.");
    }
    return jsonResponse(data, 200);
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: { code: error.code, message: error.message } }, error.status);
    }
    if (error instanceof Error && error.message.startsWith("Webhook")) {
      return jsonResponse({ error: { code: "INVALID_PAYLOAD", message: error.message } }, 400);
    }
    if (error instanceof Error && error.message.startsWith("Invalid entitlement")) {
      return jsonResponse({ error: { code: "INVALID_PAYLOAD", message: error.message } }, 400);
    }
    return jsonResponse(
      { error: { code: "INTERNAL_ERROR", message: "Billing webhook is unavailable." } },
      500,
    );
  }
});

function createServiceClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")?.trim().replace(/\/+$/, "");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ??
    Deno.env.get("SUPABASE_SECRET_KEY")?.trim();
  if (url === undefined || url.length === 0 || serviceRoleKey === undefined || serviceRoleKey.length === 0) {
    throw new HttpError(500, "CONFIGURATION_ERROR", "Billing backend is not configured.");
  }
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function readLimitedBody(
  body: ReadableStream<Uint8Array> | null,
  maxBytes: number,
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
        throw new HttpError(413, "PAYLOAD_TOO_LARGE", "Billing webhook payload is too large.");
      }
      chunks.push(result.value);
    }
  } finally {
    reader.releaseLock();
  }
  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

async function signatureDigest(signatureHeader: string | null): Promise<string | null> {
  if (signatureHeader === null || signatureHeader.trim().length === 0) return null;
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(signatureHeader.trim()),
  );
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, "0")).join("");
}

function jsonResponse(payload: unknown, status: number): Response {
  return new Response(payload === null ? null : JSON.stringify(payload), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}
