FROM pytorch/pytorch:2.6.0-cuda12.4-cudnn9-devel

ARG TRELLIS2_REVISION=75fbf0183001ed9876c8dbb35de6b68552ee08bd
ARG TRELLIS2_MODEL_REVISION=af44b45f2e35a493886929c6d786e563ec68364d
ARG NVDIFFRAST_REVISION=253ac4fcea7de5f396371124af597e6cc957bfae
ARG NVDIFFREC_REVISION=b296927cc7fd01c2ac1087c8065c4d7248f72da4
ARG CUMESH_REVISION=12289e1062f0603f2f0d0771b02e1395d247f26f
ARG FLEXGEMM_REVISION=6dd94a859c26ee8246888502eada3dd8ad85532e
ARG UTILS3D_REVISION=ca3e9ac015ab3473a37ea60f2f55063696638416
ARG TORCH_CUDA_ARCH_LIST=8.6
ARG MAX_JOBS=1

ENV DEBIAN_FRONTEND=noninteractive \
    OPENCV_IO_ENABLE_OPENEXR=1 \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    MAX_JOBS=${MAX_JOBS} \
    TORCH_CUDA_ARCH_LIST=${TORCH_CUDA_ARCH_LIST} \
    TRELLIS2_ROOT=/opt/TRELLIS.2 \
    TRELLIS2_MODEL=microsoft/TRELLIS.2-4B \
    TRELLIS2_MODEL_REVISION=${TRELLIS2_MODEL_REVISION} \
    TRELLIS2_PIPELINE_TYPE=1024_cascade \
    TRELLIS2_HF_TOKEN_REQUIRED=true \
    AI_3D_DEFAULT_PROVIDER=trellis \
    AI_3D_WORK_DIR=/var/lib/varian-ai-3d \
    AI_3D_CORS_ORIGINS=

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        blender \
        ca-certificates \
        git \
        libgl1 \
        libglib2.0-0 \
        libjpeg-dev \
        libsm6 \
        libxext6 \
        libxrender1 \
        ninja-build \
        wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone --recursive https://github.com/microsoft/TRELLIS.2.git /opt/TRELLIS.2 \
    && git -C /opt/TRELLIS.2 checkout --detach ${TRELLIS2_REVISION} \
    && git -C /opt/TRELLIS.2 submodule update --init --recursive

RUN pip install --no-cache-dir \
        easydict \
        gradio==6.0.1 \
        imageio \
        imageio-ffmpeg \
        kornia \
        lpips \
        opencv-python-headless \
        pandas \
        pillow \
        timm \
        tensorboard \
        tqdm \
        transformers \
        trimesh \
        zstandard \
    && pip install --no-cache-dir git+https://github.com/EasternJournalist/utils3d.git@${UTILS3D_REVISION}

RUN pip install --no-cache-dir flash-attn==2.7.3 --no-build-isolation

RUN git clone --recursive https://github.com/NVlabs/nvdiffrast.git /tmp/nvdiffrast \
    && git -C /tmp/nvdiffrast checkout --detach ${NVDIFFRAST_REVISION} \
    && pip install --no-cache-dir /tmp/nvdiffrast --no-build-isolation \
    && git clone --recursive --branch renderutils https://github.com/JeffreyXiang/nvdiffrec.git /tmp/nvdiffrec \
    && git -C /tmp/nvdiffrec checkout --detach ${NVDIFFREC_REVISION} \
    && pip install --no-cache-dir /tmp/nvdiffrec --no-build-isolation

RUN git clone --recursive https://github.com/JeffreyXiang/CuMesh.git /tmp/CuMesh \
    && git -C /tmp/CuMesh checkout --detach ${CUMESH_REVISION} \
    && pip install --no-cache-dir /tmp/CuMesh --no-build-isolation \
    && git clone --recursive https://github.com/JeffreyXiang/FlexGEMM.git /tmp/FlexGEMM \
    && git -C /tmp/FlexGEMM checkout --detach ${FLEXGEMM_REVISION} \
    && pip install --no-cache-dir /tmp/FlexGEMM --no-build-isolation \
    && pip install --no-cache-dir /opt/TRELLIS.2/o-voxel --no-build-isolation --no-deps

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-numpy \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --no-deps plyfile==1.1.2

COPY tool/ai_3d_worker /opt/varian/tool/ai_3d_worker

RUN pip install --no-cache-dir -r /opt/varian/tool/ai_3d_worker/requirements.txt \
    && mkdir -p /opt/varian/provenance /var/lib/varian-ai-3d \
    && pip freeze > /opt/varian/provenance/pip-freeze.txt \
    && blender --version > /opt/varian/provenance/blender-version.txt \
    && mkdir -p /opt/varian/provenance/licenses \
    && cp /opt/TRELLIS.2/LICENSE /opt/varian/provenance/licenses/trellis2-LICENSE \
    && cp /tmp/nvdiffrast/LICENSE.txt /opt/varian/provenance/licenses/nvdiffrast-LICENSE.txt \
    && cp /tmp/nvdiffrec/LICENSE.txt /opt/varian/provenance/licenses/nvdiffrec-LICENSE.txt \
    && cp /tmp/CuMesh/LICENSE /opt/varian/provenance/licenses/cumesh-LICENSE \
    && cp /tmp/FlexGEMM/LICENSE /opt/varian/provenance/licenses/flexgemm-LICENSE \
    && printf '%s\n' 'o_voxel: no license file present in the pinned source tree; legal review required' > /opt/varian/provenance/licenses/o-voxel-REVIEW.txt \
    && printf '{\n  "trellis2": "%s",\n  "trellis2Model": "%s",\n  "nvdiffrast": "%s",\n  "nvdiffrec": "%s",\n  "cumesh": "%s",\n  "flexgemm": "%s",\n  "utils3d": "%s"\n}\n' \
        "${TRELLIS2_REVISION}" \
        "${TRELLIS2_MODEL_REVISION}" \
        "${NVDIFFRAST_REVISION}" \
        "${NVDIFFREC_REVISION}" \
        "${CUMESH_REVISION}" \
        "${FLEXGEMM_REVISION}" \
        "${UTILS3D_REVISION}" > /opt/varian/provenance/git-revisions.json

WORKDIR /opt/varian
ENV PYTHONPATH=/opt/varian:/opt/TRELLIS.2

COPY tool/ai_3d_worker/deployment/trellis2/entrypoint.sh /usr/local/bin/varian-ai-3d-worker
RUN chmod 0755 /usr/local/bin/varian-ai-3d-worker

EXPOSE 20130

HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=3 \
    CMD python -c "import os, urllib.request; r=urllib.request.Request('http://127.0.0.1:20130/v1/health'); t=os.getenv('VARIAN_3D_WORKER_TOKEN', '').strip(); r.add_header('Authorization', 'Bearer '+t) if t else None; urllib.request.urlopen(r, timeout=5).read()"

ENTRYPOINT ["/usr/local/bin/varian-ai-3d-worker"]
