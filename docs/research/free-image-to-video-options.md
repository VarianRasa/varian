# Free / no-credit-card image-to-video options

**Research date:** 2026-08-24
**Scope:** image-to-video (I2V) for a Flutter Web/Desktop client; primary official sources only.
**Application code changed:** no.

## Executive decision

- **Best genuinely free hosted prototype:** a public Hugging Face ZeroGPU Space, such as the currently public [`multimodalart/wan2-1-fast`](https://huggingface.co/spaces/multimodalart/wan2-1-fast). Hugging Face documents an unauthenticated ZeroGPU allowance of **2 minutes of GPU time per day**. The Space currently exposes a Gradio `/generate_video` endpoint and uses Wan2.1 I2V 14B plus a CausVid LoRA. This is suitable for a demo or manual evaluation, not a dependable production API.
- **Best local option when the Windows machine has 24 GB VRAM:** **Wan2.2 TI2V-5B**. The model authors explicitly document I2V and T2V at 720p and a single-GPU requirement of at least **24 GB VRAM**, giving RTX 4090 as the example. It has no hosted-call cost or card requirement, but local deployment still needs a CUDA-capable NVIDIA GPU and Python/PyTorch setup.
- **Best local low-VRAM candidate:** **CogVideoX-5B-I2V** through the optimized Diffusers path. The official model card reports **from 5 GB VRAM** in BF16 and **from 4.4 GB** with INT8, but calls these optimized minimums tested on A100/H100-class systems. Treat an 8 GB card as a tight experiment and a 12 GB card as a safer planning target; the latter is an engineering recommendation, not an official minimum.
- **Best local speed/quality candidate to test below 24 GB:** **LTX-Video 2B distilled**. Lightricks documents I2V, calls the 2B distilled model suitable for light VRAM, and provides a local CUDA/PyTorch path, but does **not** publish a hard VRAM floor or a native-Windows support guarantee. Do not promise a specific GPU until it is tested on the target machine.
- **Flutter architecture:** keep Flutter as the UI/client. For Desktop, call a local Python inference service. For Web, use a server-side proxy or hosted backend. Do not put Hugging Face, fal, or Replicate credentials in a Flutter Web bundle.

## Comparison at a glance

| Option | I2V verified? | Free/no card | Realistic use | Flutter fit | Verdict |
|---|---:|---|---|---|---|
| Public HF ZeroGPU Space | Yes, if the selected Space implements I2V | Yes for anonymous quota | Short demos; shared queue | HTTP/Gradio API, but unstable | Best free hosted prototype |
| HF Inference Providers | Yes; current client table lists `fal-ai` and `wavespeed` | Free user gets $0.10/month, subject to change; HF token required | Small authenticated experiments | Good through a server proxy | Best documented provider API for a tiny prototype |
| fal direct | Yes, many video models | API key and metered billing | Production after payment setup | Good through a server proxy | Not anonymous/free |
| Replicate direct | Yes, including LTX and Wan community models | API token; selected models have limited free trials, then billing | Paid prototype/production | Good through a server proxy | Not a dependable no-card path |
| Wan2.2 TI2V-5B local | Yes | No per-call cost | 720p local generation | Desktop/local service | Best documented 24 GB-class local target |
| LTX-Video 2B distilled local | Yes | No per-call cost | Fast local iteration | Desktop/local service | Best candidate below 24 GB, but validate VRAM |
| CogVideoX-5B-I2V local | Yes | No per-call cost | 480p, six-second clips | Desktop/local service | Lowest documented optimized memory floor |
| Colab | Yes for the official CogVideoX I2V notebook | Free, but resources are variable | Manual notebook experiments | Not a product backend | Useful for evaluation only |
| Kaggle Notebooks | No product-grade I2V path verified from official docs | Not scored | No stable official I2V/API evidence found | Not recommended | Excluded from the recommendation |

## Hugging Face Inference Providers

### Current I2V support

Hugging Face's official `InferenceClient` reference defines [`image_to_video`](https://huggingface.co/docs/huggingface_hub/v1.27.0/en/package_reference/inference_client#huggingface_hub.InferenceClient.image_to_video). It accepts an image as bytes, a file, a URL, or a PIL image, accepts an optional prompt, and returns video bytes. The reference example uses `Wan-AI/Wan2.2-I2V-A14B`.

The current official provider/task matrix in the [Inference guide](https://huggingface.co/docs/huggingface_hub/guides/inference) lists `image_to_video()` as supported by:

- `fal-ai`
- `wavespeed`

The same table marks the other listed providers, including `hf-inference`, `replicate`, and `together`, as not supporting the unified `image_to_video()` method at the time checked. Provider and model availability can change.

The current Hub model metadata confirms:

- [`Wan-AI/Wan2.2-I2V-A14B`](https://huggingface.co/api/models/Wan-AI/Wan2.2-I2V-A14B?expand%5B%5D=inferenceProviderMapping): live mappings for `fal-ai` and `wavespeed`.
- [`Lightricks/LTX-Video-0.9.8-13B-distilled`](https://huggingface.co/api/models/Lightricks/LTX-Video-0.9.8-13B-distilled?expand%5B%5D=inferenceProviderMapping): a live `fal-ai` I2V mapping.
- [`Wan-AI/Wan2.2-TI2V-5B`](https://huggingface.co/api/models/Wan-AI/Wan2.2-TI2V-5B?expand%5B%5D=inferenceProviderMapping): current mappings are marked `text-to-video`, not I2V; do not infer that its local I2V capability is available through HF Providers.
- [`Wan-AI/Wan2.1-I2V-14B-720P-Diffusers`](https://huggingface.co/api/models/Wan-AI/Wan2.1-I2V-14B-720P-Diffusers?expand%5B%5D=inferenceProviderMapping): no current provider mapping in the checked response.
- [`THUDM/CogVideoX-5b-I2V`](https://huggingface.co/api/models/THUDM/CogVideoX-5b-I2V?expand%5B%5D=inferenceProviderMapping): no current provider mapping in the checked response.

### Free credits, authentication, and card caveats

The official [Inference Providers pricing page](https://huggingface.co/docs/inference-providers/pricing) currently states:

- Free users receive **$0.10/month**, marked **subject to change**.
- PRO users receive $2.00/month; Team/Enterprise organizations receive $2.00 per seat.
- Routed requests use Hugging Face billing, require no separate provider account, and apply the included credits.
- Additional usage requires purchasing credits or using a provider key billed by that provider.

The official [Inference Providers overview](https://huggingface.co/docs/inference-providers/index) requires a Hugging Face user access token with Inference Providers permission. The [token documentation](https://huggingface.co/docs/hub/security-tokens) says the token is sent as a bearer token and must not be leaked.

Exact caveats:

1. This is **not anonymous**: a Hugging Face account and token are required.
2. `$0.10` is a small monthly allowance, not unlimited free inference. The cost of a particular video depends on the selected provider/model; the official pages checked do not promise that a complete I2V request fits inside $0.10.
3. Hugging Face's [billing documentation](https://huggingface.co/docs/hub/en/billing) says the only payment method for compute services is a credit card. The free-credit page does not explicitly state whether every account can redeem the included allowance without adding a card. Therefore, treat this as **possibly card-free for the included allowance, but not an unconditional no-card guarantee**.
4. Never ship a shared HF token in Flutter Web. Use a server-side proxy, or require the user to configure their own local/provider credentials.

**Assessment:** best documented hosted API for a very small authenticated prototype; not a free production backend.

## Hugging Face Spaces and the Gradio API

### Free hardware and quotas

The official [Spaces overview](https://huggingface.co/docs/hub/en/spaces-overview) states:

- CPU Basic: 2 vCPU, 16 GB RAM, 50 GB non-persistent disk, no hourly cost.
- Gradio/Docker Spaces that run on compute normally require a paid plan to create; Static Spaces are free.
- Personal free accounts in good standing can host up to two ZeroGPU Spaces.
- Free CPU Spaces sleep after inactivity; the overview gives the default free hardware lifecycle and sleep behavior.

The official [ZeroGPU documentation](https://huggingface.co/docs/hub/en/spaces-zerogpu) states:

- Existing ZeroGPU Spaces are free for all users.
- Anonymous users receive **2 minutes of GPU quota per day** with low queue priority.
- Free authenticated accounts receive **5 minutes per day** with medium priority.
- PRO users receive 40 minutes per day; paid quota extensions exist.
- ZeroGPU uses a shared RTX Pro 6000 Blackwell allocation: 48 GB VRAM for `large` and 96 GB for `xlarge`.
- A GPU-decorated function defaults to a 60-second maximum unless a longer duration is explicitly configured.

This is the strongest verified answer to “anonymous/free I2V without a card”: an existing public ZeroGPU Space can be used without caller authentication, within the anonymous quota. It is a public demo resource, not a provider SLA.

### Live I2V Space checked

[`multimodalart/wan2-1-fast`](https://huggingface.co/spaces/multimodalart/wan2-1-fast) was public and running on `zero-a10g` when checked. Its official Space API metadata is [`/api/spaces/multimodalart/wan2-1-fast`](https://huggingface.co/api/spaces/multimodalart/wan2-1-fast).

The Space's own source [`app.py`](https://huggingface.co/spaces/multimodalart/wan2-1-fast/raw/main/app.py) verifies:

- Model: `Wan-AI/Wan2.1-I2V-14B-480P-Diffusers`.
- A CausVid LoRA is loaded for fast 4–8-step generation.
- `@spaces.GPU(duration=get_duration)` is used, with a requested duration of 60, 75, or 90 seconds depending on settings.
- The UI clamps output to 8–81 frames at 24 FPS, approximately 0.3–3.4 seconds.
- The API function is named `generate_video` and returns an MP4 path plus a seed.

The live [Gradio API schema](https://multimodalart-wan2-1-fast.hf.space/gradio_api/info) exposes `/generate_video`, accepts an uploaded image plus prompt and generation parameters, and reports `username: null` in the public app configuration. The [Gradio Python client guide](https://www.gradio.app/guides/getting-started-with-the-python-client) documents calling public Spaces programmatically and warns that public Spaces may rate-limit heavy use.

Exact caveats for using this from Flutter:

- The endpoint is owned and maintained by the Space author; its model, API name, hardware, queue, or availability can change without compatibility guarantees.
- Anonymous quota is shared under Hugging Face's ZeroGPU policy and is too small for normal app traffic.
- Queue priority is low for anonymous callers.
- Returned files are Space-hosted temporary artifacts; the app should download them promptly if the endpoint returns a temporary URL.
- A Flutter client would need to implement the Gradio upload/queue protocol or use a small proxy service. A stable typed REST contract is not provided by the Space.
- Do not use this path for private user images unless the privacy and retention behavior of the specific Space has been reviewed.

**Assessment:** use for a no-card demo, QA, and model selection; do not make it the production backend.

## Local open-source models on Windows

All three model families below expose Python/PyTorch/CUDA workflows rather than a Dart-native runtime. The Flutter layer should call a local HTTP/Gradio service on Desktop. The official sources checked describe CUDA/Linux-style commands but do not make a blanket native-Windows support guarantee; validate the exact PyTorch/CUDA dependency set on the target Windows machine.

### Wan2.2 TI2V-5B

Official author repository: [`Wan-Video/Wan2.2`](https://github.com/Wan-Video/Wan2.2).

Verified facts:

- `Wan2.2-TI2V-5B` supports both T2V and I2V.
- It supports 720p output at 24 FPS.
- The official I2V command uses `--offload_model True --convert_model_dtype --t5_cpu`.
- The authors state that the single-GPU I2V path can run on a GPU with **at least 24 GB VRAM**, giving an RTX 4090 as the example for the 5B TI2V path.
- The model repository states the models use the Apache 2.0 license.

Caveats:

- 24 GB is the authors' documented target for the optimized 5B path, not a guarantee for every resolution, frame count, driver, or PyTorch build.
- The 14B `Wan2.2-I2V-A14B` model is a different tier: the official README states **at least 80 GB VRAM** for its single-GPU path. It is not a realistic ordinary Windows desktop target.
- 720p generation is still slow on consumer hardware. The official README says the 5B model can generate a 5-second 720p clip in under 9 minutes on a single consumer GPU without specific optimization; actual time depends on settings.

**Planning verdict:** strongest documented local target when the machine has an RTX 4090-class 24 GB GPU.

### Wan2.1 I2V

Official author repository: [`Wan-Video/Wan2.1`](https://github.com/Wan-Video/Wan2.1) and the [720P Diffusers model card](https://huggingface.co/Wan-AI/Wan2.1-I2V-14B-720P-Diffusers).

Verified facts:

- Wan2.1 provides 14B I2V models for 480p and 720p.
- The repository provides a single-GPU path and an optimized/offload path, plus a Diffusers `WanImageToVideoPipeline`.
- The smaller Wan2.1 1.3B model's official 8.19 GB figure is for **T2V**, not I2V; it is not a substitute for image conditioning.

Caveats:

- The official text checked does not publish a clear I2V VRAM minimum for the 14B model. Do not market it as an 8 GB or 12 GB Windows solution.
- A 24 GB card may work only with offload and reduced settings, but that is an engineering expectation, not an official guarantee.
- Wan2.1 I2V had no current HF Inference Provider mapping in the checked Hub response, so local execution or a third-party Space is the relevant path.

**Planning verdict:** good local model if the target machine is already 24 GB-class or better; less attractive than Wan2.2 TI2V-5B for a new Windows integration because the official hardware target is less explicit.

### LTX-Video

Official author repository: [`Lightricks/LTX-Video`](https://github.com/Lightricks/LTX-Video). Official model card: [`Lightricks/LTX-Video-0.9.8-13B-distilled`](https://huggingface.co/Lightricks/LTX-Video-0.9.8-13B-distilled).

Verified facts:

- LTX-Video supports I2V, keyframe conditioning, video extension, and video-to-video.
- The official model list includes `ltxv-2b-0.9.8-distilled` for light VRAM usage and `ltxv-13b-0.9.8-distilled` for faster generation with a quality trade-off.
- The official local setup was tested with Python 3.10.5, CUDA 12.2, and PyTorch >=2.1.2.
- The official I2V command accepts an image conditioning path and renders through the local Python pipeline.
- The official repository's community section reports an 8-bit community implementation running 720x480x121 on an RTX 4060 8 GB, but explicitly labels that as a community contribution rather than the Lightricks baseline.

Caveats:

- Lightricks does not state a hard VRAM minimum for the official 2B or 13B I2V pipelines in the sources checked.
- “Light VRAM” is directional, not a hardware guarantee. An 8 GB target is plausible for an optimized 2B/quantized setup, but must be tested.
- The 13B model needs substantially more memory than the 2B model; do not select it for an 8 GB/12 GB product baseline without a measured configuration.
- Checkpoint licenses vary. The model card links separate license files for versions; review the exact checkpoint license before redistribution or commercial use.

**Planning verdict:** the first local model to benchmark on an 8–16 GB Windows GPU because it is designed for fast iteration, but record the chosen resolution, frames, precision, and actual peak VRAM before promising support.

### CogVideoX-5B-I2V

Official author repository: [`THUDM/CogVideo`](https://github.com/THUDM/CogVideo). Official I2V model card: [`THUDM/CogVideoX-5b-I2V`](https://huggingface.co/THUDM/CogVideoX-5b-I2V).

Verified facts:

- CogVideoX-5B-I2V supports image-to-video at 720x480.
- The base I2V output is six seconds at 8 FPS.
- The official Diffusers memory table reports **from 5 GB** in BF16 and **from 4.4 GB** with INT8 quantization.
- The official example uses sequential CPU offload, VAE tiling, and VAE slicing.
- The author repository says CogVideoX-5B can run on desktop GPUs such as an RTX 3060.
- The newer CogVideoX1.5-5B-I2V is listed as a higher-resolution/longer-video variant; the official table reports Diffusers BF16 from 10 GB and INT8 from 7 GB for that 1.5 model.

Caveats:

- The reported memory figures are optimized minimums. The model card says the measurements were tested on NVIDIA A100/H100 systems and may not transfer exactly to other GPUs.
- Without the listed optimizations, peak memory can be about three times higher according to the model card.
- INT8 reduces memory but slows inference.
- The base I2V model is limited to 720x480 and six seconds; it is not a 720p production-quality equivalent to Wan2.2.
- The model card uses the CogVideoX license rather than simply Apache 2.0 for the 5B I2V checkpoint; review that license before commercial redistribution.

**Planning verdict:** clearest low-memory experiment. Use 12 GB as a safer Windows planning target even though the official optimized minimum is lower.

## Practical Windows GPU planning

The following separates official facts from conservative engineering planning:

| GPU VRAM | What can reasonably be tested | Status |
|---:|---|---|
| 8 GB | CogVideoX-5B-I2V optimized; LTX 2B distilled/quantized may be possible | CogVideoX memory floor is official; LTX result is unverified planning |
| 12 GB | CogVideoX-5B-I2V is a safer fit; LTX 2B distilled is the main candidate | Planning recommendation, not a vendor guarantee |
| 16 GB | LTX 2B distilled and CogVideoX variants are the practical first tests; Wan2.1 14B is not a documented target | Planning recommendation |
| 24 GB | Wan2.2 TI2V-5B is the documented consumer target; LTX 13B may be testable with the right configuration | Wan2.2 floor is official; LTX 13B fit is unverified |
| 48–80 GB | Larger Wan/LTX configurations become more realistic | Exact model/configuration still controls the requirement |

For every local option, benchmark the actual combination of resolution, frame count, precision, CPU offload, and VAE settings. “Minimum VRAM” is not the same as a responsive app configuration.

## Google Colab and Kaggle

### Google Colab

Colab is relevant for manual model evaluation because the official [CogVideo repository](https://github.com/THUDM/CogVideo) links an official [CogVideoX-5B-I2V Colab notebook](https://colab.research.google.com/drive/17CqYCqSwz39nZAX2YyonDxosVKUZGzcX?usp=sharing).

The official [Colab FAQ](https://research.google.com/colaboratory/faq.html) states:

- Colab is free of charge and can provide GPUs/TPUs.
- Free resources are not guaranteed or unlimited; hardware, GPU availability, idle timeouts, and usage limits fluctuate.
- Free runtimes can run for at most 12 hours, depending on availability and usage.
- Free managed runtimes prohibit remote proxies and prohibit bypassing the notebook UI to interact primarily through a web UI.
- Colab also lists media serving and deepfake creation among prohibited activities on managed runtimes.

**Conclusion:** use Colab to compare models or create a one-off test video. Do not expose a Flutter production API through a free Colab runtime; it is unstable and the documented free-runtime restrictions directly conflict with using it as a web service.

### Kaggle

The official [Kaggle Notebooks documentation](https://www.kaggle.com/docs/notebooks) confirms the notebook product, but the official pages checked did not provide a stable, model-specific I2V endpoint or a quota statement suitable for a product commitment. No Kaggle-specific I2V service was included in the recommendation. Treat Kaggle as an optional manual notebook experiment only, after checking the current account's UI and terms.

## Hosted provider audit: anonymous and free without a card

| Provider/path | Anonymous? | I2V? | Card-free status | Exact caveat |
|---|---:|---:|---|---|
| Existing HF ZeroGPU Space | **Yes** | Yes, Space-dependent | Anonymous ZeroGPU quota is documented | Shared public demo; 2 GPU minutes/day, low priority, no SLA |
| HF Inference Providers | No | Yes through `fal-ai`/`wavespeed` mappings | $0.10 free-user credits are documented; unconditional card-free redemption is not | Requires HF account/token; extra use is paid |
| fal direct Model APIs | No | Yes | No general free I2V allowance verified | Official auth docs require an API key for model calls; pricing is usage-based |
| Replicate direct | No | Yes | Select models may be free temporarily | Official docs require an API token; pricing pages show paid I2V models and say free access ends after a bit |
| Free Colab runtime | Account-based, not anonymous API | Notebook-dependent | Free | Not a stable API; free-runtime web-service/proxy bypass is restricted |

Supporting primary sources:

- [HF ZeroGPU quotas](https://huggingface.co/docs/hub/en/spaces-zerogpu)
- [HF Inference Providers pricing](https://huggingface.co/docs/inference-providers/pricing)
- [fal authentication](https://fal.ai/docs/documentation/model-apis/authentication)
- [fal pricing](https://fal.ai/pricing)
- [Replicate API tokens](https://replicate.com/docs/topics/security/api-tokens)
- [Replicate billing and free limits](https://replicate.com/docs/topics/billing)
- [Replicate pricing](https://replicate.com/pricing)

### Final answer to the no-card question

- **Yes, for a limited public-demo path:** an existing public HF ZeroGPU I2V Space can be called anonymously within the documented quota. The checked Wan Space is a concrete current example.
- **No, for a dependable anonymous hosted API:** no provider among the official HF routed API, fal direct API, or Replicate API was verified to offer unlimited or production-suitable anonymous/free I2V without credentials and billing controls.
- **For a no-card product path:** local inference is the only predictable option. Use a local service on Windows Desktop, and use a server-side hosted backend for Web if users do not have suitable GPUs.

## Recommended implementation boundary for the Flutter app

1. **Flutter Desktop + user has NVIDIA GPU:** run LTX 2B distilled or CogVideoX-5B-I2V locally behind a small Python service; offer Wan2.2 TI2V-5B when the machine has a documented 24 GB-class GPU.
2. **Flutter Web demo with zero budget:** call a public ZeroGPU Space only through a deliberately disposable adapter/proxy, enforce small input/output limits, and expect outages and quota errors.
3. **Flutter Web or Desktop shared product:** route through a server-side provider adapter. HF Inference Providers is the cheapest documented first experiment because the user gets a small routed credit allowance, but it still needs an HF token and must stop before paid overage.
4. **Security:** never embed a shared HF/fal/Replicate token in Flutter Web. The official HF and provider security docs treat these tokens as secrets.

## Sources

All sources below are first-party documentation, official model cards, official author repositories, or official service API responses.

- [Hugging Face Inference Providers overview](https://huggingface.co/docs/inference-providers/index)
- [Hugging Face Inference Providers pricing](https://huggingface.co/docs/inference-providers/pricing)
- [Hugging Face Inference guide and provider/task matrix](https://huggingface.co/docs/huggingface_hub/guides/inference)
- [Hugging Face `InferenceClient.image_to_video`](https://huggingface.co/docs/huggingface_hub/v1.27.0/en/package_reference/inference_client#huggingface_hub.InferenceClient.image_to_video)
- [Hugging Face image-to-video task](https://huggingface.co/tasks/image-to-video)
- [Hugging Face user access tokens](https://huggingface.co/docs/hub/security-tokens)
- [Hugging Face billing](https://huggingface.co/docs/hub/en/billing)
- [Hugging Face Spaces overview](https://huggingface.co/docs/hub/en/spaces-overview)
- [Hugging Face Spaces ZeroGPU](https://huggingface.co/docs/hub/en/spaces-zerogpu)
- [Hugging Face Gradio API client guide](https://www.gradio.app/guides/getting-started-with-the-python-client)
- [Live Wan2.1 Fast Space](https://huggingface.co/spaces/multimodalart/wan2-1-fast)
- [Live Wan2.1 Fast Space source](https://huggingface.co/spaces/multimodalart/wan2-1-fast/raw/main/app.py)
- [Live Wan2.1 Fast Space metadata](https://huggingface.co/api/spaces/multimodalart/wan2-1-fast)
- [Live Wan2.1 Fast Gradio API schema](https://multimodalart-wan2-1-fast.hf.space/gradio_api/info)
- [Wan2.2 official repository](https://github.com/Wan-Video/Wan2.2)
- [Wan2.1 official repository](https://github.com/Wan-Video/Wan2.1)
- [Wan2.1 I2V 720P Diffusers model card](https://huggingface.co/Wan-AI/Wan2.1-I2V-14B-720P-Diffusers)
- [LTX-Video official repository](https://github.com/Lightricks/LTX-Video)
- [LTX-Video 0.9.8 distilled model card](https://huggingface.co/Lightricks/LTX-Video-0.9.8-13B-distilled)
- [CogVideo official repository](https://github.com/THUDM/CogVideo)
- [CogVideoX-5B-I2V model card](https://huggingface.co/THUDM/CogVideoX-5b-I2V)
- [Google Colab FAQ](https://research.google.com/colaboratory/faq.html)
- [Official CogVideoX I2V Colab notebook](https://colab.research.google.com/drive/17CqYCqSwz39nZAX2YyonDxosVKUZGzcX?usp=sharing)
- [Kaggle Notebooks documentation](https://www.kaggle.com/docs/notebooks)
- [fal Model APIs quick start](https://fal.ai/docs/documentation/model-apis/quickstart)
- [fal Model APIs authentication](https://fal.ai/docs/documentation/model-apis/authentication)
- [fal pricing](https://fal.ai/pricing)
- [Replicate pricing](https://replicate.com/pricing)
- [Replicate API tokens](https://replicate.com/docs/topics/security/api-tokens)
- [Replicate billing](https://replicate.com/docs/topics/billing)
