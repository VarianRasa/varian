import { resolveAllowedOrigin } from "./cors.ts";
type PreviewDependencies = {
  fetcher: typeof fetch;
  resolveDns: (hostname: string, type: "A" | "AAAA") => Promise<string[]>;
};

const defaultDependencies: PreviewDependencies = {
  fetcher: fetch,
  resolveDns: (hostname, type) => Deno.resolveDns(hostname, type),
};
let dependencies = defaultDependencies;

export function setLinkPreviewDependenciesForTests(
  overrides: Partial<PreviewDependencies> | null,
) {
  dependencies = overrides === null
    ? defaultDependencies
    : { ...defaultDependencies, ...overrides };
}
const MAX_REQUEST_BYTES = 16 * 1024;

const MAX_RESPONSE_BYTES = 1024 * 1024;
const MAX_REDIRECTS = 3;
const FETCH_TIMEOUT_MS = 8_000;
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 30;

type RateBucket = {
  startedAt: number;
  count: number;
};

const rateBuckets = new Map<string, RateBucket>();

class HttpError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.name = "HttpError";
    this.status = status;
  }
}

export async function handleLinkPreview(request: Request): Promise<Response> {
  const origin = request.headers.get("origin");
  try {
    const allowedOrigin = resolveAllowedOrigin(
      origin,
      Deno.env.get("ALLOWED_ORIGINS"),
    );
    if (origin !== null && allowedOrigin === null) {
      throw new HttpError(403, "Origin tidak diizinkan.");
    }
    if (request.method === "OPTIONS") {
      return createResponse(null, 204, allowedOrigin);
    }
    if (request.method !== "POST" && request.method !== "GET") {
      throw new HttpError(405, "Metode tidak didukung.");
    }
    enforceRateLimit(request);
    if (request.method === "GET") {
      return await handleAsset(request, allowedOrigin);
    }
    return await handlePreview(request, allowedOrigin);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof HttpError
      ? error.message
      : "Preview tidak dapat dimuat.";
    const errorOrigin = resolveAllowedOrigin(
      origin,
      Deno.env.get("ALLOWED_ORIGINS"),
    );
    return createResponse(
      JSON.stringify({ error: message }),
      status,
      errorOrigin,
      {},
      origin === null || errorOrigin !== null,
    );
  }
}

if (import.meta.main) Deno.serve(handleLinkPreview);

async function handlePreview(request: Request, origin: string | null) {
  const body = await readRequestBody(request);
  let input: unknown;
  try {
    input = JSON.parse(body);
  } catch (_) {
    throw new HttpError(400, "Payload tidak valid.");
  }
  if (typeof input !== "object" || input === null || !("url" in input)) {
    throw new HttpError(400, "URL wajib diisi.");
  }
  const source = normalizeUrl((input as { url?: unknown }).url);
  const fetched = await fetchWithRedirects(source);
  const contentType = getContentType(fetched.response);
  if (!isHtml(contentType)) {
    await fetched.response.body?.cancel();
    clearTimeout(fetched.timeout);
    return createResponse(
      JSON.stringify({
        url: source.toString(),
        finalUrl: fetched.url.toString(),
        mediaType: mediaTypeFor(contentType),
        title: fileTitle(fetched.url),
        siteName: fetched.url.hostname,
        imageUrl: contentType.startsWith("image/")
          ? assetUrl(request, fetched.url)
          : null,
        faviconUrl: null,
      }),
      200,
      origin,
    );
  }

  let html: string;
  try {
    html = await readResponseText(fetched.response, fetched.controller.signal);
  } finally {
    clearTimeout(fetched.timeout);
  }
  const metadata = parseHtml(html, fetched.url);
  return createResponse(
    JSON.stringify({
      url: source.toString(),
      finalUrl: fetched.url.toString(),
      mediaType: "webpage",
      title: metadata.title,
      description: metadata.description,
      siteName: metadata.siteName,
      imageUrl: metadata.imageUrl === null
        ? null
        : assetUrl(request, metadata.imageUrl),
      faviconUrl: metadata.faviconUrl === null
        ? null
        : assetUrl(request, metadata.faviconUrl),
    }),
    200,
    origin,
  );
}

