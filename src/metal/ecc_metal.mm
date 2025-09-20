#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

#include "ecc_metal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// Type aliases for compatibility
typedef uint32_t u32;
typedef uint64_t u64;

static MetalContext g_ctx = {0};
static int g_initialized = 0;

const char* getMetalErrorString(int error) {
    switch(error) {
        case 0: return "Success";
        case -1: return "Device not found";
        case -2: return "Library creation failed";
        case -3: return "Function not found";
        case -4: return "Pipeline creation failed";
        case -5: return "Buffer creation failed";
        case -6: return "Command buffer creation failed";
        case -7: return "Compute encoder creation failed";
        default: return "Unknown error";
    }
}

int initMetal(MetalContext* ctx) {
    @autoreleasepool {
        // Get the default Metal device
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            printf("Error: Metal is not supported on this device\n");
            return -1;
        }

        printf("Using Metal device: %s\n", [[device name] UTF8String]);

        // Create command queue
        id<MTLCommandQueue> commandQueue = [device newCommandQueue];
        if (!commandQueue) {
            printf("Error: Failed to create Metal command queue\n");
            return -1;
        }

        // Load the Metal shader library
        NSError* error = nil;

        // Use the corrected scalar multiplication shader file
        NSArray* possiblePaths = @[
            @"src/metal/secp256k1_correct.metal",
            @"../src/metal/secp256k1_correct.metal",
            [NSString stringWithFormat:@"%s/src/metal/secp256k1_correct.metal", getenv("PWD") ?: "."]
        ];

        NSString* shaderSource = nil;
        for (NSString* shaderPath in possiblePaths) {
            shaderSource = [NSString stringWithContentsOfFile:shaderPath
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];
            if (shaderSource && !error) {
                printf("Loaded Metal shader from: %s\n", [shaderPath UTF8String]);
                break;
            }
        }

        if (error || !shaderSource) {
            printf("Error: Could not load Metal shader file from any of the attempted paths\n");
            printf("Attempted paths:\n");
            for (NSString* path in possiblePaths) {
                printf("  %s\n", [path UTF8String]);
            }
            return -2;
        }

        id<MTLLibrary> library = [device newLibraryWithSource:shaderSource
                                                      options:nil
                                                        error:&error];
        if (error || !library) {
            printf("Error: Failed to create Metal library: %s\n",
                   error ? [[error localizedDescription] UTF8String] : "Unknown error");
            return -2;
        }

        // Get the kernel function
        id<MTLFunction> kernelFunction = [library newFunctionWithName:@"getPublicKeyKernel"];
        if (!kernelFunction) {
            printf("Error: Failed to find Metal kernel function\n");
            return -3;
        }

        // Create compute pipeline state
        id<MTLComputePipelineState> computePipeline = [device newComputePipelineStateWithFunction:kernelFunction
                                                                                            error:&error];
        if (error || !computePipeline) {
            printf("Error: Failed to create Metal compute pipeline: %s\n",
                   error ? [[error localizedDescription] UTF8String] : "Unknown error");
            return -4;
        }

        // Store references (bridged to void* for C compatibility)
        ctx->device = (__bridge_retained void*)device;
        ctx->command_queue = (__bridge_retained void*)commandQueue;
        ctx->library = (__bridge_retained void*)library;
        ctx->compute_pipeline = (__bridge_retained void*)computePipeline;

        return 0;
    }
}

void cleanupMetal(MetalContext* ctx) {
    @autoreleasepool {
        if (ctx->compute_pipeline) {
            CFRelease(ctx->compute_pipeline);
        }
        if (ctx->library) {
            CFRelease(ctx->library);
        }
        if (ctx->command_queue) {
            CFRelease(ctx->command_queue);
        }
        if (ctx->device) {
            CFRelease(ctx->device);
        }
        memset(ctx, 0, sizeof(MetalContext));
    }
}

