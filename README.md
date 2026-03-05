
This repository is the official artifact for the paper 
"An Empirical Study of LLM Serving in Confidential GPUs," 
Eunseong Park, Timo Thans, Vishnu Kumar Kalidasan, 
Qinghao Hu, and Wenjie Xiong, ISPASS 2026.

---

# Background

Confidential Computing (CC) protects data in use by performing gaps in a hardware-based Trusted Execution Environment (TEE). As Large Language Models (LLMs) increasingly handle sensitive information, deploying them on **Confidential GPUs** (e.g., NVIDIA H100 with TEE) has become critical.

However, the hardware abstractions and memory encryption inherent in CC environments introduce performance overheads. This study provides an empirical analysis of these overheads across various serving frameworks (**vLLM, SGLang**) and optimization techniques (e.g., Chunked Prefill, PagedAttention, and Speculative Decoding) to understand the trade-offs between security and performance in LLM serving.

---

# Prerequisites

### Hardware Requirements
- **CPU**: Host system with TEE support (e.g., AMD SEV-SNP or Intel TDX).
- **GPU**: NVIDIA GPU.

### Software Requirements

For experiments in cc mode, a properly configured Confidential Computing VM environment is required.
Follow the official NVIDIA CC deployment guide to configure the host, VM, GPU driver, and runtime stack: [NVIDIA CC Deployment Guide] (https://docs.nvidia.com/cc-deployment-guide-tdx.pdf)

---

# Environment Setup

### 1. Create Conda Environment

```bash
cd setup
conda env create -f environment.yml
conda activate sglang-vllm-latest
```

---

### 2. Verify Installation

```bash
pip show vllm
pip show sglang
```

---

### 3. Replace `bench_serving.py`

We use a modified version of SGLang's `bench_serving.py` to report additional metrics (e.g., ITL p75).  
Replace the original file inside your conda environment:

```bash
SGLANG_PATH=$(python -c "import sglang; print(sglang.__path__[0])")
cp bench_serving.py $SGLANG_PATH/
```

---

### 4. Prepare Hugging Face Credentials

All experiments download models from Hugging Face.  
Before running any scripts, log in and create your credentials:

```bash
huggingface-cli login
```

In addition, Llama models require individual access approval per model.
You must visit each model page and request access before running experiments. For example: [Llama 3.1 8B Instruct] (https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct)

After access is approved, the scripts will be able to download the models successfully.

---

# Running Experiments

### 1. Move to the script directory

```bash
cd ../scripts
```

Each directory contains scripts for a specific experimental configuration.

##### Experiment Configurations

| Directory Name        | LLM Serving Framework | Model(s) Used                               |
|-----------------------|-----------------------|---------------------------------------------|
| compile_figure_8      | SGLang, vLLM          | llama3.1-8B                                 |
| offload_figure_9      | vLLM                  | Qwen2.5-14B                                 |
| swap_figure_12        | SGLang                | Qwen3-1.7B                                  |
| chunked_figure11      | SGLang                | llama3.1-8B                                 |
| offline_figure_5to7   | vLLM, SGLang          | llama3.1-8B, llama3.2-3B, llama3.1-8B-FP8   |
| online_figure_8       | SGLang                | llama3.1-8B, llama3.2-3B, llama3.1-8B-FP8   |

---

### 2. Execute a Script

Enter the desired directory and run:

```bash
./<script_name>
```

During execution:

- You will be prompted for your **sudo password** to start and terminate the LLM server process.
- You will be asked to select a mode based on your current VM setting:
  - `cc`
  - `noncc`

The selected mode ONLY determines the output directory name, not the VM setting. To setup VM, follow Step 0.  
To change the output directory name manually, modify the `OUTPUT_DIR` variable inside the script.

---

# Output Files

After execution, a result directory will be created containing:

- `*.csv`  
  Performance metrics recorded per run.

- `*master*.log`  
  Full terminal output during framework execution.

- `*errors*.log`  
  Error logs (if any failures occur).

---

# License

This project is licensed under the MIT License. See the LICENSE file for details.

---

# Citation

```bash
@inproceedings{park2026confidentialllm,
  title     = {An Empirical Study of LLM Serving in Confidential GPUs},
  author    = {Park, Eunseong and Thans, Timo and Kalidasan, Vishnu Kumar and Hu, Qinghao and Xiong, Wenjie},
  booktitle = {Proceedings of the 2026 IEEE International Symposium on Performance Analysis of Systems and Software (ISPASS)},
  year      = {2026}
}
```
