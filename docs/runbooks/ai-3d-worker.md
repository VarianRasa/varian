# AI 3D worker runbook

## Scope and safety

Use this runbook for the local/demo worker or an operator-authorized deployment. Do not paste bearer tokens, artifact URLs (they contain access tokens), prompts, or user files into issues or logs. Do not restart a shared worker until its operator confirms that in-flight jobs may be interrupted.

## Check service health

1. Request `GET /v1/health` from the worker host. For a local demo, use `http://127.0.0.1:20130/v1/health`.
2. If `VARIAN_3D_WORKER_TOKEN` is configured, send it as a bearer token through a secret-safe client. Never put it in shell history or support output.
3. A `401` means auth is enabled and the request lacks the configured token. A connection failure usually means the process is stopped, the port is wrong, or the host firewall/network path is blocking access.
4. Check worker process logs for sanitized error codes and provider availability. Do not emit raw provider responses or credentials.

## Diagnose a job

1. Query `GET /v1/3d/jobs/{jobId}` with the same auth context used to create it.
2. `queued` or `processing` means poll again after a short delay. `failed` includes a worker error code/message; correct provider setup before retrying.
3. For the `demo` provider, verify only the local API/job/artifact lifecycle. It does not validate GPU drivers, model checkpoints, Supabase, or production credentials.
4. For a successful job, retrieve the artifact URL returned by the worker. Treat its query token as a credential; do not share or log it.

## Recovery and escalation

- For a local demo, stop the process with Ctrl+C and restart it using the documented demo setup in `tool/ai_3d_worker/README.md`.
- Restarting an in-memory worker loses job state. Confirm with the deployment owner before restarting a shared worker or deleting its artifact directory.
- If the service is healthy but a production provider fails, record the sanitized provider name, error code, job ID, and timestamp, then escalate to the worker/deployment owner. Do not change provider credentials or run migrations as part of triage.
