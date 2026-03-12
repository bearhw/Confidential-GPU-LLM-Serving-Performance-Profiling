#!/bin/bash
set -e

echo "Installing sglang"
pip install sglang

echo "Removing incompatible sgl_kernel"
pip uninstall -y sgl-kernel || true

# clone only if repo does not exist
if [ ! -d "sglang" ]; then
    echo "Cloning sglang repo"
    git clone https://github.com/sgl-project/sglang.git
fi

echo "Building sgl_kernel"

cd sglang/sgl-kernel

export TORCH_CUDA_ARCH_LIST="9.0"

pip install -v .
