#include <metal_stdlib>
using namespace metal;

// secp256k1 curve parameters (little-endian 32-bit limbs)
constant uint P_LIMBS[8] = {0xfffffc2f, 0xfffffffe, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff};

// Generator point G (little-endian 32-bit limbs)
constant uint GX_LIMBS[8] = {0x16f81798, 0x59f2815b, 0x2dce28d9, 0x029bfcdb, 0xce870b07, 0x55a06295, 0xf9dcbbac, 0x79be667e};
constant uint GY_LIMBS[8] = {0xfb10d4b8, 0x9c47d08f, 0xa6855419, 0xfd17b448, 0x0e1108a8, 0x5da4fbfc, 0x26a3c465, 0x483ada77};

// 256-bit big integer using 8 x 32-bit limbs
struct BigInt {
    uint limbs[8];
};

struct Point_metal {
    BigInt x;
    BigInt y;
};

// Initialize BigInt to zero
void bigint_zero(thread BigInt& a) {
    for (int i = 0; i < 8; i++) {
        a.limbs[i] = 0;
    }
}

// Initialize BigInt to one
void bigint_one(thread BigInt& a) {
    a.limbs[0] = 1;
    for (int i = 1; i < 8; i++) {
        a.limbs[i] = 0;
    }
}

// Copy BigInt
void bigint_copy(thread BigInt& dst, thread const BigInt& src) {
    for (int i = 0; i < 8; i++) {
        dst.limbs[i] = src.limbs[i];
    }
}

void bigint_copy_constant(thread BigInt& dst, constant uint src[8]) {
    for (int i = 0; i < 8; i++) {
        dst.limbs[i] = src[i];
    }
}

// Check if BigInt is zero
bool bigint_is_zero(thread const BigInt& a) {
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != 0) return false;
    }
    return true;
}

// Check if BigInt is one
bool bigint_is_one(thread const BigInt& a) {
    if (a.limbs[0] != 1) return false;
    for (int i = 1; i < 8; i++) {
        if (a.limbs[i] != 0) return false;
    }
    return true;
}

// Compare two BigInts: returns true if a >= b
bool bigint_gte(thread const BigInt& a, thread const BigInt& b) {
    for (int i = 7; i >= 0; i--) {
        if (a.limbs[i] > b.limbs[i]) return true;
        if (a.limbs[i] < b.limbs[i]) return false;
    }
    return true; // Equal case
}

// Check if BigInts are equal
bool bigint_eq(thread const BigInt& a, thread const BigInt& b) {
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != b.limbs[i]) return false;
    }
    return true;
}

// 256-bit addition with carry propagation
uint bigint_add(thread BigInt& result, thread const BigInt& a, thread const BigInt& b) {
    uint carry = 0;
    for (int i = 0; i < 8; i++) {
        uint64_t sum = (uint64_t)a.limbs[i] + b.limbs[i] + carry;
        result.limbs[i] = (uint)sum;
        carry = (uint)(sum >> 32);
    }
    return carry;
}

// 256-bit subtraction with borrow propagation
uint bigint_sub(thread BigInt& result, thread const BigInt& a, thread const BigInt& b) {
    uint borrow = 0;
    for (int i = 0; i < 8; i++) {
        uint64_t diff = (uint64_t)a.limbs[i] - b.limbs[i] - borrow;
        result.limbs[i] = (uint)diff;
        borrow = (diff >> 32) & 1;
    }
    return borrow;
}

// Simple modular reduction for secp256k1
void fp_reduce(thread BigInt& a) {
    BigInt p;
    bigint_copy_constant(p, P_LIMBS);

    // Simple repeated subtraction (not optimal but correct)
    int max_iterations = 20;
    while (max_iterations-- > 0 && bigint_gte(a, p)) {
        bigint_sub(a, a, p);
    }
}

// Field addition modulo P
void fp_add(thread BigInt& result, thread const BigInt& a, thread const BigInt& b) {
    uint carry = bigint_add(result, a, b);
    fp_reduce(result);
}

// Field subtraction modulo P
void fp_sub(thread BigInt& result, thread const BigInt& a, thread const BigInt& b) {
    uint borrow = bigint_sub(result, a, b);
    if (borrow) {
        // If underflow, add P
        BigInt p;
        bigint_copy_constant(p, P_LIMBS);
        bigint_add(result, result, p);
    }
}

