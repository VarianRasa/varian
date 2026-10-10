export const OPENVERSE_HOST = "api.openverse.org";
export const MAX_QUERY_LENGTH = 200;
export const MAX_PAGE = 10_000;
export const MAX_PAGE_SIZE = 100;
export const DEFAULT_PAGE_SIZE = 24;
export const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
export const MAX_REDIRECTS = 3;
export const FETCH_TIMEOUT_MS = 8_000;

type ProviderKind = "images" | "audio";

export class AssetLibraryProxyError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "AssetLibraryProxyError";
    this.status = status;
  }
}

/**
 * Requires a gateway-validated user JWT rather than the public anon key.
 * Supabase's gateway performs signature and expiry verification; this local
 * claim check prevents the public anon role from using the proxy directly.
 */
export function assertAuthenticatedJwt(authorization: string): void {
  if (
    authorization.length > 4096 ||
    !/^Bearer\s+[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/i.test(
      authorization,
    )
  ) {
    throw new AssetLibraryProxyError(401, "Authentication required.");
  }

  const token = authorization.replace(/^Bearer\s+/i, "");
  const payload = decodeJwtPayload(token);
  const subject = payload?.sub;
  if (
    payload?.role !== "authenticated" ||
    typeof subject !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(subject)
  ) {
    throw new AssetLibraryProxyError(401, "Authentication required.");
  }
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const encoded = token.split(".")[1];
  if (encoded === undefined || encoded.length > 3072) return null;
  try {
    const base64 = encoded.replace(/-/g, "+").replace(/_/g, "/");
    const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, "=");
    const bytes = Uint8Array.from(
      atob(padded),
      (character) => character.charCodeAt(0),
    );
    const decoded: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (
      typeof decoded !== "object" || decoded === null ||
      Array.isArray(decoded)
    ) return null;
    return decoded as Record<string, unknown>;
  } catch (_) {
    return null;
  }
}

/**
 * Builds an upstream URL from the fixed route and a small, explicit query
 * contract. User input never controls the upstream origin or path.
 */
export function buildOpenverseUrl(requestUrl: URL): URL {
  const kind = providerKindFromPath(requestUrl.pathname) ??
    providerKind(requestUrl.searchParams.get("kind"));
  if (kind === null) {
    throw new AssetLibraryProxyError(404, "Unknown asset provider route.");
  }

  const rawQuery = requestUrl.searchParams.get("q");
  if (rawQuery !== null && hasControlCharacter(rawQuery)) {
    throw new AssetLibraryProxyError(400, "Search query is invalid.");
  }
  const query = rawQuery?.trim() ?? "";
  if (query.length > MAX_QUERY_LENGTH || hasControlCharacter(query)) {
    throw new AssetLibraryProxyError(400, "Search query is invalid.");
  }

  const page = positiveInteger(
    requestUrl.searchParams.get("page"),
    1,
    MAX_PAGE,
    "page",
  );
  const pageSize = positiveInteger(
    requestUrl.searchParams.get("page_size"),
    DEFAULT_PAGE_SIZE,
    MAX_PAGE_SIZE,
    "page_size",
  );

  const upstream = new URL(`https://${OPENVERSE_HOST}/v1/${kind}/`);
  upstream.searchParams.set("q", query);
  upstream.searchParams.set("page", String(page));
  upstream.searchParams.set("page_size", String(pageSize));
  assertAllowedOpenverseUrl(upstream);
  return upstream;
}

/** Rejects every host/path except the Openverse API search endpoints. */
export function assertAllowedOpenverseUrl(url: URL): void {
  if (
    url.protocol !== "https:" ||
    url.hostname.toLowerCase() !== OPENVERSE_HOST ||
    url.username.length > 0 ||
    url.password.length > 0 ||
    (url.port !== "" && url.port !== "443") ||
    url.hash.length > 0 ||
    !["/v1/images/", "/v1/audio/"].includes(url.pathname)
  ) {
    throw new AssetLibraryProxyError(502, "Provider redirect is not allowed.");
  }

  const allowedParams = new Set(["q", "page", "page_size"]);
  for (const key of url.searchParams.keys()) {
    if (!allowedParams.has(key) || url.searchParams.getAll(key).length !== 1) {
      throw new AssetLibraryProxyError(502, "Provider request is not allowed.");
    }
  }
  const query = url.searchParams.get("q");
  if (
    query === null ||
    query.length > MAX_QUERY_LENGTH ||
    hasControlCharacter(query)
  ) {
    throw new AssetLibraryProxyError(502, "Provider request is not allowed.");
  }
  if (
    url.searchParams.get("page") === null ||
    url.searchParams.get("page_size") === null
  ) {
    throw new AssetLibraryProxyError(502, "Provider request is not allowed.");
  }
  positiveInteger(url.searchParams.get("page"), 1, MAX_PAGE, "page");
  positiveInteger(
    url.searchParams.get("page_size"),
    DEFAULT_PAGE_SIZE,
    MAX_PAGE_SIZE,
    "page_size",
  );
}

