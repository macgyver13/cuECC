import platform
from pathlib import Path

SETTINGS_PATH = Path(__file__)
BENCHMARK_DIR = SETTINGS_PATH.parent
PROJECT_DIR = BENCHMARK_DIR.parent

BUILD_DIR = PROJECT_DIR / "build"

# Platform-specific library extensions and naming
if platform.system() == "Windows":
    LIB_EXT = ".dll"
    LIBCUECC_SO_PATH = BUILD_DIR / f"cuecc{LIB_EXT}"
    LIBCUECC_OPENCL_SO_PATH = BUILD_DIR / f"cuecc_opencl{LIB_EXT}"
    LIBCUECC_METAL_SO_PATH = BUILD_DIR / f"cuecc_metal{LIB_EXT}"
elif platform.system() == "Darwin":
    LIB_EXT = ".dylib"
    LIBCUECC_SO_PATH = BUILD_DIR / f"libcuecc{LIB_EXT}"
    LIBCUECC_OPENCL_SO_PATH = BUILD_DIR / f"libcuecc_opencl{LIB_EXT}"
    LIBCUECC_METAL_SO_PATH = BUILD_DIR / f"libcuecc_metal{LIB_EXT}"
else:  # Linux and other Unix-like systems
    LIB_EXT = ".so"
    LIBCUECC_SO_PATH = BUILD_DIR / f"libcuecc{LIB_EXT}"
    LIBCUECC_OPENCL_SO_PATH = BUILD_DIR / f"libcuecc_opencl{LIB_EXT}"
    LIBCUECC_METAL_SO_PATH = BUILD_DIR / f"libcuecc_metal{LIB_EXT}"
