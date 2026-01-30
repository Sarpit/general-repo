#!/bin/bash
#===============================================================================
# Concurrent Requests Demo Script
# Description: Demonstrates how vLLM handles multiple simultaneous requests
#              using continuous batching
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

# Temp directory for results
RESULTS_DIR=$(mktemp -d)
trap "rm -rf $RESULTS_DIR" EXIT

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

# Function to make a single request and record timing
make_request() {
    local id=$1
    local prompt=$2
    local max_tokens=$3
    local output_file="${RESULTS_DIR}/request_${id}.json"

    local start_time=$(date +%s.%N)

    curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${API_KEY}" \
      -d '{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "'"${prompt}"'"}],
        "max_tokens": '${max_tokens}'
      }' > "$output_file" 2>/dev/null

    local end_time=$(date +%s.%N)
    local elapsed=$(echo "$end_time - $start_time" | bc)

    # Extract token counts
    local prompt_tokens=$(jq -r '.usage.prompt_tokens // 0' "$output_file")
    local completion_tokens=$(jq -r '.usage.completion_tokens // 0' "$output_file")

    echo "${id},${elapsed},${prompt_tokens},${completion_tokens}" >> "${RESULTS_DIR}/timings.csv"
}

#===============================================================================
# Demo 1: Sequential vs Parallel Requests
#===============================================================================
print_header "Demo 1: Sequential vs Parallel Request Processing"

echo -e "${YELLOW}This demo shows the difference between:${NC}"
echo "  1. Sequential requests (one at a time)"
echo "  2. Parallel requests (sent simultaneously)"
echo ""
echo -e "${CYAN}vLLM's continuous batching allows parallel requests to share GPU time efficiently.${NC}"
echo ""

NUM_REQUESTS=5
PROMPT="What is 2+2? Answer in one word."
MAX_TOKENS=10

print_subheader "Sequential Requests (${NUM_REQUESTS} requests, one at a time)"

> "${RESULTS_DIR}/timings.csv"
SEQ_START=$(date +%s.%N)

for i in $(seq 1 $NUM_REQUESTS); do
    echo -ne "\r  Processing request $i of $NUM_REQUESTS..."
    make_request "seq_$i" "$PROMPT" $MAX_TOKENS
done

SEQ_END=$(date +%s.%N)
SEQ_TOTAL=$(echo "$SEQ_END - $SEQ_START" | bc)

echo -e "\r  ${GREEN}✓ Completed $NUM_REQUESTS sequential requests${NC}    "
echo ""

# Show individual timings
echo -e "${YELLOW}Individual request times:${NC}"
while IFS=, read -r id elapsed prompt_tok comp_tok; do
    printf "    Request %-6s: %6.3fs (tokens: %d → %d)\n" "$id" "$elapsed" "$prompt_tok" "$comp_tok"
done < "${RESULTS_DIR}/timings.csv"

echo ""
echo -e "  ${GREEN}Total sequential time: ${SEQ_TOTAL}s${NC}"
echo ""

read -p "Press Enter to run parallel requests..."

print_subheader "Parallel Requests (${NUM_REQUESTS} requests, all at once)"

> "${RESULTS_DIR}/timings.csv"
PAR_START=$(date +%s.%N)

# Launch all requests in background
for i in $(seq 1 $NUM_REQUESTS); do
    make_request "par_$i" "$PROMPT" $MAX_TOKENS &
done

# Wait for all to complete
echo -e "  ${YELLOW}Waiting for all parallel requests to complete...${NC}"
wait

PAR_END=$(date +%s.%N)
PAR_TOTAL=$(echo "$PAR_END - $PAR_START" | bc)

echo -e "  ${GREEN}✓ Completed $NUM_REQUESTS parallel requests${NC}"
echo ""

# Show individual timings
echo -e "${YELLOW}Individual request times:${NC}"
sort "${RESULTS_DIR}/timings.csv" | while IFS=, read -r id elapsed prompt_tok comp_tok; do
    printf "    Request %-6s: %6.3fs (tokens: %d → %d)\n" "$id" "$elapsed" "$prompt_tok" "$comp_tok"