async function handleAsset(request: Request, origin: string | null) {
  const source = new URL(request.url).searchParams.get("asset");
  if (source === null || source.trim().length === 0) {
    throw new HttpError(400, "Asset tidak ditemukan.");
  }
  const fetched = await fetchWithRedirects(normalizeUrl(source));
  try {
    const contentType = getContentType(fetched.response);
    if (!contentType.startsWith("image/")) {
      await fetched.response.body?.cancel();
      throw new HttpError(415, "Asset bukan gambar.");
    }
    const bytes = await readResponseBytes(
      fetched.response,
      fetched.controller.signal,
    );
    return createResponse(bytes, 200, origin, {
      "content-type": contentType.split(";", 1)[0] ||
        "application/octet-stream",
      "cache-control": "public, max-age=3600",
    });
  } finally {
    clearTimeout(fetched.timeout);
  }
}

async function fetchWithRedirects(source: URL) {
  let current = new URL(source.toString());
  for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects += 1) {
    await assertSafeUrl(current);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    let upstream: Response;
    try {
      upstream = await dependencies.fetcher(current, {
        redirect: "manual",
        signal: controller.signal,
        headers: {
          accept: "text/html,application/xhtml+xml,image/*,*/*;q=0.8",
          "user-agent": "Varian Link Preview/1.0",
        },
      });
    } catch {
      clearTimeout(timeout);
      throw new HttpError(502, "Situs tujuan tidak dapat diakses.");
    }

    if (upstream.status >= 300 && upstream.status < 400) {
      if (redirects === MAX_REDIRECTS) {
        clearTimeout(timeout);
        await upstream.body?.cancel();
        throw new HttpError(502, "Terlalu banyak pengalihan.");
      }
      const location = upstream.headers.get("location");
      clearTimeout(timeout);
      await upstream.body?.cancel();
      if (location === null) {
        throw new HttpError(502, "Pengalihan tidak valid.");
      }
      try {
        current = new URL(location, current);
      } catch {
        throw new HttpError(502, "Pengalihan tidak valid.");
      }
      continue;
    }
    if (upstream.status < 200 || upstream.status >= 300) {
      clearTimeout(timeout);
      await upstream.body?.cancel();
      throw new HttpError(502, `Situs tujuan merespons ${upstream.status}.`);
    }
    return { response: upstream, url: current, timeout, controller };
  }
  throw new HttpError(502, "Terlalu banyak pengalihan.");
}

async function assertSafeUrl(url: URL) {
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new HttpError(400, "Hanya URL HTTP atau HTTPS yang didukung.");
  }
  if (url.username || url.password || url.hostname.length === 0) {
    throw new HttpError(400, "URL tidak valid.");
  }
  const hostname = url.hostname.toLowerCase().replace(/\.$/, "");
  if (hostname === "localhost" || hostname.endsWith(".localhost")) {
    throw new HttpError(400, "Alamat lokal tidak didukung.");
  }
  if (url.port && !["80", "443"].includes(url.port)) {
    throw new HttpError(400, "Port tujuan tidak didukung.");
  }
  if (isPrivateIp(hostname)) {
    throw new HttpError(400, "Tujuan jaringan tidak aman.");
  }
  if (isIpLiteral(hostname)) return;

  const records: string[] = [];
  for (const type of ["A", "AAAA"] as const) {
    try {
      const answers = await dependencies.resolveDns(hostname, type);
      records.push(...answers);
    } catch {
      // Missing records for one address family are acceptable only if another family resolves.
    }
  }
  if (records.length === 0 || records.some(isPrivateIp)) {
    throw new HttpError(400, "Tujuan jaringan tidak aman.");
  }
}

function normalizeUrl(value: unknown) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, "URL wajib diisi.");
  }
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch (_) {
    throw new HttpError(400, "URL tidak valid.");
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new HttpError(400, "Hanya URL HTTP atau HTTPS yang didukung.");
  }
  if (url.username || url.password || url.hostname.length === 0) {
    throw new HttpError(400, "URL tidak valid.");
  }
  return url;
}

function parseHtml(html: string, finalUrl: URL) {
  const metas = new Map<string, string>();
  for (const match of html.matchAll(/<meta\b[^>]*>/gi)) {
    const attributes = attributesOf(match[0]);
    const key = (attributes.property ?? attributes.name)?.toLowerCase();
    const value = attributes.content?.trim();
    if (
      key !== undefined && value !== undefined && value.length > 0 &&
      !metas.has(key)
    ) {
      metas.set(key, clean(value));
    }
  }
  const titleTag = html.match(/<title\b[^>]*>([\s\S]*?)<\/title\s*>/i)?.[1];
  const title = firstText([
    metas.get("og:title"),
    titleTag === undefined ? null : clean(titleTag),
    finalUrl.hostname,
  ]);
  const description = firstOptionalText([
    metas.get("og:description"),
    metas.get("description"),
  ]);
  const siteName = firstText([metas.get("og:site_name"), finalUrl.hostname]);
  let faviconUrl: URL | null = null;
  for (const match of html.matchAll(/<link\b[^>]*>/gi)) {
    const attributes = attributesOf(match[0]);
    const rel = attributes.rel?.toLowerCase().split(/\s+/) ?? [];
    if (rel.includes("icon") || rel.includes("shortcut")) {
      faviconUrl = resolveHttpUrl(attributes.href, finalUrl);
      if (faviconUrl !== null) break;
    }
  }
  faviconUrl ??= new URL("/favicon.ico", finalUrl);
  const imageUrl = resolveHttpUrl(
    metas.get("og:image") ?? metas.get("twitter:image"),
    finalUrl,
  );
  return { title, description, siteName, faviconUrl, imageUrl };
}

