import {
  buildGradioInput,
  gradioApiUrl,
  isSupportedVideoCapability,
  normalizeSpaceUrl,
  parseGradioEventStream,
} from "./helpers.ts";

const DEFAULT_SPACE_URL = "https://multimodalart-wan2-1-fast.hf.space";

Deno.test("buildGradioInput maps both image source forms to the exact data array", () => {
  for (
    const source of [
      "data:image/png;base64,AAAA",
      "https://images.example.com/source.png",
    ]
  ) {
    const payload = buildGradioInput({
      capability: "imageToVideo",
      prompt: "animate the facade",
      source,
      duration: "5",
      aspectRatio: "16:9",
      negativePrompt: "blurry",
    });
    const expected = [
      { url: source },
      "animate the facade",
      512,
      896,
      "blurry",
      2,
      1,
      4,
      42,
      true,
    ];
    if (JSON.stringify(payload) !== JSON.stringify(expected)) {
      throw new Error(`unexpected payload: ${JSON.stringify(payload)}`);
    }
  }
});

Deno.test("gradioApiUrl adds the Gradio API prefix to the Space origin", () => {
  const url = gradioApiUrl(
    "https://multimodalart-wan2-1-fast.hf.space/",
    "/call/generate_video",
  );
  if (
    url !==
      "https://multimodalart-wan2-1-fast.hf.space/gradio_api/call/generate_video"
  ) {
    throw new Error(`unexpected Gradio API URL: ${url}`);
  }
});

Deno.test("keeps only imageToVideo supported", () => {
  if (!isSupportedVideoCapability("imageToVideo")) {
    throw new Error("imageToVideo must be supported");
  }
  for (
    const capability of [
      "videoFromImage",
      "firstLastFrame",
      "cameraMotion",
      "animateObject",
      "videoRestyle",
    ]
  ) {
    if (isSupportedVideoCapability(capability)) {
      throw new Error(`${capability} must not be supported`);
    }
  }
});

Deno.test("parseGradioEventStream extracts the completed video URL", () => {
  const body = [
    "event: generating",
    'data: [{"video":null},42]',
    "",
    "event: complete",
    'data: [{"video":{"path":"/tmp/video.mp4","url":"https://multimodalart-wan2-1-fast.hf.space/file=video.mp4"}},42]',
    "",
  ].join("\n");
  const videoUrl = parseGradioEventStream(body, DEFAULT_SPACE_URL);
  if (
    videoUrl !== "https://multimodalart-wan2-1-fast.hf.space/file=video.mp4"
  ) {
    throw new Error(`unexpected video URL: ${videoUrl}`);
  }
});

Deno.test("parseGradioEventStream rejects unsafe or incomplete terminal events", () => {
  const bodies = [
    'event: error\ndata: ["generation failed"]\n',
    'event: complete\ndata: [{"video":{}}]\n',
    'event: complete\ndata: [{"video":{"url":"http://multimodalart-wan2-1-fast.hf.space/file=video.mp4"}}]\n',
    'event: complete\ndata: [{"video":{"url":"https://other.hf.space/file=video.mp4"}}]\n',
  ];
  for (const body of bodies) {
    let rejected = false;
    try {
      parseGradioEventStream(body, DEFAULT_SPACE_URL);
    } catch (_) {
      rejected = true;
    }
    if (!rejected) throw new Error(`expected rejection for: ${body}`);
  }
});

Deno.test("normalizeSpaceUrl defaults and rejects non-HF hosts", () => {
  if (normalizeSpaceUrl(undefined) !== DEFAULT_SPACE_URL) {
    throw new Error("missing Space URL must use the public default");
  }
  if (
    normalizeSpaceUrl("https://custom.hf.space/") !== "https://custom.hf.space"
  ) {
    throw new Error("HF Space URL was not normalized");
  }
  if (
    normalizeSpaceUrl("https://huggingface.co/") !== "https://huggingface.co"
  ) {
    throw new Error("huggingface.co should be allowed");
  }
  let rejected = false;
  try {
    normalizeSpaceUrl("https://example.com");
  } catch (_) {
    rejected = true;
  }
  if (!rejected) throw new Error("non-HF host must be rejected");
});
