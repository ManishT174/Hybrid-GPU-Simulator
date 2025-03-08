// sim_engine.h
// High-level simulation engine for GPU simulator

#pragma once

#include <vector>
#include <queue>
#include <memory>
#include <functional>
#include <unordered_map>
#include <string>
#include "memory_model.h"

namespace gpu_simulator {

// Forward declarations
class MemoryModel;

// Simulation time
using SimTime = uint64_t;

// Memory transaction types
struct MemoryTransaction {
    uint32_t address;
    uint32_t data;
    bool     is_write;
    uint32_t size;
    uint32_t warp_id;
    uint32_t thread_mask;
};

// Event types for simulation
enum class EventType {
    MEMORY_REQUEST,
    MEMORY_RESPONSE,
    INSTRUCTION_FETCH,
    WARP_COMPLETE,
    SIMULATION_END
};

// Simulation event structure
struct SimEvent {
    EventType type;
    SimTime   time;
    void*     data;
    
    // Comparison operator for priority queue
    bool operator>(const SimEvent& other) const {
        return time > other.time;
    }
};

// Configuration structure
struct SimConfig {
    uint32_t num_warps;
    uint32_t threads_per_warp;
    uint32_t cache_size;
    uint32_t cache_line_size;
    uint32_t memory_latency;
    std::string trace_file;
};

// Statistics collection
struct SimStats {
    uint64_t total_cycles;
    uint64_t instructions_executed;
    uint64_t memory_requests;
    uint64_t cache_hits;
    uint64_t cache_misses;
    double   ipc;
    double   cache_hit_rate;
};

class SimulationEngine {
public:
    // Constructor and destructor
    explicit SimulationEngine(const SimConfig& config);
    ~SimulationEngine();

    // Delete copy constructor and assignment
    SimulationEngine(const SimulationEngine&) = delete;
    SimulationEngine& operator=(const SimulationEngine&) = delete;

    // Core simulation methods
    void initialize();
    void run();
    void stop();
    bool is_running() const;

    // Event management
    void schedule_event(EventType type, SimTime delay, void* data = nullptr);
    void process_event(const SimEvent& event);

    // DPI-C interface methods
    static void memory_request_callback(uint32_t address, uint32_t data, 
                                      bool is_write, uint32_t warp_id, 
                                      uint32_t thread_mask);
    static void instruction_complete_callback(uint32_t warp_id, 
                                           uint32_t pc, 
                                           uint32_t instruction);

    // Statistics and reporting
    SimStats get_statistics() const;
    void print_statistics() const;
    void dump_trace(const std::string& filename) const;

private:
    // Internal state
    SimConfig config_;
    SimStats stats_;
    bool running_;
    SimTime current_time_;

    // Event queue
    std::priority_queue<SimEvent, std::vector<SimEvent>, 
                       std::greater<SimEvent>> event_queue_;

    // Memory subsystem
    std::unique_ptr<MemoryModel> memory_model_;

    // Warp state tracking
    struct WarpState {
        uint32_t pc;
        uint32_t thread_mask;
        bool     active;
        SimTime  last_active;
    };
    std::vector<WarpState> warp_states_;

    // Internal methods
    void process_memory_request(const MemoryTransaction* trans);
    void process_memory_response(const MemoryTransaction* trans);
    void process_instruction_fetch(uint32_t warp_id);
    void process_warp_complete(uint32_t warp_id);

    // Statistics tracking
    void update_statistics();
    void calculate_performance_metrics();

    // Trace management
    struct TraceEntry {
        SimTime   time;
        EventType type;
        uint32_t  warp_id;
        uint32_t  address;
        uint32_t  data;
    };
    std::vector<TraceEntry> simulation_trace_;

    // Debug and verification
    void check_simulation_state() const;
    void verify_memory_consistency() const;
    void log_event(const SimEvent& event);

    // Performance optimization
    static constexpr size_t EVENT_QUEUE_RESERVE_SIZE = 1024;
    static constexpr size_t TRACE_RESERVE_SIZE = 10000;
};

} // namespace gpu_simulator