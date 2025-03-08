// interfaces.sv - Updated version
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

// Shared Memory Interface
interface shared_mem_if #(
  parameter THREADS_PER_WARP = 32
)(
  input logic clk,
  input logic rst_n
);
  // Address and data signals
  logic [31:0] address     [THREADS_PER_WARP-1:0];
  logic [31:0] write_data  [THREADS_PER_WARP-1:0];
  logic [3:0]  byte_enable [THREADS_PER_WARP-1:0];
  logic [31:0] read_data   [THREADS_PER_WARP-1:0];
  
  // Control signals
  logic [31:0] thread_mask;
  logic [5:0]  warp_id;
  logic        write_en;
  logic        request_valid;
  logic        ready;
  
  // Response
  logic [31:0] resp_thread_mask;
  logic [5:0]  resp_warp_id;
  logic        resp_valid;
  logic        resp_ready;
  
  // Modports
  modport master (
    output address,
    output write_data,
    output byte_enable,
    output thread_mask,
    output warp_id,
    output write_en,
    output request_valid,
    output resp_ready,
    input  read_data,
    input  ready,
    input  resp_thread_mask,
    input  resp_warp_id,
    input  resp_valid
  );
  
  modport slave (
    input  address,
    input  write_data,
    input  byte_enable,
    input  thread_mask,
    input  warp_id,
    input  write_en,
    input  request_valid,
    input  resp_ready,
    output read_data,
    output ready,
    output resp_thread_mask,
    output resp_warp_id,
    output resp_valid
  );
endinterface

// Texture Interface
interface texture_if #(
  parameter THREADS_PER_WARP = 32
)(
  input logic clk,
  input logic rst_n
);
  // Texture coordinates and configuration
  logic [31:0] base_address;
  logic [11:0] u [THREADS_PER_WARP-1:0];
  logic [11:0] v [THREADS_PER_WARP-1:0];
  logic [3:0]  mip_level;
  logic [1:0]  filter_mode;
  logic [1:0]  address_mode;
  
  // Control signals
  logic [31:0] thread_mask;
  logic [5:0]  warp_id;
  logic        request_valid;
  logic        ready;
  
  // Response data
  logic [31:0] read_data [4][THREADS_PER_WARP-1:0]; // RGBA for each thread
  logic [31:0] resp_thread_mask;
  logic [5:0]  resp_warp_id;
  logic        resp_valid;
  logic        resp_ready;
  
  // Modports
  modport master (
    output base_address,
    output u,
    output v,
    output mip_level,
    output filter_mode,
    output address_mode,
    output thread_mask,
    output warp_id,
    output request_valid,
    output resp_ready,
    input  read_data,
    input  ready,
    input  resp_thread_mask,
    input  resp_warp_id,
    input  resp_valid
  );
  
  modport slave (
    input  base_address,
    input  u,
    input  v,
    input  mip_level,
    input  filter_mode,
    input  address_mode,
    input  thread_mask,
    input  warp_id,
    input  request_valid,
    input  resp_ready,
    output read_data,
    output ready,
    output resp_thread_mask,
    output resp_warp_id,
    output resp_valid
  );
endinterface

// Atomic Operation Interface
interface atomic_if (
  input logic clk,
  input logic rst_n
);
  import atomic_types::*;
  
  // Request signals
  atomic_op_e op;
  logic [31:0] address;
  logic [31:0] data;
  logic [31:0] compare_data;
  logic [5:0]  warp_id;
  logic [4:0]  lane_id;
  logic        request_valid;
  logic        ready;
  
  // Response signals
  logic [31:0] result;
  logic [5:0]  resp_warp_id;
  logic [4:0]  resp_lane_id;
  logic        resp_valid;
  logic        resp_ready;
  
  // Memory interface signals
  logic [31:0] mem_address;
  logic [31:0] mem_write_data;
  logic        mem_write_en;
  logic        mem_atomic_en;
  atomic_op_e  mem_atomic_op;
  logic        mem_request_valid;
  logic [31:0] mem_read_data;
  logic        mem_response_valid;
  logic        mem_ready;
  
  // Modports
  modport master (
    output op,
    output address,
    output data,
    output compare_data,
    output warp_id,
    output lane_id,
    output request_valid,
    output resp_ready,
    input  result,
    input  ready,
    input  resp_warp_id,
    input  resp_lane_id,
    input  resp_valid
  );
  
  modport slave (
    input  op,
    input  address,
    input  data,
    input  compare_data,
    input  warp_id,
    input  lane_id,
    input  request_valid,
    input  resp_ready,
    output result,
    output ready,
    output resp_warp_id,
    output resp_lane_id,
    output resp_valid
  );
  
  modport memory (
    output mem_address,
    output mem_write_data,
    output mem_write_en,
    output mem_atomic_en,
    output mem_atomic_op,
    output mem_request_valid,
    input  mem_read_data,
    input  mem_response_valid,
    input  mem_ready
  );
endinterface

// Barrier Interface
interface barrier_if (
  input logic clk,
  input logic rst_n
);
  // Barrier arrival signals
  logic [15:0] barrier_id;
  logic [31:0] thread_mask;
  logic [9:0]  block_id;
  logic [5:0]  warp_id;
  logic        request_valid;
  logic        ready;
  
  // Barrier release signals
  logic [15:0] release_barrier_id;
  logic [9:0]  release_block_id;
  logic [31:0] release_warp_mask;
  logic        release_valid;
  logic        release_ready;
  
  // Stall signals for warp scheduler
  logic        stall;
  logic [31:0] stall_warp_mask;
  
  // Modports
  modport execution (
    output barrier_id,
    output thread_mask,
    output block_id,
    output warp_id,
    output request_valid,
    output release_ready,
    input  ready,
    input  release_barrier_id,
    input  release_block_id,
    input  release_warp_mask,
    input  release_valid
  );
  
  modport controller (
    input  barrier_id,
    input  thread_mask,
    input  block_id,
    input  warp_id,
    input  request_valid,
    input  release_ready,
    output ready,
    output release_barrier_id,
    output release_block_id,
    output release_warp_mask,
    output release_valid
  );
  
  modport scheduler (
    input  stall,
    input  stall_warp_mask,
    input  release_valid,
    input  release_warp_mask
  );
endinterface