function attributesOf(tag: string) {
  const result: Record<string, string> = {};
  for (
    const match of tag.matchAll(
      /([:\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/gi,
    )
  ) {
    result[match[1].toLowerCase()] = match[2] ?? match[3] ?? match[4] ?? "";
  }
  return result;
}

function resolveHttpUrl(value: string | undefined, base: URL) {
  if (value === undefined || value.trim().length === 0) return null;
  try {
    const resolved = new URL(decodeHtml(value.trim()), base);
    return resolved.protocol === "http:" || resolved.protocol === "https:"
      ? resolved
      : null;
  } catch (_) {
    return null;
  }
}

function clean(value: string) {
  return decodeHtml(value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim());
}

function decodeHtml(value: string) {
  return value.replace(
    /&(#x[0-9a-f]+|#\d+|amp|quot|apos|lt|gt);/gi,
    (match, entity: string) => {
      const normalized = entity.toLowerCase();
      if (normalized.startsWith("#x")) {
        return String.fromCodePoint(parseInt(normalized.slice(2), 16));
      }
      if (normalized.startsWith("#")) {
        return String.fromCodePoint(parseInt(normalized.slice(1), 10));
      }
      return {
        amp: "&",
        quot: '"',
        apos: "'",
        lt: "<",
        gt: ">",
      }[normalized as "amp" | "quot" | "apos" | "lt" | "gt"] ?? match;
    },
  );
}

function firstText(values: Array<string | null | undefined>) {
  return values.find((value) =>
    value !== null && value !== undefined && value.trim().length > 0
  )?.trim() ?? "";
}

function firstOptionalText(values: Array<string | null | undefined>) {
  const value = firstText(values);
  return value.length > 0 ? value : null;
}

function mediaTypeFor(contentType: string) {
  if (contentType.startsWith("image/")) return "image";
  if (contentType.startsWith("video/")) return "video";
  if (contentType.startsWith("audio/")) return "audio";
  if (contentType.startsWith("application/pdf")) return "pdf";
  return "file";
}

function fileTitle(url: URL) {
  const segments = url.pathname.split("/").filter(Boolean);
  return segments.length > 0 ? segments[segments.length - 1] : url.hostname;
}

function isHtml(contentType: string) {
  return contentType.includes("text/html") ||
    contentType.includes("application/xhtml+xml");
}

function getContentType(response: Response) {
  return response.headers.get("content-type")?.toLowerCase() ?? "";
}

function assetUrl(request: Request, source: URL) {
  const configuredBase = Deno.env.get("SUPABASE_URL");
  const url = configuredBase === undefined
    ? new URL(request.url)
    : new URL(configuredBase);
  url.protocol = "https:";
  url.pathname = "/functions/v1/link-preview";
  url.search = "";
  url.searchParams.set("asset", source.toString());
  return url.toString();
}

async function readRequestBody(request: Request) {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(length) && length > MAX_REQUEST_BYTES) {
    throw new HttpError(413, "Payload terlalu besar.");
  }
  return new TextDecoder().decode(
    await readLimitedBytes(request.body, MAX_REQUEST_BYTES),
  );
}

async function readResponseText(response: Response, signal: AbortSignal) {
  return new TextDecoder().decode(
    await readLimitedBytes(response.body, MAX_RESPONSE_BYTES, signal),
  );
}

async function readResponseBytes(response: Response, signal: AbortSignal) {
  return readLimitedBytes(response.body, MAX_RESPONSE_BYTES, signal);
}

async function readLimitedBytes(
  body: ReadableStream<Uint8Array> | null,
  max: number,
  signal?: AbortSignal,
) {
  if (body === null) return new Uint8Array();
  const reader = body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      length += result.value.byteLength;
      if (length > max) throw new HttpError(413, "Respons terlalu besar.");
      chunks.push(result.value);
    }
  } catch (error) {
    if (signal?.aborted) {
      await reader.cancel().catch(() => {});
      throw new HttpError(504, "Situs tujuan merespons terlalu lambat.");
    }
    if (error instanceof HttpError && error.status === 413) {
      await reader.cancel().catch(() => {});
    }
    throw error;
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

function createResponse(
  body: BodyInit | null,
  status: number,
  origin: string | null,
  extra: Record<string, string> = {},
  allowCors = true,
) {
  const headers = new Headers({
    "cache-control": "no-store",
    ...extra,
  });
  if (allowCors) {
    headers.set("access-control-allow-origin", origin ?? "*");
    if (origin !== null && origin !== "*") headers.set("vary", "Origin");
  }
  if (body instanceof Uint8Array) {
    headers.set("access-control-expose-headers", "content-type, cache-control");
  } else {
    headers.set("content-type", "application/json; charset=utf-8");
  }
  headers.set("access-control-allow-methods", "POST, GET, OPTIONS");
  headers.set(
    "access-control-allow-headers",
    "authorization, apikey, content-type, x-client-info",
  );
  return new Response(body, { status, headers });
}

function consumeRateLimit(
  request: Request,
  now: number,
  maxBuckets: number,
) {
  const address = request.headers.get("cf-connecting-ip")?.trim() ?? "";
  const key = address || "shared-anonymous";
  for (const [bucketKey, bucket] of rateBuckets) {
    if (now - bucket.startedAt >= RATE_LIMIT_WINDOW_MS) {
      rateBuckets.delete(bucketKey);
    }
  }
  const bucket = rateBuckets.get(key);
  if (bucket === undefined) {
    if (rateBuckets.size >= maxBuckets) {
      const oldestKey = rateBuckets.keys().next().value;
      if (oldestKey !== undefined) rateBuckets.delete(oldestKey);
    }
    rateBuckets.set(key, { startedAt: now, count: 1 });
    return;
  }
  bucket.count += 1;
  if (bucket.count > RATE_LIMIT_MAX) {
    throw new HttpError(429, "Terlalu banyak permintaan. Coba lagi nanti.");
  }
}

export function resetRateLimitForTests() {
  rateBuckets.clear();
}
export function enforceRateLimitForTests(request: Request, now = Date.now()) {
  consumeRateLimit(request, now, 1_000);
}
function enforceRateLimit(request: Request) {
  consumeRateLimit(request, Date.now(), 1_000);
}

function isIpLiteral(value: string) {
  return parseIpv4(value) !== null || expandIpv6(value) !== null;
}

function isPrivateIp(value: string) {
  const ipv4 = parseIpv4(value);
  if (ipv4 !== null) {
    const [a, b, c] = ipv4;
    return a === 0 ||
      a === 10 ||
      a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && (b === 0 || b === 168)) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
      (a === 203 && b === 0 && c === 113) ||
      a >= 224;
  }
  const groups = expandIpv6(value);
  if (groups === null) return value.includes(":");
  const values = groups.map((group) => parseInt(group, 16));
  if (
    values.slice(0, 5).every((group) => group === 0) && values[5] === 0xffff
  ) {
    const mappedIpv4 = [
      values[6] >> 8,
      values[6] & 0xff,
      values[7] >> 8,
      values[7] & 0xff,
    ].join(".");
    return isPrivateIp(mappedIpv4);
  }
  return values.every((value) => value === 0) ||
    (values.slice(0, 7).every((value) => value === 0) && values[7] === 1) ||
    (values[0] & 0xffc0) === 0xfe80 ||
    (values[0] & 0xfe00) === 0xfc00 ||
    (values[0] & 0xff00) === 0xff00;
}

function parseIpv4(value: string) {
  const normalized = value.replace(/^\[|\]$/g, "");
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(normalized)) return null;
  const octets = normalized.split(".").map(Number);
  return octets.every((octet) => octet <= 255) ? octets : null;
}

function expandIpv6(value: string) {
  const normalized = value.replace(/^\[|\]$/g, "").toLowerCase();
  if (!normalized.includes(":") || !/^[0-9a-f:]+$/.test(normalized)) {
    return null;
  }
  if (normalized.includes("::")) {
    if (normalized.indexOf("::") !== normalized.lastIndexOf("::")) return null;
    const [leftValue, rightValue] = normalized.split("::");
    const left = leftValue ? leftValue.split(":") : [];
    const right = rightValue ? rightValue.split(":") : [];
    const missing = 8 - left.length - right.length;
    if (missing < 1) return null;
    return [...left, ...Array.from({ length: missing }, () => "0"), ...right];
  }
  const groups = normalized.split(":");
  return groups.length === 8 ? groups : null;
}
