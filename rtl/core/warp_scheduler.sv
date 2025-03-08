// warp_scheduler.sv - Updated version
// Warp scheduler implementation for GPU simulator with barrier support

package warp_types;
  typedef struct packed {
    logic [31:0] pc;           // Program counter
    logic [31:0] mask;         // Active thread mask
    logic [3:0]  state;        // Warp state (READY, STALLED, etc.)
    logic [5:0]  warp_id;      // Unique warp identifier
    logic        valid;        // Warp validity flag
  } warp_state_t;

  // Warp states
  typedef enum logic [3:0] {
    WARP_READY    = 4'b0001,
    WARP_STALLED  = 4'b0010,
    WARP_WAITING  = 4'b0100,
    WARP_FINISHED = 4'b1000
  } warp_state_e;
endpackage

import warp_types::*;

module warp_scheduler #(
  parameter int NUM_WARPS = 32,
  parameter int THREADS_PER_WARP = 32
)(
  input  logic clk,
  input  logic rst_n,
  
  // Interface with instruction buffer
  input  logic [31:0] instruction_in,
  input  logic        instruction_valid,
  output logic        instruction_ready,
  
  // Interface with execution unit
  output logic [31:0] instruction_out,
  output logic [31:0] thread_mask,
  output logic [5:0]  warp_id_out,
  output logic        warp_valid,
  input  logic        execution_ready,
  
  // Memory stall interface
  input  logic        memory_stall,
  input  logic [5:0]  stalled_warp_id,
  
  // Barrier interface
  input  logic        barrier_stall,
  input  logic [NUM_WARPS-1:0] barrier_warp_mask,
  input  logic        barrier_release_valid,
  input  logic [NUM_WARPS-1:0] barrier_release_warp_mask
);

  // Warp state storage
  warp_state_t warp_array [NUM_WARPS-1:0];
  logic [NUM_WARPS-1:0] warp_ready_mask;
  logic [5:0] current_warp;
  logic scheduling_active;

  // Round-robin scheduler state
  logic [5:0] rr_pointer;
  
  // Thread divergence handling
  logic [31:0] divergence_stack [NUM_WARPS-1:0][8-1:0]; // 8-level divergence stack
  logic [2:0]  stack_pointer [NUM_WARPS-1:0];           // Stack pointer for each warp

  // Barrier handling
  logic [NUM_WARPS-1:0] barrier_stall_mask;

  // Generate ready mask for scheduling
  always_comb begin
    for (int i = 0; i < NUM_WARPS; i++) begin
      warp_ready_mask[i] = (warp_array[i].state == WARP_READY) && 
                          warp_array[i].valid &&
                          !barrier_stall_mask[i]; // Not stalled at barrier
    end
  end

  // Round-robin warp selection
  always_comb begin
    logic found_warp;
    found_warp = 0;
    current_warp = '0;
    
    for (int i = 0; i < NUM_WARPS; i++) begin
      logic [5:0] idx = (rr_pointer + i) % NUM_WARPS;
      if (warp_ready_mask[idx] && !found_warp) begin
        current_warp = idx;
        found_warp = 1;
      end
    end
    
    scheduling_active = found_warp && execution_ready && !memory_stall;
  end

  // Update round-robin pointer
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr_pointer <= '0;
    end else if (scheduling_active) begin
      rr_pointer <= (current_warp + 1) % NUM_WARPS;
    end
  end

  // Warp state update logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NUM_WARPS; i++) begin
        warp_array[i] <= '{
          pc: '0,
          mask: '1,
          state: WARP_READY,
          warp_id: i[5:0],
          valid: 1'b1
        };
        stack_pointer[i] <= '0;
        for (int j = 0; j < 8; j++) begin
          divergence_stack[i][j] <= '0;
        end
      end
      barrier_stall_mask <= '0;
    end else begin
      // Handle memory stalls
      if (memory_stall) begin
        warp_array[stalled_warp_id].state <= WARP_STALLED;
      end
      
      // Handle barrier stalls
      if (barrier_stall) begin
        barrier_stall_mask <= barrier_stall_mask | barrier_warp_mask;
      end
      
      // Handle barrier releases
      if (barrier_release_valid) begin
        barrier_stall_mask <= barrier_stall_mask & ~barrier_release_warp_mask;
        
        // Update warp states for released warps
        for (int i = 0; i < NUM_WARPS; i++) begin
          if (barrier_release_warp_mask[i] && warp_array[i].valid) begin
            warp_array[i].state <= WARP_READY;
          end
        end
      end
      
      // Update scheduled warp
      if (scheduling_active) begin
        warp_array[current_warp].pc <= warp_array[current_warp].pc + 4;
      end
      
      // Handle new instruction allocation
      if (instruction_valid && instruction_ready) begin
        // Logic for allocating new instructions to warps
        // This would involve finding an invalid warp and initializing it
        for (int i = 0; i < NUM_WARPS; i++) begin
          if (!warp_array[i].valid) begin
            warp_array[i].valid <= 1'b1;
            warp_array[i].pc <= '0;
            warp_array[i].mask <= '1;
            warp_array[i].state <= WARP_READY;
            break;
          end
        end
      end
      
      // Thread divergence handling (for branch instructions)
      // This is a simplified implementation - actual divergence handling is more complex
      if (scheduling_active) begin
        import decoder_types::*;
        decoded_instr_t decoded_instr;
        instruction_decoder decoder(.instruction(instruction_out), .decoded_instr(decoded_instr), .valid_instruction());
        
        if (decoded_instr.is_branch && decoded_instr.thread_diverge) begin
          // Save the current mask and PC+4 on divergence stack
          if (stack_pointer[current_warp] < 8) begin
            divergence_stack[current_warp][stack_pointer[current_warp]] <= warp_array[current_warp].mask;
            stack_pointer[current_warp] <= stack_pointer[current_warp] + 1;
          end
          
          // Divergence occurs - thread mask will be updated by execution unit
          // For now, we just maintain the current thread mask
        end
        
        // Convergence handling
        if (decoded_instr.thread_converge) begin
          // Restore mask from divergence stack
          if (stack_pointer[current_warp] > 0) begin
            stack_pointer[current_warp] <= stack_pointer[current_warp] - 1;
            warp_array[current_warp].mask <= divergence_stack[current_warp][stack_pointer[current_warp]-1];
          end
        end
      end
    end
  end

  // Output assignments
  assign instruction_out = (scheduling_active) ? instruction_in : '0;
  assign thread_mask = (scheduling_active) ? warp_array[current_warp].mask : '0;
  assign warp_id_out = current_warp;
  assign warp_valid = scheduling_active;
  assign instruction_ready = 1'b1; // Can be modified based on resource availability

  // Performance counters
  logic [31:0] scheduled_warps_count;
  logic [31:0] barrier_stalls_count;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scheduled_warps_count <= '0;
      barrier_stalls_count <= '0;
    end else begin
      if (scheduling_active) begin
        scheduled_warps_count <= scheduled_warps_count + 1;
      end
      
      if (barrier_stall) begin
        barrier_stalls_count <= barrier_stalls_count + 1;
      end
    end
  end

endmodule