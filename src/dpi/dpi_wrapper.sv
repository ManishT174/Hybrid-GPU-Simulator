// dpi_wrapper.sv
// SystemVerilog wrapper for DPI-C interface

module dpi_wrapper #(
  parameter int NUM_WARPS = 32,
  parameter int THREADS_PER_WARP = 32,
  parameter int CACHE_SIZE = 16384,
  parameter int CACHE_LINE_SIZE = 128,
  parameter int MEMORY_LATENCY = 100
)(
  input  logic        clk,
  input  logic        rst_n,
  
  // Memory interface
  input  logic [31:0] mem_address,
  input  logic [31:0] mem_write_data,
  input  logic        mem_write_en,
  input  logic [5:0]  mem_warp_id,
  input  logic [31:0] mem_thread_mask,
  input  logic        mem_request_valid,
  output logic [31:0] mem_read_data,
  output logic        mem_response_valid,
  output logic        mem_ready,
  
  // Instruction interface
  input  logic [31:0] pc,
  input  logic [31:0] instruction,
  input  logic [5:0]  instruction_warp_id,
  input  logic [31:0] instruction_thread_mask,
  input  logic        instruction_valid,
  output logic [31:0] next_instruction,
  output logic [31:0] next_pc,
  output logic        instruction_ready,
  
  // Debug interface
  input  logic        print_stats,
  output logic [31:0] perf_instructions,
  output logic [31:0] perf_mem_requests,
  output logic [31:0] perf_cache_hits,
  output logic [31:0] perf_stalls
);

  import dpi_import_pkg::*;
  
  // Local variables
  logic initialized;
  logic mem_req_pending;
  logic init_error;
  
  // Initialize simulator on reset
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ConfigDPI config;
      int error_code;
      
      config.num_warps = NUM_WARPS;
      config.threads_per_warp = THREADS_PER_WARP;
      config.cache_size = CACHE_SIZE;
      config.cache_line_size = CACHE_LINE_SIZE;
      config.memory_latency = MEMORY_LATENCY;
      
      error_code = initialize_simulator(config);
      init_error = (error_code != 0);
      initialized = !init_error;
      
      if (init_error) begin
        $display("Error initializing simulator: %s", get_error_string(error_code));
      end
      
      mem_req_pending = 0;
      mem_response_valid = 0;
      instruction_ready = 0;
    end
  end
  
  // Memory request handling
  always_ff @(posedge clk) begin
    if (rst_n && initialized) begin
      if (mem_request_valid && !mem_req_pending) begin
        int error_code;
        
        error_code = memory_request(
          mem_address,
          mem_write_data,
          mem_write_en,
          mem_warp_id,
          mem_thread_mask
        );
        
        if (error_code == 0) begin
          mem_req_pending = !mem_write_en;  // Only wait for response on reads
          mem_ready = 1;
        end else begin
          $display("Memory request error: %s", get_error_string(error_code));
          mem_ready = 0;
        end
      end
      
      // Check for memory response
      if (mem_req_pending) begin
        int error_code;
        logic [31:0] data;
        
        error_code = get_memory_response(data);
        if (error_code == 0) begin
          mem_read_data = data;
          mem_response_valid = 1;
          mem_req_pending = 0;
        end else begin
          mem_response_valid = 0;
        end
      end else begin
        mem_response_valid = 0;
      end
    end
  end
  
  // Instruction handling
  always_ff @(posedge clk) begin
    if (rst_n && initialized) begin
      if (instruction_valid) begin
        int error_code;
        
        error_code = instruction_complete(
          pc,
          instruction,
          instruction_warp_id,
          instruction_thread_mask
        );
        
        if (error_code == 0) begin
          instruction_ready = 1;
        end else begin
          $display("Instruction processing error: %s", get_error_string(error_code));
          instruction_ready = 0;
        end
      end
      
      // Fetch next instruction
      if (instruction_ready) begin
        int error_code;
        InstructionDPI next_instr;
        
        error_code = get_next_instruction(instruction_warp_id, next_instr);
        if (error_code == 0) begin
          next_instruction = next_instr.instruction;
          next_pc = next_instr.pc;
        end
      end
    end
  end
  
  // Statistics handling
  always_ff @(posedge clk) begin
    if (rst_n && initialized) begin
      if (print_stats) begin
        print_statistics();
      end
      
      // Update performance counters
      PerformanceCountersDPI counters;
      int error_code;
      
      error_code = get_performance_counters(counters);
      if (error_code == 0) begin
        perf_instructions = counters.instructions_executed[31:0];
        perf_mem_requests = counters.memory_requests[31:0];
        perf_cache_hits = counters.cache_hits[31:0];
        perf_stalls = counters.stall_cycles[31:0];
      end
    end
  end
  
  // Cleanup on simulation end
  final begin
    if (initialized) begin
      cleanup_simulator();
    end
  end

endmodule