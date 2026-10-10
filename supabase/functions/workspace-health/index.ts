import {
  buildHealthPayload,
  buildPublicHealthPayload,
  type HealthCheck,
} from "./helpers.ts";

const probeTimeoutMs = 5_000;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: { "cache-control": "no-store" },
    });
  }
  if (request.method !== "GET") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const version = Deno.env.get("APP_VERSION")?.trim() || "unknown";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim().replace(/\/+$/, "");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  const checks: HealthCheck[] = [];

  if (!supabaseUrl || !anonKey) {
    checks.push({
      name: "configuration",
      status: "unhealthy",
      message: "Supabase health configuration is incomplete",
      latencyMs: 0,
    });
  } else {
    checks.push(
      await probe(
        "auth",
        `${supabaseUrl}/auth/v1/settings`,
        { apikey: anonKey, authorization: `Bearer ${anonKey}` },
      ),
    );
    if (!serviceRoleKey) {
      checks.push({
        name: "database",
        status: "degraded",
        message: "Service role probe is not configured",
        latencyMs: 0,
      });
    } else {
      checks.push(
        await probe(
          "database",
          `${supabaseUrl}/rest/v1/workspace_release_policies?select=project_id&limit=1`,
          {
            apikey: serviceRoleKey,
            authorization: `Bearer ${serviceRoleKey}`,
          },
        ),
      );
    }
  }

  const payload = buildHealthPayload(version, checks);
  const publicPayload = buildPublicHealthPayload(payload.status, version);
  return jsonResponse(publicPayload, payload.status === "healthy" ? 200 : 503);
});

async function probe(
  name: string,
  url: string,
  headers: Record<string, string>,
): Promise<HealthCheck> {
  const startedAt = performance.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), probeTimeoutMs);
  try {
    const response = await fetch(url, {
      method: "GET",
      headers,
      signal: controller.signal,
    });
    return {
      name,
      status: response.ok ? "healthy" : "unhealthy",
      message: response.ok ? "ok" : `upstream returned ${response.status}`,
      latencyMs: Math.max(0, Math.round(performance.now() - startedAt)),
    };
  } catch (_) {
    return {
      name,
      status: "unhealthy",
      message: "upstream probe failed",
      latencyMs: Math.max(0, Math.round(performance.now() - startedAt)),
    };
  } finally {
    clearTimeout(timeout);
  }
}

function jsonResponse(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}
