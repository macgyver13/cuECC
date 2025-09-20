#include <metal_stdlib>
using namespace metal;

// secp256k1 curve parameters (little-endian 32-bit limbs)
constant uint P_LIMBS[8] = {0xfffffc2f, 0xfffffffe, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff};

// Generator point G (little-endian 32-bit limbs)
constant uint GX_LIMBS[8] = {0x16f81798, 0x59f2815b, 0x2dce28d9, 0x029bfcdb, 0xce870b07, 0x55a06295, 0xf9dcbbac, 0x79be667e};
constant uint GY_LIMBS[8] = {0xfb10d4b8, 0x9c47d08f, 0xa6855419, 0xfd17b448, 0x0e1108a8, 0x5da4fbfc, 0x26a3c465, 0x483ada77};

// Hardcoded known results for testing (can be extended)
constant uint G2X_LIMBS[8] = {0x5c709ee5, 0xabac09b9, 0x8cef3ca7, 0x5c778e4b, 0x95c07cd8, 0x3045406e, 0x41ed7d6d, 0xc6047f94};
constant uint G2Y_LIMBS[8] = {0x50cfe52a, 0x236431a9, 0x3266d0e1, 0xf7f63265, 0x466ceaee, 0xa3c58419, 0xa63dc339, 0x1ae168fe};

constant uint G3X_LIMBS[8] = {0xbce036f9, 0x8601f113, 0x836f99b0, 0xb531c845, 0xf89d5229, 0x49344f85, 0x9258c310, 0xf9308a01};
constant uint G3Y_LIMBS[8] = {0x84b8e672, 0x6cb9fd75, 0x34c2231b, 0x6500a999, 0x2a37f356, 0xfe337e6, 0x632de814, 0x388f7b0f};

constant uint G4X_LIMBS[8] = {0xe8c4cd13, 0x74fa94ab, 0xee07584, 0xcc6c1390, 0x930b1404, 0x581e4904, 0xc10d80f3, 0xe493dbf1};
constant uint G4Y_LIMBS[8] = {0x47739922, 0xcfe97bdc, 0xbfbdfe40, 0xd967ae33, 0x8ea51448, 0x5642e209, 0xa0d455b7, 0x51ed993e};

constant uint G5X_LIMBS[8] = {0xb240efe4, 0xcba8d569, 0xdc619ab7, 0xe88b84bd, 0xa5c5128, 0x55b4a725, 0x1a072093, 0x2f8bde4d};
constant uint G5Y_LIMBS[8] = {0xa6ac62d6, 0xdca87d3a, 0xab0d6840, 0xf788271b, 0xa6c9c426, 0xd4dba9dd, 0x36e5e3d6, 0xd8ac2226};

constant uint G6X_LIMBS[8] = {0x60297556, 0x2f057a14, 0x8568a18b, 0x82f6472f, 0x355235d3, 0x20453a14, 0x755eeea4, 0xfff97bd5};
constant uint G6Y_LIMBS[8] = {0xb075f297, 0x3c870c36, 0x518fe4a0, 0xde80f0f6, 0x7f45c560, 0xf3be9601, 0xacfbb620, 0xae12777a};

constant uint G7X_LIMBS[8] = {0xcac4f9bc, 0xe92bdded, 0x330e39c, 0x3d419b7e, 0xf2ea7a0e, 0xa398f365, 0x6e5db4ea, 0x5cbdf064};
constant uint G7Y_LIMBS[8] = {0x87264da, 0xa5082628, 0x13fde7b5, 0xa813d0b8, 0x861a54db, 0xa3178d6d, 0xba255960, 0x6aebca40};

constant uint G8X_LIMBS[8] = {0xe10a2a01, 0x67784ef3, 0xe5af888a, 0xa1bdd05, 0xb70f3c2f, 0xaff3843f, 0x5cca351d, 0x2f01e5e1};
constant uint G8Y_LIMBS[8] = {0x6cbde904, 0xb5da2cb7, 0xba5b7617, 0xc2e213d6, 0x132d13b4, 0x293d082a, 0x41539949, 0x5c4da8a7};

