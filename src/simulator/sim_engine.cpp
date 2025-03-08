// sim_engine.cpp
// Implementation of simulation engine

#include "sim_engine.h"
#include <iostream>
#include <fstream>
#include <cassert>
#include <cstring>
#include <algorithm>
#include <iomanip>

namespace gpu_simulator {

SimulationEngine::SimulationEngine(const SimConfig& config)
    : config_(config)
    , running_(false)
    , current_time_(0)
    , memory_model_(std::make_unique<MemoryModel>(config.cache_size, 
                                                 config.cache_line_size,
                                                 config.memory_latency)) {
    // Initialize warp states
    warp_states_.resize(config.num_warps);
    for (auto& state : warp_states_) {
        state.pc = 0;
        state.thread_mask = 0xFFFFFFFF;  // All threads active initially
        state.active = true;
        state.last_active = 0;
    }

    // Reserve space for event queue and trace
    simulation_trace_.reserve(TRACE_RESERVE_SIZE);
}

SimulationEngine::~SimulationEngine() {
    stop();
}

void SimulationEngine::initialize() {
    // Reset simulation state
    current_time_ = 0;
    stats_ = SimStats{};
    while (!event_queue_.empty()) {
        event_queue_.pop();
    }
    simulation_trace_.clear();

    // Initialize memory model
    memory_model_->initialize();

    // Schedule initial events
    for (uint32_t warp_id = 0; warp_id < config_.num_warps; ++warp_id) {
        schedule_event(EventType::INSTRUCTION_FETCH, 0, 
                      reinterpret_cast<void*>(static_cast<uintptr_t>(warp_id)));
    }
}

void SimulationEngine::run() {
    running_ = true;

    while (running_ && !event_queue_.empty()) {
        // Process next event
        SimEvent event = event_queue_.top();
        event_queue_.pop();

        // Update simulation time
        current_time_ = event.time;

        // Process the event
        process_event(event);

        // Update statistics periodically
        if (current_time_ % 1000 == 0) {
            update_statistics();
        }

        // Check for simulation end conditions
        if (current_time_ >= 1000000 || // Maximum cycle limit
            std::all_of(warp_states_.begin(), warp_states_.end(),
                       [](const WarpState& w) { return !w.active; })) {
            running_ = false;
        }
    }

    // Final statistics update
    calculate_performance_metrics();
}

void SimulationEngine::process_event(const SimEvent& event) {
    log_event(event);

    switch (event.type) {
        case EventType::MEMORY_REQUEST: {
            auto* trans = static_cast<MemoryTransaction*>(event.data);
            process_memory_request(trans);
            delete trans;
            break;
        }
        case EventType::MEMORY_RESPONSE: {
            auto* trans = static_cast<MemoryTransaction*>(event.data);
            process_memory_response(trans);
            delete trans;
            break;
        }
        case EventType::INSTRUCTION_FETCH: {
            uint32_t warp_id = reinterpret_cast<uintptr_t>(event.data);
            process_instruction_fetch(warp_id);
            break;
        }
        case EventType::WARP_COMPLETE: {
            uint32_t warp_id = reinterpret_cast<uintptr_t>(event.data);
            process_warp_complete(warp_id);
            break;
        }
        case EventType::SIMULATION_END:
            running_ = false;
            break;
    }
}

void SimulationEngine::process_memory_request(const MemoryTransaction* trans) {
    // Update statistics
    stats_.memory_requests++;

    // Process through memory model
    SimTime response_time = memory_model_->process_request(trans->address, 
                                                         trans->data,
                                                         trans->is_write);

    // Schedule response event
    if (!trans->is_write) {
        auto* response = new MemoryTransaction(*trans);
        schedule_event(EventType::MEMORY_RESPONSE, response_time, response);
    }

    // Update warp state
    warp_states_[trans->warp_id].last_active = current_time_;
}

void SimulationEngine::process_memory_response(const MemoryTransaction* trans) {
    // Notify RTL through DPI-C
    memory_request_callback(trans->address, trans->data, false, 
                          trans->warp_id, trans->thread_mask);

    // Schedule next instruction fetch
    schedule_event(EventType::INSTRUCTION_FETCH, 1, 
                  reinterpret_cast<void*>(static_cast<uintptr_t>(trans->warp_id)));
}

void SimulationEngine::process_instruction_fetch(uint32_t warp_id) {
    if (!warp_states_[warp_id].active) {
        return;
    }

    // Simulate instruction fetch and execution
    WarpState& warp = warp_states_[warp_id];
    uint32_t instruction = memory_model_->read_instruction(warp.pc);
    
    // Update statistics
    stats_.instructions_executed++;
    
    // Notify RTL through DPI-C
    instruction_complete_callback(warp_id, warp.pc, instruction);
    
    // Update PC and schedule next instruction
    warp.pc += 4;
    schedule_event(EventType::INSTRUCTION_FETCH, 4, 
                  reinterpret_cast<void*>(static_cast<uintptr_t>(warp_id)));
}

void SimulationEngine::process_warp_complete(uint32_t warp_id) {
    warp_states_[warp_id].active = false;
    
    // Check if all warps are complete
    if (std::all_of(warp_states_.begin(), warp_states_.end(),
                    [](const WarpState& w) { return !w.active; })) {
        schedule_event(EventType::SIMULATION_END, 1, nullptr);
    }
}

void SimulationEngine::schedule_event(EventType type, SimTime delay, void* data) {
    SimEvent event{
        .type = type,
        .time = current_time_ + delay,
        .data = data
    };
    event_queue_.push(event);
}

void SimulationEngine::update_statistics() {
    stats_.total_cycles = current_time_;
    
    auto [hits, misses] = memory_model_->get_cache_stats();
    stats_.cache_hits = hits;
    stats_.cache_misses = misses;
}

void SimulationEngine::calculate_performance_metrics() {
    stats_.ipc = static_cast<double>(stats_.instructions_executed) / 
                 static_cast<double>(stats_.total_cycles);
    
    stats_.cache_hit_rate = static_cast<double>(stats_.cache_hits) /
                           static_cast<double>(stats_.cache_hits + stats_.cache_misses);
}

SimStats SimulationEngine::get_statistics() const {
    return stats_;
}

void SimulationEngine::print_statistics() const {
    std::cout << "\nSimulation Statistics:\n"
              << "=====================\n"
              << "Total Cycles: " << stats_.total_cycles << "\n"
              << "Instructions Executed: " << stats_.instructions_executed << "\n"
              << "IPC: " << std::fixed << std::setprecision(2) << stats_.ipc << "\n"
              << "Memory Requests: " << stats_.memory_requests << "\n"
              << "Cache Hit Rate: " << std::fixed << std::setprecision(2) 
              << (stats_.cache_hit_rate * 100.0) << "%\n";
}

void SimulationEngine::dump_trace(const std::string& filename) const {
    std::ofstream trace_file(filename);
    if (!trace_file) {
        std::cerr << "Error: Could not open trace file: " << filename << "\n";
        return;
    }

    trace_file << "Time,Event,WarpID,Address,Data\n";
    for (const auto& entry : simulation_trace_) {
        trace_file << entry.time << ","
                  << static_cast<int>(entry.type) << ","
                  << entry.warp_id << ","
                  << std::hex << entry.address << ","
                  << entry.data << std::dec << "\n";
    }
}

void SimulationEngine::log_event(const SimEvent& event) {
    if (simulation_trace_.size() < TRACE_RESERVE_SIZE) {
        TraceEntry entry{
            .time = event.time,
            .type = event.type,
            .warp_id = 0,  // Updated based on event type
            .address = 0,
            .data = 0
        };

        if (event.data) {
            switch (event.type) {
                case EventType::MEMORY_REQUEST:
                case EventType::MEMORY_RESPONSE: {
                    auto* trans = static_cast<const MemoryTransaction*>(event.data);
                    entry.warp_id = trans->warp_id;
                    entry.address = trans->address;
                    entry.data = trans->data;
                    break;
                }
                case EventType::INSTRUCTION_FETCH:
                case EventType::WARP_COMPLETE:
                    entry.warp_id = reinterpret_cast<uintptr_t>(event.data);
                    break;
                default:
                    break;
            }
        }

        simulation_trace_.push_back(entry);
    }
}

void SimulationEngine::memory_request_callback(uint32_t address, uint32_t data,
                                             bool is_write, uint32_t warp_id,
                                             uint32_t thread_mask) {
    // Create new memory transaction
    auto* trans = new MemoryTransaction{
        .address = address,
        .data = data,
        .is_write = is_write,
        .size = 4,  // Assuming 32-bit access
        .warp_id = warp_id,
        .thread_mask = thread_mask
    };

    // Get singleton instance and schedule event
    static SimulationEngine* instance = nullptr;
    if (instance) {
        instance->schedule_event(EventType::MEMORY_REQUEST, 1, trans);
    }
}

void SimulationEngine::instruction_complete_callback(uint32_t warp_id,
                                                   uint32_t pc,
                                                   uint32_t instruction) {
    static SimulationEngine* instance = nullptr;
    if (instance) {
        // Update warp state
        WarpState& warp = instance->warp_states_[warp_id];
        warp.pc = pc + 4;
        warp.last_active = instance->current_time_;

        // Check for special instructions (e.g., branch, exit)
        bool is_branch = (instruction & 0x7F) == 0x63;  // RISC-V branch opcode
        bool is_exit = (instruction & 0x7F) == 0x73;    // RISC-V system opcode

        if (is_exit) {
            instance->schedule_event(EventType::WARP_COMPLETE, 1,
                reinterpret_cast<void*>(static_cast<uintptr_t>(warp_id)));
        } else {
            // Schedule next instruction fetch with appropriate delay
            SimTime delay = is_branch ? 3 : 1;  // Extra cycles for branch resolution
            instance->schedule_event(EventType::INSTRUCTION_FETCH, delay,
                reinterpret_cast<void*>(static_cast<uintptr_t>(warp_id)));
        }
    }
}

void SimulationEngine::check_simulation_state() const {
    // Verify warp states
    for (size_t i = 0; i < warp_states_.size(); ++i) {
        const auto& warp = warp_states_[i];
        assert(warp.pc % 4 == 0 && "PC must be aligned to 4 bytes");
        assert(warp.thread_mask != 0 || !warp.active && "Inactive warp must have zero thread mask");
    }

    // Verify event queue
    assert(!event_queue_.empty() || !running_ && "Event queue cannot be empty while running");

    // Verify memory model state
    memory_model_->verify_state();
}

void SimulationEngine::verify_memory_consistency() const {
    // Track all memory writes
    struct MemoryWrite {
        uint32_t address;
        uint32_t data;
        SimTime time;
    };
    std::vector<MemoryWrite> writes;

    // Extract memory writes from trace
    for (const auto& entry : simulation_trace_) {
        if (entry.type == EventType::MEMORY_REQUEST) {
            writes.push_back({entry.address, entry.data, entry.time});
        }
    }

    // Verify read-after-write ordering
    for (const auto& entry : simulation_trace_) {
        if (entry.type == EventType::MEMORY_RESPONSE) {
            // Find last write to this address
            auto it = std::find_if(writes.rbegin(), writes.rend(),
                [&](const MemoryWrite& w) {
                    return w.address == entry.address && w.time < entry.time;
                });

            if (it != writes.rend()) {
                assert(entry.data == it->data && 
                       "Memory read must reflect most recent write");
            }
        }
    }
}

void SimulationEngine::stop() {
    running_ = false;
    calculate_performance_metrics();
}

bool SimulationEngine::is_running() const {
    return running_;
}

} // namespace gpu_simulator