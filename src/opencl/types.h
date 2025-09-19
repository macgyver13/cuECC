#ifndef OPENCL_TYPES_H
#define OPENCL_TYPES_H

#include <stdint.h>

// Type definitions compatible with C
typedef uint64_t u64;

// Point structure for OpenCL
typedef struct {
    u64 x[4];
    u64 y[4];
} Point;

#endif // OPENCL_TYPES_H