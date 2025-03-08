// gpu_top.sv - Updated version
// Top-level module for GPU simulator

module gpu_top #(
  parameter int NUM_WARPS = 32,
  parameter int THREADS_PER_WARP = 32,
  parameter int CACHE_SIZE = 16384,
  parameter int CACHE_LINE_SIZE = 128,
  parameter int SHARED_MEM_SIZE = 16384,
  parameter int NUM_BANKS = 32,
  parameter int MAX_BARRIERS = 16
)(
  input  logic        clk,
  input  logic        rst_n,
  
  // External memory interface
  output logic [31:0] mem_address,
  output logic [31:0] mem_write_data,
  output logic        mem_write_en,
  output logic        mem_request_valid,
  input  logic [31:0] mem_read_data,
  input  logic        mem_ready,
  
  // Instruction fetch interface
  input  logic [31:0] instruction_in,
  input  logic        instruction_valid,
  output logic        instruction_ready,
  
  // Debug interface
  output logic [31:0] debug_warp_status [NUM_WARPS-1:0],
  output logic [31:0] debug_performance_counters [8:0]  // Extended for new counters
);

  // Interface instantiations
  mem_if #(
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) mem_if_inst (
    .clk(clk),
    .rst_n(rst_n)
  );

  exec_if #(
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) exec_if_inst (
    .clk(clk),
    .rst_n(rst_n)
  );

  // Shared memory interface
  shared_mem_if #(
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) shared_mem_if_inst (
    .clk(clk),
    .rst_n(rst_n)
  );

  // Texture cache interface
  texture_if #(
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) texture_if_inst (
    .clk(clk),
    .rst_n(rst_n)
  );

  // Atomic operation interface
  atomic_if atomic_if_inst (
    .clk(clk),
    .rst_n(rst_n)
  );

  // Barrier synchronization interface
  barrier_if barrier_if_inst (
    .clk(clk),
    .rst_n(rst_n)
  );
  
  // Decoded instruction
  import decoder_types::*;
  decoded_instr_t decoded_instr;
  logic valid_instruction;

  // Instruction decoder
  instruction_decoder instruction_decoder_inst (
    .instruction(instruction_in),
    .decoded_instr(decoded_instr),
    .valid_instruction(valid_instruction)
  );

  // Warp scheduler instantiation
  warp_scheduler #(
    .NUM_WARPS(NUM_WARPS),
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) warp_scheduler_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Instruction interface
    .instruction_in(instruction_in),
    .instruction_valid(instruction_valid && valid_instruction),
    .instruction_ready(instruction_ready),
    
    // Execution interface
    .instruction_out(exec_if_inst.instruction),
    .thread_mask(exec_if_inst.thread_mask),
    .warp_id_out(exec_if_inst.warp_id),
    .warp_valid(exec_if_inst.instruction_valid),
    .execution_ready(exec_if_inst.ready),
    
    // Memory stall interface
    .memory_stall(mem_if_inst.request_valid && !mem_if_inst.ready),
    .stalled_warp_id(mem_if_inst.warp_id),
    
    // Barrier interface
    .barrier_stall(barrier_if_inst.stall),
    .barrier_warp_mask(barrier_if_inst.stall_warp_mask),
    .barrier_release_valid(barrier_if_inst.release_valid),
    .barrier_release_warp_mask(barrier_if_inst.release_warp_mask)
  );

  // Execution unit instantiation
  execution_unit #(
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .VECTOR_LANES(8)
  ) execution_unit_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Instruction interface
    .instruction_in(exec_if_inst.instruction),
    .thread_mask(exec_if_inst.thread_mask),
    .warp_id(exec_if_inst.warp_id),
    .instruction_valid(exec_if_inst.instruction_valid),
    .execution_ready(exec_if_inst.ready),
    
    // Register file interface
    .rs1_addr(exec_if_inst.rs1_addr),
    .rs2_addr(exec_if_inst.rs2_addr),
    .rs1_data(exec_if_inst.rs1_data),
    .rs2_data(exec_if_inst.rs2_data),
    .rd_addr(exec_if_inst.rd_addr),
    .rd_data(exec_if_inst.rd_data),
    .rd_write_en(exec_if_inst.rd_write_en),
    
    // Memory interface
    .mem_request(mem_if_inst.request_valid),
    .mem_address(mem_if_inst.address[0]),
    .mem_write_en(mem_if_inst.write_en),
    .mem_write_data(mem_if_inst.write_data[0]),
    .mem_ready(mem_if_inst.ready),
    .mem_read_data(mem_if_inst.read_data[0]),
    
    // Shared memory interface
    .shared_mem_request(shared_mem_if_inst.request_valid),
    .shared_mem_address(shared_mem_if_inst.address),
    .shared_mem_write_data(shared_mem_if_inst.write_data),
    .shared_mem_write_en(shared_mem_if_inst.write_en),
    .shared_mem_ready(shared_mem_if_inst.ready),
    .shared_mem_read_data(shared_mem_if_inst.read_data),
    
    // Texture interface
    .texture_request(texture_if_inst.request_valid),
    .texture_base_addr(texture_if_inst.base_address),
    .texture_u(texture_if_inst.u),
    .texture_v(texture_if_inst.v),
    .texture_ready(texture_if_inst.ready),
    .texture_read_data(texture_if_inst.read_data),
    
    // Atomic interface
    .atomic_request(atomic_if_inst.request_valid),
    .atomic_op(atomic_if_inst.op),
    .atomic_address(atomic_if_inst.address),
    .atomic_data(atomic_if_inst.data),
    .atomic_ready(atomic_if_inst.ready),
    .atomic_result(atomic_if_inst.result),
    
    // Barrier interface
    .barrier_request(barrier_if_inst.request_valid),
    .barrier_id(barrier_if_inst.barrier_id),
    .barrier_ready(barrier_if_inst.ready)
  );

  // Register file instantiation
  register_file #(
    .NUM_REGISTERS(32),
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .NUM_WARPS(NUM_WARPS)
  ) register_file_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Read port 1
    .rs1_addr(exec_if_inst.rs1_addr),
    .rs1_warp_id(exec_if_inst.warp_id),
    .rs1_data(exec_if_inst.rs1_data),
    
    // Read port 2
    .rs2_addr(exec_if_inst.rs2_addr),
    .rs2_warp_id(exec_if_inst.warp_id),
    .rs2_data(exec_if_inst.rs2_data),
    
    // Write port
    .rd_addr(exec_if_inst.rd_addr),
    .rd_warp_id(exec_if_inst.warp_id),
    .rd_data(exec_if_inst.rd_data),
    .rd_thread_mask(exec_if_inst.thread_mask),
    .rd_write_en(exec_if_inst.rd_write_en),
    
    // Scoreboard interface
    .register_busy(),  // TODO: Connect to scoreboard
    .clear_busy_reg('0),
    .clear_busy_warp('0),
    .clear_busy_en(1'b0)
  );

  // Memory controller instantiation
  memory_controller #(
    .CACHE_SIZE(CACHE_SIZE),
    .CACHE_LINE_SIZE(CACHE_LINE_SIZE),
    .NUM_BANKS(8),
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) memory_controller_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Execution unit interface
    .exec_address(mem_if_inst.address),
    .exec_write_data(mem_if_inst.write_data),
    .exec_thread_mask(mem_if_inst.thread_mask),
    .exec_write_en(mem_if_inst.write_en),
    .exec_warp_id(mem_if_inst.warp_id),
    .exec_request_valid(mem_if_inst.request_valid),
    .exec_read_data(mem_if_inst.read_data),
    .exec_ready(mem_if_inst.ready),
    
    // External memory interface
    .mem_address(mem_address),
    .mem_write_data(mem_write_data),
    .mem_write_en(mem_write_en),
    .mem_request_valid(mem_request_valid),
    .mem_read_data(mem_read_data),
    .mem_ready(mem_ready)
  );

  // Shared memory instantiation
  shared_memory #(
    .SHARED_MEM_SIZE(SHARED_MEM_SIZE),
    .NUM_BANKS(NUM_BANKS),
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .MAX_WARPS(NUM_WARPS)
  ) shared_memory_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Request interface
    .req_address(shared_mem_if_inst.address),
    .req_write_data(shared_mem_if_inst.write_data),
    .req_byte_enable(shared_mem_if_inst.byte_enable),
    .req_thread_mask(shared_mem_if_inst.thread_mask),
    .req_write_en(shared_mem_if_inst.write_en),
    .req_warp_id(shared_mem_if_inst.warp_id),
    .req_valid(shared_mem_if_inst.request_valid),
    .req_ready(shared_mem_if_inst.ready),
    
    // Response interface
    .resp_read_data(shared_mem_if_inst.read_data),
    .resp_thread_mask(shared_mem_if_inst.resp_thread_mask),
    .resp_warp_id(shared_mem_if_inst.resp_warp_id),
    .resp_valid(shared_mem_if_inst.resp_valid),
    .resp_ready(shared_mem_if_inst.resp_ready),
    
    // Performance counters
    .bank_conflict_count(debug_performance_counters[4]),
    .access_count(debug_performance_counters[5])
  );

  // Atomic unit instantiation
  atomic_unit #(
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .MAX_PENDING_REQS(16)
  ) atomic_unit_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Request interface
    .req_op(atomic_if_inst.op),
    .req_address(atomic_if_inst.address),
    .req_data(atomic_if_inst.data),
    .req_compare_data(atomic_if_inst.compare_data),
    .req_warp_id(atomic_if_inst.warp_id),
    .req_lane_id(atomic_if_inst.lane_id),
    .req_valid(atomic_if_inst.request_valid),
    .req_ready(atomic_if_inst.ready),
    
    // Response interface
    .resp_data(atomic_if_inst.result),
    .resp_warp_id(atomic_if_inst.resp_warp_id),
    .resp_lane_id(atomic_if_inst.resp_lane_id),
    .resp_valid(atomic_if_inst.resp_valid),
    .resp_ready(atomic_if_inst.resp_ready),
    
    // Memory interface
    .mem_address(atomic_if_inst.mem_address),
    .mem_write_data(atomic_if_inst.mem_write_data),
    .mem_write_en(atomic_if_inst.mem_write_en),
    .mem_atomic_en(atomic_if_inst.mem_atomic_en),
    .mem_atomic_op(atomic_if_inst.mem_atomic_op),
    .mem_request_valid(atomic_if_inst.mem_request_valid),
    .mem_read_data(atomic_if_inst.mem_read_data),
    .mem_response_valid(atomic_if_inst.mem_response_valid),
    .mem_ready(atomic_if_inst.mem_ready),
    
    // Performance counters
    .atomic_op_count(debug_performance_counters[6]),
    .atomic_contention_count(debug_performance_counters[7])
  );

  // Barrier controller instantiation
  barrier_controller #(
    .MAX_BARRIERS(MAX_BARRIERS),
    .MAX_BLOCKS(32),
    .WARPS_PER_BLOCK(32),
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) barrier_controller_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Barrier arrive interface
    .arrive_barrier_id(barrier_if_inst.barrier_id),
    .arrive_thread_mask(barrier_if_inst.thread_mask),
    .arrive_block_id(barrier_if_inst.block_id),
    .arrive_warp_id(barrier_if_inst.warp_id),
    .arrive_valid(barrier_if_inst.request_valid),
    .arrive_ready(barrier_if_inst.ready),
    
    // Barrier release interface
    .release_barrier_id(barrier_if_inst.release_barrier_id),
    .release_block_id(barrier_if_inst.release_block_id),
    .release_warp_mask(barrier_if_inst.release_warp_mask),
    .release_valid(barrier_if_inst.release_valid),
    .release_ready(barrier_if_inst.release_ready),
    
    // Performance monitoring
    .barrier_count(debug_performance_counters[8]),
    .stalled_cycle_count()
  );

  // Texture cache instantiation
  texture_cache #(
    .CACHE_SIZE(CACHE_SIZE / 2),  // Share cache with main memory
    .CACHE_LINE_SIZE(CACHE_LINE_SIZE),
    .NUM_WAYS(4),
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) texture_cache_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Request interface
    .req_base_address(texture_if_inst.base_address),
    .req_u(texture_if_inst.u),
    .req_v(texture_if_inst.v),
    .req_mip_level(texture_if_inst.mip_level),
    .req_filter_mode(texture_if_inst.filter_mode),
    .req_address_mode(texture_if_inst.address_mode),
    .req_thread_mask(texture_if_inst.thread_mask),
    .req_warp_id(texture_if_inst.warp_id),
    .req_valid(texture_if_inst.request_valid),
    .req_ready(texture_if_inst.ready),
    
    // Response interface
    .resp_data(texture_if_inst.read_data),
    .resp_thread_mask(texture_if_inst.resp_thread_mask),
    .resp_warp_id(texture_if_inst.resp_warp_id),
    .resp_valid(texture_if_inst.resp_valid),
    .resp_ready(texture_if_inst.resp_ready),
    
    // Memory interface - connect to main memory controller
    .mem_address(),  // TODO: Connect through arbiter
    .mem_request_valid(),
    .mem_read_data(32'h0),
    .mem_response_valid(1'b0),
    .mem_ready(1'b0),
    
    // Performance counters
    .texture_req_count(),
    .cache_hit_count(),
    .cache_miss_count()
  );

  // Performance counter collection
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      debug_performance_counters <= '{default: '0};
    end else begin
      // Counter 0: Instructions executed
      debug_performance_counters[0] <= debug_performance_counters[0] + 
                                     (exec_if_inst.instruction_valid && exec_if_inst.ready);
      
      // Counter 1: Memory requests
      debug_performance_counters[1] <= debug_performance_counters[1] + 
                                     mem_if_inst.request_valid;
      
      // Counter 2: Cache hits (from memory controller)
      
      // Counter 3: Active warps
      debug_performance_counters[3] <= debug_performance_counters[3];  // TODO: Implement
      
      // Counters 4-8 are handled by the respective modules
    end
  end

  // Debug warp status collection
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      debug_warp_status <= '{default: '0};
    end else begin
      // TODO: Implement warp status collection
    end
  end

endmodule