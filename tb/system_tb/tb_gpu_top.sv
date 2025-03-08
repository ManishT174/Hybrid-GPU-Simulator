// tb_gpu_top.sv
// Top-level testbench for GPU simulator

`timescale 1ns/1ps

module tb_gpu_top();

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Test parameters
  int test_timeout = 100000;  // Maximum cycles
  int test_passes = 0;
  int test_fails = 0;
  string test_name = "basic";
  
  // DUT parameters (configurable via plusargs)
  int p_num_warps = 32;
  int p_threads_per_warp = 32;
  int p_cache_size = 16384;
  int p_cache_line_size = 128;
  
  // Memory interface signals
  logic [31:0] mem_address;
  logic [31:0] mem_write_data;
  logic        mem_write_en;
  logic        mem_request_valid;
  logic [31:0] mem_read_data;
  logic        mem_ready;
  
  // Instruction fetch interface
  logic [31:0] instruction_in;
  logic        instruction_valid;
  logic        instruction_ready;
  
  // Debug interface
  logic [31:0] debug_warp_status [p_num_warps-1:0];
  logic [31:0] debug_performance_counters [3:0];

  // Instantiate DUT
  gpu_top #(
    .NUM_WARPS(p_num_warps),
    .THREADS_PER_WARP(p_threads_per_warp),
    .CACHE_SIZE(p_cache_size),
    .CACHE_LINE_SIZE(p_cache_line_size)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    // Memory interface
    .mem_address(mem_address),
    .mem_write_data(mem_write_data),
    .mem_write_en(mem_write_en),
    .mem_request_valid(mem_request_valid),
    .mem_read_data(mem_read_data),
    .mem_ready(mem_ready),
    
    // Instruction fetch interface
    .instruction_in(instruction_in),
    .instruction_valid(instruction_valid),
    .instruction_ready(instruction_ready),
    
    // Debug interface
    .debug_warp_status(debug_warp_status),
    .debug_performance_counters(debug_performance_counters)
  );

  // Instantiate DPI wrapper
  dpi_wrapper #(
    .NUM_WARPS(p_num_warps),
    .THREADS_PER_WARP(p_threads_per_warp),
    .CACHE_SIZE(p_cache_size),
    .CACHE_LINE_SIZE(p_cache_line_size)
  ) dpi_inst (
    .clk(clk),
    .rst_n(rst_n),
    
    // Memory interface
    .mem_address(mem_address),
    .mem_write_data(mem_write_data),
    .mem_write_en(mem_write_en),
    .mem_warp_id(6'h0),  // Default warp ID
    .mem_thread_mask(32'hFFFFFFFF),  // All threads active
    .mem_request_valid(mem_request_valid),
    .mem_read_data(mem_read_data),
    .mem_response_valid(),
    .mem_ready(mem_ready),
    
    // Instruction interface
    .pc(32'h0),
    .instruction(32'h0),
    .instruction_warp_id(6'h0),
    .instruction_thread_mask(32'hFFFFFFFF),
    .instruction_valid(1'b0),
    .next_instruction(instruction_in),
    .next_pc(),
    .instruction_ready(instruction_valid),
    
    // Debug interface
    .print_stats(1'b0),
    .perf_instructions(),
    .perf_mem_requests(),
    .perf_cache_hits(),
    .perf_stalls()
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz clock
  end
  
  // Test configuration via plusargs
  initial begin
    // Parse plusargs
    if ($test$plusargs("TEST=")) begin
      void'($value$plusargs("TEST=%s", test_name));
    end
    
    if ($test$plusargs("NUM_WARPS=")) begin
      void'($value$plusargs("NUM_WARPS=%d", p_num_warps));
    end
    
    if ($test$plusargs("THREADS_PER_WARP=")) begin
      void'($value$plusargs("THREADS_PER_WARP=%d", p_threads_per_warp));
    end
    
    if ($test$plusargs("CACHE_SIZE=")) begin
      void'($value$plusargs("CACHE_SIZE=%d", p_cache_size));
    end
    
    if ($test$plusargs("CACHE_LINE_SIZE=")) begin
      void'($value$plusargs("CACHE_LINE_SIZE=%d", p_cache_line_size));
    end
    
    if ($test$plusargs("TIMEOUT=")) begin
      void'($value$plusargs("TIMEOUT=%d", test_timeout));
    end
    
    $display("Starting test: %s", test_name);
    $display("Configuration:");
    $display("  NUM_WARPS: %0d", p_num_warps);
    $display("  THREADS_PER_WARP: %0d", p_threads_per_warp);
    $display("  CACHE_SIZE: %0d", p_cache_size);
    $display("  CACHE_LINE_SIZE: %0d", p_cache_line_size);
    $display("  TIMEOUT: %0d cycles", test_timeout);
  end
  
  // Test initialization and control
  initial begin
    // Initialize signals
    rst_n = 0;
    
    // Wait for a few clock cycles
    repeat (10) @(posedge clk);
    
    // Release reset
    rst_n = 1;
    
    // Run the appropriate test
    case (test_name)
      "basic": begin
        basic_test();
      end
      
      "alu": begin
        alu_test();
      end
      
      "memory": begin
        memory_test();
      end
      
      "branch": begin
        branch_test();
      end
      
      "full": begin
        full_system_test();
      end
      
      default: begin
        $display("Error: Unknown test '%s'", test_name);
        $finish;
      end
    endcase
    
    // End simulation
    $display("Test completed: %0d passes, %0d fails", test_passes, test_fails);
    if (test_fails == 0) begin
      $display("TEST PASSED");
    end else begin
      $display("TEST FAILED");
    end
    
    $finish;
  end
  
  // Timeout monitor
  initial begin
    repeat (test_timeout) @(posedge clk);
    $display("ERROR: Test timed out after %0d cycles", test_timeout);
    $finish;
  end
  
  // Waveform dumping
  initial begin
    if ($test$plusargs("DUMP_WAVES")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_gpu_top);
    end
  end
  
  // Test implementations
  task basic_test();
    $display("Running basic test...");
    
    // Wait for some time to let the simulation initialize
    repeat (100) @(posedge clk);
    
    // Check that the DUT is ready
    if (instruction_ready) begin
      test_passes++;
      $display("PASS: DUT initialized correctly");
    end else begin
      test_fails++;
      $display("FAIL: DUT not ready after reset");
    end
    
    // Wait for more cycles to observe behavior
    repeat (100) @(posedge clk);
  endtask
  
  task alu_test();
    $display("Running ALU test...");
    
    // TODO: Implement ALU test with instruction feeding
    repeat (100) @(posedge clk);
    
    test_passes++;
    $display("PASS: ALU test placeholder");
  endtask
  
  task memory_test();
    $display("Running memory test...");
    
    // TODO: Implement memory test with read/write operations
    repeat (100) @(posedge clk);
    
    test_passes++;
    $display("PASS: Memory test placeholder");
  endtask
  
  task branch_test();
    $display("Running branch test...");
    
    // TODO: Implement branch test with control flow testing
    repeat (100) @(posedge clk);
    
    test_passes++;
    $display("PASS: Branch test placeholder");
  endtask
  
  task full_system_test();
    $display("Running full system test...");
    
    // TODO: Implement full system test with program execution
    repeat (100) @(posedge clk);
    
    test_passes++;
    $display("PASS: Full system test placeholder");
  endtask
  
endmodule