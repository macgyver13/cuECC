import ctypes
import struct
from dataclasses import dataclass
from typing import Tuple

CtypeUint256 = ctypes.c_uint64 * 4
CtypeBigInt = ctypes.c_uint32 * 8


@dataclass
class Point:
    x: int
    y: int


class CtypePoint(ctypes.Structure):
    _fields_ = [("x", CtypeUint256), ("y", CtypeUint256)]


def as_uint256(value: int) -> Tuple[int, int, int, int]:
    return tuple(reversed(struct.unpack(">4Q", value.to_bytes(32, "big", signed=False))))  # type: ignore


def as_ctype_uint256(value: int) -> CtypeUint256:
    return CtypeUint256(*as_uint256(value))


def as_python_int(value: CtypeUint256) -> int:
    return int.from_bytes(
        b"".join(reversed([v.to_bytes(8, "big", signed=False) for v in value])),
        "big",
        signed=False,
    )


def as_bigint(value: int) -> Tuple[int, int, int, int, int, int, int, int]:
    """Convert integer to 8x32-bit limbs for BigInt structure (little-endian)"""
    return tuple(struct.unpack("<8I", value.to_bytes(32, "little", signed=False)))


def as_ctype_bigint(value: int) -> CtypeBigInt:
    """Convert integer to ctypes BigInt structure"""
    return CtypeBigInt(*as_bigint(value))


def bigint_as_python_int(value: CtypeBigInt) -> int:
    """Convert ctypes BigInt back to Python integer"""
    return int.from_bytes(
        b"".join([v.to_bytes(4, "little", signed=False) for v in value]),
        "little",
        signed=False,
    )
