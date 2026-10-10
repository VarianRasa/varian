export const maxBodyBytes = 32 * 1024;

export function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export function isAuthorized(request: Request, secret: string): boolean {
  const provided = request.headers.get("x-retention-job-secret")?.trim() ?? "";
  return secret.length >= 16 && constantTimeEqual(provided, secret);
}

export function normalizeProjectId(value: unknown): string {
  if (typeof value !== "string") {
    throw new Error("Project ID is required.");
  }
  const projectId = value.trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(projectId)) {
    throw new Error("Project ID is invalid.");
  }
  return projectId;
}

export function jsonResponse(payload: unknown, status: number): Response {
  return new Response(payload === null ? null : JSON.stringify(payload), {
    status,
    headers: {
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}
