#!/bin/bash
#===============================================================================
# Rate Limiting Demo Script
# Description: Demonstrates rate limiting and resource management in the stack
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
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

#===============================================================================
# Introduction
#===============================================================================
print_header "Rate Limiting and Resource Management Demo"

echo -e "${YELLOW}This demo shows how to control and limit resource usage:${NC}"
echo ""
echo "  1. API Key Authentication"
echo "  2. Max Tokens Limiting"
echo "  3. Request Timeout Handling"
echo "  4. Rate Limit Response (429 Too Many Requests)"
echo "  5. Token Usage Tracking"
echo ""

#===============================================================================
# Demo 1: Authentication
#===============================================================================
print_header "Demo 1: API Key Authentication"

print_subheader "1a. Request without API Key"
echo -e "${YELLOW}Attempting request without authorization header:${NC}"
echo ""

response=$(curl -s -w "\n%{http_code}" "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [{"role": "user", "content": "Hello"}],
    "max_tokens": 10
  }' 2>/dev/null)

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" == "401" ] || [ "$http_code" == "403" ]; then
    echo -e "  ${RED}✗ HTTP $http_code - Unauthorized${NC}"
    echo -e "  ${YELLOW}Response: $(echo "$body" | jq -r '.error.message // .detail // .' 2>/dev/null | head -c 100)${NC}"
else
    echo -e "  ${YELLOW}HTTP $http_code - (Auth may be disabled in demo mode)${NC}"
fi
echo ""

print_subheader "1b. Request with valid API Key"
echo -e "${YELLOW}Attempting request with Authorization: Bearer ${API_KEY}${NC}"
echo ""

response=$(curl -s -w "\n%{http_code}" "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [{"role": "user", "content": "Say OK"}],
    "max_tokens": 10
  }' 2>/dev/null)

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" == "200" ]; then
    echo -e "  ${GREEN}✓ HTTP $http_code - Authorized${NC}"
    echo -e "  ${CYAN}Response: $(echo "$body" | jq -r '.choices[0].message.content' 2>/dev/null)${NC}"
else
    echo -e "  ${RED}HTTP $http_code${NC}"
fi
echo ""

read -p "Press Enter to continue..."

#===============================================================================
# Demo 2: Max Tokens Limiting
#===============================================================================
print_header "Demo 2: Max Tokens Limiting"

echo -e "${YELLOW}The max_tokens parameter limits response length:${NC}"
echo ""

print_subheader "2a. Request with max_tokens=10"

response=$(curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [{"role": "user", "content": "Write a long story about a robot."}],
    "max_tokens": 10
  }' 2>/dev/null)

echo -e "${CYAN}Response (truncated at ~10 tokens):${NC}"
echo "$response" | jq -r '.choices[0].message.content'
echo ""
echo -e "${YELLOW}Tokens used:${NC}"
echo "$response" | jq '.usage'
echo ""
finish_reason=$(echo "$response" | jq -r '.choices[0].finish_reason')
echo -e "${MAGENTA}Finish reason: $finish_reason${NC}"
if [ "$finish_reason" == "length" ]; then
    echo -e "${YELLOW}  └─ 'length' means response was cut off by max_tokens limit${NC}"
fi
echo ""

print_subheader "2b. Request with max_tokens=100"

response=$(curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [{"role": "user", "content": "Write a short story about a robot in 2 sentences."}],
    "max_tokens": 100
  }' 2>/dev/null)

echo -e "${CYAN}Response (allowed up to 100 tokens):${NC}"
echo "$response" | jq -r '.choices[0].message.content'
echo ""
echo -e "${YELLOW}Tokens used:${NC}"
echo "$response" | jq '.usage'
echo ""
finish_reason=$(echo "$response" | jq -r '.choices[0].finish_reason')
echo -e "${MAGENTA}Finish reason: $finish_reason${NC}"
if [ "$finish_reason" == "stop" ]; then
    echo -e "${GREEN}  └─ 'stop' means response completed naturally${NC}"
fi
echo ""

read -p "Press Enter to continue..."

#===============================================================================
# Demo 3: Context Length Limits
#===============================================================================
print_header "Demo 3: Context Length Limits"

