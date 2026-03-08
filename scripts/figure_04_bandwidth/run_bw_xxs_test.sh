#!/bin/bash

# 1. 경로 설정 수정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# scripts/figure_04_bandwidth -> scripts -> PROJECT_ROOT 순으로 올라감
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
OUTPUT_DIR="$PROJECT_ROOT/results"
CUDA_SAMPLES_DIR="$PROJECT_ROOT/cuda-samples"

mkdir -p "$OUTPUT_DIR"

# 2. 사용자 입력 (CC vs Non-CC)
echo "------------------------------------------------"
echo "Select the environment for this measurement:"
echo "1) CC (Confidential Computing)"
echo "2) Non-CC"
read -p "Enter choice [1 or 2]: " env_choice

case $env_choice in
    1) ENV_TAG="cc" ;;
    2) ENV_TAG="noncc" ;;
    *) 
       echo "Invalid choice. Defaulting to 'unknown'."
       ENV_TAG="unknown" 
       ;;
esac

# 최종 파일 이름 설정
OUTPUT_FILE="$OUTPUT_DIR/raw_bandwidth_${ENV_TAG}_xxs.txt"

# 3. 서브모듈 체크 및 자동 업데이트
if [ ! -d "$CUDA_SAMPLES_DIR" ] || [ -z "$(ls -A "$CUDA_SAMPLES_DIR")" ]; then
    echo "Submodule directory is empty. Initializing submodules..."
    git -C "$PROJECT_ROOT" submodule update --init --recursive
fi

# 4. bandwidthTest 위치 찾기 및 컴파일
BW_TEST_DIR=$(find "$CUDA_SAMPLES_DIR" -type d -name "bandwidthTest" | head -n 1)

if [ -z "$BW_TEST_DIR" ]; then
    echo "Error: Could not find bandwidthTest directory."
    exit 1
fi

echo "Compiling bandwidthTest in: $BW_TEST_DIR"
cd "$BW_TEST_DIR"
make -s

# 5. 실행 및 결과 저장
if [ -f "./bandwidthTest" ]; then
    echo "Running benchmark (1KB to 1MB)..."
    ./bandwidthTest --mode=range --start=1024 --end=1048576 --increment=1024 > "$OUTPUT_FILE"
    echo "------------------------------------------------"
    echo "Success! Results saved to: $OUTPUT_FILE"
else
    echo "Error: Compilation failed."
    exit 1
fi
