// memory_model.h
// Memory subsystem simulation for GPU simulator

#pragma once

#include <cstdint>
#include <vector>
#include <unordered_map>
#include <utility>
#include <memory>

namespace gpu_simulator {

// Forward declarations
class CacheLine;
class CacheSet;

// Cache configuration and statistics
struct CacheConfig {
    uint32_t total_size;        // Total cache size in bytes
    uint32_t line_size;         // Cache line size in bytes
    uint32_t associativity;     // Number of ways
    uint32_t num_banks;         // Number of memory banks
    uint32_t memory_latency;    // DRAM access latency in cycles
};

struct CacheStats {
    uint64_t reads;
    uint64_t writes;
    uint64_t hits;
    uint64_t misses;
    uint64_t evictions;
    uint64_t bank_conflicts;
};

// Memory access result
struct MemoryResult {
    bool hit;
    uint32_t latency;
    uint32_t data;
};

class MemoryModel {
public:
    // Constructor and destructor
    MemoryModel(uint32_t cache_size, uint32_t line_size, uint32_t memory_latency);
    ~MemoryModel();

    // Delete copy constructor and assignment
    MemoryModel(const MemoryModel&) = delete;
    MemoryModel& operator=(const MemoryModel&) = delete;

    // Core memory operations
    void initialize();
    uint64_t process_request(uint32_t address, uint32_t data, bool is_write);
    uint32_t read_instruction(uint32_t address);

    // Cache management
    bool lookup_cache(uint32_t address, uint32_t& data);
    void update_cache(uint32_t address, uint32_t data);
    void evict_cache_line(uint32_t set_index, uint32_t way);

    // Statistics and monitoring
    std::pair<uint64_t, uint64_t> get_cache_stats() const;
    void print_cache_state() const;
    void verify_state() const;

private:
    // Cache organization
    struct CacheLine {
        uint32_t tag;
        std::vector<uint32_t> data;
        bool valid;
        bool dirty;
        uint64_t last_access;

        CacheLine(uint32_t line_size_bytes) 
            : tag(0), data(line_size_bytes/4, 0), 
              valid(false), dirty(false), last_access(0) {}
    };

    struct CacheSet {
        std::vector<CacheLine> ways;
        
        CacheSet(uint32_t associativity, uint32_t line_size_bytes) {
            ways.reserve(associativity);
            for (uint32_t i = 0; i < associativity; ++i) {
                ways.emplace_back(line_size_bytes);
            }
        }
    };

    // Configuration
    CacheConfig config_;
    
    // Cache structure
    std::vector<CacheSet> sets_;
    
    // Main memory simulation
    std::unordered_map<uint32_t, uint32_t> main_memory_;
    
    // Statistics
    CacheStats stats_;
    uint64_t current_cycle_;

    // Internal methods
    uint32_t get_set_index(uint32_t address) const;
    uint32_t get_tag(uint32_t address) const;
    uint32_t get_offset(uint32_t address) const;
    uint32_t get_bank_index(uint32_t address) const;
    
    // Replacement policy
    uint32_t select_victim(const CacheSet& set) const;
    
    // Memory timing
    uint32_t calculate_access_latency(uint32_t address, bool is_hit) const;
    uint32_t check_bank_conflicts(uint32_t address) const;

    // Address translation
    uint32_t translate_address(uint32_t address) const;
    bool check_alignment(uint32_t address, uint32_t size) const;

    // Cache coherence
    void handle_coherence(uint32_t address);
    void invalidate_cache_line(uint32_t address);

    // Debug support
    struct MemoryAccess {
        uint32_t address;
        uint32_t data;
        bool is_write;
        uint64_t cycle;
    };
    std::vector<MemoryAccess> access_history_;
    static constexpr size_t MAX_HISTORY_SIZE = 1000;
};

} // namespace gpu_simulator