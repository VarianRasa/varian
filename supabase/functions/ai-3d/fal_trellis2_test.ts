import {
  buildFalTrellis2Payload,
  cancelFalTrellis2Job,
  createFalTrellis2Job,
  falArtifactUrl,
  falJobId,
  pollFalTrellis2Job,
} from "./fal_trellis2.ts";
import { Ai3DError } from "./helpers.ts";

Deno.test("maps Varian 3D controls to the hosted TRELLIS.2 input contract", () => {
  const payload = buildFalTrellis2Payload({
    imageUrl: "data:image/png;base64,AAAA",
    meshQuality: "high",
    textureMode: "pbr",
    triangleBudget: 100000,
    seed: 123,
  });
  if (payload.image_url !== "data:image/png;base64,AAAA") throw new Error("image URL was not mapped");
  if (payload.resolution !== 1536) throw new Error("high resolution was not mapped");
  if (payload.decimation_target !== 100000) throw new Error("triangle budget was not mapped");
  if (payload.texture_size !== 4096) throw new Error("texture size was not mapped");
  if (payload.seed !== 123) throw new Error("seed was not mapped");
});

Deno.test("runs the hosted TRELLIS.2 queue lifecycle without exposing the key", async () => {
  const previousKey = Deno.env.get("FAL_KEY");
  const previousFetch = globalThis.fetch;
  const requests: Array<{ url: string; method: string; authorization: string | null; body: string }> = [];
  Deno.env.set("FAL_KEY", "unit-test-key");
  let call = 0;
  globalThis.fetch = async (input, init = {}) => {
    const url = String(input);
    requests.push({
      url,
      method: init.method ?? "GET",
      authorization: new Headers(init.headers).get("Authorization"),
      body: typeof init.body === "string" ? init.body : "",
    });
    call += 1;
    if (call === 1) return new Response(JSON.stringify({ request_id: "request-123" }), { status: 200 });
    if (call === 2) return new Response(JSON.stringify({ status: "IN_PROGRESS" }), { status: 200 });
    if (call === 3) return new Response(JSON.stringify({ status: "COMPLETED" }), { status: 200 });
    if (call === 4) {
      return new Response(JSON.stringify({ model_glb: { url: "https://v3b.fal.media/files/model.glb" } }), { status: 200 });
    }
    return new Response(null, { status: 204 });
  };
  try {
    const created = await createFalTrellis2Job({
      imageUrl: "https://images.example.com/chair.png",
      meshQuality: "balanced",
      textureMode: "pbr",
      triangleBudget: 50000,
      seed: -1,
    });
    if (created.jobId !== falJobId("request-123") || created.status !== "queued") {
      throw new Error("queue response was not normalized");
    }
    const processing = await pollFalTrellis2Job(String(created.jobId));
    if (processing.status !== "processing") throw new Error("processing status was not normalized");
    const completed = await pollFalTrellis2Job(String(created.jobId));
    const artifact = completed.artifact as Record<string, unknown> | undefined;
    if (completed.status !== "completed" || artifact?.url !== "https://v3b.fal.media/files/model.glb") {
      throw new Error("completed artifact was not normalized");
    }
    const canceled = await cancelFalTrellis2Job(String(created.jobId));
    if (canceled.status !== "canceled") throw new Error("cancel response was not normalized");
    if (requests[0].authorization !== "Key unit-test-key") throw new Error("FAL authorization was not server-side");
    if (requests[0].url !== "https://queue.fal.run/fal-ai/trellis-2") throw new Error("unexpected queue URL");
    const submitted = JSON.parse(requests[0].body) as Record<string, unknown>;
    if (submitted.image_url !== "https://images.example.com/chair.png" || submitted.seed !== null) {
      throw new Error("queue payload was not normalized");
    }
  } finally {
    globalThis.fetch = previousFetch;
    if (previousKey === undefined) Deno.env.delete("FAL_KEY");
    else Deno.env.set("FAL_KEY", previousKey);
  }
});

Deno.test("accepts only HTTPS fal.media GLB artifacts", () => {
  if (falArtifactUrl("https://v3.fal.media/files/model.glb?token=1") !== "https://v3.fal.media/files/model.glb?token=1") {
    throw new Error("trusted FAL artifact was rejected");
  }
  for (const value of [
    "http://v3.fal.media/files/model.glb",
    "https://evil.example/files/model.glb",
    "https://v3.fal.media/files/model.obj",
    "https://user:pass@v3.fal.media/files/model.glb",
  ]) {
    let rejected = false;
    try {
      falArtifactUrl(value);
    } catch (_) {
      rejected = true;
    }
    if (!rejected) throw new Error(`untrusted FAL artifact was accepted: ${value}`);
  }
});

Deno.test("classifies hosted authorization failures without exposing provider details", async () => {
  const previousKey = Deno.env.get("FAL_KEY");
  const previousFetch = globalThis.fetch;
  Deno.env.set("FAL_KEY", "unit-test-key");
  globalThis.fetch = async () => new Response("provider-secret-detail", { status: 403 });
  try {
    let error: unknown;
    try {
      await createFalTrellis2Job({
        imageUrl: "https://images.example.com/chair.png",
        meshQuality: "draft",
        textureMode: "none",
        triangleBudget: 50000,
        seed: 1,
      });
    } catch (caught) {
      error = caught;
    }
    if (!(error instanceof Ai3DError) || error.code !== "UPSTREAM_AUTH_ERROR") {
      throw new Error("provider authorization failure was not classified");
    }
    if (error.message.includes("provider-secret-detail")) {
      throw new Error("provider response detail leaked");
    }
  } finally {
    globalThis.fetch = previousFetch;
    if (previousKey === undefined) Deno.env.delete("FAL_KEY");
    else Deno.env.set("FAL_KEY", previousKey);
  }
});
