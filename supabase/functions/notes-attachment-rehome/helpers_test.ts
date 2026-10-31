import {
  attachmentPath,
  attachmentSignatureMatches,
  isAuthorizedWorkerRequest,
  resolveAllowedOrigin,
} from "./helpers.ts";

Deno.test("accepts only bounded payloads with an allowed matching signature", () => {
  const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  if (!attachmentSignatureMatches(png, "image/png")) {
    throw new Error("valid PNG signature rejected");
  }
  if (attachmentSignatureMatches(png, "application/pdf")) {
    throw new Error("mismatched PDF signature accepted");
  }
  if (attachmentSignatureMatches(new Uint8Array(), "image/png")) {
    throw new Error("empty image accepted");
  }
  if (attachmentSignatureMatches(new Uint8Array([1]), "image/svg+xml")) {
    throw new Error("unsupported MIME type accepted");
  }
});

Deno.test("derives the same owner- and project-bound paths as the database", () => {
  const id = "123e4567-e89b-12d3-a456-426614174000";
  const owner = "223e4567-e89b-12d3-a456-426614174001";
  if (attachmentPath(owner, null, id) !== `private/${owner}/${id}`) {
    throw new Error("private path mismatch");
  }
  if (attachmentPath(owner, "proj-1", id) !== `project/70726f6a2d31/${id}`) {
    throw new Error("project path mismatch");
  }
});

Deno.test('allows only exact configured browser origins', () => {
  const allowed = 'https://notes.example.test';
  if (resolveAllowedOrigin(allowed, allowed) !== allowed) {
    throw new Error('configured origin rejected');
  }
  for (const [origin, configured] of [
    ['https://attacker.example', allowed],
    [allowed, '*'],
    ['https://notes.example.test.evil', allowed],
    ['null', allowed],
  ] as const) {
    if (resolveAllowedOrigin(origin, configured) !== null) {
      throw new Error(`unconfigured origin accepted: ${origin}`);
    }
  }
  if (resolveAllowedOrigin(null, allowed) !== null) {
    throw new Error('native request without Origin gained CORS access');
  }
});

Deno.test("requires the dedicated worker secret header", () => {
  const valid = new Request("https://example.test", {
    method: "POST",
    headers: { "x-notes-attachment-worker-secret": "worker-secret-123456" },
  });
  const invalid = new Request("https://example.test", {
    method: "POST",
    headers: { "x-notes-attachment-worker-secret": "wrong-secret-123456" },
  });
  if (!isAuthorizedWorkerRequest(valid, "worker-secret-123456")) {
    throw new Error("valid worker request rejected");
  }
  if (isAuthorizedWorkerRequest(invalid, "worker-secret-123456")) {
    throw new Error("invalid worker request accepted");
  }
  if (isAuthorizedWorkerRequest(valid, "short")) {
    throw new Error("short configured secret accepted");
  }
});
