#ifndef ECC_METAL_H
#define ECC_METAL_H

#ifdef __cplusplus
extern "C" {
#endif

// Forward declare types to avoid conflicts with macOS Point type
typedef unsigned int u32;

typedef struct {
    u32 limbs[8];
} BigInt;

typedef struct {
    BigInt x;
    BigInt y;
} ECCPoint;

typedef struct {
    void* device;
    void* command_queue;
    void* library;
    void* compute_pipeline;
} MetalContext;

// Initialize Metal context
int initMetal(MetalContext* ctx);

// Clean up Metal resources
void cleanupMetal(MetalContext* ctx);

// Main public key generation function
void getPublicKeyByPrivateKeyMetal(ECCPoint output[], BigInt flattenedPrivateKeys[], int n);

// BigInt primitive operations for testing (Step 1)
u32 bigintAdd(BigInt* result, const BigInt* a, const BigInt* b);
u32 bigintSub(BigInt* result, const BigInt* a, const BigInt* b);
int bigintEq(const BigInt* a, const BigInt* b);
int bigintLt(const BigInt* a, const BigInt* b);
int bigintGte(const BigInt* a, const BigInt* b);
int bigintTestBit(const BigInt* a, u32 bit_index);
void bigintShl(BigInt* result, const BigInt* a, u32 n);
void bigintShr(BigInt* result, const BigInt* a, u32 n);

// Error handling
const char* getMetalErrorString(int error);

#ifdef __cplusplus
}
#endif

#endif // ECC_METAL_H