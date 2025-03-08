#!/bin/bash
# compile.sh - Script to compile GPU simulator with various options

# Default values
SV_SIM="vcs"  # Default simulator (VCS)
CLEAN=0
FAST=0
DEBUG=1
GCC_ONLY=0
DPI_ONLY=0
VER_ARGS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -c|--clean)
      CLEAN=1
      shift
      ;;
    -f|--fast)
      FAST=1
      DEBUG=0
      shift
      ;;
    --gcc-only)
      GCC_ONLY=1
      shift
      ;;
    --dpi-only)
      DPI_ONLY=1
      shift
      ;;
    --simulator)
      SV_SIM="$2"
      shift 2
      ;;
    -a|--args)
      VER_ARGS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  -c, --clean           Clean build directories before compilation"
      echo "  -f, --fast            Fast compilation (disable debug info)"
      echo "  --gcc-only            Compile only C++ components"
      echo "  --dpi-only            Compile only DPI library"
      echo "  --simulator SIM       Set SystemVerilog simulator (default: vcs)"
      echo "  -a, --args ARGS       Pass additional arguments to simulator"
      echo "  -h, --help            Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Directories
SRC_DIR="src"
INCLUDE_DIR="include"
RTL_DIR="rtl"
TB_DIR="tb"
BUILD_DIR="build"
BIN_DIR="bin"

# Clean if requested
if [ "$CLEAN" -eq 1 ]; then
  echo "Cleaning build directories..."
  rm -rf "$BUILD_DIR"
  rm -rf "$BIN_DIR"
fi

# Create directories if they don't exist
mkdir -p "$BUILD_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$BUILD_DIR/simulator"
mkdir -p "$BUILD_DIR/memory"
mkdir -p "$BUILD_DIR/dpi"

# Set compiler flags
if [ "$DEBUG" -eq 1 ]; then
  CXXFLAGS="-std=c++17 -Wall -Wextra -pedantic -g -O0 -fPIC"
  SV_FLAGS="-sverilog -timescale=1ns/1ps -full64 -debug_access+all +vcs+fsdbon"
else
  CXXFLAGS="-std=c++17 -Wall -Wextra -pedantic -O3 -fPIC"
  SV_FLAGS="-sverilog -timescale=1ns/1ps -full64"
fi

# Compile C++ components
if [ "$DPI_ONLY" -eq 0 ]; then
  echo "Compiling C++ components..."
  
  # Find all .cpp files
  CPP_SRCS=$(find "$SRC_DIR" -name "*.cpp")
  
  # Compile each source file
  for src in $CPP_SRCS; do
    obj="${src/$SRC_DIR/$BUILD_DIR}"
    obj="${obj/.cpp/.o}"
    obj_dir=$(dirname "$obj")
    
    # Create directory if needed
    mkdir -p "$obj_dir"
    
    echo "Compiling $src"
    g++ $CXXFLAGS -I"$INCLUDE_DIR" -c "$src" -o "$obj"
    
    if [ $? -ne 0 ]; then
      echo "Error compiling $src"
      exit 1
    fi
  done
fi

# Create DPI library
echo "Creating DPI library..."
CPP_OBJS=$(find "$BUILD_DIR" -name "*.o")
g++ -shared -o "$BUILD_DIR/libgpusim.so" $CPP_OBJS

if [ $? -ne 0 ]; then
  echo "Error creating DPI library"
  exit 1
fi

# Exit if only C++ compilation requested
if [ "$GCC_ONLY" -eq 1 ]; then
  echo "C++ compilation completed successfully."
  exit 0
fi

# Compile SystemVerilog
echo "Compiling SystemVerilog with $SV_SIM..."

# Set simulator-specific flags
case $SV_SIM in
  vcs)
    # VCS-specific commands
    vcs $SV_FLAGS -LDFLAGS "-L$BUILD_DIR -lgpusim" \
      -l "$BIN_DIR/compile.log" \
      -o "$BIN_DIR/gpu_simulator" \
      $VER_ARGS \
      $(find "$RTL_DIR" -name "*.sv") \
      $(find "$TB_DIR" -name "*.sv")
    ;;
  
  questa)
    # Questa-specific commands
    vlog $SV_FLAGS \
      -l "$BIN_DIR/compile.log" \
      $(find "$RTL_DIR" -name "*.sv") \
      $(find "$TB_DIR" -name "*.sv")
    
    vopt -o "$BIN_DIR/gpu_simulator_opt" tb_top -work work
    
    echo "To run simulation, use: vsim -c -do \"run -all; exit\" $BIN_DIR/gpu_simulator_opt"
    ;;
  
  xcelium)
    # Xcelium-specific commands
    xrun $SV_FLAGS \
      -l "$BIN_DIR/compile.log" \
      -sv \
      $(find "$RTL_DIR" -name "*.sv") \
      $(find "$TB_DIR" -name "*.sv")
    ;;
  
  *)
    echo "Unsupported simulator: $SV_SIM"
    exit 1
    ;;
esac

if [ $? -ne 0 ]; then
  echo "Error compiling SystemVerilog"
  exit 1
fi

echo "Compilation completed successfully."
exit 0