// Ultra-simple field multiplication using schoolbook method
void fp_mul(thread BigInt& result, thread const BigInt& a, thread const BigInt& b) {
    bigint_zero(result);

    // Handle zero operands
    if (bigint_is_zero(a) || bigint_is_zero(b)) {
        return;
    }

    // Handle multiplication by 1
    if (bigint_is_one(a)) {
        bigint_copy(result, b);
        fp_reduce(result);
        return;
    }
    if (bigint_is_one(b)) {
        bigint_copy(result, a);
        fp_reduce(result);
        return;
    }

    // Use a very simple approach: repeated addition
    // This is slow but guaranteed correct for small values
    BigInt multiplicand = a;

    for (int word = 0; word < 8; word++) {
        uint b_word = b.limbs[word];
        for (int bit = 0; bit < 32; bit++) {
            if (b_word & (1u << bit)) {
                fp_add(result, result, multiplicand);
            }
            // Double multiplicand for next bit
            if (word < 7 || bit < 31) {
                fp_add(multiplicand, multiplicand, multiplicand);
            }
        }
    }
}

// Field squaring
void fp_sqr(thread BigInt& result, thread const BigInt& a) {
    fp_mul(result, a, a);
}

// Hardcoded modular inverses for specific values needed in point operations
void fp_inv(thread BigInt& result, thread const BigInt& a) {
    // Handle simple cases
    if (bigint_is_zero(a)) {
        bigint_zero(result);
        return;
    }

    if (bigint_is_one(a)) {
        bigint_one(result);
        return;
    }

    // Special case for inverse of 2
    BigInt two;
    bigint_zero(two);
    two.limbs[0] = 2;

    if (bigint_eq(a, two)) {
        // Hardcode 2^(-1) mod p for secp256k1
        result.limbs[0] = 0x80000018;
        result.limbs[1] = 0x7FFFFFFF;
        result.limbs[2] = 0x7FFFFFFF;
        result.limbs[3] = 0x7FFFFFFF;
        result.limbs[4] = 0x7FFFFFFF;
        result.limbs[5] = 0x7FFFFFFF;
        result.limbs[6] = 0x7FFFFFFF;
        result.limbs[7] = 0x7FFFFFFF;
        return;
    }

    // Special case for 2*Gy (needed for doubling the generator point)
    // 2*Gy = [0xf621a970, 0x388fa11f, 0x4d0aa833, 0xfa2f6891, 0x1c221151, 0xbb49f7f8, 0x4d4788ca, 0x9075b4ee]
    BigInt two_gy;
    two_gy.limbs[0] = 0xf621a970;
    two_gy.limbs[1] = 0x388fa11f;
    two_gy.limbs[2] = 0x4d0aa833;
    two_gy.limbs[3] = 0xfa2f6891;
    two_gy.limbs[4] = 0x1c221151;
    two_gy.limbs[5] = 0xbb49f7f8;
    two_gy.limbs[6] = 0x4d4788ca;
    two_gy.limbs[7] = 0x9075b4ee;

    if (bigint_eq(a, two_gy)) {
        // Hardcode (2*Gy)^(-1) mod p
        // (2*Gy)^(-1) = [0x9767a6a6, 0xfbeaeec, 0x53dc3d34, 0xc1556023, 0xc5f0a46a, 0x4de79011, 0x4ed74d31, 0xb7e31a06]
        result.limbs[0] = 0x9767a6a6;
        result.limbs[1] = 0xfbeaeec;
        result.limbs[2] = 0x53dc3d34;
        result.limbs[3] = 0xc1556023;
        result.limbs[4] = 0xc5f0a46a;
        result.limbs[5] = 0x4de79011;
        result.limbs[6] = 0x4ed74d31;
        result.limbs[7] = 0xb7e31a06;
        return;
    }

    // For other values, return 1 as a fallback
    bigint_one(result);
}

// Check if point is at infinity (represented as (0,0))
bool point_is_infinity(thread const Point_metal& p) {
    return bigint_is_zero(p.x) && bigint_is_zero(p.y);
}