void getPublicKeyByPrivateKeyMetal(ECCPoint output[], BigInt flattenedPrivateKeys[], int n) {
    @autoreleasepool {
        // Initialize Metal if not already done
        if (!g_initialized) {
            if (initMetal(&g_ctx) != 0) {
                printf("Error: Failed to initialize Metal\n");
                return;
            }
            g_initialized = 1;
        }

        id<MTLDevice> device = (__bridge id<MTLDevice>)g_ctx.device;
        id<MTLCommandQueue> commandQueue = (__bridge id<MTLCommandQueue>)g_ctx.command_queue;
        id<MTLComputePipelineState> computePipeline = (__bridge id<MTLComputePipelineState>)g_ctx.compute_pipeline;

        // Create Metal buffers
        NSUInteger inputSize = sizeof(BigInt) * n;
        NSUInteger outputSize = sizeof(ECCPoint) * n;

        id<MTLBuffer> inputBuffer = [device newBufferWithBytes:flattenedPrivateKeys
                                                        length:inputSize
                                                       options:MTLResourceStorageModeShared];

        id<MTLBuffer> outputBuffer = [device newBufferWithLength:outputSize
                                                         options:MTLResourceStorageModeShared];

        id<MTLBuffer> nBuffer = [device newBufferWithBytes:&n
                                                    length:sizeof(uint32_t)
                                                   options:MTLResourceStorageModeShared];

        if (!inputBuffer || !outputBuffer || !nBuffer) {
            printf("Error: Failed to create Metal buffers\n");
            return;
        }

        // Create command buffer
        id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
        if (!commandBuffer) {
            printf("Error: Failed to create Metal command buffer\n");
            return;
        }

        // Create compute command encoder
        id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
        if (!encoder) {
            printf("Error: Failed to create Metal compute encoder\n");
            return;
        }

        // Set the pipeline state and buffers
        [encoder setComputePipelineState:computePipeline];
        [encoder setBuffer:outputBuffer offset:0 atIndex:0];
        [encoder setBuffer:inputBuffer offset:0 atIndex:1];
        [encoder setBuffer:nBuffer offset:0 atIndex:2];

        // Calculate thread group sizes
        NSUInteger threadGroupSize = computePipeline.maxTotalThreadsPerThreadgroup;
        if (threadGroupSize > 256) threadGroupSize = 256; // Conservative limit

        MTLSize threadsPerThreadgroup = MTLSizeMake(threadGroupSize, 1, 1);
        MTLSize threadsPerGrid = MTLSizeMake((n + threadGroupSize - 1) / threadGroupSize * threadGroupSize, 1, 1);

        // Dispatch the compute shader
        [encoder dispatchThreads:threadsPerGrid threadsPerThreadgroup:threadsPerThreadgroup];
        [encoder endEncoding];

        // Commit and wait for completion
        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];

        // Check for errors
        if (commandBuffer.error) {
            printf("Error: Metal compute command failed: %s\n",
                   [[commandBuffer.error localizedDescription] UTF8String]);
            return;
        }

        // Copy results back
        memcpy(output, [outputBuffer contents], outputSize);

        printf("Metal computation completed successfully for %d keys\n", n);
    }
}

// BigInt primitive operations for testing (Step 1)
// These are CPU implementations that call the same algorithms as the Metal shaders

// CPU implementations of BigInt operations that match the Metal algorithms
// These provide validation references and can be used for testing

u32 bigintAdd(BigInt* result, const BigInt* a, const BigInt* b) {
    u32 carry = 0;
    for (int i = 0; i < 8; i++) {
        u64 sum = (u64)a->limbs[i] + b->limbs[i] + carry;
        result->limbs[i] = (u32)sum;
        carry = (u32)(sum >> 32);
    }
    return carry;
}

u32 bigintSub(BigInt* result, const BigInt* a, const BigInt* b) {
    u32 borrow = 0;
    for (int i = 0; i < 8; i++) {
        u64 diff = (u64)a->limbs[i] - b->limbs[i] - borrow;
        result->limbs[i] = (u32)diff;
        borrow = (diff >> 32) & 1;
    }
    return borrow;
}

int bigintEq(const BigInt* a, const BigInt* b) {
    for (int i = 0; i < 8; i++) {
        if (a->limbs[i] != b->limbs[i]) return 0;
    }
    return 1;
}

int bigintLt(const BigInt* a, const BigInt* b) {
    for (int i = 7; i >= 0; i--) {
        if (a->limbs[i] < b->limbs[i]) return 1;
        if (a->limbs[i] > b->limbs[i]) return 0;
    }
    return 0; // Equal case
}

int bigintGte(const BigInt* a, const BigInt* b) {
    for (int i = 7; i >= 0; i--) {
        if (a->limbs[i] > b->limbs[i]) return 1;
        if (a->limbs[i] < b->limbs[i]) return 0;
    }
    return 1; // Equal case
}

int bigintTestBit(const BigInt* a, u32 bit_index) {
    if (bit_index >= 256) return 0;
    u32 limb_index = bit_index / 32;
    u32 bit_in_limb = bit_index % 32;
    return (a->limbs[limb_index] & (1u << bit_in_limb)) != 0;
}

void bigintShl(BigInt* result, const BigInt* a, u32 n) {
    if (n == 0) {
        memcpy(result, a, sizeof(BigInt));
        return;
    }
    if (n >= 32) {
        memset(result, 0, sizeof(BigInt));
        return;
    }

    u32 carry = 0;
    for (int i = 0; i < 8; i++) {
        u32 new_carry = a->limbs[i] >> (32 - n);
        result->limbs[i] = (a->limbs[i] << n) | carry;
        carry = new_carry;
    }
}

void bigintShr(BigInt* result, const BigInt* a, u32 n) {
    if (n == 0) {
        memcpy(result, a, sizeof(BigInt));
        return;
    }
    if (n >= 32) {
        memset(result, 0, sizeof(BigInt));
        return;
    }

    u32 carry = 0;
    for (int i = 7; i >= 0; i--) {
        u32 new_carry = a->limbs[i] << (32 - n);
        result->limbs[i] = (a->limbs[i] >> n) | carry;
        carry = new_carry;
    }
}