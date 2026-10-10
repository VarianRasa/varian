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
  validateCorsOrigin,
  validateGlb,
  validatePng,
} from "./helpers.ts";

function expectError(action: () => unknown, code: string): void {
  let error: unknown;
  try {
    action();
  } catch (caught) {
    error = caught;
  }
  if (!(error instanceof Ai3DError) || error.code !== code) {
    throw new Error(`Expected Ai3DError ${code}, got ${String(error)}`);
  }
}

function ascii(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const result = new Uint8Array(parts.reduce((total, part) => total + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function paddedJson(value: unknown): Uint8Array {
  const bytes = ascii(JSON.stringify(value));
  const paddedLength = Math.ceil(bytes.length / 4) * 4;
  const result = new Uint8Array(paddedLength).fill(0x20);
  result.set(bytes);
  return result;
}

function glbChunk(type: number, data: Uint8Array): Uint8Array {
  const result = new Uint8Array(8 + data.length);
  const view = new DataView(result.buffer);
  view.setUint32(0, data.length, true);
  view.setUint32(4, type, true);
  result.set(data, 8);
  return result;
}

function validGlb(includeBinary = true): Uint8Array {
  const json = paddedJson({
    asset: { version: "2.0" },
    meshes: [{ primitives: [{ attributes: { POSITION: 0 } }] }],
    accessors: [{ count: 3 }],
  });
  const chunks = [glbChunk(0x4e4f534a, json)];
  if (includeBinary) chunks.push(glbChunk(0x004e4942, new Uint8Array([0, 0, 0, 0])));
  const result = new Uint8Array(12 + chunks.reduce((total, chunk) => total + chunk.length, 0));
  const view = new DataView(result.buffer);
  result.set(ascii("glTF"), 0);
  view.setUint32(4, 2, true);
  view.setUint32(8, result.length, true);
  let offset = 12;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

function pngChunk(type: string, data: Uint8Array): Uint8Array {
  const result = new Uint8Array(12 + data.length);
  const view = new DataView(result.buffer);
  view.setUint32(0, data.length, false);
  result.set(ascii(type), 4);
  result.set(data, 8);
  return result;
}

function validPng(width = 64, height = 32): Uint8Array {
  const header = new Uint8Array(13);
  const view = new DataView(header.buffer);
  view.setUint32(0, width, false);
  view.setUint32(4, height, false);
  header.set([8, 6, 0, 0, 0], 8);
  return concat(
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", header),
    pngChunk("IEND", new Uint8Array()),
  );
}

Deno.test("rejects unsafe worker URLs and normalizes trusted URLs", () => {
  if (normalizeWorkerBaseUrl("https://worker.example.com/v1///") !== "https://worker.example.com/v1") {
    throw new Error("worker URL was not normalized");
  }
  if (normalizeWorkerBaseUrl("http://127.0.0.1:20130/v1") !== "http://127.0.0.1:20130/v1") {
    throw new Error("loopback development URL should be allowed");
  }
  for (const value of [
    "http://worker.example.com/v1",
    "https://user:password@worker.example.com/v1",
    "https://worker.example.com/v1?redirect=https://evil.example",
    "https://worker.example.com/v1#fragment",
  ]) {
    expectError(() => normalizeWorkerBaseUrl(value), "CONFIGURATION_ERROR");
  }
});

Deno.test("keeps restricted providers disabled unless explicitly enabled", () => {
  const defaults = configuredAi3dProviders(undefined, false, false);
  if (!defaults.has("triposr") || !defaults.has("comfyui") || defaults.has("trellis")) {
    throw new Error("default providers are incomplete");
  }
  if (defaults.has("hunyuan3d") || defaults.has("demo")) {
    throw new Error("restricted providers are enabled by default");
  }
  const configured = configuredAi3dProviders("triposr,hunyuan3d,demo,unknown", true, false);
  if (configured.has("hunyuan3d") || !configured.has("demo") || configured.has("unknown")) {
    throw new Error("provider opt-in policy was not enforced");
  }
  if (configuredAi3dProviders("hunyuan3d", false, true).has("hunyuan3d")) {
    throw new Error("Hunyuan was enabled without legal approval");
  }
  if (!configuredAi3dProviders("hunyuan3d", false, true, true).has("hunyuan3d")) {
    throw new Error("explicit Hunyuan opt-in was rejected");
  }
  if (configuredAi3dProviders("trellis", false, false, false, true, false, false).has("trellis")) {
    throw new Error("TRELLIS was enabled without legal approval");
  }
  if (configuredAi3dProviders("trellis", false, false, false, true, true, false).has("trellis")) {
    throw new Error("TRELLIS was enabled without dependency review");
  }
  if (!configuredAi3dProviders("trellis", false, false, false, true, true, true).has("trellis")) {
    throw new Error("explicit TRELLIS opt-in was rejected");
  }
  if (configuredAi3dProviders("fal-trellis2", false, false, false, false, false, false, false).has("fal-trellis2")) {
    throw new Error("hosted TRELLIS.2 was enabled without explicit opt-in");
  }
  if (!configuredAi3dProviders("fal-trellis2", false, false, false, false, false, false, true).has("fal-trellis2")) {
    throw new Error("explicit hosted TRELLIS.2 opt-in was rejected");
  }
});

Deno.test("requires a strict bearer authorization header", () => {
  if (readBearerToken("Bearer valid-token") !== "valid-token") {
    throw new Error("bearer token was not parsed");
  }
  for (const value of [null, "", "Basic credentials", "Bearer", "Bearer token extra"]) {
    expectError(() => readBearerToken(value), "UNAUTHORIZED");
  }
});

Deno.test("rejects job and project path traversal values", () => {
  if (safeJobId("job-01:_draft") !== "job-01:_draft") throw new Error("safe job ID was changed");
  if (safeProjectId("project-01") !== "project-01") throw new Error("safe project ID was changed");
  for (const value of ["../secret", "/tmp/file", "job\\nested", ""])
    expectError(() => safeJobId(value), "VALIDATION_ERROR");
  expectError(() => safeProjectId(""), "VALIDATION_ERROR");
  expectError(() => safeJobId("a".repeat(129)), "VALIDATION_ERROR");
});

Deno.test("enforces source URL allowlist and HTTPS policy", () => {
  const allowed = new Set(["images.example.com"]);
  if (safeSourceUrl("https://images.example.com/source.png", allowed) !== "https://images.example.com/source.png") {
    throw new Error("allowlisted image URL was rejected");
  }
  for (const value of [
    "http://images.example.com/source.png",
    "https://images.example.com/source.png#fragment",
    "https://user:password@images.example.com/source.png",
    "https://169.254.169.254/latest/meta-data",
    "https://evil.example.com/source.png",
  ]) {
    expectError(() => safeSourceUrl(value, allowed), "VALIDATION_ERROR");
  }
});

Deno.test("enforces exact CORS origins without reflecting arbitrary callbacks", () => {
  const allowed = new Set(["https://app.example.com"]);
  if (validateCorsOrigin(null, allowed) !== null) throw new Error("missing origin should be allowed");
  if (validateCorsOrigin("https://app.example.com", allowed) !== "https://app.example.com") {
    throw new Error("configured origin was rejected");
  }
  if (validateCorsOrigin("https://app.example.com", new Set(["*"])) !== "*") {
    throw new Error("wildcard origin was not handled");
  }
  expectError(() => validateCorsOrigin("https://evil.example.com", allowed), "CORS_DENIED");
});

Deno.test("enforces prompt, optional text, and integer bounds", () => {
  if (requirePrompt("  a chair  ") !== "a chair") throw new Error("prompt was not trimmed");
  if (optionalText("  draft  ", "meshQuality", 20) !== "draft") throw new Error("optional text was not trimmed");
  if (parseInteger(1000, "triangleBudget", 100, 1000, 500000) !== 1000) throw new Error("integer was rejected");
  for (const action of [
    () => requirePrompt(""),
    () => requirePrompt("x".repeat(2001)),
    () => optionalText("x".repeat(21), "meshQuality", 20),
    () => parseInteger(1.5, "triangleBudget", 100, 1000, 500000),
    () => parseInteger(500001, "triangleBudget", 100, 1000, 500000),
  ]) expectError(action, "VALIDATION_ERROR");
});

Deno.test("accepts only structurally valid bounded GLB artifacts", () => {
  const artifact = validGlb();
  const result = validateGlb(artifact);
  if (result.byteLength !== artifact.length || result.triangleCount !== 1) {
    throw new Error(`unexpected GLB result: ${JSON.stringify(result)}`);
  }
  const wrongLength = artifact.slice();
  new DataView(wrongLength.buffer).setUint32(8, wrongLength.length + 1, true);
  expectError(() => validateGlb(wrongLength), "INVALID_ARTIFACT");
  expectError(() => validateGlb(validGlb(false)), "INVALID_ARTIFACT");
  expectError(() => validateGlb(artifact, artifact.length - 1), "INVALID_ARTIFACT");
});

Deno.test("accepts only bounded PNG previews with safe dimensions", () => {
  const preview = validPng();
  const result = validatePng(preview);
  if (result.byteLength !== preview.length || result.width !== 64 || result.height !== 32) {
    throw new Error(`unexpected PNG result: ${JSON.stringify(result)}`);
  }
  const wrongSignature = preview.slice();
  wrongSignature[0] = 0;
  expectError(() => validatePng(wrongSignature), "INVALID_ARTIFACT");
  expectError(() => validatePng(validPng(4097, 32)), "INVALID_ARTIFACT");
  expectError(() => validatePng(preview, preview.length - 1), "INVALID_ARTIFACT");
});
