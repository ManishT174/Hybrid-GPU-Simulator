#!/bin/bash
# run_sim.sh - Script to run GPU simulator with different configurations

# Default values
TEST_NAME="all"
DEBUG=0
WAVES=0
GUI=0
NUM_WARPS=32
THREADS_PER_WARP=32
CACHE_SIZE=16384
CACHE_LINE_SIZE=128
PROGRAM=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--test)
      TEST_NAME="$2"
      shift 2
      ;;
    -d|--debug)
      DEBUG=1
      shift
      ;;
    -w|--waves)
      WAVES=1
      shift
      ;;
    -g|--gui)
      GUI=1
      shift
      ;;
    --warps)
      NUM_WARPS="$2"
      shift 2
      ;;
    --threads)
      THREADS_PER_WARP="$2"
      shift 2
      ;;
    --cache-size)
      CACHE_SIZE="$2"
      shift 2
      ;;
    --cache-line)
      CACHE_LINE_SIZE="$2"
      shift 2
      ;;
    -p|--program)
      PROGRAM="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  -t, --test NAME       Run specific test (default: all)"
      echo "  -d, --debug           Enable debug output"
      echo "  -w, --waves           Enable waveform dumping"
      echo "  -g, --gui             Start simulator GUI"
      echo "  --warps N             Set number of warps (default: 32)"
      echo "  --threads N           Set threads per warp (default: 32)"
      echo "  --cache-size N        Set cache size in bytes (default: 16384)"
      echo "  --cache-line N        Set cache line size in bytes (default: 128)"
      echo "  -p, --program FILE    Load specific program file"
      echo "  -h, --help            Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Build directory
BUILD_DIR="build"
BIN_DIR="bin"

# Ensure directories exist
mkdir -p "$BUILD_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "logs"

# Create command arguments
ARGS=""

# Add test argument
ARGS="$ARGS +TEST=$TEST_NAME"

# Add configuration arguments
ARGS="$ARGS +NUM_WARPS=$NUM_WARPS +THREADS_PER_WARP=$THREADS_PER_WARP"
ARGS="$ARGS +CACHE_SIZE=$CACHE_SIZE +CACHE_LINE_SIZE=$CACHE_LINE_SIZE"

# Add program if specified
if [ ! -z "$PROGRAM" ]; then
  ARGS="$ARGS +PROGRAM=$PROGRAM"
fi

# Add debug flag if needed
if [ "$DEBUG" -eq 1 ]; then
  ARGS="$ARGS +DEBUG=1"
fi

# Generate timestamp for log files
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="logs/sim_${TIMESTAMP}.log"

# Check if binary exists
if [ ! -f "$BIN_DIR/gpu_simulator" ]; then
  echo "Simulator binary not found. Building..."
  make
fi

# Run simulation
echo "Running simulation with arguments: $ARGS"
if [ "$GUI" -eq 1 ]; then
  # Run with GUI
  "$BIN_DIR/gpu_simulator" -gui $ARGS | tee "$LOG_FILE"
elif [ "$WAVES" -eq 1 ]; then
  # Run with waveform dumping
  "$BIN_DIR/gpu_simulator" +fsdbfile+waves.fsdb +fsdb+all $ARGS | tee "$LOG_FILE"
else
  # Run in batch mode
  "$BIN_DIR/gpu_simulator" $ARGS | tee "$LOG_FILE"
fi

# Check exit status
EXIT_STATUS=$?
if [ $EXIT_STATUS -eq 0 ]; then
  echo "Simulation completed successfully."
else
  echo "Simulation failed with exit code $EXIT_STATUS."
fi

exit $EXIT_STATUS