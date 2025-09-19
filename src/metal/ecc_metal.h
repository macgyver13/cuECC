#ifndef ECC_METAL_H
#define ECC_METAL_H

#ifdef __cplusplus
extern "C" {
#endif

// Forward declare types to avoid conflicts with macOS Point type
typedef unsigned long long u64;

typedef struct {
    u64 x[4];
    u64 y[4];
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
void getPublicKeyByPrivateKeyMetal(ECCPoint output[], u64 flattenedPrivateKeys[][4], int n);

// Error handling
const char* getMetalErrorString(int error);

#ifdef __cplusplus
}
#endif

#endif // ECC_METAL_H