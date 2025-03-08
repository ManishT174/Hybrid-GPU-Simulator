// shared_memory.sv
// Shared memory implementation for GPU simulator

package shared_mem_types;
  typedef struct packed {
    logic [31:0] address;
    logic [31:0] data;
    logic [3:0]  byte_enable;
    logic        write_en;
    logic [5:0]  warp_id;
    logic [31:0] thread_mask;
    logic [4:0]  bank_id;
  } shared_mem_request_t;

  typedef enum logic [2:0] {
    IDLE        = 3'b000,
    ARBITRATE   = 3'b001,
    ACCESS      = 3'b010,
    BROADCAST   = 3'b011,
    BANK_CONF   = 3'b100
  } shared_mem_state_e;
endpackage

import shared_mem_types::*;

module shared_memory #(
  parameter int SHARED_MEM_SIZE = 16384,  // 16KB shared memory
  parameter int NUM_BANKS       = 32,      // 32 banks
  parameter int THREADS_PER_WARP = 32,
  parameter int MAX_WARPS       = 32
)(
  input  logic        clk,
  input  logic        rst_n,

  // Execution unit interface - request channel
  input  logic [31:0] req_address [THREADS_PER_WARP-1:0],
  input  logic [31:0] req_write_data [THREADS_PER_WARP-1:0],
  input  logic [3:0]  req_byte_enable [THREADS_PER_WARP-1:0],
  input  logic [31:0] req_thread_mask,
  input  logic        req_write_en,
  input  logic [5:0]  req_warp_id,
  input  logic        req_valid,
  output logic        req_ready,

  // Execution unit interface - response channel
  output logic [31:0] resp_read_data [THREADS_PER_WARP-1:0],
  output logic [31:0] resp_thread_mask,
  output logic [5:0]  resp_warp_id,
  output logic        resp_valid,
  input  logic        resp_ready,

  // Performance counters
  output logic [31:0] bank_conflict_count,
  output logic [31:0] access_count
);

  // Bank width calculation (e.g., for 16KB shared memory with 32 banks, each bank is 512B)
  localparam int BANK_SIZE = SHARED_MEM_SIZE / NUM_BANKS;
  localparam int BANK_ADDR_WIDTH = $clog2(BANK_SIZE);
  localparam int SHARED_MEM_ADDR_WIDTH = $clog2(SHARED_MEM_SIZE);
  
  // Memory arrays for each bank (4-byte aligned)
  logic [31:0] mem_banks [NUM_BANKS-1:0][BANK_SIZE/4-1:0];
  
  // Bank access tracking
  logic [NUM_BANKS-1:0] bank_accessed;
  logic [NUM_BANKS-1:0] bank_conflict;
  logic [4:0]          bank_id [THREADS_PER_WARP-1:0];
  logic [BANK_ADDR_WIDTH-3:0] bank_addr [THREADS_PER_WARP-1:0];
  
  // Request queue for handling bank conflicts
  shared_mem_request_t request_queue [$];
  shared_mem_request_t current_request;
  
  // State machine
  shared_mem_state_e current_state;
  shared_mem_state_e next_state;

  // Responses
  logic [31:0] thread_resp_data [THREADS_PER_WARP-1:0];
  logic [31:0] resp_mask;
  logic [5:0]  resp_id;
  logic        resp_v;

  // Function to calculate bank ID and address from global address
  function automatic void calculate_bank_addr(input logic [31:0] address, 
                                            output logic [4:0] bank, 
                                            output logic [BANK_ADDR_WIDTH-3:0] addr);
    // For a simple implementation, the bank is determined by lower bits of the address
    // This is a basic version that can lead to bank conflicts with strided access
    
    // Calculate bank ID (low bits of address)
    bank = address[6:2];  // Assuming 4-byte words, this maps to bank
    
    // Calculate address within bank (higher bits of address)
    addr = address[SHARED_MEM_ADDR_WIDTH-1:7];
  endfunction

  // Bank conflict detection
  always_comb begin
    bank_accessed = '0;
    bank_conflict = '0;
    
    // For each active thread, check which banks are accessed
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (req_thread_mask[i]) begin
        calculate_bank_addr(req_address[i], bank_id[i], bank_addr[i]);
        
        // Mark this bank as accessed
        if (bank_accessed[bank_id[i]]) begin
          // Conflict if two threads access the same bank with different addresses
          if (bank_addr[i] != bank_addr[bank_id[i]]) begin
            bank_conflict[bank_id[i]] = 1'b1;
          end
        end else begin
          bank_accessed[bank_id[i]] = 1'b1;
        end
      end
    end
  end

  // State machine for memory access
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= IDLE;
      bank_conflict_count <= '0;
      access_count <= '0;
      resp_mask <= '0;
      resp_id <= '0;
      resp_v <= 1'b0;
      
      // Initialize memory (could be done differently in real hardware)
      for (int b = 0; b < NUM_BANKS; b++) begin
        for (int a = 0; a < BANK_SIZE/4; a++) begin
          mem_banks[b][a] <= '0;
        end
      end
    end else begin
      current_state <= next_state;
      
      case (current_state)
        IDLE: begin
          // Ready to accept new requests
          resp_v <= 1'b0;
        end
        
        ARBITRATE: begin
          // Process request queue or current request
          if (request_queue.size() > 0) begin
            current_request = request_queue.pop_front();
          end
          
          // Track access statistics
          access_count <= access_count + 1;
        end
        
        ACCESS: begin
          // Handle memory access for each thread
          for (int i = 0; i < THREADS_PER_WARP; i++) begin
            if (current_request.thread_mask[i]) begin
              // Calculate bank and address
              logic [4:0] bank;
              logic [BANK_ADDR_WIDTH-3:0] addr;
              calculate_bank_addr(req_address[i], bank, addr);
              
              if (current_request.write_en) begin
                // Write operation
                if (current_request.byte_enable[0]) mem_banks[bank][addr][7:0]   <= req_write_data[i][7:0];
                if (current_request.byte_enable[1]) mem_banks[bank][addr][15:8]  <= req_write_data[i][15:8];
                if (current_request.byte_enable[2]) mem_banks[bank][addr][23:16] <= req_write_data[i][23:16];
                if (current_request.byte_enable[3]) mem_banks[bank][addr][31:24] <= req_write_data[i][31:24];
              end else begin
                // Read operation
                thread_resp_data[i] <= mem_banks[bank][addr];
              end
            end
          end
          
          // Prepare response
          resp_mask <= current_request.thread_mask;
          resp_id <= current_request.warp_id;
          
          // Only set valid for read operations
          resp_v <= !current_request.write_en;
        end
        
        BANK_CONF: begin
          // Handle bank conflicts by serializing access
          bank_conflict_count <= bank_conflict_count + 1;
          
          // For simplicity, we'll just complete the access in the next cycle
          // In a real implementation, this would need more sophisticated logic
        end
        
        BROADCAST: begin
          // Broadcast data to all threads (for synchronized accesses)
          resp_v <= 1'b1;
        end
      endcase
    end
  end

  // Next state logic
  always_comb begin
    next_state = current_state;
    
    case (current_state)
      IDLE: begin
        if (req_valid && req_ready) begin
          next_state = ARBITRATE;
        end
      end
      
      ARBITRATE: begin
        if (|bank_conflict) begin
          next_state = BANK_CONF;
        end else begin
          next_state = ACCESS;
        end
      end
      
      ACCESS: begin
        next_state = BROADCAST;
      end
      
      BANK_CONF: begin
        next_state = ACCESS;
      end
      
      BROADCAST: begin
        if (resp_ready || !resp_v) begin
          next_state = IDLE;
        end
      end
    endcase
  end

  // Output assignments
  assign req_ready = (current_state == IDLE);
  assign resp_valid = resp_v;
  assign resp_read_data = thread_resp_data;
  assign resp_thread_mask = resp_mask;
  assign resp_warp_id = resp_id;

  // Debug interface (could be expanded)
  function automatic string get_state_name(shared_mem_state_e state);
    case (state)
      IDLE:      return "IDLE";
      ARBITRATE: return "ARBITRATE";
      ACCESS:    return "ACCESS";
      BROADCAST: return "BROADCAST";
      BANK_CONF: return "BANK_CONF";
      default:   return "UNKNOWN";
    endcase
  endfunction

endmodule