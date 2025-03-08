// interfaces.sv
// Interface definitions for GPU simulator

// Memory Interface
interface mem_if #(
  parameter THREADS_PER_WARP = 32
)(
  input logic clk,
  input logic rst_n
);
  // Warp identification
  logic [5:0]  warp_id;
  logic [31:0] thread_mask;

  // Address and data signals
  logic [31:0] address     [THREADS_PER_WARP-1:0];
  logic [31:0] write_data  [THREADS_PER_WARP-1:0];
  logic [31:0] read_data   [THREADS_PER_WARP-1:0];
  
  // Control signals
  logic        write_en;
  logic        request_valid;
  logic        ready;
  logic        response_valid;

  // Modports
  modport master (
    output warp_id,
    output thread_mask,
    output address,
    output write_data,
    output write_en,
    output request_valid,
    input  read_data,
    input  ready,
    input  response_valid
  );

  modport slave (
    input  warp_id,
    input  thread_mask,
    input  address,
    input  write_data,
    input  write_en,
    input  request_valid,
    output read_data,
    output ready,
    output response_valid
  );
endinterface