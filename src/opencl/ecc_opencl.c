#include "ecc_opencl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef __APPLE__
#include <OpenCL/opencl.h>
#else
#include <CL/cl.h>
#endif

static OpenCLContext g_ctx = {0};
static int g_initialized = 0;

const char* getOpenCLErrorString(cl_int error) {
    switch(error) {
        case CL_SUCCESS: return "Success";
        case CL_DEVICE_NOT_FOUND: return "Device not found";
        case CL_DEVICE_NOT_AVAILABLE: return "Device not available";
        case CL_COMPILER_NOT_AVAILABLE: return "Compiler not available";
        case CL_MEM_OBJECT_ALLOCATION_FAILURE: return "Memory object allocation failure";
        case CL_OUT_OF_RESOURCES: return "Out of resources";
        case CL_OUT_OF_HOST_MEMORY: return "Out of host memory";
        case CL_PROFILING_INFO_NOT_AVAILABLE: return "Profiling information not available";
        case CL_MEM_COPY_OVERLAP: return "Memory copy overlap";
        case CL_IMAGE_FORMAT_MISMATCH: return "Image format mismatch";
        case CL_IMAGE_FORMAT_NOT_SUPPORTED: return "Image format not supported";
        case CL_BUILD_PROGRAM_FAILURE: return "Build program failure";
        case CL_MAP_FAILURE: return "Map failure";
        case CL_INVALID_VALUE: return "Invalid value";
        case CL_INVALID_DEVICE_TYPE: return "Invalid device type";
        case CL_INVALID_PLATFORM: return "Invalid platform";
        case CL_INVALID_DEVICE: return "Invalid device";
        case CL_INVALID_CONTEXT: return "Invalid context";
        case CL_INVALID_QUEUE_PROPERTIES: return "Invalid queue properties";
        case CL_INVALID_COMMAND_QUEUE: return "Invalid command queue";
        case CL_INVALID_HOST_PTR: return "Invalid host pointer";
        case CL_INVALID_MEM_OBJECT: return "Invalid memory object";
        case CL_INVALID_IMAGE_FORMAT_DESCRIPTOR: return "Invalid image format descriptor";
        case CL_INVALID_IMAGE_SIZE: return "Invalid image size";
        case CL_INVALID_SAMPLER: return "Invalid sampler";
        case CL_INVALID_BINARY: return "Invalid binary";
        case CL_INVALID_BUILD_OPTIONS: return "Invalid build options";
        case CL_INVALID_PROGRAM: return "Invalid program";
        case CL_INVALID_PROGRAM_EXECUTABLE: return "Invalid program executable";
        case CL_INVALID_KERNEL_NAME: return "Invalid kernel name";
        case CL_INVALID_KERNEL_DEFINITION: return "Invalid kernel definition";
        case CL_INVALID_KERNEL: return "Invalid kernel";
        case CL_INVALID_ARG_INDEX: return "Invalid argument index";
        case CL_INVALID_ARG_VALUE: return "Invalid argument value";
        case CL_INVALID_ARG_SIZE: return "Invalid argument size";
        case CL_INVALID_KERNEL_ARGS: return "Invalid kernel arguments";
        case CL_INVALID_WORK_DIMENSION: return "Invalid work dimension";
        case CL_INVALID_WORK_GROUP_SIZE: return "Invalid work group size";
        case CL_INVALID_WORK_ITEM_SIZE: return "Invalid work item size";
        case CL_INVALID_GLOBAL_OFFSET: return "Invalid global offset";
        case CL_INVALID_EVENT_WAIT_LIST: return "Invalid event wait list";
        case CL_INVALID_EVENT: return "Invalid event";
        case CL_INVALID_OPERATION: return "Invalid operation";
        case CL_INVALID_GL_OBJECT: return "Invalid OpenGL object";
        case CL_INVALID_BUFFER_SIZE: return "Invalid buffer size";
        case CL_INVALID_MIP_LEVEL: return "Invalid mip level";
        case CL_INVALID_GLOBAL_WORK_SIZE: return "Invalid global work size";
        default: return "Unknown error";
    }
}

char* loadKernelSource(const char* filename, size_t* size) {
    FILE* file = fopen(filename, "r");
    if (!file) {
        printf("Error: Could not open kernel file %s\n", filename);
        return NULL;
    }

    fseek(file, 0, SEEK_END);
    *size = ftell(file);
    rewind(file);

    char* source = (char*)malloc(*size + 1);
    if (!source) {
        fclose(file);
        return NULL;
    }

    fread(source, 1, *size, file);
    source[*size] = '\0';
    fclose(file);

    return source;
}

