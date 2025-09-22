# Detect operating system
ifeq ($(OS),Windows_NT)
    DETECTED_OS := Windows
    # Handle Windows paths
    PROJECT_DIR := $(shell cd)
    BUILD_DIR := $(PROJECT_DIR)\build
    SRC_DIR := $(PROJECT_DIR)\src

    # Windows file extensions
    LIB_EXT := .dll
    EXE_EXT := .exe

    # Path separator
    PATH_SEP := \\

    # Commands
    MKDIR := if not exist
    RM := del /Q /S
    RMDIR := rmdir /Q /S
else
    DETECTED_OS := $(shell uname -s)
    # Unix-style paths
    PROJECT_DIR := $(realpath .)
    BUILD_DIR := $(PROJECT_DIR)/build
    SRC_DIR := $(PROJECT_DIR)/src

    # Unix file extensions
    LIB_EXT := .so
    EXE_EXT :=

    # Path separator
    PATH_SEP := /

    # Commands
    MKDIR := mkdir -p
    RM := rm -rf
    RMDIR := rm -rf
endif

# Library targets with OS-specific extensions
ifeq ($(DETECTED_OS),Windows)
    LIB_TARGET = $(BUILD_DIR)$(PATH_SEP)cuecc$(LIB_EXT)
    OPENCL_LIB_TARGET = $(BUILD_DIR)$(PATH_SEP)cuecc_opencl$(LIB_EXT)
    METAL_LIB_TARGET = $(BUILD_DIR)$(PATH_SEP)cuecc_metal$(LIB_EXT)
else
    LIB_TARGET = $(BUILD_DIR)/libcuecc$(LIB_EXT)
    OPENCL_LIB_TARGET = $(BUILD_DIR)/libcuecc_opencl$(LIB_EXT)
    METAL_LIB_TARGET = $(BUILD_DIR)/libcuecc_metal$(LIB_EXT)
endif

LIB_SOURCE = $(SRC_DIR)$(PATH_SEP)*.cu
LIB_DEPENDENCIES = $(SRC_DIR)$(PATH_SEP)**$(PATH_SEP)*.cuh

# OpenCL library
OPENCL_LIB_SOURCE = $(SRC_DIR)$(PATH_SEP)opencl$(PATH_SEP)ecc_opencl.c
OPENCL_LIB_DEPENDENCIES = $(SRC_DIR)$(PATH_SEP)opencl$(PATH_SEP)*.h $(SRC_DIR)$(PATH_SEP)opencl$(PATH_SEP)*.cl

# Metal library (macOS only)
METAL_LIB_SOURCE = $(SRC_DIR)$(PATH_SEP)metal$(PATH_SEP)ecc_metal.mm
METAL_LIB_DEPENDENCIES = $(SRC_DIR)$(PATH_SEP)metal$(PATH_SEP)*.h $(SRC_DIR)$(PATH_SEP)metal$(PATH_SEP)*.metal

NVCC = nvcc

# Platform-specific NVCC flags
ifeq ($(DETECTED_OS),Windows)
    NVCC_FLAGS = -shared -rdc=true -o $(LIB_TARGET)
else
    NVCC_FLAGS = -Xcompiler -fPIC -shared -rdc=true -o $(LIB_TARGET)
endif

# OpenCL detection and configuration
ifeq ($(DETECTED_OS),Windows)
	# Windows OpenCL detection
	CC = cl
	OPENCL_AVAILABLE = 0
	OPENCL_FLAGS =

	# Check for CUDA OpenCL (NVIDIA)
	ifdef CUDA_PATH
		ifneq ($(wildcard $(CUDA_PATH)$(PATH_SEP)lib$(PATH_SEP)x64$(PATH_SEP)OpenCL.lib),)
			OPENCL_FLAGS = /LIBPATH:"$(CUDA_PATH)$(PATH_SEP)lib$(PATH_SEP)x64" OpenCL.lib
			OPENCL_CFLAGS_EXTRA = /I"$(CUDA_PATH)$(PATH_SEP)include"
			OPENCL_AVAILABLE = 1
		endif
	endif

	# Check for Intel OpenCL
	ifdef INTELOCLSDKROOT
		ifneq ($(wildcard $(INTELOCLSDKROOT)$(PATH_SEP)lib$(PATH_SEP)x64$(PATH_SEP)OpenCL.lib),)
			OPENCL_FLAGS = /LIBPATH:"$(INTELOCLSDKROOT)$(PATH_SEP)lib$(PATH_SEP)x64" OpenCL.lib
			OPENCL_CFLAGS_EXTRA = /I"$(INTELOCLSDKROOT)$(PATH_SEP)include"
			OPENCL_AVAILABLE = 1
		endif
	endif

	# Fallback: check standard Windows paths
	ifeq ($(OPENCL_AVAILABLE),0)
		ifneq ($(wildcard C:$(PATH_SEP)Windows$(PATH_SEP)System32$(PATH_SEP)OpenCL.dll),)
			OPENCL_FLAGS = OpenCL.lib
			OPENCL_AVAILABLE = 1
		endif
	endif

	OPENCL_CFLAGS = /c /DDLL_EXPORTS $(OPENCL_CFLAGS_EXTRA)
