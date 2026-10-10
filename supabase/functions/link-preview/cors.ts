export function resolveAllowedOrigin(
  origin: string | null,
  configuredOriginsValue: string | undefined,
) {
  const configured = (configuredOriginsValue ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  if (origin !== null && isLocalDevelopmentOrigin(origin)) return origin;
  if (configured.length === 0 || configured.includes("*")) return null;
  if (origin !== null && configured.includes(origin)) return origin;
  return null;
}

function isLocalDevelopmentOrigin(origin: string) {
  try {
    const url = new URL(origin);
    const hostname = url.hostname.replace(/^\[|\]$/g, "");
    return (
      url.origin === origin &&
      url.protocol === "http:" &&
      url.port === "3000" &&
      ["localhost", "127.0.0.1", "::1"].includes(hostname)
    );
  } catch (_) {
    return false;
  }
}
