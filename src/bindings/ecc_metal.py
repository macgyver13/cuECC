import ctypes
from contextlib import AbstractContextManager, nullcontext
from pathlib import Path
from typing import List

from bindings.hooks import use_get_public_key_by_private_key
from bindings.utils import (
    CtypeBigInt,
    Point,
    as_ctype_bigint,
    bigint_as_python_int,
)


class EccMetal:
    def __init__(self, library_path: Path) -> None:
        self._library_path = library_path
        self._library = ctypes.CDLL(str(library_path), mode=ctypes.RTLD_GLOBAL)

        # Define ECCPoint structure for Metal using BigInt (32-bit limbs)
        class CtypeECCPoint(ctypes.Structure):
            _fields_ = [
                ("x", CtypeBigInt),
                ("y", CtypeBigInt),
            ]

        # Load the Metal-specific function
        self._get_public_key_by_private_key_metal = self._library.getPublicKeyByPrivateKeyMetal
        self._get_public_key_by_private_key_metal.argtypes = [
            ctypes.POINTER(CtypeECCPoint),
            ctypes.POINTER(CtypeBigInt),
            ctypes.c_int,
        ]
        self._get_public_key_by_private_key_metal.restype = None
        self._CtypeECCPoint = CtypeECCPoint

    def get_public_key_by_private_key(
        self,
        private_keys: List[int],
        kernel_context: AbstractContextManager[None] | None = None,
    ) -> List[Point]:
        if kernel_context is None:
            kernel_context = nullcontext()

        n = len(private_keys)

        args = (
            (self._CtypeECCPoint * n)(),
            (CtypeBigInt * n)(*[as_ctype_bigint(key) for key in private_keys]),
            n,
        )

        with kernel_context:
            self._get_public_key_by_private_key_metal(*args)

        points = [
            Point(x=bigint_as_python_int(point.x), y=bigint_as_python_int(point.y))
            for point in args[0]
        ]

        return points