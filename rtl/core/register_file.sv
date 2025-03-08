// register_file.sv
// Register file implementation for GPU simulator
// Supports vector registers with per-thread addressing

package register_types;
  typedef struct packed {
    logic [31:0] data;
    logic        valid;
  } register_entry_t;
endpackage

import register_types::*;

module register_file #(
  parameter int NUM_REGISTERS    = 32,
  parameter int THREADS_PER_WARP = 32,
  parameter int NUM_WARPS       = 32
)(
  input  logic        clk,
  input  logic        rst_n,

  // Read port 1
  input  logic [4:0]  rs1_addr,
  input  logic [5:0]  rs1_warp_id,
  output logic [31:0] rs1_data [THREADS_PER_WARP-1:0],

  // Read port 2
  input  logic [4:0]  rs2_addr,
  input  logic [5:0]  rs2_warp_id,
  output logic [31:0] rs2_data [THREADS_PER_WARP-1:0],

  // Write port
  input  logic [4:0]  rd_addr,
  input  logic [5:0]  rd_warp_id,
  input  logic [31:0] rd_data [THREADS_PER_WARP-1:0],
  input  logic [31:0] rd_thread_mask,
  input  logic        rd_write_en,

  // Scoreboard interface
  output logic [NUM_REGISTERS-1:0] register_busy [NUM_WARPS-1:0],
  input  logic [4:0]              clear_busy_reg,
  input  logic [5:0]              clear_busy_warp,
  input  logic                    clear_busy_en
);

  // Register file storage
  register_entry_t register_file [NUM_WARPS-1:0][NUM_REGISTERS-1:0][THREADS_PER_WARP-1:0];

  // Write operation
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Reset all registers
      for (int w = 0; w < NUM_WARPS; w++) begin
        for (int r = 0; r < NUM_REGISTERS; r++) begin
          for (int t = 0; t < THREADS_PER_WARP; t++) begin
            register_file[w][r][t].data <= '0;
            register_file[w][r][t].valid <= 1'b1;
          end
        end
      end
    end else if (rd_write_en) begin
      // Write data for each active thread
      for (int t = 0; t < THREADS_PER_WARP; t++) begin
        if (rd_thread_mask[t]) begin
          register_file[rd_warp_id][rd_addr][t].data <= rd_data[t];
          register_file[rd_warp_id][rd_addr][t].valid <= 1'b1;
        end
      end
    end
  end

  // Read operations
  always_comb begin
    // Read port 1
    for (int t = 0; t < THREADS_PER_WARP; t++) begin
      rs1_data[t] = register_file[rs1_warp_id][rs1_addr][t].data;
    end
    
    // Read port 2
    for (int t = 0; t < THREADS_PER_WARP; t++) begin
      rs2_data[t] = register_file[rs2_warp_id][rs2_addr][t].data;
    end
  end

  // Register scoreboarding
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int w = 0; w < NUM_WARPS; w++) begin
        register_busy[w] <= '0;
      end
    end else begin
      // Set busy bit on write
      if (rd_write_en) begin
        register_busy[rd_warp_id][rd_addr] <= 1'b1;
      end
      
      // Clear busy bit
      if (clear_busy_en) begin
        register_busy[clear_busy_warp][clear_busy_reg] <= 1'b0;
      end
    end
  end

  // Bank conflict detection
  logic [NUM_REGISTERS-1:0] bank_access_mask;
  logic bank_conflict;
  
  always_comb begin
    bank_access_mask = '0;
    bank_conflict = 1'b0;
    
    // Set access mask for read ports
    if (rs1_addr != '0) bank_access_mask[rs1_addr] = 1'b1;
    if (rs2_addr != '0) bank_access_mask[rs2_addr] = 1'b1;
    
    // Check for multiple accesses to same bank
    bank_conflict = $countones(bank_access_mask) < 
                   (((rs1_addr != '0) ? 1 : 0) + 
                    ((rs2_addr != '0) ? 1 : 0));
  end

  // Performance monitoring
  logic [31:0] read_operations;
  logic [31:0] write_operations;
  logic [31:0] bank_conflicts;
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_operations <= '0;
      write_operations <= '0;
      bank_conflicts <= '0;
    end else begin
      // Count read operations
      if (rs1_addr != '0) read_operations <= read_operations + 1;
      if (rs2_addr != '0) read_operations <= read_operations + 1;
      
      // Count write operations
      if (rd_write_en) write_operations <= write_operations + 1;
      
      // Count bank conflicts
      if (bank_conflict) bank_conflicts <= bank_conflicts + 1;
    end
  end

  // Special zero register handling
  always_comb begin
    if (rs1_addr == '0) begin
      for (int t = 0; t < THREADS_PER_WARP; t++) begin
        rs1_data[t] = '0;
      end
    end
    
    if (rs2_addr == '0) begin
      for (int t = 0; t < THREADS_PER_WARP; t++) begin
        rs2_data[t] = '0;
      end
    end
  end

  // Debug interface
  function automatic string get_register_state(logic [5:0] warp_id, logic [4:0] reg_id);
    string state = $sformatf("Warp %0d, Reg %0d:\n", warp_id, reg_id);
    for (int t = 0; t < THREADS_PER_WARP; t++) begin
      state = {state, $sformatf("  Thread %0d: 0x%8h (Valid: %b)\n", 
               t, register_file[warp_id][reg_id][t].data,
               register_file[warp_id][reg_id][t].valid)};
    end
    return state;
  endfunction

endmodule