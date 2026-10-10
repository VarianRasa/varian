import {
  enforceRateLimitForTests,
  handleLinkPreview,
  resetRateLimitForTests,
  setLinkPreviewDependenciesForTests,
} from "./index.ts";
Deno.env.set("ALLOWED_ORIGINS", "");

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function responseWithStream(stream: ReadableStream<Uint8Array>) {
  return new Response(stream, { headers: { "content-type": "text/html" } });
}

Deno.test("link preview rejects redirects to private addresses before a second fetch", async () => {
  let fetches = 0;
  setLinkPreviewDependenciesForTests({
    resolveDns: async () => ["93.184.216.34"],
    fetcher: async () => {
      fetches += 1;
      return new Response(null, {
        status: 302,
        headers: { location: "http://127.0.0.1/admin" },
      });
    },
  });
  try {
    const response = await handleLinkPreview(
      new Request("https://service.test", {
        method: "POST",
        body: JSON.stringify({ url: "https://example.test" }),
      }),
    );
    assert(
      response.status === 400,
      "private redirect destination must be rejected",
    );
    assert(fetches === 1, "handler must not fetch unsafe redirect destination");
  } finally {
    setLinkPreviewDependenciesForTests(null);
  }
});

Deno.test("link preview rejects mixed public and private DNS answers", async () => {
  setLinkPreviewDependenciesForTests({
    resolveDns: async (_hostname, type) =>
      type === "A" ? ["93.184.216.34", "10.0.0.8"] : [],
    fetcher: async () =>
      new Response("<title>unexpected</title>", {
        headers: { "content-type": "text/html" },
      }),
  });
  try {
    const response = await handleLinkPreview(
      new Request("https://service.test", {
        method: "POST",
        body: JSON.stringify({ url: "https://example.test" }),
      }),
    );
    assert(response.status === 400, "mixed answer set must fail closed");
  } finally {
    setLinkPreviewDependenciesForTests(null);
  }
});

Deno.test("link preview cancels and rejects oversized streamed responses", async () => {
  let cancelled = false;
  setLinkPreviewDependenciesForTests({
    resolveDns: async () => ["93.184.216.34"],
    fetcher: async () =>
      responseWithStream(
        new ReadableStream<Uint8Array>({
          pull(controller) {
            controller.enqueue(new Uint8Array(1024 * 1024 + 1));
          },
          cancel() {
            cancelled = true;
          },
        }),
      ),
  });
  try {
    const response = await handleLinkPreview(
      new Request("https://service.test", {
        method: "POST",
        body: JSON.stringify({ url: "https://example.test" }),
      }),
    );
    assert(response.status === 413, "oversized response must be rejected");
    assert(cancelled, "oversized upstream stream must be cancelled");
  } finally {
    setLinkPreviewDependenciesForTests(null);
  }
});

Deno.test("link preview deadline covers a stalled response body", async () => {
  let cancelled = false;
  setLinkPreviewDependenciesForTests({
    resolveDns: async () => ["93.184.216.34"],
    fetcher: async (_input, init) => {
      let controllerRef:
        | ReadableStreamDefaultController<Uint8Array>
        | undefined;
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          controllerRef = controller;
        },
      });
      init?.signal?.addEventListener("abort", () => {
        controllerRef?.error(new DOMException("aborted", "AbortError"));
        cancelled = true;
      }, { once: true });
      return responseWithStream(stream);
    },
  });
  try {
    const response = await handleLinkPreview(
      new Request("https://service.test", {
        method: "POST",
        body: JSON.stringify({ url: "https://example.test" }),
      }),
    );
    assert(
      response.status === 504,
      "stalled response body must hit upstream timeout",
    );
    assert(cancelled, "timeout must cancel the response stream");
  } finally {
    setLinkPreviewDependenciesForTests(null);
  }
});

Deno.test("link preview rejects credentials and unsafe ports before network calls", async () => {
  let fetches = 0;
  setLinkPreviewDependenciesForTests({
    fetcher: async () => {
      fetches += 1;
      return new Response("unexpected");
    },
  });
  try {
    const credentialResponse = await handleLinkPreview(
      new Request("https://service.test", {
        method: "POST",
        body: JSON.stringify({ url: "https://user:pass@example.test" }),
      }),
    );
    assert(
      credentialResponse.status === 400,
      "URL credentials must be rejected",
    );
    const portResponse = await handleLinkPreview(
      new Request("https://service.test", {
        method: "POST",
        body: JSON.stringify({ url: "https://example.test:8443" }),
      }),
    );
    assert(portResponse.status === 400, "unsafe ports must be rejected");
    assert(fetches === 0, "invalid URLs must not be fetched");
  } finally {
    setLinkPreviewDependenciesForTests(null);
  }
});

Deno.test("rate limiter ignores spoofed forwarded IP and bounds the anonymous bucket", () => {
  resetRateLimitForTests();
  const request = new Request("https://service.test", {
    headers: { "x-forwarded-for": "192.0.2.10" },
  });
  for (let index = 0; index < 30; index += 1) {
    enforceRateLimitForTests(request, 0);
  }
  let rejected = false;
  try {
    enforceRateLimitForTests(request, 30);
  } catch {
    rejected = true;
  }
  assert(
    rejected,
    "spoofed forwarding header must not create another quota bucket",
  );
});
