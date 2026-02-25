#!/bin/bash
set -euo pipefail

# --- (A) sudo 인증 1회 + keepalive ---
sudo -v || { echo "sudo auth failed"; exit 1; }
( while true; do sleep 60; sudo -n -v || exit; done ) &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

# --- (B) root/일반 사용자 모두 동작 ---
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi
 
# Prompt user for CC or non-CC mode
read -p "Enter mode (cc or noncc): " MODE
MODE=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')  # Convert input to lowercase

if [[ "$MODE" != "cc" && "$MODE" != "noncc" ]]; then
  echo "Invalid mode. Please enter 'cc' or 'noncc'."
  exit 1
fi

# Output directory name (same as CSV file name without extension)
OUTPUT_DIR="sglang_online_req16_nps4_${MODE}_5000_$(date +'%Y-%m-%d')"

# Create the output directory
mkdir -p "$OUTPUT_DIR"

# Output CSV file
CSV_FILE="${OUTPUT_DIR}/sglang_online_nps4_${MODE}_$(date +'%Y-%m-%d').csv"
RATIO_CSV_FILE="${OUTPUT_DIR}/sglang_online_ratio_nps4_${MODE}_$(date +'%Y-%m-%d').csv"
ERROR_LOG="${OUTPUT_DIR}/sglang_online_errors_nps4_${MODE}_$(date +'%Y-%m-%d').log"
MASTER_LOG="${OUTPUT_DIR}/sglang_master_online_nps4_${MODE}_$(date +'%Y-%m-%d').log"
CHUNKED_PREFILL_LOG="${OUTPUT_DIR}/chunkedPrefill_$(date +'%Y-%m-%d').log"

# Initialize CSV with headers
echo "model_path,max_num_seqs,successful_requests,total_input_tokens,total_output_tokens,request_throughput,input_token_throughput,output_token_throughput,total_token_throughput,mean_e2e_latency,median_e2e_latency,p25_e2e_latency,p75_e2e_latency,p99_e2e_latency,mean_ttft,median_ttft,p25_ttft,p75_ttft,p99_ttft,mean_tpot,median_tpot,p25_tpot,p75_tpot,p99_tpot,mean_itl,median_itl,p25_itl,p75_itl,p99_itl" > "$CSV_FILE"

echo "model_path,max_num_seqs,ttfts_out,itls_out,tpots_out,e2e_latencies_out" > "$RATIO_CSV_FILE"
# Initialize error log and master log
echo "=== SGLang Benchmark Error Log $(date) ===" > "$ERROR_LOG"
echo "=== SGLang Master Log $(date) ===" > "$MASTER_LOG"
echo "=== Chunked Prefill Log $(date) ===" > "$CHUNKED_PREFILL_LOG"

# Array of model paths
declare -a MODEL_PATHS=(
#    "Qwen/Qwen2.5-7B-Instruct-GPTQ-Int8"
#    "Qwen/Qwen2.5-3B"
#    "Qwen/Qwen2.5-7B"
    "meta-llama/Llama-3.1-8B"
)

declare -a MAX_NUM_SEQUENCES=(16 32 64 128)

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" >> "$ERROR_LOG"
    echo "[$timestamp] ERROR: $1" >&2
}

