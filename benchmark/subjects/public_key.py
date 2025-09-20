import csv
import random
from typing import TextIO, List, Tuple, Any
import os

import click

from benchmark.adapter import adapt_get_public_key_by_private_key
from benchmark.reference.ecc import Ecc as ReferenceEcc
from benchmark.reference.ecc_optimized import EccOptimized
from benchmark.settings import LIBCUECC_SO_PATH, LIBCUECC_OPENCL_SO_PATH, LIBCUECC_METAL_SO_PATH
from benchmark.utils import fast_primes, generate_crypto_primes, generate_range_primes
from bindings.ecc import Ecc as CuEcc
from bindings.ecc_opencl import EccOpenCL
from bindings.ecc_metal import EccMetal


def load_gpu_implementation(gpu_backend: str) -> List[Tuple[str, Any]]:
    """Load GPU implementations based on the selected backend."""
    implementations = []

    if gpu_backend in ["cuda", "both", "all"]:
        try:
            if not os.path.exists(LIBCUECC_SO_PATH):
                print(f"Warning: CUDA library not found at {LIBCUECC_SO_PATH}")
                print("Run 'make cuda' to build the CUDA library")
            else:
                cu_ecc = CuEcc(LIBCUECC_SO_PATH)
                implementations.append(("CUDA", cu_ecc))
                print("✓ CUDA implementation loaded")
        except Exception as e:
            print(f"Warning: Failed to load CUDA implementation: {e}")

    if gpu_backend in ["opencl", "both", "all"]:
        try:
            if not os.path.exists(LIBCUECC_OPENCL_SO_PATH):
                print(f"Warning: OpenCL library not found at {LIBCUECC_OPENCL_SO_PATH}")
                print("Run 'make opencl' to build the OpenCL library")
            else:
                opencl_ecc = EccOpenCL(LIBCUECC_OPENCL_SO_PATH)
                implementations.append(("OpenCL", opencl_ecc))
                print("✓ OpenCL implementation loaded")
        except Exception as e:
            print(f"Warning: Failed to load OpenCL implementation: {e}")

    if gpu_backend in ["metal", "both", "all"]:
        try:
            if not os.path.exists(LIBCUECC_METAL_SO_PATH):
                print(f"Warning: Metal library not found at {LIBCUECC_METAL_SO_PATH}")
                print("Run 'make metal' to build the Metal library")
            else:
                metal_ecc = EccMetal(LIBCUECC_METAL_SO_PATH)
                implementations.append(("Metal", metal_ecc))
                print("✓ Metal implementation loaded")
        except Exception as e:
            print(f"Warning: Failed to load Metal implementation: {e}")

    return implementations


def report(out: TextIO, gpu_backend: str = "both", cpu_backend: str = "none", start_from: int = 1, end_at: int = 30, prime_strategy: str = "small"):
    print("[*] Benchmark: get_public_key_from_private_key")
    print(f"[*] GPU Backend: {gpu_backend}")
    print(f"[*] CPU Backend: {cpu_backend}")
    print(f"[*] Prime Strategy: {prime_strategy}")

    writer = csv.DictWriter(out, fieldnames=["n", "name", "elapsed_time", "is_same"])
    writer.writeheader()

    # Load GPU implementations based on backend selection
    gpu_implementations = []
    if gpu_backend != "none":
        gpu_implementations = load_gpu_implementation(gpu_backend)

    # Start with GPU implementations
    implementations_to_test = gpu_implementations.copy()

    # Add CPU implementations based on cpu_backend selection
    if cpu_backend in ["optimized", "both"]:
        try:
            optimized_ecc = EccOptimized()
            implementations_to_test.append(("CPU-Optimized", optimized_ecc))
            print("✓ CPU-Optimized implementation loaded (coincurve/libsecp256k1)")
        except ImportError:
            print("Warning: coincurve not available, skipping optimized CPU implementation")

    if cpu_backend in ["reference", "both"]:
        reference_ecc = ReferenceEcc()
        implementations_to_test.append(("CPU-Reference", reference_ecc))
        print("✓ CPU-Reference implementation loaded (pure Python)")

    # Warnings for missing implementations
    if not gpu_implementations and gpu_backend != "none":
        print(f"Warning: No GPU implementations available for backend '{gpu_backend}'")

    if not implementations_to_test:
        print("Error: No implementations selected. Use --gpu-backend and/or --cpu-backend to select implementations.")
        return

    if gpu_backend == "none":
        print("[*] GPU backend disabled")
    if cpu_backend == "none":
        print("[*] CPU backend disabled")

    print(f"[*] Testing {len(implementations_to_test)} implementation(s): {[name for name, _ in implementations_to_test]}")

    print(f"- Generating primes using '{prime_strategy}' strategy...")

    if prime_strategy == "small":
        primes = fast_primes(1000000)  # Generate primes up to 1M - sufficient for randomness
    elif prime_strategy == "crypto":
        # Pre-generate some 256-bit cryptographic primes for reuse
        max_needed = 2**end_at
        primes = generate_crypto_primes(min(max_needed, 10000), bits=256)
        print(f"  Generated {len(primes)} cryptographic primes (256-bit)")
    elif prime_strategy == "large":
        # Generate large primes in a reasonable range
        max_needed = 2**end_at
        primes = generate_range_primes(min(max_needed, 10000), min_val=2**31, max_val=2**32)
        print(f"  Generated {len(primes)} large primes (32-bit range)")
    else:
        raise ValueError(f"Unknown prime strategy: {prime_strategy}")

    runnables = [
        (name, adapt_get_public_key_by_private_key(ecc))
        for name, ecc in implementations_to_test
    ]

    for n in range(start_from, end_at + 1):
        print(f"- For 2**n where n = {n}...")

        private_keys = random.choices(primes, k=2**n)

        results = [(name, *runnable(private_keys)) for name, runnable in runnables]

        is_same = all(
            [
                all([public_key == row[0] for public_key in row])
                for row in zip(*[public_keys for _, public_keys, _ in results])
            ]
        )

        writer.writerows(
            [
                {"n": n, "name": name, "elapsed_time": elapsed_time, "is_same": is_same}
                for name, _, elapsed_time in results
            ]
        )

        out.flush()

        for name, public_keys, elapsed_time in results:
            print(f"  - {name}: {elapsed_time} (Sample: {public_keys[0]})")


