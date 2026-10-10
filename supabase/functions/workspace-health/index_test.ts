import {
  buildHealthPayload,
  buildPublicHealthPayload,
  type HealthCheck,
} from "./helpers.ts";

Deno.test("returns healthy only when all probes are healthy", () => {
  const checks: HealthCheck[] = [
    { name: "auth", status: "healthy", message: "ok", latencyMs: 3 },
    { name: "database", status: "healthy", message: "ok", latencyMs: 5 },
  ];
  const payload = buildHealthPayload(
    "1.2.3",
    checks,
    new Date("2026-09-14T00:00:00Z"),
  );
  if (payload.status !== "healthy") {
    throw new Error("healthy checks were downgraded");
  }
  if (payload.version !== "1.2.3") throw new Error("version was not preserved");
  if (payload.timestamp !== "2026-09-14T00:00:00.000Z") {
    throw new Error("timestamp was not normalized");
  }
});

Deno.test("downgrades health when a probe is degraded or unhealthy", () => {
  const degraded = buildHealthPayload("dev", [
    { name: "auth", status: "healthy", message: "ok", latencyMs: 1 },
    { name: "database", status: "degraded", message: "slow", latencyMs: 90 },
  ]);
  if (degraded.status !== "degraded") {
    throw new Error("degraded probe was ignored");
  }

  const unhealthy = buildHealthPayload("dev", [
    { name: "auth", status: "unhealthy", message: "failed", latencyMs: 0 },
    { name: "database", status: "degraded", message: "slow", latencyMs: 90 },
  ]);
  if (unhealthy.status !== "unhealthy") {
    throw new Error("unhealthy probe was ignored");
  }
});

Deno.test("public health payload contains only status and approved version", () => {
  for (
    const [internal, expected] of [
      ["healthy", "healthy"],
      ["degraded", "degraded"],
      ["unhealthy", "unavailable"],
    ] as const
  ) {
    const payload = buildPublicHealthPayload(internal, "release-42");
    if (payload.status !== expected) {
      throw new Error(`unexpected public status for ${internal}`);
    }
    if (payload.version !== "release-42") {
      throw new Error("build version was not preserved");
    }
    if (Object.keys(payload).sort().join(",") !== "status,version") {
      throw new Error("public health response contains diagnostic fields");
    }
  }
});

Deno.test("public health payload does not disclose component or configuration details", () => {
  const internal = buildHealthPayload("release-42", [
    {
      name: "database",
      status: "unhealthy",
      message: "service role key missing",
      latencyMs: 0,
    },
  ]);
  const publicPayload = buildPublicHealthPayload(internal.status, "release-42");
  const serialized = JSON.stringify(publicPayload);
  for (
    const detail of [
      "database",
      "service role",
      "latency",
      "checks",
      "timestamp",
    ]
  ) {
    if (serialized.includes(detail)) {
      throw new Error(`public response disclosed ${detail}`);
    }
  }
});