cleanup_server() {
  echo "Cleaning up sglang server..."

  # 0) Kill parent process explicitly by PID first
  if [[ -f server.pid ]]; then
    local PARENT_PID=$(cat server.pid 2>/dev/null || true)
    if [[ -n "$PARENT_PID" && "$PARENT_PID" =~ ^[0-9]+$ ]]; then
      if ps -p "$PARENT_PID" > /dev/null 2>&1; then
        echo "Killing parent PID=$PARENT_PID (TERM → KILL)"
        $SUDO kill -TERM "$PARENT_PID" 2>/dev/null || true
        sleep 2
        $SUDO kill -KILL "$PARENT_PID" 2>/dev/null || true
      fi
    fi
  fi

  # 1) PID/SID 기반 정밀 종
  local SID=""
  if [[ -f server.sid ]]; then SID=$(cat server.sid || true); fi

  if [[ -n "$SID" && "$SID" =~ ^[0-9]+$ ]]; then
    # 내 세션은 보호
    local MYSID
    MYSID=$(ps -o sid= -p $$ | tr -d " ")

    if [[ "$SID" = "$MYSID" ]]; then
      echo "WARN: server SID == current shell SID, skip session kill; fallback to PID/pattern."
      SID=""
    fi
  fi

  if [[ -n "$SID" ]]; then
    echo "Killing session SID=$SID (TERM → KILL)"
    # 세션 단위 종료 (pkill -s SID 사용: 내 셸/다른 세션 영향 없음)
    $SUDO pkill -TERM -s "$SID" 2>/dev/null || true
    sleep 2
    $SUDO pkill -KILL -s "$SID" 2>/dev/null || true
  else
    echo "No valid server.sid found; fallback to pattern matching."
  fi

  # 2) Aggressive pattern-based cleanup (always run)
  # 서버 커맨드라인만 정밀 타격
  # Kill any zombie processes first
  ps aux | grep "sglang" | grep "<defunct>" | awk "{print \$2}" | xargs -r $SUDO kill -9 2>/dev/null || true

  mapfile -t PIDS < <(ps -e -o pid= -o args= | awk "/python .*sglang\.launch_server/ || /sglang::scheduler/ {print \$1}")
  if [[ ${#PIDS[@]} -gt 0 ]]; then
    echo "Killing remaining PIDs: ${PIDS[*]}"
    for pid in "${PIDS[@]}"; do $SUDO kill -TERM "$pid" 2>/dev/null || true; done
    sleep 2
    for pid in "${PIDS[@]}"; do $SUDO kill -KILL "$pid" 2>/dev/null || true; done
  fi

  # 3) GPU 잔류(sglang 엔진) 마무리
  mapfile -t GPUPIDS < <(nvidia-smi --query-compute-apps=pid --format=csv,noheader | grep -E "^[0-9]+$" || true)
  for gpid in "${GPUPIDS[@]}"; do
    cmd=$(tr "\0" " " < /proc/"$gpid"/cmdline 2>/dev/null || true)
    if [[ "$cmd" == *"sglang.launch_server"* || "$cmd" == *"sglang::scheduler"* ]]; then
      echo "Force-killing GPU PID $gpid"
      $SUDO kill -KILL "$gpid" 2>/dev/null || true
    fi
  done

  # 4) 포트/프로세스 완전 해제 대기 (최대 30초)
  for _ in {1..30}; do
    if ! pgrep -f "sglang.launch_server" >/dev/null && \
       ! pgrep -f "sglang::" >/dev/null && \
       ! (ss -ltn | awk "{print \$4}" | grep -q ":30000$"); then
      break
    fi
    sleep 1
  done

  echo "Remaining sglang procs:"
  pgrep -af "sglang.launch_server\|sglang::" || echo " - none"
  nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader | grep -E "sglang" || echo " - no sglang on GPU"

  rm -f server.log server.sid server.pid
  echo "✅ cleanup done"
}

run_benchmark() {
    local model_path=$1
    local max_num_seqs=$2
    
    echo "Running benchmark for $model_path..."
    cleanup_server
    
    # Remove stale pid/sid files
    rm -f server.pid server.sid

    echo "Starting server (waiting for readiness)..."
    setsid python -m sglang.launch_server --model-path "$model_path" --max-running-requests "$max_num_seqs"  --max-prefill-tokens 8192 > server.log 2>&1 &
    
    # Wait up to 300s for server to be ready
    echo "Waiting for server to initialize..."
    for i in {1..60}; do
        if pgrep -f "sglang::" > /dev/null && curl -s http://localhost:30000/health > /dev/null 2>&1; then
            echo "✓ Server is ready (took $((i*5)) seconds)"
            break
        fi
        sleep 5
        if (( i % 6 == 0 )); then echo -n " ${i}x5s"; fi
    done
    echo ""
    
    # Final check if server started
    if ! pgrep -f "sglang::" > /dev/null; then
        log_error "Server failed to start or crashed for model $model_path."
        cleanup_server
        return 1
    fi
    SERVER_PID=$!
    echo "$SERVER_PID" > server.pid

    SERVER_SID=$(ps -o sid= -p "$SERVER_PID" | tr -d " ")
    echo "$SERVER_SID" > server.sid
    sleep 5
    local result
    if ! python3 -m sglang.bench_serving --backend sglang --dataset-name random --random-output-len 128 --random-input-len 128 --num-prompts 5000 --random-range-ratio 1  --request-rate 16 > benchmark.log 2>&1; then
        log_error "Benchmark failed for model $model_path"
        cat benchmark.log >> "$ERROR_LOG"
        cat benchmark.log >> "$MASTER_LOG"  # Append to master log
        rm -f benchmark.log
        return 1
    fi

    # Append output to master log=
    echo "=== Benchmark Output for $model_path===" >> "$MASTER_LOG"
    cat benchmark.log >> "$MASTER_LOG"
    
    # Parse and store the latest result
    result=$(cat benchmark.log)
    rm -f benchmark.log
    
    if ! echo "$result" | grep -q "Successful requests:"; then
        log_error "Benchmark output missing metrics for model $model_path"
        echo "Full benchmark output:" >> "$ERROR_LOG"
        echo "$result" >> "$ERROR_LOG"
        return 1
    fi
        local successful_requests=$(echo "$result" | grep "Successful requests:" | awk '{print $3}')
local total_input_tokens=$(echo "$result" | grep "Total input tokens:" | awk '{print $4}')
local total_output_tokens=$(echo "$result" | grep "Total generated tokens:" | awk '{print $4}')
local request_throughput=$(echo "$result" | grep "Request throughput" | awk '{print $4}')
local input_token_throughput=$(echo "$result" | grep "Input token throughput" | awk '{print $5}')
local output_token_throughput=$(echo "$result" | grep "Output token throughput" | awk '{print $5}')
local total_token_throughput=$(echo "$result" | grep "Total token throughput" | awk '{print $5}')

local mean_e2e_latency=$(echo "$result" | grep "Mean E2E Latency" | awk '{print $5}')
local median_e2e_latency=$(echo "$result" | grep "Median E2E Latency" | awk '{print $5}')
local p25_e2e_latency=$(echo "$result" | grep "P25 E2E Latency" | awk '{print $5}')
local p75_e2e_latency=$(echo "$result" | grep "P75 E2E Latency" | awk '{print $5}')
local p99_e2e_latency=$(echo "$result" | grep "P99 E2E Latency" | awk '{print $5}')
local mean_ttft=$(echo "$result" | grep "Mean TTFT" | awk '{print $4}')
local median_ttft=$(echo "$result" | grep "Median TTFT" | awk '{print $4}')
local p25_ttft=$(echo "$result" | grep "P25 TTFT" | awk '{print $4}')
local p75_ttft=$(echo "$result" | grep "P75 TTFT" | awk '{print $4}')
local p99_ttft=$(echo "$result" | grep "P99 TTFT" | awk '{print $4}')

local mean_tpot=$(echo "$result" | grep "Mean TPOT" | awk '{print $4}')
local median_tpot=$(echo "$result" | grep "Median TPOT" | awk '{print $4}')
local p25_tpot=$(echo "$result" | grep "P25 TPOT" | awk '{print $4}')
local p75_tpot=$(echo "$result" | grep "P75 TPOT" | awk '{print $4}')
local p99_tpot=$(echo "$result" | grep "P99 TPOT" | awk '{print $4}')

local mean_itl=$(echo "$result" | grep "Mean ITL" | awk '{print $4}')
local median_itl=$(echo "$result" | grep "Median ITL" | awk '{print $4}')
local p25_itl=$(echo "$result" | grep "P25 ITL" | awk '{print $4}')
local p75_itl=$(echo "$result" | grep "P75 ITL" | awk '{print $4}')
local p99_itl=$(echo "$result" | grep "P99 ITL" | awk '{print $4}')

local ttfts_out=$(echo "$result" | grep "^TTFTs:" | sed 's/^TTFTs: //')
local itls_out=$(echo "$result" | grep "^ITLs:" | sed 's/^ITLs: //')
local e2e_latencies_out=$(echo "$result" | grep "^E2E Latencies:" | sed 's/^E2E Latencies: //')
local tpots_out=$(echo "$result" | grep "^TPOTs:" | sed 's/^TPOTs: //')

ttfts_out=$(echo "$ttfts_out" | tr -d '[]' | sed 's/, /;/g')
itls_out=$(echo "$itls_out" | tr -d '[]' | sed 's/, /;/g')
e2e_latencies_out=$(echo "$e2e_latencies_out" | tr -d '[]' | sed 's/, /;/g')
tpots_out=$(echo "$tpots_out" | tr -d '[]' | sed 's/, /;/g')

echo "$model_path,$max_num_seqs,$successful_requests,$total_input_tokens,$total_output_tokens,$request_throughput,$input_token_throughput,$output_token_throughput,$total_token_throughput,$mean_e2e_latency,$median_e2e_latency,$p25_e2e_latency,$p75_e2e_latency,$p99_e2e_latency,$mean_ttft,$median_ttft,$p25_ttft,$p75_ttft,$p99_ttft,$mean_tpot,$median_tpot,$p25_tpot,$p75_tpot,$p99_tpot,$mean_itl,$median_itl,$p25_itl,$p75_itl,$p99_itl" >> "$CSV_FILE"

echo "$model_path,\"$ttfts_out\",\"$itls_out\",\"$e2e_latencies_out\",\"$tpots_out\"" >> "$RATIO_CSV_FILE" 

    return 0
}

for i in {1..3}; do
for model_path in "${MODEL_PATHS[@]}"; do
for max_num_seqs in "${MAX_NUM_SEQUENCES[@]}"; do
        echo "=== Starting benchmark run at $(date) ===" >> "$ERROR_LOG"
        if ! run_benchmark "$model_path" "$max_num_seqs"; then
            log_error "Benchmark run failed for model $model_path"
            continue
        fi
done
done

echo "All benchmarks completed. Results saved to $CSV_FILE"
echo "Chunked prefill logs saved to $CHUNKED_PREFILL_LOG"
echo "Error logs and outputs compressed to benchmark_logs.zip"

done