else ifeq ($(DETECTED_OS),Darwin)
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
ifeq ($(DETECTED_OS),Windows)
	OPENCL_HEADERS_AVAILABLE = 0
	# Check CUDA headers
	ifdef CUDA_PATH
		ifneq ($(wildcard $(CUDA_PATH)$(PATH_SEP)include$(PATH_SEP)CL$(PATH_SEP)cl.h),)
			OPENCL_HEADERS_AVAILABLE = 1
		endif
	endif
	# Check Intel OpenCL headers
	ifdef INTELOCLSDKROOT
		ifneq ($(wildcard $(INTELOCLSDKROOT)$(PATH_SEP)include$(PATH_SEP)CL$(PATH_SEP)cl.h),)
			OPENCL_HEADERS_AVAILABLE = 1
		endif
	endif
	ifeq ($(OPENCL_HEADERS_AVAILABLE),0)
		OPENCL_CFLAGS_EXTRA += /I"$(SRC_DIR)"
	endif
else ifeq ($(DETECTED_OS),Darwin)
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

# Set OpenCL compilation flags based on platform
ifeq ($(DETECTED_OS),Windows)
	OPENCL_CFLAGS = /c /DDLL_EXPORTS /I"$(SRC_DIR)" $(OPENCL_CFLAGS_EXTRA)
else
	OPENCL_CFLAGS = -fPIC -shared -I$(SRC_DIR) $(OPENCL_CFLAGS_EXTRA)
endif

# Metal compilation flags (macOS only)
ifeq ($(shell uname),Darwin)
	METAL_AVAILABLE = 1
	# Check if Python is running in x86_64 mode and build for compatible architecture
	PYTHON_ARCH := $(shell python3 -c "import platform; print(platform.machine())")
	ifeq ($(PYTHON_ARCH),x86_64)
		METAL_CFLAGS = -fPIC -shared -I$(SRC_DIR) -framework Metal -framework Foundation -fobjc-arc -arch x86_64
	else
		METAL_CFLAGS = -fPIC -shared -I$(SRC_DIR) -framework Metal -framework Foundation -fobjc-arc
	endif
	METAL_CC = clang++
else
	METAL_AVAILABLE = 0
endif

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
ifeq ($(DETECTED_OS),Windows)
	@$(MKDIR) "$(BUILD_DIR)" 2>NUL || echo Build directory ready
	$(NVCC) $(NVCC_FLAGS) $(LIB_SOURCE)
else
	@$(MKDIR) $(BUILD_DIR)
	$(NVCC) $(NVCC_FLAGS) $(LIB_SOURCE)
endif

$(OPENCL_LIB_TARGET): $(OPENCL_LIB_SOURCE) $(OPENCL_LIB_DEPENDENCIES)
ifeq ($(DETECTED_OS),Windows)
	@$(MKDIR) "$(BUILD_DIR)" 2>NUL || echo Build directory ready
	@if "$(OPENCL_AVAILABLE)" == "0" ( \
		echo Error: OpenCL libraries not found! & \
		echo. & \
		echo Please install OpenCL development packages: & \
		echo. & \
		echo For NVIDIA GPUs: & \
		echo   Install CUDA Toolkit which includes OpenCL & \
		echo. & \
		echo For Intel GPUs: & \
		echo   Install Intel OpenCL SDK & \
		echo. & \
		echo After installation, run 'make clean && make opencl' & \
		exit /b 1 \
	)
	@if "$(OPENCL_HEADERS_AVAILABLE)" == "0" ( \
		echo Error: OpenCL headers not found! & \
		echo Please install OpenCL SDK & \
		exit /b 1 \
	)
	@echo Building OpenCL library...
	@echo OpenCL flags: $(OPENCL_FLAGS)
	$(CC) $(OPENCL_CFLAGS) /Fe:$(OPENCL_LIB_TARGET) $(OPENCL_LIB_SOURCE) /link $(OPENCL_FLAGS)
else
	@$(MKDIR) $(BUILD_DIR)
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
endif

$(METAL_LIB_TARGET): $(METAL_LIB_SOURCE) $(METAL_LIB_DEPENDENCIES)
	@mkdir -p $(BUILD_DIR)
