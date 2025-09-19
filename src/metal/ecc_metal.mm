#import <Metal/Metal.h>
#import <Foundation/Foundation.h>

#include "ecc_metal.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

        // Try multiple possible paths for the shader file
        NSArray* possiblePaths = @[
            @"src/metal/secp256k1_pubkey.metal",
            @"../src/metal/secp256k1_pubkey.metal",
            [NSString stringWithFormat:@"%s/src/metal/secp256k1_pubkey.metal", getenv("PWD") ?: "."]
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

void getPublicKeyByPrivateKeyMetal(ECCPoint output[], u64 flattenedPrivateKeys[][4], int n) {
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
        NSUInteger inputSize = sizeof(u64) * 4 * n;
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