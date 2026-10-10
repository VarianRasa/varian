import {
  assertAllowedOpenverseUrl,
  assertAuthenticatedJwt,
  AssetLibraryProxyError,
  buildOpenverseUrl,
  fetchOpenverseJson,
  resolveAllowedOrigin,
} from "./helpers.ts";

Deno.test("requires a verified authenticated-user JWT claim", () => {
  const payload = (claims: Record<string, unknown>) =>
    `Bearer e30.${base64Url(JSON.stringify(claims))}.sig`;

  assertAuthenticatedJwt(
    payload({
      role: "authenticated",
      sub: "00000000-0000-4000-8000-000000000001",
    }),
  );
  for (
    const authorization of [
      payload({ role: "anon" }),
      payload({ role: "authenticated" }),
      "Bearer e30.e30.e30",
      "Bearer not-a-jwt",
    ]
  ) {
    try {
      assertAuthenticatedJwt(authorization);
      throw new Error("accepted a non-user JWT");
    } catch (error) {
      if (!(error instanceof AssetLibraryProxyError) || error.status !== 401) {
        throw error;
      }
    }
  }
});

function base64Url(value: string): string {
  return btoa(value).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

Deno.test("builds only bounded Openverse image and audio URLs", () => {
  const image = buildOpenverseUrl(
    new URL(
      "https://example.test/functions/v1/asset-library/images/?q=lake&page=2&page_size=12",
    ),
  );
  if (
    image.toString() !==
      "https://api.openverse.org/v1/images/?q=lake&page=2&page_size=12"
  ) {
    throw new Error(`unexpected image URL: ${image}`);
  }

  const audio = buildOpenverseUrl(
    new URL(
      "https://example.test/functions/v1/asset-library?kind=audio&q=voice",
    ),
  );
  if (
    audio.pathname !== "/v1/audio/" || audio.searchParams.get("q") !== "voice"
  ) {
    throw new Error("audio route was not normalized");
  }

  for (
    const value of [
      "https://example.test/functions/v1/asset-library/images?page_size=101",
      "https://example.test/functions/v1/asset-library/images?page=0",
      "https://example.test/functions/v1/asset-library/images?page=2%0A",
      "https://example.test/functions/v1/asset-library/images?q=lake%0A",
      `https://example.test/functions/v1/asset-library/images?q=${
        "x".repeat(201)
      }`,
    ]
  ) {
    try {
      buildOpenverseUrl(new URL(value));
      throw new Error(`accepted invalid provider query: ${value}`);
    } catch (error) {
      if (!(error instanceof AssetLibraryProxyError) || error.status !== 400) {
        throw error;
      }
    }
  }
});

Deno.test("allows only the fixed Openverse upstream", () => {
  assertAllowedOpenverseUrl(
    new URL("https://api.openverse.org/v1/images/?q=lake&page=1&page_size=24"),
  );

  for (
    const value of [
      "http://api.openverse.org/v1/images/?q=lake&page=1&page_size=24",
      "https://evil.example/v1/images/?q=lake&page=1&page_size=24",
      "https://api.openverse.org/v1/other/?q=lake&page=1&page_size=24",
      "https://api.openverse.org/v1/images/?q=lake&page=1&page_size=24&next=1",
    ]
  ) {
    try {
      assertAllowedOpenverseUrl(new URL(value));
      throw new Error(`accepted unsafe upstream URL: ${value}`);
    } catch (error) {
      if (!(error instanceof AssetLibraryProxyError) || error.status !== 502) {
        throw error;
      }
    }
  }
});

Deno.test("rejects redirects to another host or endpoint", async () => {
  const source = new URL(
    "https://api.openverse.org/v1/images/?q=lake&page=1&page_size=24",
  );
  for (
    const location of [
      "https://evil.example/steal",
      "https://api.openverse.org/v1/audio/?q=lake&page=1&page_size=24",
      " https://api.openverse.org/v1/images/?q=lake&page=2&page_size=24",
    ]
  ) {
    try {
      await fetchOpenverseJson(
        source,
        () =>
          Promise.resolve(
            new Response(null, { status: 302, headers: { location } }),
          ),
      );
      throw new Error(`accepted unsafe redirect: ${location}`);
    } catch (error) {
      if (!(error instanceof AssetLibraryProxyError) || error.status !== 502) {
        throw error;
      }
    }
  }
});

Deno.test("follows a bounded same-endpoint redirect and validates JSON", async () => {
  let calls = 0;
  const result = await fetchOpenverseJson(
    new URL("https://api.openverse.org/v1/images/?q=lake&page=1&page_size=24"),
    (_url) => {
      calls += 1;
      if (calls === 1) {
        return Promise.resolve(
          new Response(null, {
            status: 302,
            headers: {
              location:
                "https://api.openverse.org/v1/images/?q=lake&page=2&page_size=24",
            },
          }),
        );
      }
      return Promise.resolve(
        new Response('{"results":[]}', {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    },
  );
  if (calls !== 2 || result.finalUrl.searchParams.get("page") !== "2") {
    throw new Error("same-host redirect was not followed safely");
  }
  if (new TextDecoder().decode(result.body) !== '{"results":[]}') {
    throw new Error("provider body was not preserved");
  }
});

Deno.test("rejects malformed JSON shapes and unsafe provider URLs", async () => {
  const source = new URL(
    "https://api.openverse.org/v1/images/?q=lake&page=1&page_size=24",
  );
  for (
    const body of [
      "{}",
      JSON.stringify({ results: [{ id: "1", url: "http://evil.example/a" }] }),
      JSON.stringify({ results: [{ id: "1", url: " https://example.org/a" }] }),
      JSON.stringify({ results: new Array(101).fill({ id: "1" }) }),
    ]
  ) {
    try {
      await fetchOpenverseJson(
        source,
        () =>
          Promise.resolve(
            new Response(body, {
              status: 200,
              headers: { "content-type": "application/json" },
            }),
          ),
      );
      throw new Error("accepted a malformed provider shape");
    } catch (error) {
      if (!(error instanceof AssetLibraryProxyError) || error.status !== 502) {
        throw error;
      }
    }
  }
});

Deno.test("rejects oversized or non-JSON provider responses", async () => {
  const source = new URL(
    "https://api.openverse.org/v1/images/?q=lake&page=1&page_size=24",
  );
  for (
    const response of [
      new Response("not json", {
        status: 200,
        headers: {
          "content-type": "text/plain",
          "content-length": "8",
        },
      }),
      new Response("{}", {
        status: 200,
        headers: {
          "content-type": "application/json",
          "content-length": "999999999",
        },
      }),
    ]
  ) {
    try {
      await fetchOpenverseJson(source, () => Promise.resolve(response));
      throw new Error("accepted an invalid provider response");
    } catch (error) {
      if (!(error instanceof AssetLibraryProxyError) || error.status !== 502) {
        throw error;
      }
    }
  }
});

Deno.test("resolves configured CORS origins without allowing arbitrary origins", () => {
  if (
    resolveAllowedOrigin("https://app.example", "https://app.example") !==
      "https://app.example"
  ) {
    throw new Error("configured origin was rejected");
  }
  if (
    resolveAllowedOrigin("https://evil.example", "https://app.example") !== null
  ) {
    throw new Error("unconfigured origin was accepted");
  }
  if (resolveAllowedOrigin(null, "https://app.example") !== null) {
    throw new Error("null origin should not receive configured CORS");
  }
});
