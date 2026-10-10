export type JsonObject = Record<string, unknown>;

export class Ai3DError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export function readBearerToken(header: string | null): string {
  const match = /^Bearer\s+(\S+)$/i.exec(header?.trim() ?? "");
  if (!match) throw new Ai3DError(401, "UNAUTHORIZED", "Authentication is required.");
  return match[1];
}

export function normalizeWorkerBaseUrl(value: string): string {
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch (_) {
    throw new Ai3DError(500, "CONFIGURATION_ERROR", "3D worker URL is invalid.");
  }
  if (
    url.protocol !== "https:" &&
    !(url.protocol === "http:" && ["localhost", "127.0.0.1", "::1"].includes(url.hostname.toLowerCase()))
  ) {
    throw new Ai3DError(500, "CONFIGURATION_ERROR", "3D worker URL must use HTTPS.");
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Ai3DError(500, "CONFIGURATION_ERROR", "3D worker URL contains unsupported URL parts.");
  }
  return url.toString().replace(/\/+$/, "");
}

export function requirePrompt(value: unknown): string {
  if (typeof value !== "string") {
    throw new Ai3DError(400, "VALIDATION_ERROR", "prompt is required.");
  }
  const prompt = value.trim();
  if (prompt.length === 0 || prompt.length > 2000) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "prompt must contain 1-2000 characters.");
  }
  return prompt;
}

export function optionalText(value: unknown, field: string, max: number): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new Ai3DError(400, "VALIDATION_ERROR", `${field} is invalid.`);
  }
  const text = value.trim();
  if (text.length > max) {
    throw new Ai3DError(400, "VALIDATION_ERROR", `${field} is too long.`);
  }
  return text.length === 0 ? undefined : text;
}

const DEFAULT_AI_3D_PROVIDERS = new Set(["triposr", "trellis", "comfyui"]);
const KNOWN_AI_3D_PROVIDERS = new Set([
  "triposr",
  "trellis",
  "fal-trellis2",
  "hunyuan3d",
  "comfyui",
  "demo",
]);

export function configuredAi3dProviders(
  configured: string | undefined,
  allowDemo: boolean,
  enableHunyuan: boolean,
  hunyuanLegalApproved = false,
  enableTrellis2 = false,
  trellis2LegalApproved = false,
  trellis2DependencyReviewed = false,
  enableFalTrellis2 = false,
): Set<string> {
  const value = configured?.trim();
  const providers = new Set(
    (value && value.length > 0 ? value : [...DEFAULT_AI_3D_PROVIDERS].join(","))
      .split(",")
      .map((provider) => provider.trim().toLowerCase())
      .filter((provider) => KNOWN_AI_3D_PROVIDERS.has(provider)),
  );
  if (allowDemo) providers.add("demo");
  else providers.delete("demo");
  if (!enableHunyuan || !hunyuanLegalApproved) providers.delete("hunyuan3d");
  if (!enableTrellis2 || !trellis2LegalApproved || !trellis2DependencyReviewed) {
    providers.delete("trellis");
  }
  if (!enableFalTrellis2) providers.delete("fal-trellis2");
  return providers;
}

export function safeJobId(value: unknown): string {
  const id = value === undefined || value === null ? crypto.randomUUID() : String(value).trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(id)) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "jobId contains invalid characters.");
  }
  return id;
}

export function safeProjectId(value: unknown): string {
  const projectId = optionalText(value, "projectId", 200);
  if (projectId === undefined) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "projectId is required.");
  }
  return projectId;
}

export function safeSourceUrl(value: string, allowedHosts: Set<string>): string {
  let url: URL;
  try {
    url = new URL(value);
  } catch (_) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "sourceImageUrl is invalid.");
  }
  if (url.protocol !== "https:" || url.username || url.password || url.hash) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "sourceImageUrl must be an HTTPS URL without credentials or fragments.");
  }
  if (allowedHosts.size > 0 && !allowedHosts.has(url.hostname.toLowerCase())) {
    throw new Ai3DError(400, "VALIDATION_ERROR", "sourceImageUrl host is not allowlisted.");
  }
  return url.toString();
}

export function validateCorsOrigin(value: string | null, configuredOrigins: Set<string>): string | null {
  const origin = value?.trim() ?? "";
  if (origin.length === 0) return null;
  if (configuredOrigins.has("*")) return "*";
  if (!configuredOrigins.has(origin)) {
    throw new Ai3DError(403, "CORS_DENIED", "Origin is not allowed.");
  }
  return origin;
}

export function parseInteger(value: unknown, field: string, fallback: number, min: number, max: number): number {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== "number" || !Number.isInteger(value) || value < min || value > max) {
    throw new Ai3DError(400, "VALIDATION_ERROR", `${field} is invalid.`);
  }
  return value;
}

