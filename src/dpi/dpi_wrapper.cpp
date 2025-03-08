// dpi_wrapper.cpp
// Implementation of DPI-C wrapper interface

#include "dpi_wrapper.h"
#include "sim_engine.h"
#include "memory_model.h"
#include <stdexcept>
#include <cassert>
#include <iostream>

namespace gpu_simulator {
namespace dpi {

DPIWrapper& DPIWrapper::instance() {
    static DPIWrapper instance;
    return instance;
}

DPIWrapper::DPIWrapper() 
    : initialized_(false) {
}

DPIWrapper::~DPIWrapper() {
    cleanup();
}

void DPIWrapper::initialize(const ConfigDPI& config) {
    if (initialized_) {
        cleanup();
    }

    // Create simulation components
    SimConfig sim_config{
        .num_warps = config.num_warps,
        .threads_per_warp = config.threads_per_warp,
        .cache_size = config.cache_size,
        .cache_line_size = config.cache_line_size,
        .memory_latency = config.memory_latency
    };

    sim_engine_ = std::make_unique<SimulationEngine>(sim_config);
    memory_model_ = std::make_unique<MemoryModel>(
        config.cache_size,
        config.cache_line_size,
        config.memory_latency
    );

    sim_engine_->initialize();
    memory_model_->initialize();
    initialized_ = true;
}

void DPIWrapper::cleanup() {
    if (initialized_) {
        sim_engine_.reset();
        memory_model_.reset();
        initialized_ = false;
    }
}

DPIError DPIWrapper::process_memory_request(const MemoryTransactionDPI& transaction) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        validate_address(transaction.address);
        validate_warp_id(transaction.warp_id);

        uint64_t completion_time = memory_model_->process_request(
            transaction.address,
            transaction.data,
            transaction.is_write
        );

        // Schedule memory response in simulation engine
        if (!transaction.is_write) {
            sim_engine_->schedule_event(
                EventType::MEMORY_RESPONSE,
                completion_time - sim_engine_->get_current_time(),
                new MemoryTransaction{
                    .address = transaction.address,
                    .data = transaction.data,
                    .is_write = false,
                    .size = transaction.size,
                    .warp_id = transaction.warp_id,
                    .thread_mask = transaction.thread_mask
                }
            );
        }

        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in process_memory_request: " << e.what() << std::endl;
        return DPIError::MEMORY_ERROR;
    }
}

DPIError DPIWrapper::get_memory_response(uint32_t& data) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        // Process any pending events
        sim_engine_->run();

        // TODO: Implement response queue and return next response
        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in get_memory_response: " << e.what() << std::endl;
        return DPIError::MEMORY_ERROR;
    }
}

DPIError DPIWrapper::process_instruction(const InstructionDPI& instruction) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        validate_warp_id(instruction.warp_id);

        sim_engine_->instruction_complete_callback(
            instruction.warp_id,
            instruction.pc,
            instruction.instruction
        );

        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in process_instruction: " << e.what() << std::endl;
        return DPIError::SIMULATION_ERROR;
    }
}

DPIError DPIWrapper::get_next_instruction(uint32_t warp_id, InstructionDPI& instruction) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        validate_warp_id(warp_id);

        // TODO: Implement instruction fetch from simulation engine
        instruction.pc = 0;  // Placeholder
        instruction.instruction = 0;  // Placeholder
        instruction.warp_id = warp_id;
        instruction.thread_mask = 0xFFFFFFFF;  // All threads active

        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in get_next_instruction: " << e.what() << std::endl;
        return DPIError::SIMULATION_ERROR;
    }
}

DPIError DPIWrapper::update_warp_state(uint32_t warp_id, const WarpStateDPI& state) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        validate_warp_id(warp_id);
        // TODO: Implement warp state update in simulation engine
        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in update_warp_state: " << e.what() << std::endl;
        return DPIError::SIMULATION_ERROR;
    }
}

