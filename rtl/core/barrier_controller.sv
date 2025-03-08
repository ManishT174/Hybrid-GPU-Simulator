// barrier_controller.sv
// Barrier synchronization controller for GPU simulator

package barrier_types;
  typedef struct packed {
    logic [15:0] barrier_id;    // Barrier identifier
    logic [31:0] thread_mask;   // Mask of threads participating in barrier
    logic [9:0]  block_id;      // Block identifier
    logic [5:0]  warp_id;       // Warp identifier
    logic        valid;         // Valid flag
  } barrier_request_t;

  typedef enum logic [2:0] {
    IDLE        = 3'b000,
    COLLECTING  = 3'b001,
    RELEASING   = 3'b010,
    TIMEOUT     = 3'b011,
    ERROR       = 3'b100
  } barrier_state_e;
endpackage

import barrier_types::*;

module barrier_controller #(
  parameter int MAX_BARRIERS   = 16,   // Maximum number of active barriers
  parameter int MAX_BLOCKS     = 32,   // Maximum number of thread blocks
  parameter int WARPS_PER_BLOCK = 32,  // Maximum warps per block
  parameter int THREADS_PER_WARP = 32  // Threads per warp
)(
  input  logic        clk,
  input  logic        rst_n,

  // Warp scheduler interface - barrier arrive
  input  logic [15:0] arrive_barrier_id,
  input  logic [31:0] arrive_thread_mask,
  input  logic [9:0]  arrive_block_id,
  input  logic [5:0]  arrive_warp_id,
  input  logic        arrive_valid,
  output logic        arrive_ready,

  // Warp scheduler interface - barrier release
  output logic [15:0] release_barrier_id,
  output logic [9:0]  release_block_id,
  output logic [WARPS_PER_BLOCK-1:0] release_warp_mask,
  output logic        release_valid,
  input  logic        release_ready,

  // Performance monitoring
  output logic [31:0] barrier_count,       // Total barriers executed
  output logic [31:0] stalled_cycle_count  // Cycles stalled at barriers
);

  // Barrier tracking structure
  typedef struct packed {
    logic [15:0] barrier_id;                       // Barrier identifier
    logic [9:0]  block_id;                         // Block identifier
    logic [WARPS_PER_BLOCK-1:0] arrived_warps;     // Warps that have arrived
    logic [WARPS_PER_BLOCK-1:0] expected_warps;    // Warps participating in barrier
    logic [31:0] thread_masks [WARPS_PER_BLOCK-1:0]; // Thread masks for each warp
    logic        active;                           // Barrier is active
    logic [31:0] cycle_counter;                    // Cycles spent in barrier
  } barrier_entry_t;

  // Barrier table
  barrier_entry_t barrier_table [MAX_BARRIERS-1:0];
  
  // State machine for each barrier
  barrier_state_e barrier_states [MAX_BARRIERS-1:0];
  
  // Free entry tracker
  logic [MAX_BARRIERS-1:0] barrier_free;
  
  // Barrier completion tracker
  logic [MAX_BARRIERS-1:0] barrier_complete;
  
  // Helper signals
  logic [15:0] release_barrier_id_next;
  logic [9:0]  release_block_id_next;
  logic [WARPS_PER_BLOCK-1:0] release_warp_mask_next;
  logic        release_valid_next;
  
  // Find a free barrier entry
  function automatic int find_free_barrier();
    for (int i = 0; i < MAX_BARRIERS; i++) begin
      if (barrier_free[i]) return i;
    end
    return -1;  // No free entries
  endfunction
  
  // Find an existing barrier entry
  function automatic int find_barrier(logic [15:0] barrier_id, logic [9:0] block_id);
    for (int i = 0; i < MAX_BARRIERS; i++) begin
      if (!barrier_free[i] && 
          barrier_table[i].active && 
          barrier_table[i].barrier_id == barrier_id &&
          barrier_table[i].block_id == block_id) begin
        return i;
      end
    end
    return -1;  // Not found
  endfunction
  
  // Check if all expected warps have arrived
  function automatic logic is_barrier_complete(int index);
    return (barrier_table[index].arrived_warps == barrier_table[index].expected_warps) &&
           (barrier_table[index].expected_warps != '0);
  endfunction

  // Main control logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset state
      barrier_free <= '1;  // All entries are free
      barrier_count <= '0;
      stalled_cycle_count <= '0;
      
      for (int i = 0; i < MAX_BARRIERS; i++) begin
        barrier_table[i].active <= 1'b0;
        barrier_table[i].arrived_warps <= '0;
        barrier_table[i].expected_warps <= '0;
        barrier_table[i].cycle_counter <= '0;
        barrier_states[i] <= IDLE;
      end
      
      release_barrier_id <= '0;
      release_block_id <= '0;
      release_warp_mask <= '0;
      release_valid <= 1'b0;
      
      release_barrier_id_next <= '0;
      release_block_id_next <= '0;
      release_warp_mask_next <= '0;
      release_valid_next <= 1'b0;
      
    end else begin
      // Default values
      arrive_ready <= 1'b1;  // Ready to accept new arrivals
      
      // Process barrier releases
      release_barrier_id <= release_barrier_id_next;
      release_block_id <= release_block_id_next;
      release_warp_mask <= release_warp_mask_next;
      release_valid <= release_valid_next;
      
      release_valid_next <= 1'b0;  // Default to no release
      
      // Handle barrier state machine for each entry
      for (int i = 0; i < MAX_BARRIERS; i++) begin
        if (!barrier_free[i] && barrier_table[i].active) begin
          case (barrier_states[i])
            IDLE: begin
              // Nothing to do in idle state
            end
            
            COLLECTING: begin
              // Count cycles spent in barrier
              barrier_table[i].cycle_counter <= barrier_table[i].cycle_counter + 1;
              stalled_cycle_count <= stalled_cycle_count + 1;
              
              // Check if all warps have arrived
              if (is_barrier_complete(i)) begin
                barrier_states[i] <= RELEASING;
                barrier_complete[i] <= 1'b1;
                
                // Prepare release signals
                release_barrier_id_next <= barrier_table[i].barrier_id;
                release_block_id_next <= barrier_table[i].block_id;
                release_warp_mask_next <= barrier_table[i].arrived_warps;
                release_valid_next <= 1'b1;
              end
            end
            
            RELEASING: begin
              // If release acknowledged, free the entry
              if (release_ready && release_valid && 
                  release_barrier_id == barrier_table[i].barrier_id &&
                  release_block_id == barrier_table[i].block_id) begin
                barrier_free[i] <= 1'b1;
                barrier_table[i].active <= 1'b0;
                barrier_states[i] <= IDLE;
                barrier_count <= barrier_count + 1;
                barrier_complete[i] <= 1'b0;
              end
            end
            
            TIMEOUT: begin
              // Handle timeout condition (could implement timeout policy here)
              barrier_states[i] <= RELEASING;
            end
            
            ERROR: begin
              // Handle error condition
              barrier_states[i] <= IDLE;
              barrier_free[i] <= 1'b1;
              barrier_table[i].active <= 1'b0;
            end
          endcase
        end
      end
      
      // Process new barrier arrivals
      if (arrive_valid && arrive_ready) begin
        int barrier_index = find_barrier(arrive_barrier_id, arrive_block_id);
        
        if (barrier_index >= 0) begin
          // Existing barrier
          int warp_position = arrive_warp_id;
          
          // Record this warp's arrival
          barrier_table[barrier_index].arrived_warps[warp_position] <= 1'b1;
          barrier_table[barrier_index].thread_masks[warp_position] <= arrive_thread_mask;
          
          // Check if this completes the barrier
          if (is_barrier_complete(barrier_index)) begin
            barrier_states[barrier_index] <= RELEASING;
            barrier_complete[barrier_index] <= 1'b1;
            
            // Prepare release signals
            release_barrier_id_next <= barrier_table[barrier_index].barrier_id;
            release_block_id_next <= barrier_table[barrier_index].block_id;
            release_warp_mask_next <= barrier_table[barrier_index].arrived_warps;
            release_valid_next <= 1'b1;
          end
        end else begin
          // New barrier or barrier not found
          int free_index = find_free_barrier();
          
          if (free_index >= 0) begin
            // Initialize new barrier entry
            barrier_free[free_index] <= 1'b0;
            barrier_table[free_index].barrier_id <= arrive_barrier_id;
            barrier_table[free_index].block_id <= arrive_block_id;
            barrier_table[free_index].arrived_warps <= '0;
            barrier_table[free_index].arrived_warps[arrive_warp_id] <= 1'b1;
            barrier_table[free_index].expected_warps <= '1;  // Assume all warps participate
            barrier_table[free_index].thread_masks[arrive_warp_id] <= arrive_thread_mask;
            barrier_table[free_index].active <= 1'b1;
            barrier_table[free_index].cycle_counter <= '0;
            barrier_states[free_index] <= COLLECTING;
          end else begin
            // No free barrier entries - this should not happen in normal operation
            // Could implement error handling or queue mechanism here
            arrive_ready <= 1'b0;
          end
        end
      end
    end
  end

  // Debug function to get state name
  function automatic string get_state_name(barrier_state_e state);
    case (state)
      IDLE:       return "IDLE";
      COLLECTING: return "COLLECTING";
      RELEASING:  return "RELEASING";
      TIMEOUT:    return "TIMEOUT";
      ERROR:      return "ERROR";
      default:    return "UNKNOWN";
    endcase
  endfunction

endmodule