done

echo ""
echo -e "  ${GREEN}Total parallel time: ${PAR_TOTAL}s${NC}"
echo ""

# Calculate speedup
SPEEDUP=$(echo "scale=2; $SEQ_TOTAL / $PAR_TOTAL" | bc)
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}  SPEEDUP: ${SPEEDUP}x faster with parallel requests!${NC}"
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""

read -p "Press Enter to continue to the next demo..."

#===============================================================================
# Demo 2: Continuous Batching Visualization
#===============================================================================
print_header "Demo 2: Continuous Batching in Action"

echo -e "${YELLOW}How vLLM processes multiple requests:${NC}"
echo ""
echo "  Traditional Batching:"
echo "  ┌────────────────────────────────────────────────┐"
echo "  │ Req1: [████████████████]                       │ ← All wait"
echo "  │ Req2: [████████]        ← Padding/waste        │   for longest"
echo "  │ Req3: [████]            ← Padding/waste        │"
echo "  └────────────────────────────────────────────────┘"
echo ""
echo "  Continuous Batching (vLLM):"
echo "  ┌────────────────────────────────────────────────┐"
echo "  │ Req1: [████████████████]                       │"
echo "  │ Req2: [████████]←(done, slot freed)            │"
echo "  │ Req3: [████]←(done)                            │"
echo "  │ Req4:          [████████████] (new request)   │"
echo "  │ Req5:                [██████████] (new)        │"
echo "  └────────────────────────────────────────────────┘"
echo ""

print_subheader "Live Demo: Variable-Length Responses"

echo -e "${YELLOW}Sending 3 requests with different expected output lengths:${NC}"
echo "  • Request A: Short answer (max 20 tokens)"
echo "  • Request B: Medium answer (max 100 tokens)"
echo "  • Request C: Long answer (max 200 tokens)"
echo ""

> "${RESULTS_DIR}/timings.csv"

# Launch requests with different lengths
echo -e "${CYAN}Launching all requests simultaneously...${NC}"
echo ""

START_TIME=$(date +%s.%N)

# Short response
(
    start=$(date +%s.%N)
    curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${API_KEY}" \
      -d '{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "Say hello in one word."}],
        "max_tokens": 20
      }' > "${RESULTS_DIR}/short.json" 2>/dev/null
    end=$(date +%s.%N)
    elapsed=$(echo "$end - $start" | bc)
    tokens=$(jq -r '.usage.completion_tokens' "${RESULTS_DIR}/short.json")
    echo "A_SHORT,${elapsed},${tokens}" >> "${RESULTS_DIR}/var_timings.csv"
    echo -e "  ${GREEN}✓ Request A (short) completed in ${elapsed}s - ${tokens} tokens${NC}"
) &

# Medium response
(
    start=$(date +%s.%N)
    curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${API_KEY}" \
      -d '{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "Explain what an API is in 2-3 sentences."}],
        "max_tokens": 100
      }' > "${RESULTS_DIR}/medium.json" 2>/dev/null
    end=$(date +%s.%N)
    elapsed=$(echo "$end - $start" | bc)
    tokens=$(jq -r '.usage.completion_tokens' "${RESULTS_DIR}/medium.json")
    echo "B_MEDIUM,${elapsed},${tokens}" >> "${RESULTS_DIR}/var_timings.csv"
    echo -e "  ${GREEN}✓ Request B (medium) completed in ${elapsed}s - ${tokens} tokens${NC}"
) &

# Long response
(
    start=$(date +%s.%N)
    curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${API_KEY}" \
      -d '{
        "model": "'${MODEL_NAME}'",
        "messages": [{"role": "user", "content": "Write a short paragraph explaining how neural networks learn."}],
        "max_tokens": 200
      }' > "${RESULTS_DIR}/long.json" 2>/dev/null
    end=$(date +%s.%N)
    elapsed=$(echo "$end - $start" | bc)
    tokens=$(jq -r '.usage.completion_tokens' "${RESULTS_DIR}/long.json")
    echo "C_LONG,${elapsed},${tokens}" >> "${RESULTS_DIR}/var_timings.csv"
    echo -e "  ${GREEN}✓ Request C (long) completed in ${elapsed}s - ${tokens} tokens${NC}"
) &