export async function fetchOpenverseJson(
  source: URL,
  fetcher: typeof fetch = fetch,
): Promise<{ body: Uint8Array; contentType: string; finalUrl: URL }> {
  assertAllowedOpenverseUrl(source);
  let current = new URL(source.toString());
  const expectedPath = current.pathname;
  const deadline = Date.now() + FETCH_TIMEOUT_MS;

  for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects += 1) {
    if (current.pathname !== expectedPath) {
      throw new AssetLibraryProxyError(
        502,
        "Provider redirect is not allowed.",
      );
    }
    assertAllowedOpenverseUrl(current);
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      throw new AssetLibraryProxyError(502, "Provider timed out.");
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), remaining);
    let response: Response;
    try {
      response = await fetcher(current, {
        method: "GET",
        redirect: "manual",
        signal: controller.signal,
        headers: {
          accept: "application/json",
          "user-agent": "Varian Asset Library/1.0",
        },
      });

      if (response.status >= 300 && response.status < 400) {
        await cancelBody(response);
        if (redirects === MAX_REDIRECTS) {
          throw new AssetLibraryProxyError(502, "Too many provider redirects.");
        }
        const location = response.headers.get("location");
        if (
          location === null || location.trim().length === 0 ||
          location.trim() !== location || hasControlCharacter(location)
        ) {
          throw new AssetLibraryProxyError(
            502,
            "Provider redirect is invalid.",
          );
        }
        try {
          current = new URL(location, current);
        } catch (_) {
          throw new AssetLibraryProxyError(
            502,
            "Provider redirect is invalid.",
          );
        }
        continue;
      }

      if (response.status < 200 || response.status >= 300) {
        await cancelBody(response);
        throw new AssetLibraryProxyError(502, "Provider returned an error.");
      }

      const contentType = response.headers.get("content-type")?.toLowerCase() ??
        "";
      if (!contentType.includes("json")) {
        await cancelBody(response);
        throw new AssetLibraryProxyError(
          502,
          "Provider returned an invalid response.",
        );
      }
      const declaredLength = Number(
        response.headers.get("content-length") ?? "",
      );
      if (
        Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES
      ) {
        await cancelBody(response);
        throw new AssetLibraryProxyError(
          502,
          "Provider response is too large.",
        );
      }

      // Keep the abort signal alive while consuming the body as well as while
      // establishing the connection; an upstream can otherwise stall a stream
      // after fetch() has already resolved.
      const bytes = await readLimitedBytes(
        response.body,
        MAX_RESPONSE_BYTES,
        controller.signal,
      );
      validateOpenverseResponse(bytes);
      return {
        body: bytes,
        contentType: "application/json; charset=utf-8",
        finalUrl: current,
      };
    } catch (error) {
      if (error instanceof AssetLibraryProxyError) throw error;
      if (controller.signal.aborted) {
        throw new AssetLibraryProxyError(502, "Provider timed out.");
      }
      throw new AssetLibraryProxyError(502, "Provider is unavailable.");
    } finally {
      clearTimeout(timeout);
    }
  }

  throw new AssetLibraryProxyError(502, "Too many provider redirects.");
}

