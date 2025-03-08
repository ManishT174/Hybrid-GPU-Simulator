// dpi_wrapper.h
// DPI-C wrapper interface for GPU simulator

#pragma once

#include "dpi_types.h"
#include <memory>

// Forward declarations
namespace gpu_simulator {
class SimulationEngine;
class MemoryModel;
}

namespace gpu_simulator {
namespace dpi {

class DPIWrapper {
public:
    // Singleton access
    static DPIWrapper& instance();

    // Delete copy constructor and assignment
    DPIWrapper(const DPIWrapper&) = delete;
    DPIWrapper& operator=(const DPIWrapper&) = delete;

    // Initialization and cleanup
    void initialize(const ConfigDPI& config);
    void cleanup();

    // Memory interface
    DPIError process_memory_request(const MemoryTransactionDPI& transaction);
    DPIError get_memory_response(uint32_t& data);

    // Instruction interface
    DPIError process_instruction(const InstructionDPI& instruction);
    DPIError get_next_instruction(uint32_t warp_id, InstructionDPI& instruction);

    // Warp management
    DPIError update_warp_state(uint32_t warp_id, const WarpStateDPI& state);
    DPIError get_warp_state(uint32_t warp_id, WarpStateDPI& state);

    // Statistics and monitoring
    DPIError get_cache_stats(CacheStatsDPI& stats);
    DPIError get_performance_counters(PerformanceCountersDPI& counters);
    void print_statistics();

private:
    // Private constructor for singleton
    DPIWrapper();
    ~DPIWrapper();

    // Internal state
    std::unique_ptr<SimulationEngine> sim_engine_;
    std::unique_ptr<MemoryModel> memory_model_;
    bool initialized_;

    // Internal methods
    void validate_warp_id(uint32_t warp_id) const;
    void validate_address(uint32_t address) const;
    void update_statistics();
};

} // namespace dpi
} // namespace gpu_simulator

// DPI-C exported functions
extern "C" {
    // Initialization
    int initialize_simulator(const gpu_simulator::dpi::ConfigDPI* config);
    void cleanup_simulator();

    // Memory interface
    int process_memory_request(const gpu_simulator::dpi::MemoryTransactionDPI* transaction);
    int get_memory_response(uint32_t* data);

    // Instruction interface
    int process_instruction(const gpu_simulator::dpi::InstructionDPI* instruction);
    int get_next_instruction(uint32_t warp_id, gpu_simulator::dpi::InstructionDPI* instruction);

    // Warp management
    int update_warp_state(uint32_t warp_id, const gpu_simulator::dpi::WarpStateDPI* state);
    int get_warp_state(uint32_t warp_id, gpu_simulator::dpi::WarpStateDPI* state);

    // Statistics
    int get_cache_stats(gpu_simulator::dpi::CacheStatsDPI* stats);
    int get_performance_counters(gpu_simulator::dpi::PerformanceCountersDPI* counters);
    void print_statistics();
}