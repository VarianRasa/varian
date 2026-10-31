import { processAvailableJobs } from "./index.ts";
import { attachmentMaxBytes } from "./helpers.ts";

Deno.test("retries unavailable jobs without exposing payloads", async () => {
  const calls: string[] = [];
  const service = {
    rpc: async (name: string, _args?: Record<string, unknown>) => {
      calls.push(name);
      if (name === "claim_workspace_note_attachment_rehome_jobs") {
        return {
          data: [{
            id: "323e4567-e89b-12d3-a456-426614174002",
            job_kind: "note_scope_change",
            note_id: "423e4567-e89b-12d3-a456-426614174003",
            source_project_id: "proj-1",
            target_project_id: null,
            target_owner_user_id: "223e4567-e89b-12d3-a456-426614174001",
            requested_by: "223e4567-e89b-12d3-a456-426614174001",
            status: "copying",
            lease_token: "523e4567-e89b-12d3-a456-426614174004",
          }],
          error: null,
        };
      }
      if (name === "get_workspace_note_attachment_rehome_items") {
        return {
          data: [{
            attachment_id: "123e4567-e89b-12d3-a456-426614174000",
            source_path:
              "project/70726f6a2d31/123e4567-e89b-12d3-a456-426614174000",
            target_path:
              "private/223e4567-e89b-12d3-a456-426614174001/123e4567-e89b-12d3-a456-426614174000",
            expected_sha256: "a".repeat(64),
            mime_type: "image/png",
            size_bytes: 8,
          }],
          error: null,
        };
      }
      return { data: null, error: null };
    },
    storage: {
      from: (_bucket: string) => ({
        download: async (_path: string) => ({ data: null, error: new Error("missing") }),
        upload: async (_path: string, _bytes: Uint8Array, _options: unknown) => ({ error: null }),
        remove: async (_paths: string[]) => ({ error: null }),
      }),
    },
  };

  const result = await processAvailableJobs(
    service as unknown as Parameters<typeof processAvailableJobs>[0],
  );

  if (result.claimed !== 1 || result.completed !== 0 || result.retried !== 1) {
    throw new Error("failed copy was not retained for retry");
  }
  if (!calls.includes("record_workspace_note_attachment_rehome_failure")) {
    throw new Error("failed copy did not record retry state");
  }
  if (calls.includes("commit_workspace_note_attachment_rehome") ||
      calls.includes("complete_workspace_note_attachment_rehome_cleanup")) {
    throw new Error("failed copy changed metadata or completed the job");
  }
  if (attachmentMaxBytes !== 25 * 1024 * 1024) {
    throw new Error("worker size limit changed");
  }
});

Deno.test("resumes a cleanup job without copying source again", async () => {
  const attachmentId = "123e4567-e89b-12d3-a456-426614174000";
  const jobId = "323e4567-e89b-12d3-a456-426614174002";
  const ownerId = "223e4567-e89b-12d3-a456-426614174001";
  const sourcePath = `project/70726f6a2d31/${attachmentId}`;
  const targetPath = `private/${ownerId}/${attachmentId}`;
  const payload = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  const digest = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", payload)),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
  const calls: string[] = [];
  const downloadedPaths: string[] = [];
  let recordedFailure: Record<string, unknown> | undefined;
  const service = {
    rpc: async (name: string, args?: Record<string, unknown>) => {
      calls.push(name);
      if (name === "claim_workspace_note_attachment_rehome_jobs") {
        return {
          data: [{
            id: jobId,
            job_kind: "note_scope_change",
            note_id: "423e4567-e89b-12d3-a456-426614174003",
            source_project_id: "proj-1",
            target_project_id: null,
            target_owner_user_id: ownerId,
            requested_by: ownerId,
            status: "cleanup",
            lease_token: "lease-token",
          }],
          error: null,
        };
      }
      if (name === "get_workspace_note_attachment_rehome_items") {
        return {
          data: [{
            attachment_id: attachmentId,
            source_path: sourcePath,
            target_path: targetPath,
            expected_sha256: digest,
            mime_type: "image/png",
            size_bytes: payload.length,
          }],
          error: null,
        };
      }
      if (name === "record_workspace_note_attachment_rehome_failure") {
        recordedFailure = args;
      }
      return { data: null, error: null };
    },
    storage: {
      from: (_bucket: string) => ({
        download: async (path: string) => {
          downloadedPaths.push(path);
          return { data: new Blob([payload]), error: null };
        },
        upload: async () => {
          throw new Error("cleanup phase must not copy source bytes");
        },
        remove: async () => ({ error: new Error("temporary storage failure") }),
      }),
    },
  };

  const result = await processAvailableJobs(
    service as unknown as Parameters<typeof processAvailableJobs>[0],
  );

  if (result.claimed !== 1 || result.completed !== 0 || result.retried !== 1) {
    throw new Error("cleanup failure was not retained for retry");
  }
  if (downloadedPaths.length !== 1 || downloadedPaths[0] !== targetPath) {
    throw new Error("cleanup retry re-read the removed source object");
  }
  if (calls.includes("commit_workspace_note_attachment_rehome")) {
    throw new Error("cleanup retry attempted to switch metadata again");
  }
  if (recordedFailure?.p_error_code !== "SOURCE_CLEANUP_FAILED") {
    throw new Error("cleanup failure was not recorded with its phase error");
  }
});
