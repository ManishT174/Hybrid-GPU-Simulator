# Makefile for GPU Architecture Simulator
# Provides build targets for C++ components and SystemVerilog integration

# Compiler and flags
CXX = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -pedantic -g -O2 -fPIC
LDFLAGS = -shared

# SystemVerilog simulator
SV_SIM = vcs
SV_FLAGS = -sverilog -timescale=1ns/1ps -full64 -debug_access+all

# Directories
SRC_DIR = src
BUILD_DIR = build
INCLUDE_DIR = include
RTL_DIR = rtl
TB_DIR = tb
SCRIPTS_DIR = scripts
BIN_DIR = bin

# Source files
CPP_SRCS = $(wildcard $(SRC_DIR)/*.cpp) $(wildcard $(SRC_DIR)/*/*.cpp)
CPP_OBJS = $(patsubst $(SRC_DIR)/%.cpp,$(BUILD_DIR)/%.o,$(CPP_SRCS))

# DPI library
DPI_LIB = $(BUILD_DIR)/libgpusim.so

# RTL files
RTL_SRCS = $(wildcard $(RTL_DIR)/*.sv) $(wildcard $(RTL_DIR)/*/*.sv)
TB_SRCS = $(wildcard $(TB_DIR)/*.sv)

# Main targets
.PHONY: all clean run test

all: $(DPI_LIB) compile_rtl

# Create directories
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/simulator
	mkdir -p $(BUILD_DIR)/memory
	mkdir -p $(BUILD_DIR)/dpi

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

# Compile C++ sources
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cpp | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -I$(INCLUDE_DIR) -c $< -o $@

# Build shared library for DPI
$(DPI_LIB): $(CPP_OBJS) | $(BUILD_DIR)
	$(CXX) $(LDFLAGS) -o $@ $^

# Compile RTL with DPI library
compile_rtl: $(DPI_LIB) | $(BIN_DIR)
	$(SV_SIM) $(SV_FLAGS) -LDFLAGS "-L$(BUILD_DIR) -lgpusim" \
		-l $(BIN_DIR)/compile.log \
		-o $(BIN_DIR)/gpu_simulator \
		$(RTL_SRCS) $(TB_SRCS)

# Run simulation
run: compile_rtl
	$(BIN_DIR)/gpu_simulator -l $(BIN_DIR)/sim.log

# Run tests
test: compile_rtl
	$(BIN_DIR)/gpu_simulator -testplusarg "TEST=all" -l $(BIN_DIR)/test.log

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(BIN_DIR)
	rm -f *.log
	rm -f *.key
	rm -f *.vcd
	rm -f *.vpd
	rm -f *.fsdb

# Individual tests
test_alu: compile_rtl
	$(BIN_DIR)/gpu_simulator -testplusarg "TEST=alu" -l $(BIN_DIR)/test_alu.log

test_memory: compile_rtl
	$(BIN_DIR)/gpu_simulator -testplusarg "TEST=memory" -l $(BIN_DIR)/test_memory.log

test_branch: compile_rtl
	$(BIN_DIR)/gpu_simulator -testplusarg "TEST=branch" -l $(BIN_DIR)/test_branch.log