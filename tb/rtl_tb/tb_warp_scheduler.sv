// tb_warp_scheduler.sv
// Testbench for warp scheduler component

`timescale 1ns/1ps

module tb_warp_scheduler();

  // Parameters
  parameter int NUM_WARPS = 8;  // Reduced number for testing
  parameter int THREADS_PER_WARP = 32;

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Test control
  int test_cycles = 0;
  int test_passes = 0;
  int test_fails = 0;
  
  // Interface with instruction buffer
  logic [31:0] instruction_in;
  logic        instruction_valid;
  logic        instruction_ready;
  
  // Interface with execution unit
  logic [31:0] instruction_out;
  logic [31:0] thread_mask;
  logic [5:0]  warp_id_out;
  logic        warp_valid;
  logic        execution_ready;
  
  // Memory stall interface
  logic        memory_stall;
  logic [5:0]  stalled_warp_id;

  // Warp Scheduler instance
  warp_scheduler #(
    .NUM_WARPS(NUM_WARPS),
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    // Interface with instruction buffer
    .instruction_in(instruction_in),
    .instruction_valid(instruction_valid),
    .instruction_ready(instruction_ready),
    
    // Interface with execution unit
    .instruction_out(instruction_out),
    .thread_mask(thread_mask),
    .warp_id_out(warp_id_out),
    .warp_valid(warp_valid),
    .execution_ready(execution_ready),
    
    // Memory stall interface
    .memory_stall(memory_stall),
    .stalled_warp_id(stalled_warp_id)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz clock
  end
  
  // Test sequence
  initial begin
    // Initialize signals
    rst_n = 0;
    instruction_in = 0;
    instruction_valid = 0;
    execution_ready = 1;  // Execution unit is initially ready
    memory_stall = 0;
    stalled_warp_id = 0;
    
    // Apply reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
    
    $display("Starting warp scheduler tests");
    
    // Basic scheduling test
    test_basic_scheduling();
    
    // Test round-robin scheduling
    test_round_robin();
    
    // Test with memory stalls
    test_memory_stalls();
    
    // Test with execution unit backpressure
    test_execution_backpressure();
    
    // Test thread mask handling
    test_thread_mask();
    
    // End of test
    $display("Warp scheduler tests completed:");
    $display("  %0d tests passed", test_passes);
    $display("  %0d tests failed", test_fails);
    
    if (test_fails == 0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("SOME TESTS FAILED");
    end
    
    $finish;
  end
  
  // Cycle counter
  always @(posedge clk) begin
    if (rst_n) begin
      test_cycles <= test_cycles + 1;
    end
  end
  
  // Test implementations
  task test_basic_scheduling();
    $display("Testing basic warp scheduling...");
    
    // Check that a warp is scheduled
    instruction_in = 32'hAABBCCDD;
    instruction_valid = 1;
    execution_ready = 1;
    
    repeat (5) @(posedge clk);
    
    // Verify that a warp was scheduled
    if (warp_valid) begin
      test_passes++;
      $display("PASS: Warp scheduled successfully");
    end else begin
      test_fails++;
      $display("FAIL: No warp scheduled");
    end
    
    // Verify instruction passthrough
    if (instruction_out == instruction_in) begin
      test_passes++;
      $display("PASS: Instruction passed through correctly");
    end else begin
      test_fails++;
      $display("FAIL: Instruction not passed through correctly");
    end
    
    instruction_valid = 0;
    repeat (10) @(posedge clk);
  endtask
  
  task test_round_robin();
    $display("Testing round-robin scheduling...");
    
    // Track scheduled warp IDs
    logic [NUM_WARPS-1:0] scheduled_warps = '0;
    logic [5:0] last_warp_id = '1;
    int count_unique_warps = 0;
    
    // Schedule multiple warps
    instruction_valid = 1;
    execution_ready = 1;
    
    // Run for enough cycles to schedule all warps
    for (int i = 0; i < NUM_WARPS * 2; i++) begin
      @(posedge clk);
      
      if (warp_valid) begin
        // Check if this is a different warp from the last one
        if (warp_id_out != last_warp_id) begin
          last_warp_id = warp_id_out;
          
          // Check if this warp has been scheduled before
          if (!scheduled_warps[warp_id_out]) begin
            scheduled_warps[warp_id_out] = 1'b1;
            count_unique_warps++;
          end
        end
      end
    end
    
    // Verify that multiple unique warps were scheduled
    if (count_unique_warps > 1) begin
      test_passes++;
      $display("PASS: Round-robin scheduling works, scheduled %0d unique warps", count_unique_warps);
    end else begin
      test_fails++;
      $display("FAIL: Round-robin scheduling failed, only scheduled %0d unique warps", count_unique_warps);
    end
    
    instruction_valid = 0;
    repeat (10) @(posedge clk);
  endtask
  
  task test_memory_stalls();
    $display("Testing memory stall handling...");
    
    // First, schedule a warp
    instruction_valid = 1;
    execution_ready = 1;
    memory_stall = 0;
    
    @(posedge clk);
    
    // Record the scheduled warp ID
    logic [5:0] scheduled_warp = warp_id_out;
    
    // Now stall that warp
    memory_stall = 1;
    stalled_warp_id = scheduled_warp;
    
    repeat (3) @(posedge clk);
    
    // Verify that the stalled warp is not scheduled
    if (warp_valid && warp_id_out == scheduled_warp) begin
      test_fails++;
      $display("FAIL: Stalled warp is still being scheduled");
    end else begin
      test_passes++;
      $display("PASS: Stalled warp is not scheduled");
    end
    
    // Release the stall
    memory_stall = 0;
    
    repeat (10) @(posedge clk);
    
    // Verify the warp can be scheduled again
    int found_warp = 0;
    for (int i = 0; i < NUM_WARPS; i++) begin
      @(posedge clk);
      if (warp_valid && warp_id_out == scheduled_warp) begin
        found_warp = 1;
        break;
      end
    end
    
    if (found_warp) begin
      test_passes++;
      $display("PASS: Previously stalled warp is scheduled again");
    end else begin
      test_fails++;
      $display("FAIL: Previously stalled warp is not scheduled again");
    end
    
    instruction_valid = 0;
    repeat (10) @(posedge clk);
  endtask
  
  task test_execution_backpressure();
    $display("Testing execution unit backpressure...");
    
    // Assert instruction valid but make execution unit not ready
    instruction_valid = 1;
    execution_ready = 0;
    
    repeat (5) @(posedge clk);
    
    // Verify that no warp is scheduled when execution unit is not ready
    if (warp_valid) begin
      test_fails++;
      $display("FAIL: Warp scheduled despite execution unit not ready");
    end else begin
      test_passes++;
      $display("PASS: No warp scheduled when execution unit not ready");
    end
    
    // Make execution unit ready
    execution_ready = 1;
    
    repeat (3) @(posedge clk);
    
    // Verify that warps are scheduled when execution unit becomes ready
    if (warp_valid) begin
      test_passes++;
      $display("PASS: Warp scheduled when execution unit becomes ready");
    end else begin
      test_fails++;
      $display("FAIL: No warp scheduled when execution unit becomes ready");
    end
    
    instruction_valid = 0;
    repeat (10) @(posedge clk);
  endtask
  
  task test_thread_mask();
    $display("Testing thread mask handling...");
    
    // Verify that thread mask is set properly (all threads active)
    instruction_valid = 1;
    execution_ready = 1;
    
    repeat (3) @(posedge clk);
    
    // Check thread mask value (should be all 1's by default)
    if (warp_valid && thread_mask == 32'hFFFFFFFF) begin
      test_passes++;
      $display("PASS: Thread mask is properly initialized");
    end else begin
      test_fails++;
      $display("FAIL: Thread mask not properly initialized, value = %h", thread_mask);
    end
    
    // TODO: Add test for modifying thread mask when that functionality is implemented
    
    instruction_valid = 0;
    repeat (10) @(posedge clk);
  endtask

endmodule