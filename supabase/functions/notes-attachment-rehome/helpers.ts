import { constantTimeEqual } from "../workspace-retention/helpers.ts";

export const attachmentMaxBytes = 25 * 1024 * 1024;

const supportedMimeTypes = new Set([
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "application/pdf",
]);

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function resolveAllowedOrigin(
  origin: string | null,
  configuredOrigins: string | undefined,
): string | null {
  if (origin === null) return null;
  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    return null;
  }
  if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') ||
      parsed.origin !== origin || parsed.username.length > 0 ||
      parsed.password.length > 0) {
    return null;
  }
  const allowlist = (configuredOrigins ?? '').split(',').map((value) => value.trim());
  return allowlist.includes(origin) && !allowlist.includes('*') ? origin : null;
}

export function isAuthorizedWorkerRequest(
  request: Request,
  secret: string,
): boolean {
  const configuredSecret = secret.trim();
  const providedSecret = request.headers
    .get("x-notes-attachment-worker-secret")?.trim() ?? "";
  return configuredSecret.length >= 16 &&
    constantTimeEqual(providedSecret, configuredSecret);
}

export function attachmentPath(
  ownerId: string,
  projectId: string | null,
  attachmentId: string,
): string {
  if (!uuidPattern.test(ownerId) || !uuidPattern.test(attachmentId)) {
    throw new Error("Attachment path identity is invalid.");
  }
  if (projectId === null) return `private/${ownerId.toLowerCase()}/${attachmentId.toLowerCase()}`;
  if (projectId.length === 0 || projectId.includes("\0")) {
    throw new Error("Attachment project scope is invalid.");
  }
  const projectSegment = Array.from(new TextEncoder().encode(projectId), (byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
  return `project/${projectSegment}/${attachmentId.toLowerCase()}`;
}

export function attachmentSignatureMatches(
  bytes: Uint8Array,
  mimeType: string,
): boolean {
  if (bytes.length === 0 || bytes.length > attachmentMaxBytes) return false;
  const mime = mimeType.trim().toLowerCase();
  if (!supportedMimeTypes.has(mime)) return false;

  switch (mime) {
    case "image/png":
      return startsWith(bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
    case "image/jpeg":
      return startsWith(bytes, [255, 216, 255]);
    case "image/gif":
      return startsWithAscii(bytes, "GIF87a") ||
        startsWithAscii(bytes, "GIF89a");
    case "image/webp":
      return startsWithAscii(bytes, "RIFF") &&
        startsWithAscii(bytes, "WEBP", 8);
    case "application/pdf":
      return startsWithAscii(bytes, "%PDF-");
  }
  return false;
}

export function detectAttachmentMimeType(bytes: Uint8Array): string | null {
  for (const mimeType of supportedMimeTypes) {
    if (attachmentSignatureMatches(bytes, mimeType)) return mimeType;
  }
  return null;
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", bytes.slice().buffer as ArrayBuffer),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function startsWith(bytes: Uint8Array, prefix: number[], offset = 0): boolean {
  return bytes.length >= offset + prefix.length &&
    prefix.every((byte, index) => bytes[offset + index] === byte);
}

function startsWithAscii(
  bytes: Uint8Array,
  value: string,
  offset = 0,
): boolean {
  return startsWith(bytes, Array.from(value, (character) => character.charCodeAt(0)), offset);
}