DPIError DPIWrapper::get_warp_state(uint32_t warp_id, WarpStateDPI& state) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        validate_warp_id(warp_id);
        // TODO: Implement warp state query from simulation engine
        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in get_warp_state: " << e.what() << std::endl;
        return DPIError::INVALID_WARP;
    }
}

DPIError DPIWrapper::get_cache_stats(CacheStatsDPI& stats) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        auto [hits, misses] = memory_model_->get_cache_stats();
        stats.hits = hits;
        stats.misses = misses;
        // TODO: Get additional statistics from memory model
        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in get_cache_stats: " << e.what() << std::endl;
        return DPIError::SIMULATION_ERROR;
    }
}

DPIError DPIWrapper::get_performance_counters(PerformanceCountersDPI& counters) {
    if (!initialized_) return DPIError::SIMULATION_ERROR;

    try {
        SimStats stats = sim_engine_->get_statistics();
        counters.instructions_executed = stats.instructions_executed;
        counters.memory_requests = stats.memory_requests;
        counters.cache_hits = stats.cache_hits;
        counters.stall_cycles = 0;  // TODO: Implement stall cycle tracking
        return DPIError::SUCCESS;
    } catch (const std::exception& e) {
        std::cerr << "Error in get_performance_counters: " << e.what() << std::endl;
        return DPIError::SIMULATION_ERROR;
    }
}

void DPIWrapper::print_statistics() {
    if (!initialized_) return;

    sim_engine_->print_statistics();
    memory_model_->print_cache_state();
}

void DPIWrapper::validate_warp_id(uint32_t warp_id) const {
    if (warp_id >= sim_engine_->get_config().num_warps) {
        throw std::out_of_range("Invalid warp ID");
    }
}

void DPIWrapper::validate_address(uint32_t address) const {
    // Add address validation logic here
    if (address % 4 != 0) {
        throw std::invalid_argument("Address must be 4-byte aligned");
    }
}

// DPI-C exported function implementations
extern "C" {

int initialize_simulator(const gpu_simulator::dpi::ConfigDPI* config) {
    try {
        gpu_simulator::dpi::DPIWrapper::instance().initialize(*config);
        return static_cast<int>(DPIError::SUCCESS);
    } catch (const std::exception& e) {
        std::cerr << "Error initializing simulator: " << e.what() << std::endl;
        return static_cast<int>(DPIError::SIMULATION_ERROR);
    }
}

void cleanup_simulator() {
    gpu_simulator::dpi::DPIWrapper::instance().cleanup();
}

int process_memory_request(const gpu_simulator::dpi::MemoryTransactionDPI* transaction) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().process_memory_request(*transaction)
    );
}

int get_memory_response(uint32_t* data) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().get_memory_response(*data)
    );
}

int process_instruction(const gpu_simulator::dpi::InstructionDPI* instruction) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().process_instruction(*instruction)
    );
}

int get_next_instruction(uint32_t warp_id, gpu_simulator::dpi::InstructionDPI* instruction) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().get_next_instruction(warp_id, *instruction)
    );
}

int update_warp_state(uint32_t warp_id, const gpu_simulator::dpi::WarpStateDPI* state) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().update_warp_state(warp_id, *state)
    );
}

int get_warp_state(uint32_t warp_id, gpu_simulator::dpi::WarpStateDPI* state) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().get_warp_state(warp_id, *state)
    );
}

int get_cache_stats(gpu_simulator::dpi::CacheStatsDPI* stats) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().get_cache_stats(*stats)
    );
}

int get_performance_counters(gpu_simulator::dpi::PerformanceCountersDPI* counters) {
    return static_cast<int>(
        gpu_simulator::dpi::DPIWrapper::instance().get_performance_counters(*counters)
    );
}

void print_statistics() {
    gpu_simulator::dpi::DPIWrapper::instance().print_statistics();
}

} // extern "C"