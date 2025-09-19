PROJECT_DIR = $(realpath .)

BUILD_DIR = $(PROJECT_DIR)/build
SRC_DIR = $(PROJECT_DIR)/src

# CUDA library
LIB_TARGET = $(BUILD_DIR)/libcuecc.so
LIB_SOURCE = $(SRC_DIR)/*.cu
LIB_DEPENDENCIES = $(SRC_DIR)/**/*.cuh

# OpenCL library
OPENCL_LIB_TARGET = $(BUILD_DIR)/libcuecc_opencl.so
OPENCL_LIB_SOURCE = $(SRC_DIR)/opencl/ecc_opencl.c
OPENCL_LIB_DEPENDENCIES = $(SRC_DIR)/opencl/*.h $(SRC_DIR)/opencl/*.cl

NVCC = nvcc
NVCC_FLAGS = -Xcompiler -fPIC -shared -rdc=true -o $(LIB_TARGET)

# Compiler for OpenCL (use clang on macOS, gcc on Linux)
ifeq ($(shell uname),Darwin)
	CC = clang
	OPENCL_FLAGS = -framework OpenCL
else
	CC = gcc
	OPENCL_FLAGS = -lOpenCL
endif

OPENCL_CFLAGS = -fPIC -shared -I$(SRC_DIR) $(OPENCL_FLAGS) -o $(OPENCL_LIB_TARGET)

define COMPILE_COMMANDS 
[\
    {\
        \"directory\": \"$(BUILD_DIR)\",\
        \"command\": \"$(NVCC) $(LIB_SOURCE)\",\
        \"file\": \"$(LIB_SOURCE)\"\
    }\
]
endef

compile_commands.json: Makefile
	@echo $(COMPILE_COMMANDS) > compile_commands.json

$(LIB_TARGET): $(LIB_SOURCE) $(LIB_DEPENDENCIES)
	@mkdir -p $(BUILD_DIR)
	$(NVCC) $(NVCC_FLAGS) $(LIB_SOURCE)

$(OPENCL_LIB_TARGET): $(OPENCL_LIB_SOURCE) $(OPENCL_LIB_DEPENDENCIES)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(OPENCL_CFLAGS) $(OPENCL_LIB_SOURCE)

cuda: $(LIB_TARGET)

opencl: $(OPENCL_LIB_TARGET)

all: $(LIB_TARGET) $(OPENCL_LIB_TARGET)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all cuda opencl clean
