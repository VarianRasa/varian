import { resolveAllowedOrigin } from "./cors.ts";

Deno.test("allows the local creative canvas origin with an explicit allowlist", () => {
  const origin = "http://localhost:3000";
  const actual = resolveAllowedOrigin(origin, "https://app.example.com");
  if (actual !== origin) {
    throw new Error(`Expected ${origin}, got ${actual}`);
  }
});

Deno.test("allows configured production origins", () => {
  const origin = "https://app.example.com";
  const actual = resolveAllowedOrigin(
    origin,
    "https://app.example.com,https://staging.example.com",
  );
  if (actual !== origin) {
    throw new Error(`Expected ${origin}, got ${actual}`);
  }
});

Deno.test("fails closed for unset and empty production allowlists", () => {
  for (const configured of [undefined, ""]) {
    if (resolveAllowedOrigin("https://app.example.com", configured) !== null) {
      throw new Error("Expected an unset or empty allowlist to reject origins");
    }
  }
});

Deno.test("rejects wildcard configuration instead of reflecting an open origin", () => {
  for (
    const origin of ["https://app.example.com", "https://attacker.example"]
  ) {
    if (resolveAllowedOrigin(origin, "*") !== null) {
      throw new Error(`Wildcard configuration must not allow ${origin}`);
    }
  }
});

Deno.test("rejects unconfigured non-local origins", () => {
  const actual = resolveAllowedOrigin(
    "https://untrusted.example",
    "https://app.example.com",
  );
  if (actual !== null) {
    throw new Error(`Expected a rejected origin, got ${actual}`);
  }
});

Deno.test("does not open arbitrary local ports", () => {
  const actual = resolveAllowedOrigin(
    "http://localhost:3001",
    "https://app.example.com",
  );
  if (actual !== null) {
    throw new Error(`Expected a rejected origin, got ${actual}`);
  }
});
