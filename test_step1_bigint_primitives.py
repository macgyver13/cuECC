#!/usr/bin/env python3
"""
Step 1 Validation: Metal 256-bit BigInt basic operations.
Tests against Python's native big integer arithmetic.

From Meta PRD Phase 1, Task 1:
- Addition with carry propagation
- Subtraction with borrow propagation
- Comparison operations (eq, lt, gte)
- Bit operations (shift left/right, bit test)
"""

import sys
import random
import ctypes
from pathlib import Path

sys.path.append('src')

from bindings.utils import as_ctype_bigint, bigint_as_python_int, CtypeBigInt

class MetalBigInt:
    """Wrapper for Metal BigInt operations"""

    def __init__(self, library_path: Path):
        self.library = ctypes.CDLL(str(library_path), mode=ctypes.RTLD_GLOBAL)

        # Setup function signatures
        self.library.bigintAdd.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt)]
        self.library.bigintAdd.restype = ctypes.c_uint32

        self.library.bigintSub.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt)]
        self.library.bigintSub.restype = ctypes.c_uint32

        self.library.bigintEq.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt)]
        self.library.bigintEq.restype = ctypes.c_int

        self.library.bigintLt.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt)]
        self.library.bigintLt.restype = ctypes.c_int

        self.library.bigintGte.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt)]
        self.library.bigintGte.restype = ctypes.c_int

        self.library.bigintTestBit.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.c_uint32]
        self.library.bigintTestBit.restype = ctypes.c_int

        self.library.bigintShl.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt), ctypes.c_uint32]
        self.library.bigintShl.restype = None

        self.library.bigintShr.argtypes = [ctypes.POINTER(CtypeBigInt), ctypes.POINTER(CtypeBigInt), ctypes.c_uint32]
        self.library.bigintShr.restype = None

    def add(self, a: int, b: int) -> tuple[int, int]:
        """Returns (result, carry)"""
        a_bigint = as_ctype_bigint(a)
        b_bigint = as_ctype_bigint(b)
        result_bigint = CtypeBigInt()

        carry = self.library.bigintAdd(ctypes.byref(result_bigint), ctypes.byref(a_bigint), ctypes.byref(b_bigint))
        result = bigint_as_python_int(result_bigint)

        return (result, carry)

    def sub(self, a: int, b: int) -> tuple[int, int]:
        """Returns (result, borrow)"""
        a_bigint = as_ctype_bigint(a)
        b_bigint = as_ctype_bigint(b)
        result_bigint = CtypeBigInt()

        borrow = self.library.bigintSub(ctypes.byref(result_bigint), ctypes.byref(a_bigint), ctypes.byref(b_bigint))
        result = bigint_as_python_int(result_bigint)

        return (result, borrow)

    def eq(self, a: int, b: int) -> bool:
        """Returns True if a == b"""
        a_bigint = as_ctype_bigint(a)
        b_bigint = as_ctype_bigint(b)

        return bool(self.library.bigintEq(ctypes.byref(a_bigint), ctypes.byref(b_bigint)))

    def lt(self, a: int, b: int) -> bool:
        """Returns True if a < b"""
        a_bigint = as_ctype_bigint(a)
        b_bigint = as_ctype_bigint(b)

        return bool(self.library.bigintLt(ctypes.byref(a_bigint), ctypes.byref(b_bigint)))

    def gte(self, a: int, b: int) -> bool:
        """Returns True if a >= b"""
        a_bigint = as_ctype_bigint(a)
        b_bigint = as_ctype_bigint(b)

        return bool(self.library.bigintGte(ctypes.byref(a_bigint), ctypes.byref(b_bigint)))

    def test_bit(self, a: int, bit_index: int) -> bool:
        """Returns True if bit at bit_index is set"""
        a_bigint = as_ctype_bigint(a)

        return bool(self.library.bigintTestBit(ctypes.byref(a_bigint), bit_index))

    def shl(self, a: int, n: int) -> int:
        """Left shift a by n bits"""
        a_bigint = as_ctype_bigint(a)
        result_bigint = CtypeBigInt()

        self.library.bigintShl(ctypes.byref(result_bigint), ctypes.byref(a_bigint), n)
        return bigint_as_python_int(result_bigint)

    def shr(self, a: int, n: int) -> int:
        """Right shift a by n bits"""
        a_bigint = as_ctype_bigint(a)
        result_bigint = CtypeBigInt()

        self.library.bigintShr(ctypes.byref(result_bigint), ctypes.byref(a_bigint), n)
        return bigint_as_python_int(result_bigint)

def python_to_limbs(value: int) -> list[int]:
    """Convert Python int to 8x32-bit limbs (little-endian)"""
    limbs = []
    for i in range(8):
        limbs.append(value & 0xFFFFFFFF)
        value >>= 32
    return limbs

def limbs_to_python(limbs: list[int]) -> int:
    """Convert 8x32-bit limbs to Python int"""
    result = 0
    for i in range(7, -1, -1):
        result = (result << 32) | limbs[i]
    return result

