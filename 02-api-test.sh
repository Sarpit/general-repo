#!/bin/bash
#===============================================================================
# API Test Demo Script
# Description: Demonstrates API calls to the vLLM stack at different layers
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
VLLM_HOST="${VLLM_HOST:-127.0.0.1}"
VLLM_PORT="${VLLM_PORT:-8100}"
LITELLM_HOST="${LITELLM_HOST:-127.0.0.1}"
LITELLM_PORT="${LITELLM_PORT:-9001}"
API_KEY="${API_KEY:-secret123}"
MODEL_NAME="${MODEL_NAME:-Llama-3.1-8B-Instruct}"

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_subheader() {
    echo ""
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${NC}"
}

print_command() {
    echo -e "${YELLOW}Command:${NC}"
    echo -e "${GREEN}$1${NC}"
    echo ""
}

#===============================================================================
# Demo 1: List Available Models
#===============================================================================
print_header "Demo 1: List Available Models"

print_subheader "1a. Query vLLM directly"
CMD='curl -s http://'${VLLM_HOST}':'${VLLM_PORT}'/v1/models | jq .'
print_command "$CMD"
echo -e "${YELLOW}Response:${NC}"
eval $CMD
echo ""

print_subheader "1b. Query through LiteLLM"
CMD='curl -s http://'${LITELLM_HOST}':'${LITELLM_PORT}'/v1/models -H "Authorization: Bearer '${API_KEY}'" | jq .'
print_command "$CMD"
echo -e "${YELLOW}Response:${NC}"
eval $CMD
echo ""

read -p "Press Enter to continue to the next demo..."

#===============================================================================
# Demo 2: Simple Chat Completion (Non-Streaming)
#===============================================================================
print_header "Demo 2: Simple Chat Completion (Non-Streaming)"

print_subheader "2a. Direct vLLM API Call"

CMD='curl -s http://'${VLLM_HOST}':'${VLLM_PORT}'/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '"'"'{
    "model": "'${MODEL_NAME}'",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant. Be concise."},
      {"role": "user", "content": "What is CUDA in one sentence?"}
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }'"'"' | jq .'

print_command "curl -s http://${VLLM_HOST}:${VLLM_PORT}/v1/chat/completions \\
  -H \"Content-Type: application/json\" \\
  -d '{
    \"model\": \"${MODEL_NAME}\",
    \"messages\": [
      {\"role\": \"system\", \"content\": \"You are a helpful assistant. Be concise.\"},
      {\"role\": \"user\", \"content\": \"What is CUDA in one sentence?\"}
    ],
    \"max_tokens\": 100,
    \"temperature\": 0.7
  }'"

echo -e "${YELLOW}Response:${NC}"
START_TIME=$(date +%s.%N)
eval $CMD
END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
echo ""
echo -e "${GREEN}Response time: ${ELAPSED}s${NC}"
echo ""

print_subheader "2b. Through LiteLLM (OpenAI-compatible)"

CMD='curl -s http://'${LITELLM_HOST}':'${LITELLM_PORT}'/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer '${API_KEY}'" \
  -d '"'"'{
    "model": "'${MODEL_NAME}'",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant. Be concise."},
      {"role": "user", "content": "What is CUDA in one sentence?"}
    ],
    "max_tokens": 100,
    "temperature": 0.7
  }'"'"' | jq .'

print_command "curl -s http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions \\
  -H \"Content-Type: application/json\" \\
  -H \"Authorization: Bearer ${API_KEY}\" \\
  -d '{
    \"model\": \"${MODEL_NAME}\",
    \"messages\": [...],
    \"max_tokens\": 100
  }'"

echo -e "${YELLOW}Response:${NC}"
START_TIME=$(date +%s.%N)
eval $CMD
END_TIME=$(date +%s.%N)
ELAPSED=$(echo "$END_TIME - $START_TIME" | bc)
echo ""
echo -e "${GREEN}Response time: ${ELAPSED}s${NC}"
echo ""

read -p "Press Enter to continue to the next demo..."

#===============================================================================
# Demo 3: Streaming Response
#===============================================================================
print_header "Demo 3: Streaming Response"

echo -e "${YELLOW}Watch tokens arrive in real-time:${NC}"
echo ""

