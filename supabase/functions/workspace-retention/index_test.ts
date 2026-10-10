import {
  constantTimeEqual,
  isAuthorized,
  normalizeProjectId,
} from "./helpers.ts";

Deno.test("compares retention secrets without accepting different lengths", () => {
  if (!constantTimeEqual("secret-value", "secret-value")) throw new Error("equal secrets rejected");
  if (constantTimeEqual("secret-value", "secret-valuf")) throw new Error("different secrets accepted");
  if (constantTimeEqual("short", "longer")) throw new Error("different lengths accepted");
});

Deno.test("requires the operator secret header", () => {
  const request = new Request("https://example.test", {
    method: "POST",
    headers: { "x-retention-job-secret": "retention-secret-123" },
  });
  if (!isAuthorized(request, "retention-secret-123")) throw new Error("valid secret rejected");
  if (isAuthorized(request, "other-secret-123")) throw new Error("invalid secret accepted");
});

Deno.test("normalizes bounded project identifiers", () => {
  if (normalizeProjectId("  project-1 ") !== "project-1") throw new Error("project ID was not trimmed");
  for (const invalid of ["", "project id", "project/1", "x".repeat(129)]) {
    try {
      normalizeProjectId(invalid);
      throw new Error(`invalid project ID accepted: ${invalid}`);
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes("Project ID")) throw error;
    }
  }
});