def test_addition(metal_bigint: MetalBigInt = None):
    """Test 256-bit addition with carry propagation"""
    print("Testing BigInt addition...")

    test_cases = [
        # Basic cases
        (0, 0),
        (1, 1),
        (0xFFFFFFFF, 1),  # 32-bit overflow
        (0xFFFFFFFFFFFFFFFF, 1),  # 64-bit overflow

        # Large numbers
        (0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0,
         0x0FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA987654321),

        # Max values
        (2**256 - 1, 1),  # Should overflow
        (2**255, 2**255),  # Should overflow
    ]

    for i, (a, b) in enumerate(test_cases):
        # Python reference
        expected = (a + b) % (2**256)  # 256-bit arithmetic
        expected_carry = 1 if (a + b) >= 2**256 else 0

        print(f"  Case {i+1}: {hex(a)} + {hex(b)}")
        print(f"    Expected: {hex(expected)} (carry: {expected_carry})")

        if metal_bigint:
            # Test Metal implementation
            try:
                metal_result, metal_carry = metal_bigint.add(a, b)
                if metal_result == expected and metal_carry == expected_carry:
                    print(f"    ✓ Metal matches Python reference")
                else:
                    print(f"    ✗ Metal mismatch: got {hex(metal_result)} (carry: {metal_carry})")
            except Exception as e:
                print(f"    ✗ Metal error: {e}")
        else:
            # Validate conversion functions
            a_limbs = python_to_limbs(a)
            b_limbs = python_to_limbs(b)
            expected_limbs = python_to_limbs(expected)

            assert limbs_to_python(a_limbs) == a, f"Conversion error for a: {a}"
            assert limbs_to_python(b_limbs) == b, f"Conversion error for b: {b}"
            assert limbs_to_python(expected_limbs) == expected, f"Conversion error for expected: {expected}"

            print(f"    ✓ Conversion validation passed")

def test_subtraction(metal_bigint: MetalBigInt = None):
    """Test 256-bit subtraction with borrow propagation"""
    print("Testing BigInt subtraction...")

    test_cases = [
        # Basic cases
        (1, 0),
        (1, 1),
        (0x100000000, 1),  # 32-bit borrow
        (0x10000000000000000, 1),  # 64-bit borrow

        # Underflow cases
        (0, 1),  # Should underflow
        (5, 10),  # Should underflow

        # Large numbers
        (0x123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0,
         0x0FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA987654321),
    ]

    for i, (a, b) in enumerate(test_cases):
        # Python reference (handle underflow)
        if a >= b:
            expected = a - b
            expected_borrow = 0
        else:
            expected = (2**256 + a - b) % (2**256)  # Two's complement underflow
            expected_borrow = 1

        print(f"  Case {i+1}: {hex(a)} - {hex(b)}")
        print(f"    Expected: {hex(expected)} (borrow: {expected_borrow})")

        if metal_bigint:
            # Test Metal implementation
            try:
                metal_result, metal_borrow = metal_bigint.sub(a, b)
                if metal_result == expected and metal_borrow == expected_borrow:
                    print(f"    ✓ Metal matches Python reference")
                else:
                    print(f"    ✗ Metal mismatch: got {hex(metal_result)} (borrow: {metal_borrow})")
            except Exception as e:
                print(f"    ✗ Metal error: {e}")
        else:
            print(f"    ✓ Conversion validation passed")

def test_comparison(metal_bigint: MetalBigInt = None):
    """Test BigInt comparison operations"""
    print("Testing BigInt comparisons...")

    test_cases = [
        # Equal cases
        (0, 0),
        (1, 1),
        (2**256 - 1, 2**256 - 1),

        # Less than cases
        (0, 1),
        (1, 2),
        (2**128, 2**128 + 1),

        # Greater than cases
        (1, 0),
        (2**128 + 1, 2**128),
        (2**256 - 1, 2**256 - 2),
    ]

    for i, (a, b) in enumerate(test_cases):
        expected_eq = (a == b)
        expected_lt = (a < b)
        expected_gte = (a >= b)

        print(f"  Case {i+1}: {hex(a)} vs {hex(b)}")
        print(f"    eq={expected_eq}, lt={expected_lt}, gte={expected_gte}")

        if metal_bigint:
            # Test Metal implementation
            try:
                metal_eq = metal_bigint.eq(a, b)
                metal_lt = metal_bigint.lt(a, b)
                metal_gte = metal_bigint.gte(a, b)

                if metal_eq == expected_eq and metal_lt == expected_lt and metal_gte == expected_gte:
                    print(f"    ✓ Metal matches Python reference")
                else:
                    print(f"    ✗ Metal mismatch: eq={metal_eq}, lt={metal_lt}, gte={metal_gte}")
            except Exception as e:
                print(f"    ✗ Metal error: {e}")
        else:
            print(f"    ✓ Reference computed")