export function validateOpenverseResponse(
  body: Uint8Array,
): void {
  let decoded: unknown;
  try {
    decoded = JSON.parse(new TextDecoder().decode(body));
  } catch (_) {
    throw new AssetLibraryProxyError(502, "Provider returned invalid JSON.");
  }
  if (
    typeof decoded !== "object" || decoded === null || Array.isArray(decoded)
  ) {
    throw new AssetLibraryProxyError(502, "Provider response is invalid.");
  }
  const payload = decoded as Record<string, unknown>;
  if (
    !Array.isArray(payload.results) || payload.results.length > MAX_PAGE_SIZE
  ) {
    throw new AssetLibraryProxyError(502, "Provider response is invalid.");
  }
  for (const result of payload.results) {
    if (
      typeof result !== "object" || result === null || Array.isArray(result)
    ) {
      throw new AssetLibraryProxyError(502, "Provider response is invalid.");
    }
    const record = result as Record<string, unknown>;
    for (
      const field of [
        "id",
        "foreign_identifier",
        "title",
        "creator",
        "license",
        "license_version",
        "mimetype",
        "mime_type",
      ]
    ) {
      const value = record[field];
      if (
        value !== undefined && value !== null &&
        (typeof value !== "string" || value.length > 4096 ||
          hasControlCharacter(value))
      ) {
        throw new AssetLibraryProxyError(502, "Provider response is invalid.");
      }
    }
    for (
      const field of [
        "url",
        "thumbnail",
        "foreign_landing_url",
        "creator_url",
        "license_url",
      ]
    ) {
      const value = record[field];
      if (value === undefined || value === null) continue;
      if (
        typeof value !== "string" || value.length > 8192 ||
        value.trim() !== value || hasControlCharacter(value)
      ) {
        throw new AssetLibraryProxyError(502, "Provider response is invalid.");
      }
      try {
        const url = new URL(value);
        if (
          url.protocol !== "https:" || url.hostname.length === 0 ||
          url.username.length > 0 || url.password.length > 0
        ) {
          throw new Error("unsafe URL");
        }
      } catch (_) {
        throw new AssetLibraryProxyError(502, "Provider response is invalid.");
      }
    }
  }
  for (const field of ["page", "page_count"]) {
    const value = payload[field];
    const minimum = field === "page_count" ? 0 : 1;
    if (
      value !== undefined && value !== null &&
      (typeof value !== "number" || !Number.isSafeInteger(value) ||
        value < minimum || value > MAX_PAGE)
    ) {
      throw new AssetLibraryProxyError(502, "Provider response is invalid.");
    }
  }
}

export function providerKindFromPath(pathname: string): ProviderKind | null {
  const normalized = pathname.replace(/\/+$/, "");
  const lastSegment = normalized.slice(normalized.lastIndexOf("/") + 1)
    .toLowerCase();
  return lastSegment === "images" || lastSegment === "audio"
    ? lastSegment
    : null;
}

export function providerKind(value: string | null): ProviderKind | null {
  if (value !== null && hasControlCharacter(value)) return null;
  const normalized = value?.trim().toLowerCase();
  return normalized === "images" || normalized === "audio" ? normalized : null;
}

export function resolveAllowedOrigin(
  origin: string | null,
  configured: string | undefined,
): string | null {
  const allowed = (configured ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (allowed.length === 0) return "*";
  if (origin !== null && allowed.includes(origin)) return origin;
  return null;
}

export async function readLimitedBytes(
  body: ReadableStream<Uint8Array> | null,
  maxBytes: number,
  signal?: AbortSignal,
): Promise<Uint8Array> {
  if (signal?.aborted) {
    throw new AssetLibraryProxyError(502, "Provider timed out.");
  }
  if (body === null) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const result = await readChunk(reader, signal);
      if (result.done) {
        if (signal?.aborted) {
          throw new AssetLibraryProxyError(502, "Provider timed out.");
        }
        break;
      }
      length += result.value.byteLength;
      if (length > maxBytes) {
        await reader.cancel();
        throw new AssetLibraryProxyError(
          502,
          "Provider response is too large.",
        );
      }
      chunks.push(result.value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function readChunk(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  signal?: AbortSignal,
): Promise<ReadableStreamReadResult<Uint8Array>> {
  if (signal === undefined) return reader.read();
  if (signal.aborted) {
    throw new AssetLibraryProxyError(502, "Provider timed out.");
  }
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = () => signal.removeEventListener("abort", onAbort);
    const onAbort = () => {
      if (settled) return;
      settled = true;
      finish();
      void reader.cancel().catch(() => {});
      reject(new AssetLibraryProxyError(502, "Provider timed out."));
    };
    signal.addEventListener("abort", onAbort, { once: true });
    reader.read().then(
      (value) => {
        if (settled) return;
        settled = true;
        finish();
        resolve(value);
      },
      (error) => {
        if (settled) return;
        settled = true;
        finish();
        reject(error);
      },
    );
  });
}

function positiveInteger(
  raw: string | null,
  fallback: number,
  maximum: number,
  field: string,
): number {
  if (raw !== null && hasControlCharacter(raw)) {
    throw new AssetLibraryProxyError(400, `${field} is invalid.`);
  }
  if (raw === null || raw.trim().length === 0) return fallback;
  const normalized = raw.trim();
  if (!/^\d+$/.test(normalized)) {
    throw new AssetLibraryProxyError(400, `${field} is invalid.`);
  }
  const value = Number(normalized);
  if (!Number.isSafeInteger(value) || value < 1 || value > maximum) {
    throw new AssetLibraryProxyError(400, `${field} is invalid.`);
  }
  return value;
}

function hasControlCharacter(value: string): boolean {
  return Array.from(value).some((character) => {
    const code = character.charCodeAt(0);
    return code < 0x20 || code === 0x7f;
  });
}

async function cancelBody(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch (_) {
    // The upstream response is already being discarded.
  }
}
