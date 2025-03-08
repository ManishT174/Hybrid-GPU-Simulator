// memory_model.cpp
// Implementation of memory subsystem simulation

#include "memory_model.h"
#include <cassert>
#include <iostream>
#include <algorithm>
#include <cmath>
#include <iomanip>

namespace gpu_simulator {

MemoryModel::MemoryModel(uint32_t cache_size, uint32_t line_size, uint32_t memory_latency)
    : current_cycle_(0) {
    // Initialize configuration
    config_.total_size = cache_size;
    config_.line_size = line_size;
    config_.associativity = 8;  // 8-way set associative
    config_.num_banks = 8;      // 8 memory banks
    config_.memory_latency = memory_latency;

    // Calculate number of sets
    uint32_t num_sets = cache_size / (line_size * config_.associativity);
    sets_.reserve(num_sets);
    for (uint32_t i = 0; i < num_sets; ++i) {
        sets_.emplace_back(config_.associativity, config_.line_size);
    }

    // Initialize statistics
    stats_ = CacheStats{};

    // Reserve space for access history
    access_history_.reserve(MAX_HISTORY_SIZE);
}

MemoryModel::~MemoryModel() = default;

void MemoryModel::initialize() {
    // Clear cache state
    for (auto& set : sets_) {
        for (auto& way : set.ways) {
            way.valid = false;
            way.dirty = false;
            way.tag = 0;
            std::fill(way.data.begin(), way.data.end(), 0);
            way.last_access = 0;
        }
    }

    // Clear main memory
    main_memory_.clear();

    // Reset statistics
    stats_ = CacheStats{};
    current_cycle_ = 0;
    access_history_.clear();
}

uint64_t MemoryModel::process_request(uint32_t address, uint32_t data, bool is_write) {
    // Record access
    if (access_history_.size() < MAX_HISTORY_SIZE) {
        access_history_.push_back({address, data, is_write, current_cycle_});
    }

    // Update statistics
    if (is_write) {
        stats_.writes++;
    } else {
        stats_.reads++;
    }

    // Check alignment
    assert(check_alignment(address, 4) && "Memory access must be aligned");

    // Translate address
    uint32_t physical_address = translate_address(address);

    // Calculate set index and tag
    uint32_t set_index = get_set_index(physical_address);
    uint32_t tag = get_tag(physical_address);
    uint32_t offset = get_offset(physical_address);

    // Check cache
    CacheSet& set = sets_[set_index];
    bool hit = false;
    uint32_t hit_way = 0;

    for (uint32_t i = 0; i < config_.associativity; ++i) {
        if (set.ways[i].valid && set.ways[i].tag == tag) {
            hit = true;
            hit_way = i;
            break;
        }
    }

    // Update statistics
    if (hit) {
        stats_.hits++;
    } else {
        stats_.misses++;
    }

    // Calculate access latency
    uint32_t latency = calculate_access_latency(physical_address, hit);
    latency += check_bank_conflicts(physical_address);

    if (hit) {
        // Cache hit
        CacheLine& line = set.ways[hit_way];
        line.last_access = current_cycle_;

        if (is_write) {
            // Write hit
            line.data[offset/4] = data;
            line.dirty = true;
        } else {
            // Read hit
            data = line.data[offset/4];
        }
    } else {
        // Cache miss
        uint32_t victim_way = select_victim(set);
        CacheLine& victim = set.ways[victim_way];

        // Handle eviction if necessary
        if (victim.valid && victim.dirty) {
            // Write back dirty line
            uint32_t victim_address = (victim.tag << (32 - get_tag(0xFFFFFFFF))) | 
                                    (set_index << get_offset(0xFFFFFFFF));
            for (uint32_t i = 0; i < victim.data.size(); ++i) {
                main_memory_[victim_address + i*4] = victim.data[i];
            }
            stats_.evictions++;
        }

        // Load new line from memory
        uint32_t base_address = physical_address & ~(config_.line_size - 1);
        for (uint32_t i = 0; i < config_.line_size/4; ++i) {
            uint32_t addr = base_address + i*4;
            victim.data[i] = main_memory_[addr];
        }

        victim.tag = tag;
        victim.valid = true;
        victim.dirty = is_write;
        victim.last_access = current_cycle_;

        if (is_write) {
            victim.data[offset/4] = data;
        } else {
            data = victim.data[offset/4];
        }
    }

    // Handle cache coherence
    handle_coherence(physical_address);

    // Update cycle count
    current_cycle_ += latency;

    return current_cycle_;
}

uint32_t MemoryModel::read_instruction(uint32_t address) {
    uint32_t data;
    if (lookup_cache(address, data)) {
        return data;
    } else {
        // Instruction cache miss
        process_request(address, 0, false);
        lookup_cache(address, data);
        return data;
    }
}

bool MemoryModel::lookup_cache(uint32_t address, uint32_t& data) {
    uint32_t set_index = get_set_index(address);
    uint32_t tag = get_tag(address);
    uint32_t offset = get_offset(address);

    const CacheSet& set = sets_[set_index];
    for (const auto& way : set.ways) {
        if (way.valid && way.tag == tag) {
            data = way.data[offset/4];
            return true;
        }
    }
    return false;
}

void MemoryModel::update_cache(uint32_t address, uint32_t data) {
    uint32_t set_index = get_set_index(address);
    uint32_t tag = get_tag(address);
    uint32_t offset = get_offset(address);

    CacheSet& set = sets_[set_index];
    for (auto& way : set.ways) {
        if (way.valid && way.tag == tag) {
            way.data[offset/4] = data;
            way.dirty = true;
            way.last_access = current_cycle_;
            return;
        }
    }

    // If we get here, it's a cache miss
    process_request(address, data, true);
}

uint32_t MemoryModel::select_victim(const CacheSet& set) const {
    // First look for invalid lines
    for (uint32_t i = 0; i < config_.associativity; ++i) {
        if (!set.ways[i].valid) {
            return i;
        }
    }

    // If all valid, use LRU
    uint32_t lru_way = 0;
    uint64_t lru_time = set.ways[0].last_access;

    for (uint32_t i = 1; i < config_.associativity; ++i) {
        if (set.ways[i].last_access < lru_time) {
            lru_way = i;
            lru_time = set.ways[i].last_access;
        }
    }

    return lru_way;
}

uint32_t MemoryModel::calculate_access_latency(uint32_t address, bool is_hit) const {
    if (is_hit) {
        return 1;  // Cache hit latency
    } else {
        // Cache miss latency = memory latency + transfer time
        return config_.memory_latency + (config_.line_size / 16);  // Assuming 16B/cycle transfer
    }
}

uint32_t MemoryModel::check_bank_conflicts(uint32_t address) const {
    uint32_t bank = get_bank_index(address);
    // Simple bank conflict model - could be made more sophisticated
    return 0;  // For now, assume no conflicts
}

uint32_t MemoryModel::get_set_index(uint32_t address) const {
    uint32_t num_sets = config_.total_size / (config_.line_size * config_.associativity);
    uint32_t set_bits = static_cast<uint32_t>(std::log2(num_sets));
    uint32_t offset_bits = static_cast<uint32_t>(std::log2(config_.line_size));
    return (address >> offset_bits) & ((1 << set_bits) - 1);
}

uint32_t MemoryModel::get_tag(uint32_t address) const {
    uint32_t num_sets = config_.total_size / (config_.line_size * config_.associativity);
    uint32_t set_bits = static_cast<uint32_t>(std::log2(num_sets));
    uint32_t offset_bits = static_cast<uint32_t>(std::log2(config_.line_size));
    return address >> (offset_bits + set_bits);
}

uint32_t MemoryModel::get_offset(uint32_t address) const {
    return address & (config_.line_size - 1);
}

uint32_t MemoryModel::get_bank_index(uint32_t address) const {
    return (address >> 2) % config_.num_banks;  // Assuming 4-byte interleaving
}

std::pair<uint64_t, uint64_t> MemoryModel::get_cache_stats() const {
    return {stats_.hits, stats_.misses};
}

void MemoryModel::print_cache_state() const {
    std::cout << "\nCache State:\n";
    std::cout << "============\n";
    std::cout << "Configuration:\n";
    std::cout << "  Size: " << config_.total_size << " bytes\n";
    std::cout << "  Line Size: " << config_.line_size << " bytes\n";
    std::cout << "  Associativity: " << config_.associativity << "-way\n";
    std::cout << "  Number of Banks: " << config_.num_banks << "\n\n";

    std::cout << "Statistics:\n";
    std::cout << "  Reads: " << stats_.reads << "\n";
    std::cout << "  Writes: " << stats_.writes << "\n";
    std::cout << "  Hits: " << stats_.hits << "\n";
    std::cout << "  Misses: " << stats_.misses << "\n";
    std::cout << "  Evictions: " << stats_.evictions << "\n";
    std::cout << "  Bank Conflicts: " << stats_.bank_conflicts << "\n";

    double hit_rate = static_cast<double>(stats_.hits) / 
                     static_cast<double>(stats_.hits + stats_.misses);
    std::cout << "  Hit Rate: " << std::fixed << std::setprecision(2) 
              << (hit_rate * 100.0) << "%\n\n";

    // Print detailed cache line state (limited to avoid overwhelming output)
    std::cout << "Cache Line State (first 4 sets):\n";
    for (uint32_t i = 0; i < std::min(4u, static_cast<uint32_t>(sets_.size())); ++i) {
        std::cout << "Set " << i << ":\n";
        for (uint32_t j = 0; j < config_.associativity; ++j) {
            const CacheLine& line = sets_[i].ways[j];
            std::cout << "  Way " << j << ": ";
            if (line.valid) {
                std::cout << "Valid, Tag: 0x" << std::hex << line.tag
                         << ", Dirty: " << (line.dirty ? "Yes" : "No")
                         << ", Last Access: " << std::dec << line.last_access << "\n";
            } else {
                std::cout << "Invalid\n";
            }
        }
    }
}

void MemoryModel::verify_state() const {
    // Verify configuration
    assert(config_.total_size > 0 && "Cache size must be positive");
    assert(config_.line_size > 0 && "Cache line size must be positive");
    assert(config_.associativity > 0 && "Associativity must be positive");
    assert(config_.num_banks > 0 && "Number of banks must be positive");

    // Verify cache structure
    uint32_t expected_sets = config_.total_size / (config_.line_size * config_.associativity);
    assert(sets_.size() == expected_sets && "Incorrect number of cache sets");

    // Verify each cache line
    for (const auto& set : sets_) {
        assert(set.ways.size() == config_.associativity && "Incorrect number of ways");
        for (const auto& way : set.ways) {
            assert(way.data.size() == config_.line_size/4 && "Incorrect cache line size");
            if (!way.valid) {
                assert(!way.dirty && "Invalid line cannot be dirty");
            }
        }
    }

    // Verify access history
    assert(access_history_.size() <= MAX_HISTORY_SIZE && "Access history overflow");

    // Verify statistics consistency
    assert(stats_.hits + stats_.misses == stats_.reads + stats_.writes && 
           "Hit/miss count mismatch with access count");
}

uint32_t MemoryModel::translate_address(uint32_t address) const {
    // For now, implement a simple identity mapping
    // Could be extended to implement virtual memory translation
    return address;
}

bool MemoryModel::check_alignment(uint32_t address, uint32_t size) const {
    return (address % size) == 0;
}

void MemoryModel::handle_coherence(uint32_t address) {
    // For now, implement a simple invalidation-based protocol
    uint32_t set_index = get_set_index(address);
    uint32_t tag = get_tag(address);

    // Check other cache lines that might have this address
    for (auto& set : sets_) {
        for (auto& way : set.ways) {
            if (way.valid && way.tag == tag) {
                // In a more sophisticated implementation, we would:
                // 1. Send invalidation messages to other caches
                // 2. Wait for acknowledgments
                // 3. Handle different coherence states (MESI/MOESI)
                // For now, just mark as dirty
                way.dirty = true;
            }
        }
    }
}

void MemoryModel::invalidate_cache_line(uint32_t address) {
    uint32_t set_index = get_set_index(address);
    uint32_t tag = get_tag(address);

    CacheSet& set = sets_[set_index];
    for (auto& way : set.ways) {
        if (way.valid && way.tag == tag) {
            if (way.dirty) {
                // Write back dirty data before invalidating
                uint32_t base_address = (way.tag << (32 - get_tag(0xFFFFFFFF))) | 
                                      (set_index << get_offset(0xFFFFFFFF));
                for (uint32_t i = 0; i < way.data.size(); ++i) {
                    main_memory_[base_address + i*4] = way.data[i];
                }
            }
            way.valid = false;
            way.dirty = false;
        }
    }
}

void MemoryModel::evict_cache_line(uint32_t set_index, uint32_t way) {
    assert(set_index < sets_.size() && "Invalid set index");
    assert(way < config_.associativity && "Invalid way index");

    CacheLine& line = sets_[set_index].ways[way];
    if (line.valid && line.dirty) {
        // Write back dirty data
        uint32_t base_address = (line.tag << (32 - get_tag(0xFFFFFFFF))) | 
                               (set_index << get_offset(0xFFFFFFFF));
        for (uint32_t i = 0; i < line.data.size(); ++i) {
            main_memory_[base_address + i*4] = line.data[i];
        }
    }

    // Invalidate the line
    line.valid = false;
    line.dirty = false;
    stats_.evictions++;
}

} // namespace gpu_simulator