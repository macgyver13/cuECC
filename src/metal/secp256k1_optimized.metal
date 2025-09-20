#include <metal_stdlib>
using namespace metal;

// secp256k1 curve parameters (little-endian 32-bit limbs)
// P = 2^256 - 2^32 - 2^9 - 2^8 - 2^7 - 2^6 - 2^4 - 1
constant uint P_LIMBS[8] = {0xfffffc2f, 0xfffffffe, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff};

// Generator point G (little-endian 32-bit limbs)
constant uint GX_LIMBS[8] = {0x16f81798, 0x59f2815b, 0x2dce28d9, 0x029bfcdb, 0xce870b07, 0x55a06295, 0xf9dcbbac, 0x79be667e};
constant uint GY_LIMBS[8] = {0xfb10d4b8, 0x9c47d08f, 0xa6855419, 0xfd17b448, 0x0e1108a8, 0x5da4fbfc, 0x26a3c465, 0x483ada77};

// 256-bit big integer using 8 x 32-bit limbs for better GPU performance
struct BigInt {
    uint limbs[8];
};

// Jacobian point representation (X, Y, Z) where affine point is (X/Z^2, Y/Z^3)
struct JacobianPoint {
    BigInt x;
    BigInt y;
    BigInt z;
};

// Affine point for input/output
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

// Compare two BigInts: returns 1 if a >= b, 0 otherwise
bool bigint_gte(thread const BigInt& a, thread const BigInt& b) {
    for (int i = 7; i >= 0; i--) {
        if (a.limbs[i] > b.limbs[i]) return true;
        if (a.limbs[i] < b.limbs[i]) return false;
    }
    return true; // Equal case
}

// Check if two BigInts are equal
bool bigint_eq(thread const BigInt& a, thread const BigInt& b) {
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != b.limbs[i]) return false;
    }
    return true;
}

// Compare two BigInts: returns 1 if a < b, 0 otherwise
bool bigint_lt(thread const BigInt& a, thread const BigInt& b) {
    for (int i = 7; i >= 0; i--) {
        if (a.limbs[i] < b.limbs[i]) return true;
        if (a.limbs[i] > b.limbs[i]) return false;
    }
    return false; // Equal case
}

// Test if a specific bit is set (bit_index from 0-255)
bool bigint_test_bit(thread const BigInt& a, uint bit_index) {
    if (bit_index >= 256) return false;
    uint limb_index = bit_index / 32;
    uint bit_in_limb = bit_index % 32;
    return (a.limbs[limb_index] & (1u << bit_in_limb)) != 0;
}

// Left shift by n bits (n must be < 32 for this implementation)
void bigint_shl(thread BigInt& result, thread const BigInt& a, uint n) {
    if (n == 0) {
        bigint_copy(result, a);
        return;
    }
    if (n >= 32) {
        bigint_zero(result);
        return;
    }

    uint carry = 0;
    for (int i = 0; i < 8; i++) {
        uint new_carry = a.limbs[i] >> (32 - n);
        result.limbs[i] = (a.limbs[i] << n) | carry;
        carry = new_carry;
    }
}

