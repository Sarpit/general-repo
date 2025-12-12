# Local LLM Deployment Guide

## Overview

This guide documents a local Large Language Model (LLM) deployment using vLLM as the inference engine, with LiteLLM as an OpenAI-compatible proxy, and NGINX for routing and load balancing.

## Architecture

```
Client → NGINX → LiteLLM → vLLM → Local LLM (Llama-3.1-8B-Instruct)
```

### Components

- **vLLM**: High-performance inference engine for LLMs
- **LiteLLM**: OpenAI-compatible API proxy that translates requests to various LLM backends
- **NGINX**: Reverse proxy for routing internal and external traffic
- **Podman Compose**: Container orchestration

## Setup and Deployment

### Starting Services

```bash
# Start all services defined in compose.yaml
podman-compose -f compose.yaml up -d

# Start services (alternative command)
podman-compose -f compose.yaml start -d
```

## API Endpoints and Usage

### 1. Direct vLLM Access

**Endpoint**: `http://127.0.0.1:8100/v1/completions`

**Example Request**:
```bash
curl http://127.0.0.1:8100/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "/models/Llama-3.1-8B-Instruct",
    "prompt": "What is the capital of France?",
    "max_tokens": 100
  }'
```

**Use Case**: Direct access to vLLM inference engine for completions API.

### 2. LiteLLM via Internal Network

**Endpoint**: `http://127.0.0.1:9001/v1/chat/completions`

**Example Request**:
```bash
curl http://127.0.0.1:9001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret123" \
  -d '{
    "model": "local-llama",
    "messages": [{"role":"user","content":"Summarize vLLM vs LiteLLM in one line."}],
    "max_tokens": 64
  }'
```

**Use Case**: Access LiteLLM proxy directly for chat completions with authentication.

### 3. LiteLLM via NGINX (Internal)

**Endpoint**: `http://127.0.0.1:8080/litellm/v1/chat/completions`

**Example Request**:
```bash
curl http://127.0.0.1:8080/litellm/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret123" \
  -d '{
    "model": "local-llama",
    "messages": [{"role":"user","content":"what is docker"}],
    "max_tokens": 64
  }'
```

**Use Case**: Internal NGINX routing to LiteLLM for development/testing.

### 4. LiteLLM via NGINX (External)

**Endpoint**: `http://192.168.50.58:8080/litellm/v1/chat/completions`

**Example Request**:
```bash
curl http://192.168.50.58:8080/litellm/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret123" \
  -d '{
    "model": "local-llama",
    "messages": [{"role":"user","content":"Summarize vLLM vs LiteLLM in one line."}],
    "max_tokens": 64
  }'
```

**Use Case**: External access through NGINX for production use on the network.

## Port Configuration

| Service | Port | Access | Purpose |
|---------|------|--------|---------|
| vLLM | 8100 | Localhost | Direct inference engine access |
| LiteLLM | 9001 | Localhost | LiteLLM API proxy |
| NGINX Internal | 8080 | Localhost | Internal routing |
| NGINX External | 8080 | Network (192.168.50.58) | External access |

## API Comparison

### vLLM Direct vs LiteLLM

| Feature | vLLM Direct | LiteLLM |
|---------|-------------|---------|
| API Format | OpenAI-compatible completions | OpenAI-compatible chat |
| Model Reference | Full path: `/models/Llama-3.1-8B-Instruct` | Alias: `local-llama` |
| Authentication | None shown | Bearer token required |
| Endpoint Type | `/v1/completions` | `/v1/chat/completions` |

## Authentication

All LiteLLM endpoints require authentication:

```bash
-H "Authorization: Bearer secret123"
```

**Note**: Replace `secret123` with your actual API key in production environments.

## Model Configuration

**Model**: Llama-3.1-8B-Instruct  
**Location**: `/models/Llama-3.1-8B-Instruct`  
**Alias in LiteLLM**: `local-llama`

## Best Practices

1. **Use NGINX endpoints** for production traffic to benefit from load balancing and routing
2. **Always use authentication** when exposing LiteLLM endpoints
3. **Direct vLLM access** is useful for debugging and testing
4. **Adjust max_tokens** based on your use case (64-100 for quick responses, higher for detailed outputs)
5. **Use external NGINX endpoint** (`192.168.50.58:8080`) for accessing from other machines on the network

## Troubleshooting

### Check Service Status
```bash
podman-compose -f compose.yaml ps
```

### View Logs
```bash
podman-compose -f compose.yaml logs -f [service_name]
```

### Restart Services
```bash
podman-compose -f compose.yaml restart
```

## Example Use Cases

### Quick Query (Direct vLLM)
For testing and debugging:
```bash
curl http://127.0.0.1:8100/v1/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "/models/Llama-3.1-8B-Instruct", "prompt": "Hello!", "max_tokens": 50}'
```

### Production Chat (NGINX + LiteLLM)
For application integration:
```bash
curl http://192.168.50.58:8080/litellm/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer secret123" \
  -d '{
    "model": "local-llama",
    "messages": [{"role":"user","content":"Your query here"}],
    "max_tokens": 200
  }'
```