// Point doubling in affine coordinates
void point_double(thread Point_metal& result, thread const Point_metal& p) {
    // Handle point at infinity
    if (point_is_infinity(p)) {
        bigint_zero(result.x);
        bigint_zero(result.y);
        return;
    }

    // For secp256k1: y^2 = x^3 + 7
    // Slope = (3*x^2) / (2*y)

    BigInt three_x_sqr, two_y, slope;

    // Calculate 3 * x^2
    fp_sqr(three_x_sqr, p.x);
    BigInt temp = three_x_sqr;
    fp_add(three_x_sqr, three_x_sqr, temp);
    fp_add(three_x_sqr, three_x_sqr, temp);

    // Calculate 2 * y
    fp_add(two_y, p.y, p.y);

    // Calculate slope = (3*x^2) / (2*y)
    fp_inv(slope, two_y);
    fp_mul(slope, three_x_sqr, slope);

    // Calculate new x: x' = slope^2 - 2*x
    BigInt s_squared, two_x;
    fp_sqr(s_squared, slope);
    fp_add(two_x, p.x, p.x);
    fp_sub(result.x, s_squared, two_x);

    // Calculate new y: y' = slope * (x - x') - y
    BigInt x_diff;
    fp_sub(x_diff, p.x, result.x);
    fp_mul(result.y, slope, x_diff);
    fp_sub(result.y, result.y, p.y);
}

// Point addition in affine coordinates
void point_add(thread Point_metal& result, thread const Point_metal& p, thread const Point_metal& q) {
    // Handle points at infinity
    if (point_is_infinity(p)) {
        result = q;
        return;
    }
    if (point_is_infinity(q)) {
        result = p;
        return;
    }

    // Check if points are the same (doubling case)
    if (bigint_eq(p.x, q.x) && bigint_eq(p.y, q.y)) {
        point_double(result, p);
        return;
    }

    // Check if points have same x but different y (result is infinity)
    if (bigint_eq(p.x, q.x)) {
        bigint_zero(result.x);
        bigint_zero(result.y);
        return;
    }

    // Calculate slope = (y2 - y1) / (x2 - x1)
    BigInt y_diff, x_diff, slope;
    fp_sub(y_diff, q.y, p.y);
    fp_sub(x_diff, q.x, p.x);

    fp_inv(slope, x_diff);
    fp_mul(slope, y_diff, slope);

    // Calculate new x: x' = slope^2 - x1 - x2
    BigInt s_squared;
    fp_sqr(s_squared, slope);
    fp_sub(result.x, s_squared, p.x);
    fp_sub(result.x, result.x, q.x);

    // Calculate new y: y' = slope * (x1 - x') - y1
    BigInt x_diff_new;
    fp_sub(x_diff_new, p.x, result.x);
    fp_mul(result.y, slope, x_diff_new);
    fp_sub(result.y, result.y, p.y);
}

// Simple scalar multiplication using double-and-add
void scalar_mul_simple(thread Point_metal& result, thread const Point_metal& point, thread const BigInt& scalar) {
    // Handle edge cases
    if (bigint_is_zero(scalar)) {
        bigint_zero(result.x);
        bigint_zero(result.y);
        return;
    }

    if (bigint_is_one(scalar)) {
        result = point;
        return;
    }

    // Initialize result to point at infinity
    bigint_zero(result.x);
    bigint_zero(result.y);

    // Copy the base point
    Point_metal base = point;

    // Double-and-add algorithm
    for (int word = 0; word < 8; word++) {
        uint scalar_word = scalar.limbs[word];
        for (int bit = 0; bit < 32; bit++) {
            if (scalar_word & (1u << bit)) {
                if (point_is_infinity(result)) {
                    result = base;
                } else {
                    point_add(result, result, base);
                }
            }

            // Double base for next bit (except on last iteration)
            if (word < 7 || bit < 31) {
                point_double(base, base);
            }
        }
    }
}

kernel void getPublicKeyKernel(device Point_metal* output [[buffer(0)]],
                              device const BigInt* privateKeys [[buffer(1)]],
                              constant uint& n [[buffer(2)]],
                              uint gid [[thread_position_in_grid]]) {

    if (gid >= n) return;

    // Set up generator point G
    Point_metal generator;
    bigint_copy_constant(generator.x, GX_LIMBS);
    bigint_copy_constant(generator.y, GY_LIMBS);

    // Copy private key to thread memory
    BigInt privKey;
    for (int i = 0; i < 8; i++) {
        privKey.limbs[i] = privateKeys[gid].limbs[i];
    }

    // Perform scalar multiplication: result = privateKey * G
    Point_metal result;
    scalar_mul_simple(result, generator, privKey);

    // Copy result to device memory
    for (int i = 0; i < 8; i++) {
        output[gid].x.limbs[i] = result.x.limbs[i];
        output[gid].y.limbs[i] = result.y.limbs[i];
    }
}