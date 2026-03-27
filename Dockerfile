# ================================
# vLLM + Qwen Support (V100 Safe)
# ================================

FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive

# ---- System dependencies ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-dev \
    git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Set python3 as default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1 \
 && update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# ---- Environment ----
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    TORCH_CUDA_ARCH_LIST="7.0" \
    VLLM_USE_FLASH_ATTENTION="0" \
    VLLM_NO_FLASH_ATTENTION="1" \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

# ---- Upgrade pip ----
RUN pip install --upgrade pip setuptools wheel

# ---- PyTorch (MAX supported for V100) ----
RUN pip install --extra-index-url https://download.pytorch.org/whl/cu121 \
    torch==2.2.2 \
    torchvision==0.17.2 \
    torchaudio==2.2.2

# ---- Transformers (Qwen3 support) ----
RUN pip install \
    "transformers>=4.46.0,<5.0.0" \
    "accelerate>=0.30.0" \
    "huggingface_hub>=0.23.0" \
    "sentencepiece" \
    "einops" \
    "tiktoken"

# ---- vLLM (compatible with torch 2.2.x) ----
RUN pip install "vllm==0.4.2"

# ---- Fix for guided decoding dependency ----
RUN pip install "outlines==0.0.37"

# ---- Create non-root user ----
RUN useradd -m -u 10001 -s /bin/bash appuser
USER appuser

WORKDIR /workspace

# ---- Ports ----
EXPOSE 8000 8100

# ---- Entrypoint ----
# Allows docker-compose to pass model + config dynamically
ENTRYPOINT ["python", "-m", "vllm.entrypoints.openai.api_server"]

# Default command (overridden by compose)
CMD ["--help"]
