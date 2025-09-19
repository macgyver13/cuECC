# Ubuntu Setup Guide for cuECC

This guide provides Ubuntu-specific instructions for setting up and building cuECC with OpenCL support.

## Prerequisites

### Basic Development Tools
```bash
sudo apt update
sudo apt install build-essential pkg-config
```

### Python Environment
```bash
# Install Poetry (recommended)
curl -sSL https://install.python-poetry.org | python3 -

# Or use pip
pip install poetry
```

## GPU-Specific Setup

### NVIDIA GPUs

1. **Install NVIDIA Drivers**
   ```bash
   # Check if drivers are installed
   nvidia-smi

   # If not installed
   sudo apt install nvidia-driver-535  # or latest version
   ```

2. **Install CUDA Toolkit** (for CUDA support)
   ```bash
   # Add NVIDIA package repository
   wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.0-1_all.deb
   sudo dpkg -i cuda-keyring_1.0-1_all.deb

   # Install CUDA
   sudo apt update
   sudo apt install cuda-toolkit-12-3  # or latest version
   ```

3. **Install OpenCL for NVIDIA**
   ```bash
   sudo apt install nvidia-opencl-dev
   ```

### AMD GPUs

1. **Install AMD Drivers**
   ```bash
   # For recent AMD GPUs
   sudo apt install amdgpu-install

   # Or use Mesa drivers (open source)
   sudo apt install mesa-vulkan-drivers mesa-opencl-dev
   ```

2. **Install OpenCL for AMD**
   ```bash
   sudo apt install mesa-opencl-dev rocm-opencl-dev
   ```

### Intel GPUs

1. **Install Intel OpenCL**
   ```bash
   # For Intel integrated graphics
   sudo apt install intel-opencl-icd

   # For Intel Arc GPUs (newer)
   sudo apt install intel-level-zero-gpu level-zero-dev
   ```

### Generic OpenCL (Works with Multiple Vendors)

If you're unsure about your GPU or want maximum compatibility:

```bash
sudo apt install ocl-icd-libopencl1 opencl-headers ocl-icd-dev
```

## Building cuECC

### 1. Clone and Setup
```bash
git clone <your-repo-url>
cd cuECC
git submodule update --init --recursive
poetry install
```

### 2. Check OpenCL Availability
```bash
# Check what OpenCL implementations are available
make check-opencl

# List OpenCL devices
clinfo  # install with: sudo apt install clinfo
```

### 3. Build Libraries

```bash
# Build CUDA library (NVIDIA GPUs only)
make cuda

# Build OpenCL library (cross-platform)
make opencl

# Build both
make all
```

### 4. Run Benchmarks

```bash
# Test specific GPU backend
poetry run benchmark-public-key --gpu-backend cuda     # NVIDIA only
poetry run benchmark-public-key --gpu-backend opencl   # Any GPU
poetry run benchmark-public-key --gpu-backend none     # CPU only

# Test all available
poetry run benchmark-public-key --gpu-backend both
```

## Troubleshooting

### Common Issues

#### 1. "cannot find -lOpenCL"
```bash
# Install OpenCL development libraries
sudo apt install ocl-icd-libopencl1 opencl-headers ocl-icd-dev

# For specific vendors, see GPU-specific sections above
```

#### 2. "CL/cl.h: No such file or directory"
```bash
# Install OpenCL headers
sudo apt install opencl-headers
```

#### 3. "No OpenCL devices found"
```bash
# Check if drivers are properly installed
clinfo

# For NVIDIA
nvidia-smi

# For AMD
rocm-smi  # if using ROCm

# Restart after driver installation
sudo reboot
```

#### 4. Permission Issues with GPU
```bash
# Add user to render group (for GPU access)
sudo usermod -a -G render $USER

# Logout and login again
```

### Verify Installation

1. **Check OpenCL Devices**
   ```bash
   clinfo
   ```

2. **Test OpenCL Build**
   ```bash
   make clean
   make check-opencl
   make opencl
   ```

3. **Run Small Benchmark**
   ```bash
   poetry run benchmark-public-key --gpu-backend opencl --start-from 1 --end-at 5
   ```

## Ubuntu Version Compatibility

| Ubuntu Version | Tested | Notes |
|----------------|--------|-------|
| 22.04 LTS | ✅ | Recommended |
| 20.04 LTS | ✅ | Requires newer GPU drivers |
| 24.04 LTS | ⚠️ | Should work, may need package updates |

## Performance Tips

1. **GPU Frequency Scaling**
   ```bash
   # Set GPU to performance mode (NVIDIA)
   sudo nvidia-smi -pm 1
   sudo nvidia-smi -lgc 2100  # set max clock
   ```

2. **CPU Frequency Scaling**
   ```bash
   # Set CPU governor to performance
   sudo cpupower frequency-set -g performance
   ```

3. **Memory Overcommit**
   ```bash
   # For large batch sizes
   echo 1 | sudo tee /proc/sys/vm/overcommit_memory
   ```

## Package Summary by Use Case

### Research/Development Setup
```bash
sudo apt install build-essential pkg-config opencl-headers ocl-icd-libopencl1 ocl-icd-dev clinfo
```

### NVIDIA CUDA + OpenCL
```bash
sudo apt install nvidia-driver-535 cuda-toolkit-12-3 nvidia-opencl-dev
```

### AMD GPU Setup
```bash
sudo apt install mesa-opencl-dev rocm-opencl-dev amdgpu-install
```

### Intel GPU Setup
```bash
sudo apt install intel-opencl-icd intel-level-zero-gpu
```

## Getting Help

1. Check the main README.md for general setup
2. Run `make check-opencl` to diagnose OpenCL issues
3. Use `clinfo` to verify GPU detection
4. Check `/var/log/kern.log` for driver issues