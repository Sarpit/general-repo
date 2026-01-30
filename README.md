# vLLM Demo Scripts

This folder contains demo scripts and documentation for showcasing the vLLM + LiteLLM + Nginx + Open WebUI stack.

## Files Overview

| File | Description |
|------|-------------|
| `vllm-technical-guide.md` | Comprehensive technical documentation (convert to PDF for presentation) |
| `01-health-check.sh` | Checks health status of all services in the stack |
| `02-api-test.sh` | Demonstrates API calls at different layers (vLLM, LiteLLM) |
| `03-concurrent-requests.sh` | Shows continuous batching and parallel request processing |
| `04-rate-limiting.sh` | Demonstrates rate limiting and resource management |
| `generate-pdf.sh` | Converts markdown documentation to PDF |

## Prerequisites

- `curl` - for API requests
- `jq` - for JSON parsing
- `bc` - for calculations (usually pre-installed)

Optional (for PDF generation):
- `pandoc` + `xelatex` (recommended)
- OR `wkhtmltopdf` + `grip`
- OR just use browser print-to-PDF

## Quick Start

```bash
# Make scripts executable
chmod +x *.sh

# 1. Check all services are running
./01-health-check.sh

# 2. Demo basic API functionality
./02-api-test.sh

# 3. Demo concurrent request handling
./03-concurrent-requests.sh

# 4. Demo rate limiting features
./04-rate-limiting.sh

# Generate PDF documentation
./generate-pdf.sh
```

## Configuration

All scripts use environment variables for configuration. Defaults match the docker-compose setup:

```bash
# Override defaults if needed
export VLLM_HOST=127.0.0.1
export VLLM_PORT=8100
export LITELLM_HOST=127.0.0.1
export LITELLM_PORT=9001
export API_KEY=secret123
export MODEL_NAME=Llama-3.1-8B-Instruct
```

## Demo Flow Suggestion

### Before the Demo
1. Ensure all services are running: `docker-compose up -d`
2. Run health check: `./01-health-check.sh`
3. Generate PDF for handout: `./generate-pdf.sh`

### During the Demo

**Part 1: Architecture Overview (5-10 min)**
- Walk through `vllm-technical-guide.md` or PDF
- Explain each component's role
- Cover CUDA/GPU concepts

**Part 2: Live API Demo (10-15 min)**
- Run `./02-api-test.sh`
- Show model listing, chat completions, streaming
- Demonstrate temperature effects

**Part 3: Performance Demo (10 min)**
- Run `./03-concurrent-requests.sh`
- Show sequential vs parallel performance
- Explain continuous batching

**Part 4: Resource Management (5-10 min)**
- Run `./04-rate-limiting.sh`
- Show token tracking
- Explain rate limit configuration

**Part 5: Open WebUI Demo (5 min)**
- Open http://localhost:3000
- Show interactive chat interface
- Demonstrate real-world usage

### Q&A Preparation
Review the FAQ sections in `vllm-technical-guide.md` for common questions about:
- GPU/CUDA requirements
- Performance and scaling
- Rate limiting configuration
- Multi-GPU setups

## Troubleshooting

### Services not responding
```bash
# Check container status
docker ps

# Check container logs
docker logs vllm
docker logs litellm
docker logs openwebui
```

### GPU issues
```bash
# Check GPU availability
nvidia-smi

# Check CUDA in container
docker exec vllm nvidia-smi
```

### API errors
```bash
# Test vLLM directly
curl http://127.0.0.1:8100/health

# Test LiteLLM
curl http://127.0.0.1:9001/health

# Check models loaded
curl http://127.0.0.1:8100/v1/models | jq .
```
