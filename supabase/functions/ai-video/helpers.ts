export type JsonObject = Record<string, unknown>;
export type VideoDuration = "5" | "10";
export type AspectRatio = "16:9" | "9:16" | "1:1";

export type CreateInput = {
  capability: string;
  prompt: string;
  source: string;
  duration: VideoDuration;
  aspectRatio: AspectRatio;
  negativePrompt?: string;
  cameraMotion?: string;
};

export type GradioStreamErrorKind = "provider" | "invalid";

export class GradioStreamError extends Error {
  readonly kind: GradioStreamErrorKind;

  constructor(kind: GradioStreamErrorKind) {
    super(
      kind === "provider" ? "Gradio provider error" : "Invalid Gradio response",
    );
    this.kind = kind;
  }
}

export function isSupportedVideoCapability(value: string): boolean {
  return value === "imageToVideo";
}

export function buildGradioInput(input: CreateInput): unknown[] {
  const prompt = input.cameraMotion === undefined
    ? input.prompt
    : `${input.prompt}\nCamera motion: ${input.cameraMotion}`;
  return [
    { url: input.source },
    prompt,
    512,
    896,
    input.negativePrompt ?? "",
    2,
    1,
    4,
    42,
    true,
  ];
}

export function normalizeSpaceUrl(value: string | undefined): string {
  const raw = value?.trim() || "https://multimodalart-wan2-1-fast.hf.space";
  let url: URL;
  try {
    url = new URL(raw);
  } catch (_) {
    throw new Error("Invalid Hugging Face Space URL");
  }
  const hostname = url.hostname.toLowerCase();
  if (
    url.protocol !== "https:" || url.username || url.password ||
    url.search || url.hash || url.port ||
    (hostname !== "huggingface.co" &&
      !(hostname.endsWith(".hf.space") && hostname.length > ".hf.space".length))
  ) {
    throw new Error("Invalid Hugging Face Space URL");
  }
  return url.origin;
}

export function gradioApiUrl(spaceUrl: string, path: string): string {
  return `${normalizeSpaceUrl(spaceUrl)}/gradio_api${path}`;
}

export function parseGradioEventStream(
  body: string,
  spaceUrl: string,
): string {
  const space = new URL(normalizeSpaceUrl(spaceUrl));
  const events = body.replaceAll("\r\n", "\n").split("\n\n");
  for (const eventBlock of events) {
    let eventName = "message";
    const dataLines: string[] = [];
    for (const line of eventBlock.split("\n")) {
      if (line.startsWith("event:")) {
        eventName = line.slice("event:".length).trim();
      } else if (line.startsWith("data:")) {
        dataLines.push(line.slice("data:".length).trimStart());
      }
    }
    if (eventName === "error") {
      throw new GradioStreamError("provider");
    }
    if (eventName !== "complete") continue;

    let data: unknown;
    try {
      data = JSON.parse(dataLines.join("\n"));
    } catch (_) {
      throw new GradioStreamError("invalid");
    }
    if (!Array.isArray(data) || !isJsonObject(data[0])) {
      throw new GradioStreamError("invalid");
    }
    const video = data[0].video;
    if (!isJsonObject(video) || typeof video.url !== "string") {
      throw new GradioStreamError("invalid");
    }
    let videoUrl: URL;
    try {
      videoUrl = new URL(video.url);
    } catch (_) {
      throw new GradioStreamError("invalid");
    }
    if (
      videoUrl.protocol !== "https:" || videoUrl.username ||
      videoUrl.password ||
      videoUrl.hostname.toLowerCase() !== space.hostname ||
      videoUrl.port !== space.port
    ) {
      throw new GradioStreamError("invalid");
    }
    return videoUrl.toString();
  }
  throw new GradioStreamError("invalid");
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
