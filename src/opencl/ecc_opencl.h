#ifndef ECC_OPENCL_H
#define ECC_OPENCL_H

#ifdef __cplusplus
extern "C" {
#endif

#include "types.h"

#ifdef __APPLE__
#include <OpenCL/opencl.h>
#else
#define CL_TARGET_OPENCL_VERSION 300
#include <CL/cl.h>
#endif

typedef struct {
    cl_context context;
    cl_command_queue queue;
    cl_program program;
    cl_kernel kernel;
    cl_device_id device;
} OpenCLContext;

// Initialize OpenCL context
int initOpenCL(OpenCLContext* ctx);

// Cleanup OpenCL resources
void cleanupOpenCL(OpenCLContext* ctx);

// Generate public keys from private keys using OpenCL
void getPublicKeyByPrivateKeyOpenCL(Point output[],
                                   u64 flattenedPrivateKeys[][4],
                                   int n);

#ifdef __cplusplus
}
#endif

#endif // ECC_OPENCL_H