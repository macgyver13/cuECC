# cuECC Quick Start

GPU-accelerated elliptic curve cryptography benchmarking tool supporting CUDA, OpenCL, and Metal backends.

## Setup

1. **Install Poetry** (if not already installed):
   ```bash
   curl -sSL https://install.python-poetry.org | python3 -
   ```

2. **Install dependencies**:
   ```bash
   poetry install
   ```

3. **Build GPU libraries** (choose your platform):
   ```bash
   make cuda    # NVIDIA GPUs
   make opencl  # Cross-platform
   make metal   # macOS only
   ```

## Quick Examples

**Basic benchmark** (Metal + optimized CPU):
```bash
poetry run benchmark-public-key --gpu-backend metal --cpu-backend optimized
```

**Compare all GPU backends**:
```bash
poetry run benchmark-public-key --gpu-backend all --cpu-backend optimized
```

**CPU-only benchmark**:
```bash
poetry run benchmark-public-key --gpu-backend none --cpu-backend both
```

**Custom range** (smaller test):
```bash
poetry run benchmark-public-key --gpu-backend metal --start-from 12 --end-at 16
```

**Cryptographic primes** (256-bit for realistic crypto testing):
```bash
poetry run benchmark-public-key --gpu-backend metal --prime-strategy crypto
```

## Options

### GPU Backends
- `cuda` - NVIDIA GPUs only
- `opencl` - Cross-platform GPU support
- `metal` - macOS Metal (Apple Silicon/Intel)
- `both` - CUDA + OpenCL
- `all` - Test all available GPU backends
- `none` - Disable GPU testing

### CPU Backends
- `optimized` - Fast libsecp256k1 (coincurve)
- `reference` - Pure Python implementation
- `both` - Test both CPU implementations
- `none` - Disable CPU testing

### Prime Generation
- `small` - Fast sieve up to 1M (default, good for testing)
- `crypto` - 256-bit cryptographic primes (realistic crypto use)
- `large` - Large primes in 32-bit range (middle ground)

### Range Control
- `--start-from N` - Start from 2^N batch size (default: 1)
- `--end-at N` - End at 2^N batch size (default: 30)
- `--attempt-key KEY` - Custom run identifier

## Output

Results are saved to `build/report-public-keys-{attempt_key}.csv` with timing data and correctness validation.