// Right shift by n bits (n must be < 32 for this implementation)
void bigint_shr(thread BigInt& result, thread const BigInt& a, uint n) {
    if (n == 0) {
        bigint_copy(result, a);
        return;
    }
    if (n >= 32) {
        bigint_zero(result);
        return;
    }

    uint carry = 0;
    for (int i = 7; i >= 0; i--) {
        uint new_carry = a.limbs[i] << (32 - n);
        result.limbs[i] = (a.limbs[i] >> n) | carry;
        carry = new_carry;
    }
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

// Fast modular reduction for secp256k1
void fp_reduce(thread BigInt& a) {
    BigInt p;
    bigint_copy_constant(p, P_LIMBS);

    while (bigint_gte(a, p)) {
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

// Robust field multiplication using traditional schoolbook method
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

    // Check for small operands first
    bool a_is_small = true, b_is_small = true;
    for (int i = 1; i < 8; i++) {
        if (a.limbs[i] != 0) a_is_small = false;
        if (b.limbs[i] != 0) b_is_small = false;
    }

    // If one operand is small, use repeated addition
    if (a_is_small && a.limbs[0] <= 100) {
        BigInt temp = b;
        for (uint i = 0; i < a.limbs[0]; i++) {
            fp_add(result, result, temp);
        }
        return;
    }

    if (b_is_small && b.limbs[0] <= 100) {
        BigInt temp = a;
        for (uint i = 0; i < b.limbs[0]; i++) {
            fp_add(result, result, temp);
        }
        return;
    }

    // For larger operands, use binary multiplication
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

// Field squaring (optimized multiplication by self)
void fp_sqr(thread BigInt& result, thread const BigInt& a) {
    fp_mul(result, a, a);
}

// Simplified modular inverse using Fermat's little theorem: a^(p-2) mod p
void fp_inv(thread BigInt& result, thread const BigInt& a) {
    // Handle simple case
    if (bigint_is_one(a)) {
        bigint_one(result);
        return;
    }

    // For secp256k1, p-2 = FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
    // Use binary exponentiation with a simplified approach

    BigInt base = a;
    bigint_one(result);

    // Hardcode p-2 for secp256k1 in little-endian 32-bit limbs
    // p-2 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2D
    uint exp_limbs[8] = {0xFFFFFC2D, 0xFFFFFFFE, 0xFFFFFFFF, 0xFFFFFFFF,
                         0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF};

    // Binary exponentiation - process each bit
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

// Check if Jacobian point is at infinity
bool jacobian_is_infinity(thread const JacobianPoint& p) {
    return bigint_is_zero(p.z);
}

// Set Jacobian point to infinity
void jacobian_set_infinity(thread JacobianPoint& p) {
    bigint_one(p.x);
    bigint_one(p.y);
    bigint_zero(p.z);
}

// Convert affine point to Jacobian coordinates
void affine_to_jacobian(thread JacobianPoint& jac, thread const Point_metal& aff) {
    bigint_copy(jac.x, aff.x);
    bigint_copy(jac.y, aff.y);
    bigint_one(jac.z);
}

// Convert Jacobian point to affine coordinates
void jacobian_to_affine(thread Point_metal& aff, thread const JacobianPoint& jac) {
    if (jacobian_is_infinity(jac)) {
        bigint_zero(aff.x);
        bigint_zero(aff.y);
        return;
    }

    BigInt z_inv, z_inv_sqr, z_inv_cube;
    fp_inv(z_inv, jac.z);
    fp_sqr(z_inv_sqr, z_inv);
    fp_mul(z_inv_cube, z_inv_sqr, z_inv);

    fp_mul(aff.x, jac.x, z_inv_sqr);
    fp_mul(aff.y, jac.y, z_inv_cube);
}

void jacobian_to_affine_device(device Point_metal& aff, thread const JacobianPoint& jac) {
    if (jacobian_is_infinity(jac)) {
        // Set to zero by writing directly to device memory
        for (int i = 0; i < 8; i++) {
            aff.x.limbs[i] = 0;
            aff.y.limbs[i] = 0;
        }
        return;
    }

    BigInt z_inv, z_inv_sqr, z_inv_cube, temp_x, temp_y;
    fp_inv(z_inv, jac.z);
    fp_sqr(z_inv_sqr, z_inv);
    fp_mul(z_inv_cube, z_inv_sqr, z_inv);

    fp_mul(temp_x, jac.x, z_inv_sqr);
    fp_mul(temp_y, jac.y, z_inv_cube);

    // Copy to device memory
    for (int i = 0; i < 8; i++) {
        aff.x.limbs[i] = temp_x.limbs[i];
        aff.y.limbs[i] = temp_y.limbs[i];
    }
}

// Jacobian point doubling (dbl-2009-l algorithm)
void jacobian_double(thread JacobianPoint& result, thread const JacobianPoint& p) {
    if (jacobian_is_infinity(p)) {
        jacobian_set_infinity(result);
        return;
    }

    BigInt a, b, c, d, e, f;

    // A = X1^2
    fp_sqr(a, p.x);

    // B = Y1^2
    fp_sqr(b, p.y);

    // C = B^2
    fp_sqr(c, b);

    // D = 2*((X1+B)^2-A-C)
    BigInt temp1, temp2;
    fp_add(temp1, p.x, b);
    fp_sqr(temp1, temp1);
    fp_sub(temp1, temp1, a);
    fp_sub(temp1, temp1, c);
    fp_add(d, temp1, temp1);

    // E = 3*A
    fp_add(temp1, a, a);
    fp_add(e, temp1, a);

    // F = E^2
    fp_sqr(f, e);

    // X3 = F - 2*D
    fp_add(temp1, d, d);
    fp_sub(result.x, f, temp1);

    // Y3 = E*(D-X3) - 8*C
    fp_sub(temp1, d, result.x);
    fp_mul(temp1, e, temp1);
    fp_add(temp2, c, c);
    fp_add(temp2, temp2, temp2);
    fp_add(temp2, temp2, temp2);
    fp_sub(result.y, temp1, temp2);

    // Z3 = 2*Y1*Z1
    fp_mul(temp1, p.y, p.z);
    fp_add(result.z, temp1, temp1);
}

// Jacobian point addition (add-2007-bl algorithm)
void jacobian_add(thread JacobianPoint& result, thread const JacobianPoint& p, thread const JacobianPoint& q) {
    if (jacobian_is_infinity(p)) {
        result = q;
        return;
    }
    if (jacobian_is_infinity(q)) {
        result = p;
        return;
    }

    BigInt z1z1, z2z2, u1, u2, s1, s2, h, i, j, r, v;

    // Z1Z1 = Z1^2
    fp_sqr(z1z1, p.z);

    // Z2Z2 = Z2^2
    fp_sqr(z2z2, q.z);

    // U1 = X1*Z2Z2
    fp_mul(u1, p.x, z2z2);

    // U2 = X2*Z1Z1
    fp_mul(u2, q.x, z1z1);

    // S1 = Y1*Z2*Z2Z2
    fp_mul(s1, p.y, q.z);
    fp_mul(s1, s1, z2z2);

    // S2 = Y2*Z1*Z1Z1
    fp_mul(s2, q.y, p.z);
    fp_mul(s2, s2, z1z1);

    // Check if points are equal
    bool u_equal = true, s_equal = true;
    for (int i = 0; i < 8; i++) {
        if (u1.limbs[i] != u2.limbs[i]) u_equal = false;
        if (s1.limbs[i] != s2.limbs[i]) s_equal = false;
    }

    if (u_equal) {
        if (s_equal) {
            // Point doubling case
            jacobian_double(result, p);
        } else {
            // Points are inverses, result is infinity
            jacobian_set_infinity(result);
        }
        return;
    }

    // H = U2-U1
    fp_sub(h, u2, u1);

    // I = (2*H)^2
    fp_add(i, h, h);
    fp_sqr(i, i);

    // J = H*I
    fp_mul(j, h, i);

    // r = 2*(S2-S1)
    fp_sub(r, s2, s1);
    fp_add(r, r, r);

    // V = U1*I
    fp_mul(v, u1, i);

    // X3 = r^2 - J - 2*V
    fp_sqr(result.x, r);
    fp_sub(result.x, result.x, j);
    BigInt temp;
    fp_add(temp, v, v);
    fp_sub(result.x, result.x, temp);

    // Y3 = r*(V-X3) - 2*S1*J
    fp_sub(temp, v, result.x);
    fp_mul(result.y, r, temp);
    fp_mul(temp, s1, j);
    fp_add(temp, temp, temp);
    fp_sub(result.y, result.y, temp);

    // Z3 = ((Z1+Z2)^2 - Z1Z1 - Z2Z2)*H
    fp_add(temp, p.z, q.z);
    fp_sqr(temp, temp);
    fp_sub(temp, temp, z1z1);
    fp_sub(temp, temp, z2z2);
    fp_mul(result.z, temp, h);
}

// Scalar multiplication using double-and-add with Jacobian coordinates
void jacobian_scalar_mul(thread JacobianPoint& result, thread const JacobianPoint& point, device const BigInt& scalar) {
    jacobian_set_infinity(result);

    if (bigint_is_zero_device(scalar) || jacobian_is_infinity(point)) {
        return;
    }

    JacobianPoint addend = point;

    // Process scalar bits from LSB to MSB
    for (int i = 0; i < 256; i++) {
        int word_idx = i / 32;
        int bit_idx = i % 32;

        if (scalar.limbs[word_idx] & (1u << bit_idx)) {
            if (jacobian_is_infinity(result)) {
                result = addend;
            } else {
                jacobian_add(result, result, addend);
            }
        }

        if (i < 255) {
            jacobian_double(addend, addend);
        }
    }
}

kernel void getPublicKeyKernel(device Point_metal* output [[buffer(0)]],
                              device const BigInt* privateKeys [[buffer(1)]],
                              constant uint& n [[buffer(2)]],
                              uint gid [[thread_position_in_grid]]) {

    if (gid >= n) return;

    // Set up generator point G in Jacobian coordinates
    JacobianPoint generator;
    bigint_copy_constant(generator.x, GX_LIMBS);
    bigint_copy_constant(generator.y, GY_LIMBS);
    bigint_one(generator.z);

    // Perform scalar multiplication: result = privateKey * G
    JacobianPoint jacResult;
    jacobian_scalar_mul(jacResult, generator, privateKeys[gid]);

    // Convert result back to affine coordinates
    jacobian_to_affine_device(output[gid], jacResult);
}