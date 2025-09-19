import ctypes
import time
from contextlib import AbstractContextManager, nullcontext
from typing import List

from bindings.ecc import EccProtocol
from bindings.utils import Point


class EccOpenCL(EccProtocol):
    """OpenCL implementation of ECC operations for benchmarking"""

    def __init__(self, library_path: str = "./libcuecc_opencl.so") -> None:
        """Initialize OpenCL ECC with library path"""
        self.lib = ctypes.CDLL(library_path)

        # Define function signatures
        self.lib.getPublicKeyByPrivateKeyOpenCL.argtypes = [
            ctypes.POINTER(Point),  # output array
            ctypes.POINTER(ctypes.c_uint64 * 4),  # private keys array
            ctypes.c_int  # number of keys
        ]
        self.lib.getPublicKeyByPrivateKeyOpenCL.restype = None

    def get_public_key_by_private_key(
        self,
        private_keys: List[int],
        kernel_context: AbstractContextManager[None] | None = None,
    ) -> List[Point]:
        """Generate public keys from private keys using OpenCL"""
        if kernel_context is None:
            kernel_context = nullcontext()

        n = len(private_keys)

        # Convert private keys to the expected format (4 x uint64 per key)
        private_keys_array = (ctypes.c_uint64 * 4 * n)()
        for i, key in enumerate(private_keys):
            # Convert int to 4 x uint64 little-endian representation
            private_keys_array[i][0] = key & 0xFFFFFFFFFFFFFFFF
            private_keys_array[i][1] = (key >> 64) & 0xFFFFFFFFFFFFFFFF
            private_keys_array[i][2] = (key >> 128) & 0xFFFFFFFFFFFFFFFF
            private_keys_array[i][3] = (key >> 192) & 0xFFFFFFFFFFFFFFFF

        # Prepare output array
        output_array = (Point * n)()

        with kernel_context:
            # Call OpenCL function
            self.lib.getPublicKeyByPrivateKeyOpenCL(
                output_array,
                private_keys_array,
                n
            )

        # Convert output to Python list
        return [Point(x=point.x, y=point.y) for point in output_array]