// memory_controller.sv
// Memory controller implementation for GPU simulator
// Handles memory access coalescing and cache management

package memory_types;
  typedef struct packed {
    logic [31:0] address;
    logic [31:0] data;
    logic [31:0] mask;
    logic        write_en;
    logic [5:0]  warp_id;
    logic [31:0] thread_mask;
  } memory_request_t;

  typedef enum logic [2:0] {
    IDLE          = 3'b000,
    COALESCING    = 3'b001,
    CACHE_CHECK   = 3'b010,
    MEMORY_ACCESS = 3'b011,
    WRITEBACK     = 3'b100
  } mem_state_e;
endpackage

import memory_types::*;

module memory_controller #(
  parameter int CACHE_SIZE      = 16384,  // 16KB cache
  parameter int CACHE_LINE_SIZE = 128,    // 128B cache lines
  parameter int NUM_BANKS       = 8,
  parameter int THREADS_PER_WARP = 32
)(
  input  logic        clk,
  input  logic        rst_n,

  // Execution unit interface
  input  logic [31:0] exec_address [THREADS_PER_WARP-1:0],
  input  logic [31:0] exec_write_data [THREADS_PER_WARP-1:0],
  input  logic [31:0] exec_thread_mask,
  input  logic        exec_write_en,
  input  logic [5:0]  exec_warp_id,
  input  logic        exec_request_valid,
  output logic [31:0] exec_read_data [THREADS_PER_WARP-1:0],
  output logic        exec_ready,

  // External memory interface (to DPI-C)
  output logic [31:0] mem_address,
  output logic [31:0] mem_write_data,
  output logic        mem_write_en,
  output logic        mem_request_valid,
  input  logic [31:0] mem_read_data,
  input  logic        mem_ready
);

  // Cache structure
  logic [31:0] cache_data   [CACHE_SIZE/4-1:0];
  logic [31:0] cache_tags   [CACHE_SIZE/CACHE_LINE_SIZE-1:0];
  logic        cache_valid  [CACHE_SIZE/CACHE_LINE_SIZE-1:0];
  logic        cache_dirty  [CACHE_SIZE/CACHE_LINE_SIZE-1:0];

  // Memory request queue
  memory_request_t request_queue [$];
  memory_request_t current_request;
  
  // State machine
  mem_state_e current_state;
  mem_state_e next_state;

  // Coalescing buffer
  logic [31:0] coalesced_addresses [THREADS_PER_WARP-1:0];
  logic [31:0] coalesced_data [THREADS_PER_WARP-1:0];
  logic [THREADS_PER_WARP-1:0] coalesced_mask;
  
  // Cache management functions
  function automatic logic [31:0] get_cache_index(logic [31:0] address);
    return (address[13:7]); // For 16KB cache with 128B lines
  endfunction

  function automatic logic [31:0] get_cache_tag(logic [31:0] address);
    return address[31:14];
  endfunction

  // Coalescing logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      coalesced_mask <= '0;
    end else if (current_state == COALESCING && exec_request_valid) begin
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        if (exec_thread_mask[i]) begin
          // Check if address can be coalesced
          logic can_coalesce;
          can_coalesce = 0;
          
          for (int j = 0; j < i; j++) begin
            if (coalesced_mask[j] && 
                (exec_address[i][31:2] == coalesced_addresses[j][31:2])) begin
              can_coalesce = 1;
              break;
            end
          end
          
          if (!can_coalesce) begin
            coalesced_addresses[i] <= exec_address[i];
            coalesced_data[i] <= exec_write_data[i];
            coalesced_mask[i] <= 1'b1;
          end
        end
      end
    end
  end

  // Cache control logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < CACHE_SIZE/CACHE_LINE_SIZE; i++) begin
        cache_valid[i] <= 1'b0;
        cache_dirty[i] <= 1'b0;
        cache_tags[i] <= '0;
      end
      current_state <= IDLE;
    end else begin
      current_state <= next_state;
      
      case (current_state)
        CACHE_CHECK: begin
          // Check cache hit/miss
          logic [31:0] index = get_cache_index(current_request.address);
          logic [31:0] tag = get_cache_tag(current_request.address);
          
          if (cache_valid[index] && cache_tags[index] == tag) begin
            // Cache hit
            if (current_request.write_en) begin
              cache_data[index] <= current_request.data;
              cache_dirty[index] <= 1'b1;
            end else begin
              exec_read_data[0] <= cache_data[index];
            end
          end
        end
        
        MEMORY_ACCESS: begin
          if (mem_ready) begin
            logic [31:0] index = get_cache_index(current_request.address);
            cache_data[index] <= mem_read_data;
            cache_valid[index] <= 1'b1;
            cache_dirty[index] <= current_request.write_en;
            cache_tags[index] <= get_cache_tag(current_request.address);
          end
        end
      endcase
    end
  end

  // State machine transitions
  always_comb begin
    next_state = current_state;
    
    case (current_state)
      IDLE: begin
        if (exec_request_valid)
          next_state = COALESCING;
      end
      
      COALESCING: begin
        if (!exec_request_valid)
          next_state = CACHE_CHECK;
      end
      
      CACHE_CHECK: begin
        logic [31:0] index = get_cache_index(current_request.address);
        logic [31:0] tag = get_cache_tag(current_request.address);
        
        if (!cache_valid[index] || cache_tags[index] != tag) begin
          if (cache_dirty[index])
            next_state = WRITEBACK;
          else
            next_state = MEMORY_ACCESS;
        end else begin
          next_state = IDLE;
        end
      end
      
      WRITEBACK: begin
        if (mem_ready)
          next_state = MEMORY_ACCESS;
      end
      
      MEMORY_ACCESS: begin
        if (mem_ready)
          next_state = IDLE;
      end
    endcase
  end

  // Output assignments
  assign exec_ready = (current_state == IDLE);
  
  // Performance counters
  logic [31:0] cache_hits;
  logic [31:0] cache_misses;
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cache_hits <= '0;
      cache_misses <= '0;
    end else if (current_state == CACHE_CHECK) begin
      logic [31:0] index = get_cache_index(current_request.address);
      logic [31:0] tag = get_cache_tag(current_request.address);
      
      if (cache_valid[index] && cache_tags[index] == tag)
        cache_hits <= cache_hits + 1;
      else
        cache_misses <= cache_misses + 1;
    end
  end

endmodule