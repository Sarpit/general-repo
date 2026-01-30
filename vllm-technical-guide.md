# vLLM + LiteLLM + Nginx + Open WebUI Technical Guide

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Component Deep Dive](#component-deep-dive)
3. [CUDA and GPU Acceleration](#cuda-and-gpu-acceleration)
4. [Request Processing Flow](#request-processing-flow)
5. [Rate Limiting and Resource Management](#rate-limiting-and-resource-management)
6. [GPU Cluster Memory Allocation](#gpu-cluster-memory-allocation)
7. [Frequently Asked Questions](#frequently-asked-questions)

---

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Open WebUI    │────▶│    LiteLLM      │────▶│   Nginx Proxy   │────▶│     vLLM        │
│   (Port 3000)   │     │   (Port 9001)   │     │  (Port 8100/    │     │   (Port 8100)   │
│                 │     │                 │     │       9001)     │     │                 │
│  User Interface │     │  API Gateway    │     │  Reverse Proxy  │     │  Model Serving  │
└─────────────────┘     └─────────────────┘     └─────────────────┘     └─────────────────┘
                                                                              │
                                                                              ▼
                                                                     ┌─────────────────┐
                                                                     │   NVIDIA GPU    │
                                                                     │   (CUDA)        │
                                                                     └─────────────────┘
```

### Network Architecture
All services use `network_mode: host` - sharing the host's network namespace for:
- Simplified inter-service communication (all on localhost)
- Better performance (no Docker NAT overhead)
- Required for GPU passthrough in some configurations

---

## Component Deep Dive

### 1. vLLM (Virtual Large Language Model Server)

**What it is:** A high-throughput, memory-efficient inference engine for LLMs.

**Configuration:**
```yaml
image: docker.io/library/vllm-custom:v2
command: >
  --model /models/${MODEL_NAME}
  --served-model-name Llama-3.1-8B-Instruct
  --max-model-len 8192
  --host 0.0.0.0
  --port 8100
  --dtype half
```

| Parameter | Explanation |
|-----------|-------------|
| `--max-model-len 8192` | Maximum context window (tokens). Llama 3.1 supports up to 128K, but limited here for memory efficiency |
| `--dtype half` | Uses FP16 (16-bit floating point) instead of FP32, halving memory usage |
| `--served-model-name` | Alias exposed via API (clients see "Llama-3.1-8B-Instruct") |

**Why vLLM is fast:**
- **PagedAttention**: Novel attention algorithm that manages KV-cache like virtual memory pages, reducing memory waste by up to 90%
- **Continuous Batching**: Dynamically batches requests as they arrive, maximizing GPU utilization
- **Optimized CUDA Kernels**: Custom GPU kernels for transformer operations

### 2. LiteLLM (API Gateway/Proxy)

**What it is:** A unified API gateway that provides OpenAI-compatible endpoints for various LLM backends.

**Configuration:**
```yaml
image: bosdochst01.genisis.va.gov:5000/litellm/litellm:v1.75.8-stable
environment:
  - LITELLM_LOG=debug
  - LITELLM_MASTER_KEY=secret123
command: --port 9001 --config /config.yaml --host 127.0.0.1
```

**Why use LiteLLM:**
| Feature | Benefit |
|---------|---------|
| OpenAI API Compatibility | Any OpenAI SDK/client works without modification |
| Load Balancing | Can distribute across multiple model backends |
| Rate Limiting | Control request throughput |
| API Key Management | Single master key abstracts backend complexity |
| Logging/Observability | Debug mode provides detailed request tracing |

### 3. Nginx Reverse Proxy

**What it is:** High-performance web server acting as a reverse proxy.

**Purpose in this stack:**
- Routes traffic to appropriate backend (vLLM or LiteLLM)
- SSL termination (if configured)
- Request buffering and connection management
- Potential for caching static responses

### 4. Open WebUI

**What it is:** A self-hosted ChatGPT-like interface for interacting with LLMs.

**Configuration:**
```yaml
image: ghcr.io/open-webui/open-webui:main
environment:
  - OPENAI_API_BASE_URL=http://127.0.0.1:9001/v1
  - OPENAI_API_KEY=secret123
  - WEBUI_AUTH=false
  - OFFLINE_MODE=true
  - PORT=3000
```

| Setting | Explanation |
|---------|-------------|
| `OPENAI_API_BASE_URL` | Points to LiteLLM (not OpenAI servers) |
| `OPENAI_API_KEY=secret123` | Matches `LITELLM_MASTER_KEY` |
| `WEBUI_AUTH=false` | No login required (demo/internal use) |
| `OFFLINE_MODE=true` | No external network calls |

---

## CUDA and GPU Acceleration

### What is CUDA?
CUDA (Compute Unified Device Architecture) is NVIDIA's parallel computing platform that allows software to use GPUs for general-purpose processing.

### Configuration in Docker:
```yaml
environment:
  - NVIDIA_VISIBLE_DEVICES=all
  - CUDA_DEVICE_ORDER=PCI_BUS_ID
  - NVIDIA_DRIVER_CAPABILITIES=compute,utility
```

| Variable | Purpose |
|----------|---------|
| `NVIDIA_VISIBLE_DEVICES=all` | Makes all GPUs available to the container |
| `CUDA_DEVICE_ORDER=PCI_BUS_ID` | Orders GPUs by physical slot (consistent numbering across reboots) |
| `NVIDIA_DRIVER_CAPABILITIES=compute,utility` | Enables compute (CUDA cores) and utility (nvidia-smi) capabilities |

### How vLLM Uses CUDA:
1. **Model Loading**: Weights transferred from CPU RAM → GPU VRAM
2. **Tensor Operations**: Matrix multiplications run on thousands of CUDA cores in parallel
3. **Memory Management**: KV-cache stored in GPU memory for fast attention computation
4. **Kernel Execution**: Custom CUDA kernels optimize transformer layers

### Memory Calculation (Llama 3.1 8B with FP16):
```
Parameters: 8 billion
Bytes per parameter (FP16): 2
Model size: 8B × 2 = ~16 GB VRAM minimum
+ KV-cache overhead for context
```

---

## Request Processing Flow

### End-to-End Flow:
```
1. User types prompt in Open WebUI (browser)
           │
           ▼
2. Open WebUI sends POST to http://127.0.0.1:9001/v1/chat/completions
   Headers: Authorization: Bearer secret123
           │
           ▼
3. LiteLLM validates API key, transforms request
           │
           ▼
4. LiteLLM forwards to vLLM at http://127.0.0.1:8100/v1/chat/completions
           │
           ▼
5. vLLM tokenizes input, runs inference on GPU (CUDA)
   - Attention computed via PagedAttention
   - Tokens generated autoregressively
           │
           ▼
6. Response streams back through LiteLLM → Open WebUI → Browser
```

### vLLM's Continuous Batching

**Traditional Batching (Inefficient):**
- All requests in batch must wait for the longest one to complete
- GPU sits idle waiting for slower requests

**Continuous Batching (vLLM):**
- Each iteration processes one token per request across all batched requests
- When a request completes, its slot is immediately freed
- New requests are inserted into available slots without waiting
- Result: No idle GPU time, maximum throughput

### PagedAttention Memory Management

**Traditional KV-Cache:** Pre-allocates memory for maximum sequence length (wasteful)

**PagedAttention:**
- Memory allocated on-demand as tokens are generated
- Uses fixed-size "pages" like OS virtual memory
- Near-zero fragmentation
- Enables 2-4x more concurrent requests

---

## Rate Limiting and Resource Management

### Layer-by-Layer Rate Limiting

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Open WebUI │───▶│   Nginx     │───▶│  LiteLLM    │───▶│    vLLM     │
│             │    │             │    │             │    │             │
│ User Limits │    │ Rate Limit  │    │ API Keys    │    │ GPU Memory  │
│ Session Mgmt│    │ Connection  │    │ TPM/RPM     │    │ Max Tokens  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### LiteLLM Rate Limiting (Primary Method)

```yaml
# litellm_config.yaml
general_settings:
  master_key: secret123
  global_max_parallel_requests: 100

litellm_settings:
  max_tokens: 4096
  request_timeout: 300

user_api_key_config:
  - api_key: "user-team-a-key"
    max_parallel_requests: 10
    tpm_limit: 100000    # Tokens per minute
    rpm_limit: 60        # Requests per minute
```

### vLLM Resource Limits

```yaml
command: >
  --max-model-len 8192          # Max context window
  --max-num-seqs 256            # Max concurrent sequences
  --max-num-batched-tokens 8192 # Max tokens per batch
  --gpu-memory-utilization 0.9  # Use 90% of GPU memory
```

### Quick Reference: Where to Set Each Limit

| What to Limit | Where to Configure |
|---------------|-------------------|
| Requests per minute per user | LiteLLM (`rpm_limit`) |
| Tokens per minute per user | LiteLLM (`tpm_limit`) |
| Concurrent requests per user | LiteLLM (`max_parallel_requests`) |
| Max output tokens | LiteLLM (`max_tokens`) |
| Max context length | vLLM (`--max-model-len`) |
| Total concurrent requests | vLLM (`--max-num-seqs`) |
| GPU memory allocation | vLLM (`--gpu-memory-utilization`) |

---

## GPU Cluster Memory Allocation

### Parallelism Strategies

| Strategy | VRAM Usage | Request Handling |
|----------|-----------|------------------|
| **Single GPU** | One GPU only | Request uses 1 GPU's VRAM |
| **Tensor Parallelism (TP)** | Split across GPUs (same node) | Request uses ALL GPUs' VRAM combined |
| **Pipeline Parallelism (PP)** | Layers distributed across GPUs | Request flows through GPUs sequentially |
| **Data Parallelism (Replicas)** | Full model on each GPU/node | Request goes to ONE replica only |

### Tensor Parallelism (Model Split Across GPUs)

Use when model is too large for single GPU:
```yaml
command: >
  --model /models/${MODEL_NAME}
  --tensor-parallel-size 4    # Split across 4 GPUs
```

- Each request uses combined VRAM of all GPUs
- GPUs must communicate every layer (need fast NVLink)
- Best for large models (70B+)

### Data Parallelism (Multiple Replicas)

Use when model fits on single GPU, need more throughput:
- Each replica handles different requests independently
- Request uses only that replica's VRAM
- Linear throughput scaling
- Simpler deployment and failure isolation

### Recommendation

**For Llama 3.1 8B:** Data Parallelism (Replicas)
- Model fits comfortably in one 24GB GPU
- No inter-GPU communication overhead
- Linear throughput scaling

**For Llama 3.1 70B:** Tensor Parallelism
- Needs ~140GB VRAM (minimum 6x 24GB GPUs)
- Must split model across GPUs
- TP provides lowest latency

---

## Frequently Asked Questions

### GPU/CUDA Questions

**Q: Why use `--dtype half` instead of full precision?**
> FP16 uses 16 bits vs 32 bits for FP32. This halves memory usage with minimal quality loss for inference. Modern GPUs have Tensor Cores optimized for FP16 operations.

**Q: What happens if the GPU runs out of memory?**
> vLLM will either reject requests with OOM error, reduce batch size automatically, or distribute across multiple GPUs if configured.

**Q: What GPU is required for Llama 3.1 8B?**
> Minimum ~20GB VRAM (A10, L4, RTX 3090/4090). The 8B model at FP16 needs ~16GB plus KV-cache overhead.

### Architecture Questions

**Q: Why not connect Open WebUI directly to vLLM?**
> LiteLLM provides API key management, request logging, potential load balancing, and standard OpenAI-compatible interface.

**Q: What is `network_mode: host` and is it secure?**
> Host networking shares the host's network namespace (no container isolation). Acceptable for internal/demo environments; production would use proper network segmentation.

### Performance Questions

**Q: How many concurrent users can this handle?**
> Depends on GPU memory, prompt/response lengths, and batching efficiency. vLLM typically handles 10-50+ concurrent requests on a single GPU.

**Q: What is PagedAttention?**
> Memory management technique inspired by OS virtual memory. Uses fixed-size "pages" for KV-cache, reducing memory fragmentation by up to 90%.

### Security Questions

**Q: Is data sent to external servers?**
> No - `OFFLINE_MODE=true` and local endpoints ensure all processing stays on-premises.

---

## Key Demo Talking Points

1. **Self-hosted AI**: Complete data sovereignty - nothing leaves your infrastructure
2. **Production-grade stack**: Same architecture patterns used by AI companies
3. **GPU acceleration**: CUDA enables 100x+ speedup over CPU inference
4. **OpenAI compatibility**: Existing tools/code work without modification
5. **Modular design**: Each component can be scaled/replaced independently
