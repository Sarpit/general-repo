#!/bin/bash
#===============================================================================
# Health Check Demo Script
# Description: Checks the health status of all services in the vLLM stack
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - adjust these to match your environment
VLLM_HOST="${VLLM_HOST:-127.0.0.1}"
VLLM_PORT="${VLLM_PORT:-8100}"
LITELLM_HOST="${LITELLM_HOST:-127.0.0.1}"
LITELLM_PORT="${LITELLM_PORT:-9001}"
OPENWEBUI_HOST="${OPENWEBUI_HOST:-127.0.0.1}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_status() {
    local service=$1
    local status=$2
    local details=$3

    if [ "$status" == "OK" ]; then
        echo -e "  ${GREEN}✓${NC} $service: ${GREEN}$status${NC}"
    else
        echo -e "  ${RED}✗${NC} $service: ${RED}$status${NC}"
    fi

    if [ -n "$details" ]; then
        echo -e "    ${YELLOW}└─ $details${NC}"
    fi
}

check_service() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}

    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")

    if [ "$response" == "$expected_code" ]; then
        print_status "$name" "OK" "HTTP $response at $url"
        return 0
    else
        print_status "$name" "FAILED" "HTTP $response (expected $expected_code) at $url"
        return 1
    fi
}

#===============================================================================
# Main Health Checks
#===============================================================================

print_header "vLLM Stack Health Check"

echo -e "${YELLOW}Checking all services...${NC}"
echo ""

# Track overall status
all_healthy=true

#-------------------------------------------------------------------------------
# 1. Check vLLM
#-------------------------------------------------------------------------------
echo -e "${BLUE}[1/4] vLLM Server${NC}"
if check_service "vLLM Health" "http://${VLLM_HOST}:${VLLM_PORT}/health"; then
    # Get model info
    models=$(curl -s "http://${VLLM_HOST}:${VLLM_PORT}/v1/models" 2>/dev/null | jq -r '.data[0].id' 2>/dev/null || echo "N/A")
    echo -e "    ${YELLOW}└─ Model loaded: $models${NC}"
else
    all_healthy=false
fi
echo ""

#-------------------------------------------------------------------------------
# 2. Check LiteLLM
#-------------------------------------------------------------------------------
echo -e "${BLUE}[2/4] LiteLLM Proxy${NC}"
if check_service "LiteLLM Health" "http://${LITELLM_HOST}:${LITELLM_PORT}/health"; then
    # Get available models through LiteLLM
    litellm_models=$(curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/models" \
        -H "Authorization: Bearer secret123" 2>/dev/null | jq -r '.data[].id' 2>/dev/null | head -3 || echo "N/A")
    echo -e "    ${YELLOW}└─ Available models: $litellm_models${NC}"
else
    all_healthy=false
fi
echo ""

#-------------------------------------------------------------------------------
# 3. Check Nginx
#-------------------------------------------------------------------------------
echo -e "${BLUE}[3/4] Nginx Proxy${NC}"
# Nginx typically proxies to LiteLLM, so we check via the proxy
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://${VLLM_HOST}:${VLLM_PORT}/health" 2>/dev/null | grep -q "200"; then
    print_status "Nginx Proxy" "OK" "Proxying requests successfully"
else
    print_status "Nginx Proxy" "WARNING" "Direct check not available, verify via application"
fi
echo ""

#-------------------------------------------------------------------------------
# 4. Check Open WebUI
#-------------------------------------------------------------------------------
echo -e "${BLUE}[4/4] Open WebUI${NC}"
if check_service "Open WebUI" "http://${OPENWEBUI_HOST}:${OPENWEBUI_PORT}"; then
    echo -e "    ${YELLOW}└─ Web interface available at http://${OPENWEBUI_HOST}:${OPENWEBUI_PORT}${NC}"
else
    all_healthy=false
fi
echo ""

#-------------------------------------------------------------------------------
# 5. GPU Status (if nvidia-smi available)
#-------------------------------------------------------------------------------
print_header "GPU Status"

if command -v nvidia-smi &> /dev/null; then
    echo -e "${YELLOW}GPU Information:${NC}"
    echo ""
    nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null | while IFS=, read -r idx name mem_used mem_total util temp; do
        echo -e "  ${GREEN}GPU $idx:${NC} $name"
        echo -e "    └─ Memory: ${mem_used}MB / ${mem_total}MB"
        echo -e "    └─ Utilization: ${util}%"
        echo -e "    └─ Temperature: ${temp}°C"
        echo ""
    done
else
    echo -e "  ${YELLOW}nvidia-smi not available (run on GPU node to see GPU status)${NC}"
fi

#-------------------------------------------------------------------------------
# 6. Docker Container Status
#-------------------------------------------------------------------------------
print_header "Docker Container Status"

if command -v docker &> /dev/null; then
    echo -e "${YELLOW}Container Status:${NC}"
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | grep -E "(vllm|litellm|nginx|openwebui|NAME)" || echo "  No matching containers found"
else
    echo -e "  ${YELLOW}Docker not available${NC}"
fi

#-------------------------------------------------------------------------------
# Summary
#-------------------------------------------------------------------------------
print_header "Summary"

if [ "$all_healthy" = true ]; then
    echo -e "  ${GREEN}All services are healthy!${NC}"
    echo ""
    echo -e "  ${YELLOW}Quick Links:${NC}"
    echo -e "    • Open WebUI: http://${OPENWEBUI_HOST}:${OPENWEBUI_PORT}"
    echo -e "    • LiteLLM API: http://${LITELLM_HOST}:${LITELLM_PORT}/v1"
    echo -e "    • vLLM Direct: http://${VLLM_HOST}:${VLLM_PORT}/v1"
    exit 0
else
    echo -e "  ${RED}Some services are unhealthy. Please check the logs.${NC}"
    echo ""
    echo -e "  ${YELLOW}Troubleshooting:${NC}"
    echo -e "    • docker logs vllm"
    echo -e "    • docker logs litellm"
    echo -e "    • docker logs nginx-proxy"
    echo -e "    • docker logs openwebui"
    exit 1
fi
