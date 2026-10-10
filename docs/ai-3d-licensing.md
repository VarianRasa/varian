# AI 3D Licensing and Provenance

This is a technical inventory for the Varian integration, not legal advice.
Review the exact checkpoint, custom node, and package license before each
release. Generated user content can have separate terms from the software that
produced it.

## Approved integration shape

Flutter does not bundle model checkpoints. A worker owns the provider runtime,
Blender post-processing, provenance, and license notices. The production path
keeps the worker behind the authenticated Supabase Edge Function and returns a
validated GLB artifact.

## Component inventory

| Component | Role | Repository/license status | Release decision |
| --- | --- | --- | --- |
| TripoSR | Default MVP image-to-3D provider | Upstream repository declares MIT for its implementation; verify the exact checkpoint files and any downloaded dependencies at provisioning time. | Approved as the current local MVP after recording revision and checkpoint provenance. |
| TRELLIS.2 | High-fidelity image-to-3D provider | Upstream repository and `microsoft/TRELLIS.2-4B` model card declare MIT. Source, model, CUDA, renderer, and native dependency revisions are pinned in `tool/ai_3d_worker/provider-lock.json`; the image build records the resolved Python BOM. | Linux GPU deployment only; keep disabled for commercial use until the NVIDIA native dependency terms and `o_voxel` licensing are cleared. |
| FAL hosted TRELLIS.2 | Hosted remote image-to-3D fallback for `fal-trellis2` | Uses the hosted `fal-ai/trellis-2` API. The provider key, request payload, and upstream artifact URL remain server-side; hosted-service terms, retention, and metered pricing apply separately from the open-source TRELLIS.2 source license. | Explicit opt-in only; keep TripoSR as default and review FAL terms, budget, and data handling before user rollout. |
| Hunyuan3D-2.1 | Optional image-to-3D provider | Uses the Tencent Hunyuan 3D 2.1 Community License, not a permissive OSI license. The license restricts territory, use, distribution notices, hosted-service disclosure, AUP compliance, model improvement, and products above one million monthly active users without a separate Tencent license. | Technical license review completed on 2026-09-11 with a no-go production decision. Keep disabled unless geography, notices, AUP controls, user terms, and any commercial approval are verified. |
| Blender | Headless normalization, triangle budget, preview, and GLB export | Blender is GPL-licensed and is executed as a separate process. | Keep the executable and notices separate from the Flutter bundle unless redistribution obligations are accepted. |
| ComfyUI | Optional workflow orchestrator | ComfyUI is GPL-licensed. Every custom node and model checkpoint has its own license. | Direct provider accepts an externally installed, pinned API workflow and requires a separate custom-node review. |

## Required provenance record

Record these values beside every deployed worker image or machine:

- provider name and adapter revision;
- upstream repository commit;
- model/checkpoint identifier, revision, and download source;
- Blender version and executable source;
- ComfyUI version, workflow JSON hash, and every custom-node commit;
- Python package lock or metadata, including transitive provider packages;
- license files and attribution notices shipped with the worker.

## Current repository references

- TripoSR: https://github.com/VAST-AI-Research/TripoSR
- TRELLIS.2: https://github.com/microsoft/TRELLIS.2
- Hunyuan3D-2.1: https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1
- Blender: https://www.blender.org/about/license/
- ComfyUI: https://github.com/Comfy-Org/ComfyUI

The repository records the provider revisions in `tool/ai_3d_worker/provider-lock.json`.
The exact upstream license snapshots checked on 2026-09-11 are:

- TripoSR source MIT license SHA-256: `ade0a66629bdd7e01e46b3296b3851cff0fd27989bca53da470ad6e96ed620fb`.
- TRELLIS.2 source MIT license SHA-256: `d9a1b1e30d633d5732ea18e3cba9538d293ebc53e1a9e4e96ab739e0c5c4f1cb`.
- Hunyuan3D-2.1 Community License SHA-256: `b79ac5e11ce063b6c6570dbe9686a45a03ba08bd248aa6aa82fb342a23a81c0c`.

The pinned commits resolve on their upstream default branches. The current
worker uses no ComfyUI custom node, so its custom-node inventory is empty for
the TripoSR and direct-provider paths. TRELLIS.2 source, model, and native
dependency pins are recorded in `tool/ai_3d_worker/provider-lock.json`.
The dedicated image writes `pip-freeze.txt`, `git-revisions.json`, and the
Blender version under `/opt/varian/provenance`; those generated artifacts must
be reviewed before enabling TRELLIS.2 in production.

## Dedicated image review — 2026-09-11

The canonical image `varian-trellis2-worker:canonical` was rebuilt after the
runtime dependency fixes. Its image digest is
`sha256:a6026dfcb0acf2fb4233cb7d91a68935e077c69757341b0fcd22ddde660bfa8f`.
The image contains a 181-package license BOM and copies the relevant source
licenses into `/opt/varian/provenance/licenses`.

The review found that `nvdiffrast` and `nvdiffrec_render` are distributed under
the NVIDIA Source Code License (1-Way Commercial), whose use limitation is
non-commercial research or evaluation. `cumesh` and `flex_gemm` are MIT. The
CUDA runtime packages in the PyTorch base image have NVIDIA proprietary terms,
and the pinned `o_voxel` source tree has no license file or package license
metadata. Therefore the TRELLIS.2 provider remains disabled for commercial or
public production deployment until NVIDIA permission or a legally compatible
replacement is obtained and `o_voxel` licensing is resolved. The image is
usable for internal technical evaluation only under the applicable notices.

The Supabase Edge Function now requires all three server-side flags before it
will route jobs to `trellis`: `AI_3D_ENABLE_TRELLIS2=true`,
`AI_3D_TRELLIS2_LEGAL_APPROVED=true`, and
`AI_3D_TRELLIS2_DEPENDENCY_REVIEWED=true`. The deployed project leaves these
flags unset, so the production path remains on the approved TripoSR provider.

The Edge Function additionally requires all of the following environment flags
before it will allow `hunyuan3d`: `AI_3D_ENABLE_HUNYUAN`,
`AI_3D_HUNYUAN_LEGAL_APPROVED`, `AI_3D_HUNYUAN_TERRITORY_CONFIRMED`, and
`AI_3D_HUNYUAN_AUP_CONFIRMED`, each set to `true`. The deployed project has
none of these opt-in approval flags set; a production request for Hunyuan was
verified to return HTTP 400 on 2026-09-11.

## Hosted TRELLIS.2 fallback — 2026-09-11

The Edge Function now supports `fal-trellis2` as a separate, explicitly enabled
provider. It submits the image-only `fal-ai/trellis-2` queue request, polls the
server-side request ID, downloads only an HTTPS `.glb` from an allow-listed
`*.fal.media` host, validates the GLB and triangle budget, and stores it in the
private Supabase Storage flow used by the local worker. `FAL_KEY` is read only
from the Edge Function environment and is never sent to Flutter or the worker.

The provider is not the default: `AI_3D_ENABLE_FAL_TRELLIS2=true` and a configured
`FAL_KEY` are required. The live FAL generation smoke test remains a separately
approved operation because hosted inference is metered. The approved attempt on
2026-09-11 reached the provider but was rejected with HTTP 403 before a request
ID or artifact was returned; contract tests use a mocked queue and do not spend
provider credits.
