import ctypes
from contextlib import AbstractContextManager, nullcontext
from pathlib import Path
from typing import List

from bindings.hooks import use_get_public_key_by_private_key
from bindings.utils import (
    CtypePoint,
    CtypeUint256,
    Point,
    as_ctype_uint256,
    as_python_int,
)


class EccMetal:
    def __init__(self, library_path: Path) -> None:
        self._library_path = library_path
        self._library = ctypes.CDLL(str(library_path), mode=ctypes.RTLD_GLOBAL)

        # Define ECCPoint structure for Metal (same as Point but named differently)
        class CtypeECCPoint(ctypes.Structure):
            _fields_ = [
                ("x", CtypeUint256),
                ("y", CtypeUint256),
            ]

        # Load the Metal-specific function
        self._get_public_key_by_private_key_metal = self._library.getPublicKeyByPrivateKeyMetal
        self._get_public_key_by_private_key_metal.argtypes = [
            ctypes.POINTER(CtypeECCPoint),
            ctypes.POINTER(CtypeUint256),
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
            (CtypeUint256 * (n * 4))(*[as_ctype_uint256(key) for key in private_keys]),
            n,
        )

        with kernel_context:
            self._get_public_key_by_private_key_metal(*args)

        points = [
            Point(x=as_python_int(point.x), y=as_python_int(point.y))
            for point in args[0]
        ]

        return points