echo -e "${YELLOW}vLLM is configured with --max-model-len 8192${NC}"
echo -e "${YELLOW}This limits the total context (input + output) to 8192 tokens.${NC}"
echo ""

print_subheader "Testing with a moderately long input"

# Generate a long input
LONG_INPUT="Please analyze the following text and summarize it: "
for i in $(seq 1 50); do
    LONG_INPUT="${LONG_INPUT} This is sentence number $i which contains some words to make the input longer."
done

echo -e "${CYAN}Sending request with ~500 word input...${NC}"
echo ""

response=$(curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [{"role": "user", "content": "'"${LONG_INPUT}"'"}],
    "max_tokens": 100
  }' 2>/dev/null)

prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // "error"')
completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // "error"')

if [ "$prompt_tokens" != "error" ]; then
    echo -e "${GREEN}✓ Request successful${NC}"
    echo -e "  Prompt tokens:     $prompt_tokens"
    echo -e "  Completion tokens: $completion_tokens"
    echo -e "  Total:            $((prompt_tokens + completion_tokens)) / 8192 max"
    echo ""

    # Visual bar
    total=$((prompt_tokens + completion_tokens))
    percentage=$((total * 100 / 8192))
    bar_filled=$((percentage / 2))
    bar_empty=$((50 - bar_filled))
    echo -n "  Context usage: ["
    printf '█%.0s' $(seq 1 $bar_filled) 2>/dev/null || true
    printf '░%.0s' $(seq 1 $bar_empty) 2>/dev/null || true
    echo "] ${percentage}%"
else
    error=$(echo "$response" | jq -r '.error.message // .' 2>/dev/null)
    echo -e "${RED}✗ Request failed: $error${NC}"
fi
echo ""

read -p "Press Enter to continue..."

#===============================================================================
# Demo 4: Simulating Rate Limits
#===============================================================================
print_header "Demo 4: Understanding Rate Limit Responses"

echo -e "${YELLOW}When rate limits are exceeded, the API returns HTTP 429.${NC}"
echo ""
echo -e "${CYAN}Example rate limit configuration in LiteLLM:${NC}"
echo ""
cat << 'EOF'
  user_api_key_config:
    - api_key: "team-a-key"
      rpm_limit: 60         # 60 requests per minute
      tpm_limit: 100000     # 100K tokens per minute
      max_parallel_requests: 10
EOF
echo ""

echo -e "${YELLOW}What a 429 response looks like:${NC}"
echo ""
cat << 'EOF'
  HTTP/1.1 429 Too Many Requests
  Content-Type: application/json
  Retry-After: 30

  {
    "error": {
      "message": "Rate limit exceeded. Please retry after 30 seconds.",
      "type": "rate_limit_error",
      "code": "rate_limit_exceeded"
    }
  }
EOF
echo ""

echo -e "${CYAN}Best practices for handling rate limits:${NC}"
echo "  1. Implement exponential backoff (wait 1s, 2s, 4s, 8s...)"
echo "  2. Check the Retry-After header for guidance"
echo "  3. Monitor token usage to stay under limits"
echo "  4. Use request queuing for burst traffic"
echo ""

print_subheader "Rapid Request Test"
echo -e "${YELLOW}Sending 10 rapid requests to test rate limiting...${NC}"
echo ""

for i in $(seq 1 10); do
    response=$(curl -s -w "%{http_code}" -o /dev/null "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${API_KEY}" \
      -d '{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "Hi"}],
        "max_tokens": 5
      }' 2>/dev/null)

    if [ "$response" == "200" ]; then
        echo -e "  Request $i: ${GREEN}HTTP $response ✓${NC}"
    elif [ "$response" == "429" ]; then
        echo -e "  Request $i: ${RED}HTTP $response (Rate Limited)${NC}"
    else
        echo -e "  Request $i: ${YELLOW}HTTP $response${NC}"
    fi
done

echo ""
echo -e "${CYAN}Note: If no 429s appeared, rate limits may not be configured or limits are high.${NC}"
echo ""

read -p "Press Enter to continue..."

