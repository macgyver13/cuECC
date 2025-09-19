# OpenCL Integration for cuECC

This document describes the OpenCL integration added to cuECC for cross-platform GPU support.

## Overview

The OpenCL integration provides:
- Cross-platform GPU support (AMD, Intel, Apple Silicon, NVIDIA)
- Parallel public key generation from private keys
- Drop-in replacement for CUDA implementation in benchmarks
- secp256k1 elliptic curve operations on GPU

## Building

### Prerequisites
- OpenCL development headers and libraries
- C compiler (clang on macOS, gcc on Linux)

### Build Commands
```bash
# Build only OpenCL library
make opencl

# Build both CUDA and OpenCL libraries
make all

# Clean build directory
make clean
```

## Usage

### Command Line Benchmark
Run benchmarks with all three implementations:
```bash
poetry run benchmark-public-key
```

This will compare:
- **CUDA**: Original NVIDIA GPU implementation
- **OpenCL**: Cross-platform GPU implementation
- **Python**: Pure Python reference implementation

### Programmatic Usage
```python
from bindings.ecc_opencl import EccOpenCL

# Initialize OpenCL ECC
ecc = EccOpenCL("./build/libcuecc_opencl.so")

# Generate public keys from private keys
private_keys = [0x1234567890abcdef] * 1000
public_keys = ecc.get_public_key_by_private_key(private_keys)
```

## Implementation Details

### Architecture
- **Host Code**: `src/opencl/ecc_opencl.c` - OpenCL context management and API
- **Device Code**: `src/opencl/secp256k1_pubkey.cl` - GPU kernels
- **Python Bindings**: `src/bindings/ecc_opencl.py` - Python interface

### Kernel Implementation
The OpenCL kernel implements:
- secp256k1 curve parameters (P, A, B, Generator G)
- 256-bit modular arithmetic operations
- Point doubling and addition
- Scalar multiplication using double-and-add algorithm

### Performance Characteristics
- **Memory Layout**: Optimized for GPU coalescing
- **Work Group Size**: 64 work items (configurable)
- **Batch Processing**: Supports arbitrary batch sizes

## Platform Compatibility

### Tested Platforms
- ✅ macOS (Apple Silicon/Intel with OpenCL framework)
- ⚠️ Linux (requires OpenCL ICD and drivers)
- ⚠️ Windows (requires OpenCL runtime)

### GPU Support
- **NVIDIA**: Via OpenCL drivers
- **AMD**: Via ROCm or proprietary drivers
- **Intel**: Via Intel OpenCL runtime
- **Apple Silicon**: Via built-in OpenCL support

## Performance Notes

### Current Implementation Status
⚠️ **Important**: This is a simplified implementation for demonstration purposes.

**Current Limitations**:
- Simplified modular arithmetic (not production-ready)
- Basic scalar multiplication algorithm
- No optimized field operations
- Placeholder elliptic curve operations

**For Production Use**:
- Implement proper 256-bit modular arithmetic with carry handling
- Add Montgomery ladder or windowed NAF for scalar multiplication
- Optimize field operations for the secp256k1 prime
- Add proper error handling and validation

### Expected Performance
Based on similar implementations:
- **hhanh00/secp256k1-cl**: ~0.068ms per signature verification
- **hashcat secp256k1**: Highly optimized but variable performance

## Integration with secp256k1-cl

The project includes `hhanh00/secp256k1-cl` as a git submodule for reference:
```bash
# Update submodule
git submodule update --init --recursive

# View reference implementation
cat third_party/secp256k1-cl/README.md
```

## Troubleshooting

### Common Issues

1. **OpenCL not found**: Install OpenCL development packages
2. **No devices found**: Check GPU drivers and OpenCL ICD
3. **Kernel compilation failure**: Check OpenCL compiler support
4. **Performance issues**: Verify GPU is being used vs CPU fallback

### Debug Information
Enable verbose output by modifying the error handling in `ecc_opencl.c`.

## Future Improvements

1. **Optimize Arithmetic**: Implement proper 256-bit operations
2. **Better Algorithms**: Add windowed NAF or Montgomery ladder
3. **Memory Optimization**: Reduce memory bandwidth requirements
4. **Platform Testing**: Validate on more GPU types
5. **Error Handling**: Add comprehensive error checking
6. **Benchmarking**: Add detailed performance profiling

## Contributing

When contributing to the OpenCL implementation:
1. Maintain compatibility with the existing benchmark framework
2. Test on multiple platforms when possible
3. Document any platform-specific requirements
4. Follow the existing code style and patterns