CMD='curl -s http://'${LITELLM_HOST}':'${LITELLM_PORT}'/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer '${API_KEY}'" \
  -d '"'"'{
    "model": "'${MODEL_NAME}'",
    "messages": [
      {"role": "user", "content": "Explain how GPUs accelerate machine learning in 3 bullet points."}
    ],
    "max_tokens": 200,
    "stream": true
  }'"'"''

print_command "curl -s ... -d '{\"stream\": true, ...}'"

echo -e "${YELLOW}Streaming Response:${NC}"
echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"

# Stream and extract content
curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [
      {"role": "user", "content": "Explain how GPUs accelerate machine learning in 3 bullet points."}
    ],
    "max_tokens": 200,
    "stream": true
  }' 2>/dev/null | while IFS= read -r line; do
    # Extract content from SSE data
    if [[ $line == data:* ]]; then
        content=$(echo "${line#data: }" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
        if [ -n "$content" ]; then
            printf "%s" "$content"
        fi
    fi
done

echo ""
echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
echo ""

read -p "Press Enter to continue to the next demo..."

#===============================================================================
# Demo 4: Different Parameters
#===============================================================================
print_header "Demo 4: Temperature and Parameter Effects"

print_subheader "4a. Low Temperature (0.1) - More deterministic"

echo -e "${YELLOW}Prompt: 'Complete this: The sky is'${NC}"
echo ""

for i in 1 2 3; do
    echo -e "${CYAN}Attempt $i:${NC}"
    curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${API_KEY}" \
      -d '{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "Complete this in 5 words: The sky is"}],
        "max_tokens": 20,
        "temperature": 0.1
      }' 2>/dev/null | jq -r '.choices[0].message.content'
    echo ""
done

print_subheader "4b. High Temperature (1.5) - More creative/random"

for i in 1 2 3; do
    echo -e "${CYAN}Attempt $i:${NC}"
    curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${API_KEY}" \
      -d '{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "Complete this in 5 words: The sky is"}],
        "max_tokens": 20,
        "temperature": 1.5
      }' 2>/dev/null | jq -r '.choices[0].message.content'
    echo ""
done

read -p "Press Enter to continue to the next demo..."

#===============================================================================
# Demo 5: Token Usage Information
#===============================================================================
print_header "Demo 5: Token Usage Information"

echo -e "${YELLOW}Understanding token consumption:${NC}"
echo ""

response=$(curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Write a haiku about artificial intelligence."}
    ],
    "max_tokens": 100
  }' 2>/dev/null)

echo -e "${CYAN}Response:${NC}"
echo "$response" | jq -r '.choices[0].message.content'
echo ""

echo -e "${CYAN}Token Usage:${NC}"
echo "$response" | jq '.usage'
echo ""

prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens')
completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens')
total_tokens=$(echo "$response" | jq -r '.usage.total_tokens')

echo -e "${YELLOW}Breakdown:${NC}"
echo -e "  • Prompt tokens (input):     ${GREEN}$prompt_tokens${NC}"
echo -e "  • Completion tokens (output): ${GREEN}$completion_tokens${NC}"
echo -e "  • Total tokens:              ${GREEN}$total_tokens${NC}"
echo ""

#===============================================================================
# Summary
#===============================================================================
print_header "API Demo Complete"

echo -e "${GREEN}Key Takeaways:${NC}"
echo ""
echo "  1. vLLM provides a direct OpenAI-compatible API on port ${VLLM_PORT}"
echo "  2. LiteLLM adds authentication and management on port ${LITELLM_PORT}"
echo "  3. Both support streaming for real-time token generation"
echo "  4. Temperature controls response randomness (0=deterministic, 2=creative)"
echo "  5. Token usage helps monitor and control costs"
echo ""
echo -e "${YELLOW}Try it yourself:${NC}"
echo ""
echo "  # Using curl:"
echo "  curl http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions \\"
echo "    -H 'Authorization: Bearer ${API_KEY}' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\": \"${MODEL_NAME}\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello!\"}]}'"
echo ""
echo "  # Using Python OpenAI SDK:"
echo "  from openai import OpenAI"
echo "  client = OpenAI(base_url='http://${LITELLM_HOST}:${LITELLM_PORT}/v1', api_key='${API_KEY}')"
echo "  response = client.chat.completions.create(model='${MODEL_NAME}', messages=[...])"
echo ""
