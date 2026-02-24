
Official artifact for the ISPASS 2026 paper:

> "An Empirical Study of LLM Serving  in Confidential GPUs"

---

**1. Tested Environment**

The artifact was tested on:

GPU: NVIDIA H100 (80GB) 

Driver: 570.172.08

CUDA: 12.8

PyTorch: 2.x.x+cu121

Python: 3.10

Operating System:

Ubuntu 22.04


**3. Repository Structure**

```
.
├── machine_A
├── machine_I
├── sglang
└── vllm
```

**4. Setup Instructions**

Step 1: Clone Repository
git clone --recursive <repo_url>
cd <repo_name>

If submodules are not initialized:

git submodule update --init --recursive
Step 2: Create Environment

Using conda:

conda create -n artifact python=3.10
conda activate artifact

Install dependencies:

pip install -r requirements.txt
pip install -e ./vllm
pip install -e ./sglang

Verify installation:

python -c "import torch; import vllm; import sglang; print('OK')"



Expected runtime: ~3 hours


8. Determinism

All experiments use:

Identical batch configurations

Controlled GPU settings

Minor runtime variations may occur due to ....
