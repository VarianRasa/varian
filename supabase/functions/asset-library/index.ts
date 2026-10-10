import {
  assertAuthenticatedJwt,
  AssetLibraryProxyError,
  buildOpenverseUrl,
  fetchOpenverseJson,
  resolveAllowedOrigin,
} from "./helpers.ts";

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 30;
const RATE_LIMIT_MAX_BUCKETS = 10_000;
type RateBucket = { startedAt: number; count: number };
const rateBuckets = new Map<string, RateBucket>();

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");
  const allowedOrigin = resolveAllowedOrigin(
    origin,
    Deno.env.get("ALLOWED_ORIGINS"),
  );

  try {
    if (origin !== null && allowedOrigin === null) {
      throw new AssetLibraryProxyError(403, "Origin is not allowed.");
    }
    if (request.method === "OPTIONS") {
      return response(null, 204, allowedOrigin, {}, allowedOrigin !== null);
    }
    if (request.method !== "GET") {
      throw new AssetLibraryProxyError(405, "Method not allowed.");
    }
    // The gateway verifies the JWT because config.toml enables verify_jwt;
    // this also rejects the public anon role before the upstream is contacted.
    assertAuthenticatedJwt(request.headers.get("authorization") ?? "");
    enforceRateLimit(request);

    const upstream = buildOpenverseUrl(new URL(request.url));
    const result = await fetchOpenverseJson(upstream);
    return response(
      result.body as unknown as BodyInit,
      200,
      allowedOrigin,
      {
        "content-type": result.contentType,
        "cache-control": "private, max-age=60",
      },
      allowedOrigin !== null,
    );
  } catch (error) {
    const status = error instanceof AssetLibraryProxyError ? error.status : 500;
    const message = error instanceof AssetLibraryProxyError
      ? error.message
      : "Asset provider is unavailable.";
    return response(
      JSON.stringify({ error: message }),
      status,
      allowedOrigin,
      { "content-type": "application/json; charset=utf-8" },
      allowedOrigin !== null,
    );
  }
});

function response(
  body: BodyInit | null,
  status: number,
  origin: string | null,
  extra: Record<string, string> = {},
  allowCors = true,
): Response {
  const headers = new Headers({
    "cache-control": "no-store",
    ...extra,
  });
  if (allowCors) {
    headers.set("access-control-allow-origin", origin ?? "*");
    if (origin !== null && origin !== "*") headers.set("vary", "Origin");
  }
  headers.set("access-control-allow-methods", "GET, OPTIONS");
  headers.set(
    "access-control-allow-headers",
    "authorization, apikey, content-type, x-client-info",
  );
  if (!(body instanceof Uint8Array) && !headers.has("content-type")) {
    headers.set("content-type", "application/json; charset=utf-8");
  }
  return new Response(body, { status, headers });
}

function enforceRateLimit(request: Request): void {
  // CF-Connecting-IP is assigned by Cloudflare. Do not trust client-supplied
  // forwarding or Origin headers as rate-limit identities.
  const address = request.headers.get("cf-connecting-ip")?.trim() ||
    "anonymous";
  const now = Date.now();
  const bucket = rateBuckets.get(address);
  if (bucket === undefined || now - bucket.startedAt >= RATE_LIMIT_WINDOW_MS) {
    if (bucket === undefined && rateBuckets.size >= RATE_LIMIT_MAX_BUCKETS) {
      for (const [key, value] of rateBuckets) {
        if (now - value.startedAt >= RATE_LIMIT_WINDOW_MS) {
          rateBuckets.delete(key);
        }
      }
      if (rateBuckets.size >= RATE_LIMIT_MAX_BUCKETS) {
        throw new AssetLibraryProxyError(429, "Too many requests.");
      }
    }
    rateBuckets.set(address, { startedAt: now, count: 1 });
    return;
  }
  bucket.count += 1;
  if (bucket.count > RATE_LIMIT_MAX) {
    throw new AssetLibraryProxyError(429, "Too many requests.");
  }
}