@click.command()
@click.option("--attempt-key", required=False, help="Custom identifier for the benchmark run")
@click.option("--start-from", required=False, default=1, help="Starting power of 2 for batch size (default: 1)")
@click.option("--end-at", required=False, default=30, help="Ending power of 2 for batch size (default: 30)")
@click.option(
    "--gpu-backend",
    type=click.Choice(["cuda", "opencl", "metal", "both", "all", "none"], case_sensitive=False),
    default="both",
    help="GPU backend to use: cuda (NVIDIA only), opencl (cross-platform), metal (macOS only), both (CUDA+OpenCL), all (test all GPU backends), none (no GPU)"
)
@click.option(
    "--cpu-backend",
    type=click.Choice(["optimized", "reference", "both", "none"], case_sensitive=False),
    default="optimized",
    help="CPU backend to use: optimized (coincurve/libsecp256k1), reference (pure Python), both (test both CPU implementations), none (no CPU)"
)
@click.option(
    "--prime-strategy",
    type=click.Choice(["small", "crypto", "large"], case_sensitive=False),
    default="small",
    help="Prime generation strategy: small (sieve up to 1M), crypto (256-bit cryptographic primes), large (large range primes)"
)
def main(attempt_key: str | None, start_from: int, end_at: int, gpu_backend: str, cpu_backend: str, prime_strategy: str):
    from uuid import uuid4

    from benchmark.settings import BUILD_DIR

    if attempt_key is None:
        attempt_key = uuid4().hex[:6]

    print("[*] Attempt key:", attempt_key)

    # Validate GPU backend requirements
    if gpu_backend != "none":
        if gpu_backend == "cuda" and not os.path.exists(LIBCUECC_SO_PATH):
            print(f"Error: CUDA library not found at {LIBCUECC_SO_PATH}")
            print("Please run 'make cuda' to build the CUDA library")
            return

        if gpu_backend == "opencl" and not os.path.exists(LIBCUECC_OPENCL_SO_PATH):
            print(f"Error: OpenCL library not found at {LIBCUECC_OPENCL_SO_PATH}")
            print("Please run 'make opencl' to build the OpenCL library")
            return

        if gpu_backend == "metal" and not os.path.exists(LIBCUECC_METAL_SO_PATH):
            print(f"Error: Metal library not found at {LIBCUECC_METAL_SO_PATH}")
            print("Please run 'make metal' to build the Metal library")
            return

        if gpu_backend in ["both", "all"]:
            missing_libs = []
            if not os.path.exists(LIBCUECC_SO_PATH):
                missing_libs.append("CUDA (run 'make cuda')")
            if not os.path.exists(LIBCUECC_OPENCL_SO_PATH):
                missing_libs.append("OpenCL (run 'make opencl')")
            if gpu_backend == "all" and not os.path.exists(LIBCUECC_METAL_SO_PATH):
                missing_libs.append("Metal (run 'make metal')")

            if missing_libs:
                print(f"Warning: Missing libraries for '{gpu_backend}' mode: {', '.join(missing_libs)}")
                print("Benchmark will proceed with available implementations")

    # Validate CPU backend requirements
    if cpu_backend in ["optimized", "both"]:
        try:
            import coincurve  # noqa: F401
        except ImportError:
            print("Error: coincurve library not found. Install with: pip install coincurve")
            if cpu_backend == "optimized":
                return

    # Ensure at least one backend is selected
    if gpu_backend == "none" and cpu_backend == "none":
        print("Error: At least one backend must be selected. Use --gpu-backend and/or --cpu-backend.")
        return

    with open(BUILD_DIR / f"report-public-keys-{attempt_key}.csv", "w") as out:
        report(out, gpu_backend, cpu_backend, start_from, end_at, prime_strategy)


if __name__ == "__main__":
    main()
