import csv
import random
from typing import TextIO, List, Tuple, Any
import os

import click

from benchmark.adapter import adapt_get_public_key_by_private_key
from benchmark.reference.ecc import Ecc as ReferenceEcc
from benchmark.settings import LIBCUECC_SO_PATH, LIBCUECC_OPENCL_SO_PATH, LIBCUECC_METAL_SO_PATH
from benchmark.utils import fast_primes
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


def report(out: TextIO, gpu_backend: str = "both", start_from: int = 1, end_at: int = 30):
    print("[*] Benchmark: get_public_key_from_private_key")
    print(f"[*] GPU Backend: {gpu_backend}")

    writer = csv.DictWriter(out, fieldnames=["n", "name", "elapsed_time", "is_same"])
    writer.writeheader()

    # Load GPU implementations based on backend selection
    gpu_implementations = load_gpu_implementation(gpu_backend)

    # Start with GPU implementations
    implementations_to_test = gpu_implementations.copy()

    # Add Python reference implementation for 'cpu' or 'all' backends
    if gpu_backend in ["cpu", "all"]:
        reference_ecc = ReferenceEcc()
        implementations_to_test.append(("Python", reference_ecc))
        print("✓ Python reference implementation loaded")

    if not gpu_implementations and gpu_backend != "cpu":
        print(f"Warning: No GPU implementations available for backend '{gpu_backend}'")
        print("Falling back to Python-only benchmark")

    if gpu_backend == "cpu":
        print("[*] GPU backend disabled - running CPU-only benchmark")

    print(f"[*] Testing {len(implementations_to_test)} implementation(s): {[name for name, _ in implementations_to_test]}")

    print("- Generating primes...")
    primes = fast_primes(1000000)  # Generate primes up to 1M - sufficient for randomness

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
    type=click.Choice(["cuda", "opencl", "metal", "both", "all", "cpu"], case_sensitive=False),
    default="both",
    help="GPU backend to use: cuda (NVIDIA only), opencl (cross-platform), metal (macOS only), both (CUDA+OpenCL), all (test all available), cpu (CPU only)"
)
def main(attempt_key: str | None, start_from: int, end_at: int, gpu_backend: str):
    from uuid import uuid4

    from benchmark.settings import BUILD_DIR

    if attempt_key is None:
        attempt_key = uuid4().hex[:6]

    print("[*] Attempt key:", attempt_key)

    # Validate that we can run the requested backend
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

    with open(BUILD_DIR / f"report-public-keys-{attempt_key}.csv", "w") as out:
        report(out, gpu_backend, start_from, end_at)


if __name__ == "__main__":
    main()