#===============================================================================
# Demo 5: Token Usage Tracking
#===============================================================================
print_header "Demo 5: Token Usage Tracking"

echo -e "${YELLOW}Every response includes token usage information for monitoring:${NC}"
echo ""

response=$(curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "model": "'${MODEL_NAME}'",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is machine learning?"},
      {"role": "assistant", "content": "Machine learning is a subset of AI."},
      {"role": "user", "content": "Can you elaborate?"}
    ],
    "max_tokens": 150
  }' 2>/dev/null)

echo -e "${CYAN}Multi-turn conversation token breakdown:${NC}"
echo ""
echo "$response" | jq '{
  usage: .usage,
  model: .model,
  finish_reason: .choices[0].finish_reason
}'
echo ""

prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens')
completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens')
total_tokens=$(echo "$response" | jq -r '.usage.total_tokens')

echo -e "${YELLOW}Token Breakdown:${NC}"
echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │  Input (Prompt) Tokens                              │"
echo "  │  ├─ System message:    ~10 tokens                   │"
echo "  │  ├─ User message 1:    ~5 tokens                    │"
echo "  │  ├─ Assistant reply:   ~10 tokens                   │"
echo "  │  └─ User message 2:    ~5 tokens                    │"
printf "  │  Total prompt:        %-5d tokens                  │\n" "$prompt_tokens"
echo "  ├─────────────────────────────────────────────────────┤"
printf "  │  Output (Completion): %-5d tokens                  │\n" "$completion_tokens"
echo "  ├─────────────────────────────────────────────────────┤"
printf "  │  TOTAL:               %-5d tokens                  │\n" "$total_tokens"
echo "  └─────────────────────────────────────────────────────┘"
echo ""

echo -e "${CYAN}Why this matters for rate limiting:${NC}"
echo "  • TPM (Tokens Per Minute) limits count ALL tokens"
echo "  • Long conversations accumulate prompt tokens quickly"
echo "  • Each turn includes full conversation history"
echo "  • Consider summarizing history for long conversations"
echo ""

#===============================================================================
# Summary: Rate Limiting Configuration Reference
#===============================================================================
print_header "Rate Limiting Configuration Reference"

echo -e "${GREEN}Where to configure each limit:${NC}"
echo ""
echo "  ┌────────────────────────┬─────────────────────────────────────┐"
echo "  │ Limit Type             │ Configuration Location              │"
echo "  ├────────────────────────┼─────────────────────────────────────┤"
echo "  │ Requests/minute (RPM)  │ LiteLLM: rpm_limit per API key      │"
echo "  │ Tokens/minute (TPM)    │ LiteLLM: tpm_limit per API key      │"
echo "  │ Concurrent requests    │ LiteLLM: max_parallel_requests      │"
echo "  │ Max output tokens      │ LiteLLM/Request: max_tokens         │"
echo "  │ Max context length     │ vLLM: --max-model-len               │"
echo "  │ Connection limits      │ Nginx: limit_conn                   │"
echo "  │ Request rate/IP        │ Nginx: limit_req                    │"
echo "  │ GPU memory             │ vLLM: --gpu-memory-utilization      │"
echo "  └────────────────────────┴─────────────────────────────────────┘"
echo ""

echo -e "${YELLOW}Sample LiteLLM config with rate limits:${NC}"
echo ""
cat << 'EOF'
  # litellm_config.yaml
  model_list:
    - model_name: Llama-3.1-8B-Instruct
      litellm_params:
        model: openai/Llama-3.1-8B-Instruct
        api_base: http://127.0.0.1:8100/v1

  general_settings:
    master_key: your-secure-key-here

  litellm_settings:
    max_tokens: 4096
    request_timeout: 300

  # Per-team rate limits
  user_api_key_config:
    - api_key: "team-production"
      rpm_limit: 100
      tpm_limit: 500000
      max_parallel_requests: 20

    - api_key: "team-development"
      rpm_limit: 30
      tpm_limit: 100000
      max_parallel_requests: 5
EOF
echo ""

echo -e "${GREEN}Demo Complete!${NC}"
echo ""