wait

END_TIME=$(date +%s.%N)
TOTAL_TIME=$(echo "$END_TIME - $START_TIME" | bc)

echo ""
echo -e "${YELLOW}Results:${NC}"
echo ""

# Show that shorter requests finished first
sort -t, -k2 -n "${RESULTS_DIR}/var_timings.csv" | while IFS=, read -r name elapsed tokens; do
    bar_length=$(echo "scale=0; $tokens / 5" | bc)
    bar=$(printf '█%.0s' $(seq 1 $bar_length))
    printf "  %-10s %6.3fs  %3d tokens  %s\n" "$name" "$elapsed" "$tokens" "$bar"
done

echo ""
echo -e "${CYAN}Notice: Shorter requests complete first, freeing GPU resources${NC}"
echo -e "${CYAN}for other work - this is continuous batching in action!${NC}"
echo ""
echo -e "${GREEN}Total wall-clock time: ${TOTAL_TIME}s${NC}"
echo ""

read -p "Press Enter to continue to the load test..."

#===============================================================================
# Demo 3: Load Test
#===============================================================================
print_header "Demo 3: Load Test (Throughput Measurement)"

echo -e "${YELLOW}Testing system throughput with increasing concurrent requests...${NC}"
echo ""

for concurrency in 1 2 5 10; do
    echo -e "${CYAN}Testing with $concurrency concurrent requests...${NC}"

    > "${RESULTS_DIR}/load_timings.csv"

    START=$(date +%s.%N)

    for i in $(seq 1 $concurrency); do
        (
            curl -s "http://${LITELLM_HOST}:${LITELLM_PORT}/v1/chat/completions" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer ${API_KEY}" \
              -d '{
                "model": "'${MODEL_NAME}'",
                "messages": [{"role": "user", "content": "Count from 1 to 5."}],
                "max_tokens": 50
              }' > "${RESULTS_DIR}/load_${i}.json" 2>/dev/null

            tokens=$(jq -r '.usage.total_tokens' "${RESULTS_DIR}/load_${i}.json")
            echo "$tokens" >> "${RESULTS_DIR}/load_tokens.txt"
        ) &
    done

    wait

    END=$(date +%s.%N)
    ELAPSED=$(echo "$END - $START" | bc)

    # Calculate total tokens and throughput
    total_tokens=$(awk '{sum+=$1} END {print sum}' "${RESULTS_DIR}/load_tokens.txt")
    throughput=$(echo "scale=2; $total_tokens / $ELAPSED" | bc)
    req_per_sec=$(echo "scale=2; $concurrency / $ELAPSED" | bc)

    printf "  Concurrency: %2d | Time: %6.2fs | Tokens: %4d | Throughput: %6.1f tok/s | %5.2f req/s\n" \
        "$concurrency" "$ELAPSED" "$total_tokens" "$throughput" "$req_per_sec"

    > "${RESULTS_DIR}/load_tokens.txt"
done

echo ""
echo -e "${GREEN}Key Insight: Throughput (tokens/second) increases with concurrency${NC}"
echo -e "${GREEN}because vLLM batches requests efficiently on the GPU.${NC}"
echo ""

#===============================================================================
# Summary
#===============================================================================
print_header "Concurrent Requests Demo Complete"

echo -e "${GREEN}Key Takeaways:${NC}"
echo ""
echo "  1. vLLM uses continuous batching - no waiting for slow requests"
echo "  2. Parallel requests are processed more efficiently than sequential"
echo "  3. GPU utilization increases with concurrent requests"
echo "  4. Throughput (tokens/sec) scales with concurrency up to GPU limits"
echo "  5. Shorter responses complete first, freeing resources"
echo ""
echo -e "${YELLOW}For production monitoring:${NC}"
echo "  • vLLM exposes Prometheus metrics at /metrics"
echo "  • Key metrics: num_requests_running, num_requests_waiting, gpu_cache_usage_perc"
echo ""