int initOpenCL(OpenCLContext* ctx) {
    cl_int ret;
    cl_platform_id platform_id = NULL;
    cl_uint ret_num_devices;
    cl_uint ret_num_platforms;

    // Get platform and device information
    ret = clGetPlatformIDs(1, &platform_id, &ret_num_platforms);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to get platform ID: %s\n", getOpenCLErrorString(ret));
        return -1;
    }

    ret = clGetDeviceIDs(platform_id, CL_DEVICE_TYPE_GPU, 1, &ctx->device, &ret_num_devices);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to get device ID: %s\n", getOpenCLErrorString(ret));
        return -1;
    }

    // Create an OpenCL context
    ctx->context = clCreateContext(NULL, 1, &ctx->device, NULL, NULL, &ret);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to create context: %s\n", getOpenCLErrorString(ret));
        return -1;
    }

    // Create a command queue
    ctx->queue = clCreateCommandQueueWithProperties(ctx->context, ctx->device, NULL, &ret);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to create command queue: %s\n", getOpenCLErrorString(ret));
        return -1;
    }

    // Load and build the kernel
    size_t source_size;
    char* source_str = loadKernelSource("src/opencl/secp256k1_pubkey.cl", &source_size);
    if (!source_str) {
        return -1;
    }

    ctx->program = clCreateProgramWithSource(ctx->context, 1, (const char**)&source_str, &source_size, &ret);
    free(source_str);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to create program: %s\n", getOpenCLErrorString(ret));
        return -1;
    }

    // Build options to avoid problematic system headers
    const char* build_options = "-cl-std=CL1.2 -w -Werror -I.";
    ret = clBuildProgram(ctx->program, 1, &ctx->device, build_options, NULL, NULL);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to build program: %s\n", getOpenCLErrorString(ret));

        // Get build log
        size_t log_size;
        clGetProgramBuildInfo(ctx->program, ctx->device, CL_PROGRAM_BUILD_LOG, 0, NULL, &log_size);
        char* log = (char*)malloc(log_size);
        clGetProgramBuildInfo(ctx->program, ctx->device, CL_PROGRAM_BUILD_LOG, log_size, log, NULL);
        printf("Build log:\n%s\n", log);
        free(log);
        return -1;
    }

    ctx->kernel = clCreateKernel(ctx->program, "getPublicKeyKernel", &ret);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to create kernel: %s\n", getOpenCLErrorString(ret));
        return -1;
    }

    return 0;
}

void cleanupOpenCL(OpenCLContext* ctx) {
    if (ctx->kernel) clReleaseKernel(ctx->kernel);
    if (ctx->program) clReleaseProgram(ctx->program);
    if (ctx->queue) clReleaseCommandQueue(ctx->queue);
    if (ctx->context) clReleaseContext(ctx->context);
    memset(ctx, 0, sizeof(OpenCLContext));
}

void getPublicKeyByPrivateKeyOpenCL(Point output[], u64 flattenedPrivateKeys[][4], int n) {
    cl_int ret;

    // Initialize OpenCL if not already done
    if (!g_initialized) {
        if (initOpenCL(&g_ctx) != 0) {
            printf("Error: Failed to initialize OpenCL\n");
            return;
        }
        g_initialized = 1;
    }

    // Create memory buffers on the device for input and output
    cl_mem input_mem = clCreateBuffer(g_ctx.context, CL_MEM_READ_ONLY | CL_MEM_COPY_HOST_PTR,
                                     sizeof(u64) * 4 * n, flattenedPrivateKeys, &ret);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to create input buffer: %s\n", getOpenCLErrorString(ret));
        return;
    }

    // Note: Using our own Point struct size
    typedef struct {
        u64 x[4];
        u64 y[4];
    } Point_cl;

    cl_mem output_mem = clCreateBuffer(g_ctx.context, CL_MEM_WRITE_ONLY,
                                      sizeof(Point_cl) * n, NULL, &ret);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to create output buffer: %s\n", getOpenCLErrorString(ret));
        clReleaseMemObject(input_mem);
        return;
    }

    // Set the arguments of the kernel
    ret = clSetKernelArg(g_ctx.kernel, 0, sizeof(cl_mem), (void*)&output_mem);
    ret |= clSetKernelArg(g_ctx.kernel, 1, sizeof(cl_mem), (void*)&input_mem);
    ret |= clSetKernelArg(g_ctx.kernel, 2, sizeof(int), (void*)&n);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to set kernel arguments: %s\n", getOpenCLErrorString(ret));
        clReleaseMemObject(input_mem);
        clReleaseMemObject(output_mem);
        return;
    }

    // Execute the OpenCL kernel
    size_t global_item_size = n;
    size_t local_item_size = 64; // Work group size
    if (global_item_size % local_item_size != 0) {
        global_item_size = ((global_item_size / local_item_size) + 1) * local_item_size;
    }

    ret = clEnqueueNDRangeKernel(g_ctx.queue, g_ctx.kernel, 1, NULL, &global_item_size, &local_item_size, 0, NULL, NULL);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to execute kernel: %s\n", getOpenCLErrorString(ret));
        clReleaseMemObject(input_mem);
        clReleaseMemObject(output_mem);
        return;
    }

    // Read the memory buffer back to the host
    Point_cl* temp_output = (Point_cl*)malloc(sizeof(Point_cl) * n);
    ret = clEnqueueReadBuffer(g_ctx.queue, output_mem, CL_TRUE, 0, sizeof(Point_cl) * n, temp_output, 0, NULL, NULL);
    if (ret != CL_SUCCESS) {
        printf("Error: Failed to read output buffer: %s\n", getOpenCLErrorString(ret));
    } else {
        // Convert from Point_cl to Point
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < 4; j++) {
                output[i].x[j] = temp_output[i].x[j];
                output[i].y[j] = temp_output[i].y[j];
            }
        }
    }
    free(temp_output);

    // Clean up
    clReleaseMemObject(input_mem);
    clReleaseMemObject(output_mem);
}