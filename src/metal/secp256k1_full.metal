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

// Projective point representation (X, Y, Z) where affine point is (X/Z, Y/Z)
struct ProjectivePoint {
    BigInt x;
    BigInt y;
    BigInt z;
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

bool bigint_is_zero_device(device const BigInt& a) {
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

// Modular reduction for secp256k1
void fp_reduce(thread BigInt& a) {
    BigInt p;
    bigint_copy_constant(p, P_LIMBS);

    // Simple repeated subtraction (not optimal but correct)
    int max_iterations = 10;
    while (max_iterations-- > 0 && bigint_gte(a, p)) {
        bigint_sub(a, a, p);
    }
}

// Field addition modulo P
void fp_add(thread BigInt& result, thread const BigInt& a, thread const BigInt& b) {
    uint carry = bigint_add(result, a, b);
    if (carry) {
        // If overflow, subtract P
        BigInt p;
        bigint_copy_constant(p, P_LIMBS);
        bigint_sub(result, result, p);
    } else {
        fp_reduce(result);
    }
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

// Simple field multiplication using repeated addition (slow but correct)
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

    // Use double-and-add algorithm
    BigInt temp_a = a;

    for (int word = 0; word < 8; word++) {
        uint b_word = b.limbs[word];
        if (b_word == 0) {
            // Skip zero words, but still need to double temp_a
            for (int bit = 0; bit < 32; bit++) {
                if (word < 7 || bit < 31) {
                    fp_add(temp_a, temp_a, temp_a);
                }
            }
            continue;
        }

        for (int bit = 0; bit < 32; bit++) {
            if (b_word & (1u << bit)) {
                fp_add(result, result, temp_a);
            }
            if (word < 7 || bit < 31) {
                fp_add(temp_a, temp_a, temp_a);
            }
        }
    }
}

// Field squaring
void fp_sqr(thread BigInt& result, thread const BigInt& a) {
    fp_mul(result, a, a);
}

// Extended Euclidean algorithm for modular inverse
void fp_inv(thread BigInt& result, thread const BigInt& a) {
    if (bigint_is_zero(a)) {
        bigint_zero(result);
        return;
    }

    if (bigint_is_one(a)) {
        bigint_one(result);
        return;
    }

    // Use Fermat's little theorem: a^(p-2) mod p for prime p
    // For secp256k1, p-2 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D

    BigInt base = a;
    bigint_one(result);

    // Hardcode p-2 for secp256k1 in little-endian 32-bit limbs
    uint exp_limbs[8] = {0xFFFFFC2D, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF,
                         0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};

    // Binary exponentiation
    for (int word = 0; word < 8; word++) {
        uint exp_word = exp_limbs[word];
        for (int bit = 0; bit < 32; bit++) {
            if (exp_word & (1u << bit)) {
                fp_mul(result, result, base);
            }
            // Don't square on the very last bit
            if (word < 7 || bit < 31) {
                fp_sqr(base, base);
            }
        }
    }
}

// Check if projective point is at infinity
bool proj_is_infinity(thread const ProjectivePoint& p) {
    return bigint_is_zero(p.z);
}

// Set projective point to infinity
void proj_set_infinity(thread ProjectivePoint& p) {
    bigint_one(p.x);
    bigint_one(p.y);
    bigint_zero(p.z);
}

// Convert affine point to projective coordinates
void affine_to_proj(thread ProjectivePoint& proj, thread const Point_metal& aff) {
    bigint_copy(proj.x, aff.x);
    bigint_copy(proj.y, aff.y);
    bigint_one(proj.z);
}

// Convert projective point to affine coordinates
void proj_to_affine(thread Point_metal& aff, thread const ProjectivePoint& proj) {
    if (proj_is_infinity(proj)) {
        bigint_zero(aff.x);
        bigint_zero(aff.y);
        return;
    }

    BigInt z_inv;
    fp_inv(z_inv, proj.z);
    fp_mul(aff.x, proj.x, z_inv);
    fp_mul(aff.y, proj.y, z_inv);
}

// Projective point doubling using optimized formulas
void proj_double(thread ProjectivePoint& result, thread const ProjectivePoint& p) {
    if (proj_is_infinity(p)) {
        proj_set_infinity(result);
        return;
    }

    // For secp256k1: y^2 = x^3 + 7
    // Using doubling formulas for Weierstrass curves in projective coordinates

    BigInt a, b, c, d, e, f;

    // A = X1^2
    fp_sqr(a, p.x);

    // B = Y1^2
    fp_sqr(b, p.y);

    // C = B^2
    fp_sqr(c, b);

    // D = 2*((X1+B)^2-A-C)
    BigInt temp;
    fp_add(temp, p.x, b);
    fp_sqr(temp, temp);
    fp_sub(temp, temp, a);
    fp_sub(temp, temp, c);
    fp_add(d, temp, temp);

    // E = 3*A (for secp256k1, curve parameter a=0, so this is just 3*A)
    fp_add(temp, a, a);
    fp_add(e, temp, a);

    // F = E^2
    fp_sqr(f, e);

    // X3 = F - 2*D
    fp_add(temp, d, d);
    fp_sub(result.x, f, temp);

    // Y3 = E*(D-X3) - 8*C
    fp_sub(temp, d, result.x);
    fp_mul(result.y, e, temp);
    BigInt eight_c;
    fp_add(eight_c, c, c);
    fp_add(eight_c, eight_c, eight_c);
    fp_add(eight_c, eight_c, eight_c);
    fp_sub(result.y, result.y, eight_c);

    // Z3 = 2*Y1*Z1
    fp_mul(temp, p.y, p.z);
    fp_add(result.z, temp, temp);
}

// Projective point addition using optimized formulas
void proj_add(thread ProjectivePoint& result, thread const ProjectivePoint& p, thread const ProjectivePoint& q) {
    if (proj_is_infinity(p)) {
        result = q;
        return;
    }
    if (proj_is_infinity(q)) {
        result = p;
        return;
    }

    // Check if points are equal (for doubling case)
    if (bigint_eq(p.x, q.x) && bigint_eq(p.y, q.y) && bigint_eq(p.z, q.z)) {
        proj_double(result, p);
        return;
    }

    // Standard addition formulas for projective coordinates
    BigInt u1, u2, s1, s2, h, r;

    // U1 = X1*Z2
    fp_mul(u1, p.x, q.z);

    // U2 = X2*Z1
    fp_mul(u2, q.x, p.z);

    // S1 = Y1*Z2
    fp_mul(s1, p.y, q.z);

    // S2 = Y2*Z1
    fp_mul(s2, q.y, p.z);

    // Check if points are equal
    if (bigint_eq(u1, u2)) {
        if (bigint_eq(s1, s2)) {
            // Point doubling case
            proj_double(result, p);
        } else {
            // Points are inverses, result is infinity
            proj_set_infinity(result);
        }
        return;
    }

    // H = U2-U1
    fp_sub(h, u2, u1);

    // r = S2-S1
    fp_sub(r, s2, s1);

    // X3 = r^2 - H^3 - 2*U1*H^2
    BigInt h_sqr, h_cube, u1_h_sqr;
    fp_sqr(h_sqr, h);
    fp_mul(h_cube, h_sqr, h);
    fp_mul(u1_h_sqr, u1, h_sqr);

    fp_sqr(result.x, r);
    fp_sub(result.x, result.x, h_cube);
    BigInt temp;
    fp_add(temp, u1_h_sqr, u1_h_sqr);
    fp_sub(result.x, result.x, temp);

    // Y3 = r*(U1*H^2 - X3) - S1*H^3
    fp_sub(temp, u1_h_sqr, result.x);
    fp_mul(result.y, r, temp);
    fp_mul(temp, s1, h_cube);
    fp_sub(result.y, result.y, temp);

    // Z3 = Z1*Z2*H
    fp_mul(temp, p.z, q.z);
    fp_mul(result.z, temp, h);
}

// Scalar multiplication using binary method with projective coordinates
void scalar_mul_binary(thread Point_metal& result, thread const Point_metal& point, thread const BigInt& scalar) {
    // Handle edge cases
    if (bigint_is_zero(scalar)) {
        bigint_zero(result.x);
        bigint_zero(result.y);
        return;
    }

    // Convert to projective coordinates
    ProjectivePoint base_proj, acc_proj;
    affine_to_proj(base_proj, point);
    proj_set_infinity(acc_proj);

    // Double-and-add algorithm
    for (int word = 0; word < 8; word++) {
        uint scalar_word = scalar.limbs[word];
        for (int bit = 0; bit < 32; bit++) {
            if (scalar_word & (1u << bit)) {
                if (proj_is_infinity(acc_proj)) {
                    acc_proj = base_proj;
                } else {
                    proj_add(acc_proj, acc_proj, base_proj);
                }
            }

            // Double for next bit (except on last iteration)
            if (word < 7 || bit < 31) {
                proj_double(base_proj, base_proj);
            }
        }
    }

    // Convert back to affine coordinates
    proj_to_affine(result, acc_proj);
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
    scalar_mul_binary(result, generator, privKey);

    // Copy result to device memory
    for (int i = 0; i < 8; i++) {
        output[gid].x.limbs[i] = result.x.limbs[i];
        output[gid].y.limbs[i] = result.y.limbs[i];
    }
}