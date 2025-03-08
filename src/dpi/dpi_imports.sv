// dpi_imports.sv
// SystemVerilog DPI import declarations for GPU simulator

package dpi_import_pkg;

  // DPI type definitions matching C++ structures
  typedef struct packed {
    logic [31:0] address;
    logic [31:0] data;
    logic        is_write;
    logic [31:0] size;
    logic [31:0] warp_id;
    logic [31:0] thread_mask;
  } MemoryTransactionDPI;

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] instruction;
    logic [31:0] warp_id;
    logic [31:0] thread_mask;
  } InstructionDPI;

  typedef struct packed {
    logic [63:0] hits;
    logic [63:0] misses;
    logic [63:0] evictions;
    logic [63:0] bank_conflicts;
  } CacheStatsDPI;

  typedef struct packed {
    logic [31:0] pc;
    logic [31:0] thread_mask;
    logic        active;
    logic [63:0] last_active_cycle;
  } WarpStateDPI;

  typedef struct packed {
    logic [31:0] num_warps;
    logic [31:0] threads_per_warp;
    logic [31:0] cache_size;
    logic [31:0] cache_line_size;
    logic [31:0] memory_latency;
  } ConfigDPI;

  typedef struct packed {
    logic [63:0] instructions_executed;
    logic [63:0] memory_requests;
    logic [63:0] cache_hits;
    logic [63:0] stall_cycles;
  } PerformanceCountersDPI;

  // DPI-C import declarations
  import "DPI-C" function int initialize_simulator(input ConfigDPI config);
  import "DPI-C" function void cleanup_simulator();

  // Memory interface
  import "DPI-C" function int process_memory_request(input MemoryTransactionDPI transaction);
  import "DPI-C" function int get_memory_response(output logic [31:0] data);

  // Instruction interface
  import "DPI-C" function int process_instruction(input InstructionDPI instruction);
  import "DPI-C" function int get_next_instruction(input logic [31:0] warp_id, output InstructionDPI instruction);

  // Warp management
  import "DPI-C" function int update_warp_state(input logic [31:0] warp_id, input WarpStateDPI state);
  import "DPI-C" function int get_warp_state(input logic [31:0] warp_id, output WarpStateDPI state);

  // Statistics
  import "DPI-C" function int get_cache_stats(output CacheStatsDPI stats);
  import "DPI-C" function int get_performance_counters(output PerformanceCountersDPI counters);
  import "DPI-C" function void print_statistics();

  // Error code definitions
  typedef enum int {
    SUCCESS = 0,
    INVALID_ADDRESS = -1,
    INVALID_WARP = -2,
    INVALID_THREAD = -3,
    MEMORY_ERROR = -4,
    SIMULATION_ERROR = -5
  } DPIError;

  // Helper functions
  function automatic string get_error_string(int error_code);
    case (error_code)
      SUCCESS:           return "Success";
      INVALID_ADDRESS:   return "Invalid address";
      INVALID_WARP:      return "Invalid warp ID";
      INVALID_THREAD:    return "Invalid thread ID";
      MEMORY_ERROR:      return "Memory error";
      SIMULATION_ERROR:  return "Simulation error";
      default:           return $sformatf("Unknown error: %0d", error_code);
    endcase
  endfunction

  // Simplified memory request helper function
  function automatic int memory_request(
    input logic [31:0] address,
    input logic [31:0] data,
    input logic        is_write,
    input logic [31:0] warp_id,
    input logic [31:0] thread_mask
  );
    MemoryTransactionDPI transaction;
    transaction.address = address;
    transaction.data = data;
    transaction.is_write = is_write;
    transaction.size = 4; // Default to 4-byte access
    transaction.warp_id = warp_id;
    transaction.thread_mask = thread_mask;
    return process_memory_request(transaction);
  endfunction

  // Simplified instruction processing helper function
  function automatic int instruction_complete(
    input logic [31:0] pc,
    input logic [31:0] instruction,
    input logic [31:0] warp_id,
    input logic [31:0] thread_mask
  );
    InstructionDPI instr;
    instr.pc = pc;
    instr.instruction = instruction;
    instr.warp_id = warp_id;
    instr.thread_mask = thread_mask;
    return process_instruction(instr);
  endfunction

endpackage