ifeq ($(shell uname),Darwin)
	@echo "Building Metal library..."
	@echo "Metal flags: $(METAL_CFLAGS)"
	$(METAL_CC) $(METAL_CFLAGS) -o $(METAL_LIB_TARGET) $(METAL_LIB_SOURCE)
else
	@echo "Error: Metal is only available on macOS"
	@exit 1
endif

cuda: $(LIB_TARGET)

opencl: $(OPENCL_LIB_TARGET)

metal: $(METAL_LIB_TARGET)

ifeq ($(DETECTED_OS),Darwin)
all: $(LIB_TARGET) $(OPENCL_LIB_TARGET) $(METAL_LIB_TARGET)
else ifeq ($(DETECTED_OS),Windows)
all: $(LIB_TARGET) $(OPENCL_LIB_TARGET)
else
all: $(LIB_TARGET) $(OPENCL_LIB_TARGET)
endif

check-opencl:
	@echo === OpenCL Availability Check ===
	@echo Platform: $(DETECTED_OS)
	@echo.
	@echo OpenCL Libraries:
ifeq ($(DETECTED_OS),Windows)
	@if "$(OPENCL_AVAILABLE)" == "1" ( \
		echo   OpenCL Libraries: ✓ Found & \
		echo   Library flags: $(OPENCL_FLAGS) \
	) else ( \
		echo   OpenCL Libraries: ✗ Not found & \
		echo. & \
		echo   Install one of: & \
		echo     CUDA Toolkit ^(includes OpenCL^) & \
		echo     Intel OpenCL SDK \
	)
else ifeq ($(DETECTED_OS),Darwin)
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
	@echo.
	@echo OpenCL Headers:
ifeq ($(DETECTED_OS),Windows)
	@if "$(OPENCL_HEADERS_AVAILABLE)" == "1" ( \
		echo   OpenCL Headers: ✓ Found \
	) else ( \
		echo   OpenCL Headers: ✗ Not found & \
		echo   Install OpenCL SDK \
	)
else ifeq ($(DETECTED_OS),Darwin)
	@echo "  macOS OpenCL Headers: ✓ Available (framework)"
else
	@if [ "$(OPENCL_HEADERS_AVAILABLE)" = "1" ]; then \
		echo "  OpenCL Headers: ✓ Found"; \
	else \
		echo "  OpenCL Headers: ✗ Not found"; \
		echo "  Install with: sudo apt install opencl-headers"; \
	fi
endif
	@echo.
	@echo Build Status:
ifeq ($(DETECTED_OS),Windows)
	@if "$(OPENCL_AVAILABLE)" == "1" if "$(OPENCL_HEADERS_AVAILABLE)" == "1" ( \
		echo   OpenCL Build: ✓ Ready & \
		echo   Run: make opencl \
	) else ( \
		echo   OpenCL Build: ✗ Missing dependencies \
	)
else
	@if [ "$(OPENCL_AVAILABLE)" = "1" ] && [ "$(OPENCL_HEADERS_AVAILABLE)" = "1" ]; then \
		echo "  OpenCL Build: ✓ Ready"; \
		echo "  Run: make opencl"; \
	else \
		echo "  OpenCL Build: ✗ Missing dependencies"; \
	fi
endif
	@echo.
ifeq ($(DETECTED_OS),Windows)
	@echo Optional: Check GPU with: wmic path win32_VideoController get name
else
	@echo "Optional: Install 'clinfo' to list OpenCL devices:"
	@echo "  sudo apt install clinfo && clinfo"
endif

check-metal:
	@echo "=== Metal Availability Check ==="
	@echo "Platform: $(shell uname)"
	@echo ""
ifeq ($(shell uname),Darwin)
	@echo "Metal Support:"
	@echo "  macOS Metal Framework: ✓ Available"
	@echo ""
	@echo "Build Status:"
	@echo "  Metal Build: ✓ Ready"
	@echo "  Run: make metal"
	@echo ""
	@echo "System Information:"
	@system_profiler SPDisplaysDataType | grep -A 2 "Metal Support"
else
	@echo "Metal Support:"
	@echo "  Metal Framework: ✗ Not available (macOS only)"
	@echo ""
	@echo "Build Status:"
	@echo "  Metal Build: ✗ Not supported on this platform"
endif

clean:
ifeq ($(DETECTED_OS),Windows)
	@if exist "$(BUILD_DIR)" $(RMDIR) "$(BUILD_DIR)" 2>NUL || echo Clean completed
else
	$(RM) $(BUILD_DIR)
endif

.PHONY: all cuda opencl metal clean check-opencl check-metal
