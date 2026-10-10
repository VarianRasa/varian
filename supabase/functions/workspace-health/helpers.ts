export type HealthStatus = "healthy" | "degraded" | "unhealthy";

export type PublicHealthStatus = "healthy" | "degraded" | "unavailable";

export type HealthCheck = {
  name: string;
  status: HealthStatus;
  message: string;
  latencyMs: number;
};

export function buildHealthPayload(
  version: string,
  checks: HealthCheck[],
  now = new Date(),
): {
  status: HealthStatus;
  version: string;
  timestamp: string;
  checks: HealthCheck[];
} {
  const status = checks.some((check) => check.status === "unhealthy")
    ? "unhealthy"
    : checks.some((check) => check.status === "degraded")
    ? "degraded"
    : "healthy";
  return { status, version, timestamp: now.toISOString(), checks };
}

export function buildPublicHealthPayload(
  status: HealthStatus,
  version: string,
): { status: PublicHealthStatus; version: string } {
  return {
    status: status === "unhealthy" ? "unavailable" : status,
    version,
  };
}
