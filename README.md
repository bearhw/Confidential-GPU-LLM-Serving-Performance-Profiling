
Official artifact for the ISPASS 2026 paper:

> "An Empirical Study of LLM Serving  in Confidential GPUs"

---
# Environment Setup

## 1. Create Conda Environment

```bash
cd setup
conda env create -f environment.yml
conda activate sglang-vllm-latest
```

---

## 2. Verify Installation

```bash
pip show vllm
pip show sglang
```

---

## 3. Replace `bench_serving.py`

We use a modified version of SGLang's `bench_serving.py` to report additional metrics (e.g., ITL p75).  
Replace the original file inside your conda environment:

```bash
cp bench_serving.py <path_to_conda_env>/site-packages/sglang
```

Example:

```bash
cp bench_serving.py /path/to/miniconda3/envs/sglang-vllm-latest/lib/python3.10/site-packages/sglang
```

---

# Running Experiments

```bash
cd ../scripts
```

Each directory contains scripts for a specific experimental configuration.

## Experiment Configurations

| Directory Name        | LLM Serving Framework | Model(s) Used                               |
|-----------------------|-----------------------|---------------------------------------------|
| compile_figure_8      | SGLang, vLLM          | llama3.1-8B                                 |
| offload_figure_9      | vLLM                  | Qwen2.5-14B                                 |
| swap_figure_12        | SGLang                | Qwen3-1.7B                                  |
| chunked_figure11      | SGLang                | llama3.1-8B                                 |
| offline_figure_5to7   | vLLM, SGLang          | llama3.1-8B, llama3.2-3B, llama3.1-8B-FP8   |
| online_figure_8       | SGLang                | llama3.1-8B, llama3.2-3B, llama3.1-8B-FP8   |

---

## Execute a Script

Enter the desired directory and run:

```bash
./<script_name>
```

During execution:

- You will be prompted for your **sudo password** to start and terminate the LLM server process.
- You will be asked to select a mode:
  - `cc`
  - `noncc`

The selected mode determines the output directory name.  
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