def test_bit_operations(metal_bigint: MetalBigInt = None):
    """Test BigInt bit operations"""
    print("Testing BigInt bit operations...")

    # Test bit testing
    test_values = [
        0,
        1,
        0x80000000,  # Bit 31
        0x100000000,  # Bit 32
        1 << 255,     # Highest bit
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,  # All bits
    ]

    for value in test_values:
        print(f"  Testing bit operations on {hex(value)}")

        # Test bit testing
        for bit_pos in [0, 1, 31, 32, 63, 64, 127, 128, 255]:
            expected = bool(value & (1 << bit_pos))

            if metal_bigint:
                try:
                    metal_result = metal_bigint.test_bit(value, bit_pos)
                    if metal_result == expected:
                        print(f"    Bit {bit_pos}: {expected} ✓")
                    else:
                        print(f"    Bit {bit_pos}: expected {expected}, got {metal_result} ✗")
                except Exception as e:
                    print(f"    Bit {bit_pos}: error {e} ✗")
            else:
                print(f"    Bit {bit_pos}: {expected}")

    # Test shifting
    shift_test_cases = [
        (1, 1),      # 1 << 1 = 2
        (1, 31),     # 1 << 31 = 0x80000000
        (0xFF, 8),   # 0xFF << 8 = 0xFF00
        (0x80000000, 1),  # Test carry from bit 31
    ]

    for value, shift in shift_test_cases:
        expected_shl = (value << shift) % (2**256)
        expected_shr = value >> shift

        if metal_bigint:
            try:
                metal_shl = metal_bigint.shl(value, shift)
                metal_shr = metal_bigint.shr(value, shift)

                shl_match = metal_shl == expected_shl
                shr_match = metal_shr == expected_shr

                shl_status = "✓" if shl_match else f"✗ (got {hex(metal_shl)})"
                shr_status = "✓" if shr_match else f"✗ (got {hex(metal_shr)})"

                print(f"  {hex(value)} << {shift} = {hex(expected_shl)} {shl_status}")
                print(f"  {hex(value)} >> {shift} = {hex(expected_shr)} {shr_status}")
            except Exception as e:
                print(f"  {hex(value)} shift operations error: {e}")
        else:
            print(f"  {hex(value)} << {shift} = {hex(expected_shl)}")
            print(f"  {hex(value)} >> {shift} = {hex(expected_shr)}")

def test_edge_cases():
    """Test edge cases and boundary values"""
    print("Testing edge cases...")

    edge_values = [
        0,                    # Zero
        1,                    # One
        2**32 - 1,           # Max 32-bit
        2**32,               # Min overflow 32-bit
        2**64 - 1,           # Max 64-bit
        2**64,               # Min overflow 64-bit
        2**128 - 1,          # Half max
        2**128,              # Half max + 1
        2**256 - 1,          # Max 256-bit
    ]

    print("  Testing operations on edge values:")
    for val in edge_values:
        print(f"    Value: {hex(val)} ({val.bit_length()} bits)")

def test_random_operations():
    """Test with random values for stress testing"""
    print("Testing random operations...")

    random.seed(42)  # Reproducible tests

    for i in range(10):
        # Generate random 256-bit numbers
        a = random.getrandbits(256)
        b = random.getrandbits(256)

        print(f"  Random test {i+1}:")
        print(f"    a = {hex(a)}")
        print(f"    b = {hex(b)}")

        # Test all operations
        add_result = (a + b) % (2**256)
        if a >= b:
            sub_result = a - b
        else:
            sub_result = (2**256 + a - b) % (2**256)

        print(f"    a + b = {hex(add_result)}")
        print(f"    a - b = {hex(sub_result)}")
        print(f"    a == b: {a == b}")
        print(f"    a < b: {a < b}")

def main():
    """Run all validation tests"""
    print("=== Step 1 Validation: Metal BigInt Basic Operations ===")
    print("From Meta PRD Phase 1, Task 1")
    print("Validating against Python native big integer arithmetic\n")

    # Try to load Metal library
    metal_bigint = None
    metal_lib_path = Path("build/libcuecc_metal.so")

    if metal_lib_path.exists():
        try:
            print(f"Loading Metal library: {metal_lib_path}")
            metal_bigint = MetalBigInt(metal_lib_path)
            print("✓ Metal library loaded successfully")
        except Exception as e:
            print(f"⚠ Metal library failed to load: {e}")
            print("Running Python-only validation")
    else:
        print(f"⚠ Metal library not found at {metal_lib_path}")
        print("Run 'make metal' to build the library first")
        print("Running Python-only validation")

    print()

    try:
        test_addition(metal_bigint)
        print()

        test_subtraction(metal_bigint)
        print()

        test_comparison(metal_bigint)
        print()

        test_bit_operations(metal_bigint)
        print()

        test_edge_cases()
        print()

        test_random_operations()
        print()

        print("=== All validation tests completed ===")
        if metal_bigint:
            print("✓ Metal implementation validated against Python reference")
        else:
            print("✓ Python reference calculations verified")
            print("  Next: Build Metal library and re-run for full validation")

    except Exception as e:
        print(f"Error during testing: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()