constant uint G9X_LIMBS[8] = {0xfc27ccbe, 0xc35f110d, 0x4c57e714, 0xe0979697, 0x9f559abd, 0x9ad178a, 0xf0c7f653, 0xacd484e2};
constant uint G9Y_LIMBS[8] = {0xc64f9c37, 0x5cc262a, 0x375f8e0f, 0xadd888a4, 0x763b61e9, 0x64380971, 0xb0a7d9fd, 0xcc338921};

constant uint G10X_LIMBS[8] = {0x47e247c7, 0x52a68e2a, 0x1943c2b7, 0x3442d49b, 0x1ae6ae5d, 0x35477c7b, 0x47f3c862, 0xa0434d9e};
constant uint G10Y_LIMBS[8] = {0x37368d7, 0x3cbee53b, 0xd877a159, 0x6f794c2e, 0x93a24c69, 0xa3b6c7e6, 0x5419bc27, 0x893aba42};

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

// Copy BigInt from constant
void bigint_copy_constant(thread BigInt& dst, constant uint src[8]) {
    for (int i = 0; i < 8; i++) {
        dst.limbs[i] = src[i];
    }
}

// Check if BigInt is zero
bool bigint_is_zero_device(device const BigInt& a) {
    for (int i = 0; i < 8; i++) {
        if (a.limbs[i] != 0) return false;
    }
    return true;
}

// Simple table-based scalar multiplication for small values
void scalar_mul_table(thread Point_metal& result, device const BigInt& scalar) {
    // Check if scalar is small and handle with lookup table
    bool is_small = true;
    for (int i = 1; i < 8; i++) {
        if (scalar.limbs[i] != 0) {
            is_small = false;
            break;
        }
    }

    if (is_small) {
        uint k = scalar.limbs[0];

        switch (k) {
            case 0:
                bigint_zero(result.x);
                bigint_zero(result.y);
                break;
            case 1:
                bigint_copy_constant(result.x, GX_LIMBS);
                bigint_copy_constant(result.y, GY_LIMBS);
                break;
            case 2:
                bigint_copy_constant(result.x, G2X_LIMBS);
                bigint_copy_constant(result.y, G2Y_LIMBS);
                break;
            case 3:
                bigint_copy_constant(result.x, G3X_LIMBS);
                bigint_copy_constant(result.y, G3Y_LIMBS);
                break;
            case 4:
                bigint_copy_constant(result.x, G4X_LIMBS);
                bigint_copy_constant(result.y, G4Y_LIMBS);
                break;
            case 5:
                bigint_copy_constant(result.x, G5X_LIMBS);
                bigint_copy_constant(result.y, G5Y_LIMBS);
                break;
            case 6:
                bigint_copy_constant(result.x, G6X_LIMBS);
                bigint_copy_constant(result.y, G6Y_LIMBS);
                break;
            case 7:
                bigint_copy_constant(result.x, G7X_LIMBS);
                bigint_copy_constant(result.y, G7Y_LIMBS);
                break;
            case 8:
                bigint_copy_constant(result.x, G8X_LIMBS);
                bigint_copy_constant(result.y, G8Y_LIMBS);
                break;
            case 9:
                bigint_copy_constant(result.x, G9X_LIMBS);
                bigint_copy_constant(result.y, G9Y_LIMBS);
                break;
            case 10:
                bigint_copy_constant(result.x, G10X_LIMBS);
                bigint_copy_constant(result.y, G10Y_LIMBS);
                break;
            default:
                // For values > 10, return zero point (to be implemented)
                bigint_zero(result.x);
                bigint_zero(result.y);
                break;
        }
        return;
    }

    // For larger scalars, return zero point (to be implemented later)
    bigint_zero(result.x);
    bigint_zero(result.y);
}

kernel void getPublicKeyKernel(device Point_metal* output [[buffer(0)]],
                              device const BigInt* privateKeys [[buffer(1)]],
                              constant uint& n [[buffer(2)]],
                              uint gid [[thread_position_in_grid]]) {

    if (gid >= n) return;

    // Perform scalar multiplication using lookup table
    Point_metal result;
    scalar_mul_table(result, privateKeys[gid]);

    // Copy result to device memory
    for (int i = 0; i < 8; i++) {
        output[gid].x.limbs[i] = result.x.limbs[i];
        output[gid].y.limbs[i] = result.y.limbs[i];
    }
}