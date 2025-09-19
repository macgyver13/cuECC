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

# OpenCL detection and configuration
ifeq ($(shell uname),Darwin)
	# macOS uses OpenCL framework
	CC = clang
	OPENCL_FLAGS = -framework OpenCL
	OPENCL_AVAILABLE = 1
else
	# Linux - detect available OpenCL implementations
	CC = gcc
	OPENCL_AVAILABLE = 0
	OPENCL_FLAGS =

	# Check for various OpenCL library locations
	ifneq ($(wildcard /usr/lib/x86_64-linux-gnu/libOpenCL.so*),)
		OPENCL_FLAGS = -lOpenCL
		OPENCL_AVAILABLE = 1
	else ifneq ($(wildcard /usr/lib/libOpenCL.so*),)
		OPENCL_FLAGS = -lOpenCL
		OPENCL_AVAILABLE = 1
	else ifneq ($(wildcard /usr/local/lib/libOpenCL.so*),)
		OPENCL_FLAGS = -L/usr/local/lib -lOpenCL
		OPENCL_AVAILABLE = 1
	else ifneq ($(wildcard /opt/intel/opencl/lib64/libOpenCL.so*),)
		OPENCL_FLAGS = -L/opt/intel/opencl/lib64 -lOpenCL
		OPENCL_AVAILABLE = 1
	else
		# Try pkg-config as fallback
		OPENCL_PKGCONFIG := $(shell pkg-config --exists OpenCL 2>/dev/null && echo 1 || echo 0)
		ifeq ($(OPENCL_PKGCONFIG),1)
			OPENCL_FLAGS = $(shell pkg-config --libs OpenCL)
			OPENCL_CFLAGS_EXTRA = $(shell pkg-config --cflags OpenCL)
			OPENCL_AVAILABLE = 1
		endif
	endif
endif

# Include OpenCL headers check
ifeq ($(shell uname),Darwin)
	# macOS has OpenCL headers in the framework
	OPENCL_HEADERS_AVAILABLE = 1
else
	OPENCL_HEADERS_AVAILABLE = 0
	ifneq ($(wildcard /usr/include/CL/cl.h),)
		OPENCL_HEADERS_AVAILABLE = 1
	else ifneq ($(wildcard /usr/local/include/CL/cl.h),)
		OPENCL_CFLAGS_EXTRA += -I/usr/local/include
		OPENCL_HEADERS_AVAILABLE = 1
	else ifneq ($(wildcard /opt/intel/opencl/include/CL/cl.h),)
		OPENCL_CFLAGS_EXTRA += -I/opt/intel/opencl/include
		OPENCL_HEADERS_AVAILABLE = 1
	endif
endif

OPENCL_CFLAGS = -fPIC -shared -I$(SRC_DIR) $(OPENCL_CFLAGS_EXTRA)

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
	@if [ "$(OPENCL_AVAILABLE)" = "0" ]; then \
		echo "Error: OpenCL libraries not found!"; \
		echo ""; \
		echo "Please install OpenCL development packages:"; \
		echo ""; \
		echo "For NVIDIA GPUs:"; \
		echo "  sudo apt install nvidia-opencl-dev"; \
		echo ""; \
		echo "For AMD GPUs:"; \
		echo "  sudo apt install mesa-opencl-dev"; \
		echo ""; \
		echo "For Intel GPUs:"; \
		echo "  sudo apt install intel-opencl-icd"; \
		echo ""; \
		echo "Generic OpenCL (works with multiple vendors):"; \
		echo "  sudo apt install ocl-icd-libopencl1 opencl-headers ocl-icd-dev"; \
		echo ""; \
		echo "After installation, run 'make clean && make opencl'"; \
		exit 1; \
	fi
	@if [ "$(OPENCL_HEADERS_AVAILABLE)" = "0" ]; then \
		echo "Error: OpenCL headers not found!"; \
		echo "Please install: sudo apt install opencl-headers"; \
		exit 1; \
	fi
	@echo "Building OpenCL library..."
	@echo "OpenCL flags: $(OPENCL_FLAGS)"
	$(CC) $(OPENCL_CFLAGS) -o $(OPENCL_LIB_TARGET) $(OPENCL_LIB_SOURCE) $(OPENCL_FLAGS)

cuda: $(LIB_TARGET)

opencl: $(OPENCL_LIB_TARGET)

all: $(LIB_TARGET) $(OPENCL_LIB_TARGET)

check-opencl:
	@echo "=== OpenCL Availability Check ==="
	@echo "Platform: $(shell uname)"
	@echo ""
	@echo "OpenCL Libraries:"
ifeq ($(shell uname),Darwin)
	@echo "  macOS OpenCL Framework: ✓ Available"
else
	@if [ "$(OPENCL_AVAILABLE)" = "1" ]; then \
		echo "  OpenCL Libraries: ✓ Found"; \
		echo "  Library flags: $(OPENCL_FLAGS)"; \
	else \
		echo "  OpenCL Libraries: ✗ Not found"; \
		echo ""; \
		echo "  Install with one of:"; \
		echo "    sudo apt install ocl-icd-libopencl1 opencl-headers ocl-icd-dev  # Generic"; \
		echo "    sudo apt install nvidia-opencl-dev                              # NVIDIA"; \
		echo "    sudo apt install mesa-opencl-dev                                # AMD/Mesa"; \
		echo "    sudo apt install intel-opencl-icd                               # Intel"; \
	fi
endif
	@echo ""
	@echo "OpenCL Headers:"
ifeq ($(shell uname),Darwin)
	@echo "  macOS OpenCL Headers: ✓ Available (framework)"
else
	@if [ "$(OPENCL_HEADERS_AVAILABLE)" = "1" ]; then \
		echo "  OpenCL Headers: ✓ Found"; \
	else \
		echo "  OpenCL Headers: ✗ Not found"; \
		echo "  Install with: sudo apt install opencl-headers"; \
	fi
endif
	@echo ""
	@echo "Build Status:"
	@if [ "$(OPENCL_AVAILABLE)" = "1" ] && [ "$(OPENCL_HEADERS_AVAILABLE)" = "1" ]; then \
		echo "  OpenCL Build: ✓ Ready"; \
		echo "  Run: make opencl"; \
	else \
		echo "  OpenCL Build: ✗ Missing dependencies"; \
	fi
	@echo ""
	@echo "Optional: Install 'clinfo' to list OpenCL devices:"
	@echo "  sudo apt install clinfo && clinfo"

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all cuda opencl clean check-opencl
