// Execution Interface
interface exec_if #(
  parameter THREADS_PER_WARP = 32
)(
  input logic clk,
  input logic rst_n
);
  // Instruction and control
  logic [31:0] instruction;
  logic [31:0] thread_mask;
  logic [5:0]  warp_id;
  logic        instruction_valid;
  logic        ready;

  // Register access
  logic [4:0]  rs1_addr;
  logic [4:0]  rs2_addr;
  logic [31:0] rs1_data [THREADS_PER_WARP-1:0];
  logic [31:0] rs2_data [THREADS_PER_WARP-1:0];
  logic [4:0]  rd_addr;
  logic [31:0] rd_data  [THREADS_PER_WARP-1:0];
  logic        rd_write_en;

  // Pipeline control
  logic        stall;
  logic        flush;
  logic [31:0] pc;
  logic [31:0] next_pc;

  // Modports
  modport scheduler (
    output instruction,
    output thread_mask,
    output warp_id,
    output instruction_valid,
    output flush,
    output pc,
    input  ready,
    input  stall,
    input  next_pc
  );

  modport execution (
    input  instruction,
    input  thread_mask,
    input  warp_id,
    input  instruction_valid,
    input  flush,
    input  pc,
    output ready,
    output stall,
    output next_pc,
    output rs1_addr,
    output rs2_addr,
    input  rs1_data,
    input  rs2_data,
    output rd_addr,
    output rd_data,
    output rd_write_en
  );

  modport regfile (
    input  rs1_addr,
    input  rs2_addr,
    output rs1_data,
    output rs2_data,
    input  rd_addr,
    input  rd_data,
    input  rd_write_en
  );
endinterface