export function validateGlb(data: Uint8Array, maxBytes = 64 * 1024 * 1024): { byteLength: number; triangleCount: number } {
  if (data.byteLength < 20 || data.byteLength > maxBytes) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB size is invalid.");
  }
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  if (new TextDecoder().decode(data.slice(0, 4)) !== "glTF" || view.getUint32(4, true) !== 2) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB header is invalid.");
  }
  const declaredLength = view.getUint32(8, true);
  if (declaredLength !== data.byteLength) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB length is invalid.");
  }
  let offset = 12;
  let document: JsonObject | undefined;
  let hasBinary = false;
  while (offset < data.byteLength) {
    if (offset + 8 > data.byteLength) {
      throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB chunk is truncated.");
    }
    const length = view.getUint32(offset, true);
    const type = view.getUint32(offset + 4, true);
    offset += 8;
    const end = offset + length;
    if (end > data.byteLength) {
      throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB chunk exceeds the file.");
    }
    if (type === 0x4e4f534a && document === undefined) {
      try {
        const parsed: unknown = JSON.parse(new TextDecoder().decode(data.slice(offset, end)).trim());
        if (!isObject(parsed)) throw new Error("not object");
        document = parsed;
      } catch (_) {
        throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB JSON is invalid.");
      }
    }
    if (type === 0x004e4942) hasBinary = true;
    offset = end;
  }
  if (document === undefined || !hasBinary) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB is missing required chunks.");
  }
  const asset = document.asset;
  if (!isObject(asset) || asset.version !== "2.0") {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated GLB asset metadata is invalid.");
  }
  return { byteLength: data.byteLength, triangleCount: triangleCount(document) };
}

export function validatePng(data: Uint8Array, maxBytes = 4 * 1024 * 1024): { byteLength: number; width: number; height: number } {
  if (data.byteLength < 33 || data.byteLength > maxBytes) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview size is invalid.");
  }
  const signature = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  for (let index = 0; index < signature.length; index += 1) {
    if (data[index] !== signature[index]) {
      throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview header is invalid.");
    }
  }
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  let offset = 8;
  let width = 0;
  let height = 0;
  let foundHeader = false;
  let foundEnd = false;
  while (offset < data.byteLength) {
    if (offset + 12 > data.byteLength) {
      throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview chunk is truncated.");
    }
    const length = view.getUint32(offset, false);
    const typeStart = offset + 4;
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    const chunkEnd = dataEnd + 4;
    if (chunkEnd > data.byteLength) {
      throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview chunk exceeds the file.");
    }
    const type = new TextDecoder().decode(data.slice(typeStart, dataStart));
    if (type === "IHDR") {
      if (foundHeader || length !== 13 || offset !== 8) {
        throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview header is invalid.");
      }
      width = view.getUint32(dataStart, false);
      height = view.getUint32(dataStart + 4, false);
      const bitDepth = data[dataStart + 8];
      const colorType = data[dataStart + 9];
      const compression = data[dataStart + 10];
      const filter = data[dataStart + 11];
      const interlace = data[dataStart + 12];
      if (width === 0 || height === 0 || width > 4096 || height > 4096 || bitDepth !== 8 || ![2, 6].includes(colorType) || compression !== 0 || filter !== 0 || interlace !== 0) {
        throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview format is unsupported.");
      }
      foundHeader = true;
    }
    if (type === "IEND") {
      if (length !== 0) {
        throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview end chunk is invalid.");
      }
      foundEnd = true;
      offset = chunkEnd;
      break;
    }
    offset = chunkEnd;
  }
  if (!foundHeader || !foundEnd || offset !== data.byteLength) {
    throw new Ai3DError(502, "INVALID_ARTIFACT", "Generated preview is incomplete.");
  }
  return { byteLength: data.byteLength, width, height };
}

function triangleCount(document: JsonObject): number {
  const meshes = document.meshes;
  const accessors = document.accessors;
  if (!Array.isArray(meshes) || !Array.isArray(accessors)) return 0;
  let total = 0;
  for (const mesh of meshes) {
    if (!isObject(mesh) || !Array.isArray(mesh.primitives)) continue;
    for (const primitive of mesh.primitives) {
      if (!isObject(primitive)) continue;
      const count = accessorCount(accessors, primitive.indices) ?? positionCount(accessors, primitive.attributes);
      if (count === undefined) continue;
      const mode = typeof primitive.mode === "number" ? primitive.mode : 4;
      total += mode === 4 ? Math.floor(count / 3) : mode === 5 || mode === 6 ? Math.max(0, count - 2) : 0;
    }
  }
  return total;
}

function accessorCount(accessors: unknown[], index: unknown): number | undefined {
  if (typeof index !== "number" || !Number.isInteger(index) || !isObject(accessors[index])) return undefined;
  const count = accessors[index].count;
  return typeof count === "number" && Number.isInteger(count) ? count : undefined;
}

function positionCount(accessors: unknown[], attributes: unknown): number | undefined {
  if (!isObject(attributes)) return undefined;
  return accessorCount(accessors, attributes.POSITION);
}

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
