// dpi_types.h
// DPI type definitions for GPU simulator

#pragma once

#include <cstdint>

namespace gpu_simulator {
namespace dpi {

// Basic types for DPI-C interface
using svBit = uint8_t;
using svLogic = uint8_t;

// Memory transaction type
struct MemoryTransactionDPI {
    uint32_t address;
    uint32_t data;
    svBit    is_write;
    uint32_t size;
    uint32_t warp_id;
    uint32_t thread_mask;
};

// Instruction type
struct InstructionDPI {
    uint32_t pc;
    uint32_t instruction;
    uint32_t warp_id;
    uint32_t thread_mask;
};

// Cache statistics type
struct CacheStatsDPI {
    uint64_t hits;
    uint64_t misses;
    uint64_t evictions;
    uint64_t bank_conflicts;
};

// Warp state type
struct WarpStateDPI {
    uint32_t pc;
    uint32_t thread_mask;
    svBit    active;
    uint64_t last_active_cycle;
};

// Configuration type
struct ConfigDPI {
    uint32_t num_warps;
    uint32_t threads_per_warp;
    uint32_t cache_size;
    uint32_t cache_line_size;
    uint32_t memory_latency;
};

// Performance counters type
struct PerformanceCountersDPI {
    uint64_t instructions_executed;
    uint64_t memory_requests;
    uint64_t cache_hits;
    uint64_t stall_cycles;
};

// Error codes
enum class DPIError : int32_t {
    SUCCESS = 0,
    INVALID_ADDRESS = -1,
    INVALID_WARP = -2,
    INVALID_THREAD = -3,
    MEMORY_ERROR = -4,
    SIMULATION_ERROR = -5
};

} // namespace dpi
} // namespace gpu_simulator