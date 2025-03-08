// tb_barrier_controller.sv
// Testbench for barrier synchronization controller

`timescale 1ns/1ps

module tb_barrier_controller();

  // Parameters
  parameter int MAX_BARRIERS = 8;  // Reduced for testing
  parameter int MAX_BLOCKS = 8;    // Reduced for testing
  parameter int WARPS_PER_BLOCK = 8; // Reduced for testing
  parameter int THREADS_PER_WARP = 32;

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Test control
  int test_cycles = 0;
  int test_passes = 0;
  int test_fails = 0;
  
  // Barrier arrive interface
  logic [15:0] arrive_barrier_id;
  logic [31:0] arrive_thread_mask;
  logic [9:0]  arrive_block_id;
  logic [5:0]  arrive_warp_id;
  logic        arrive_valid;
  logic        arrive_ready;

  // Barrier release interface
  logic [15:0] release_barrier_id;
  logic [9:0]  release_block_id;
  logic [WARPS_PER_BLOCK-1:0] release_warp_mask;
  logic        release_valid;
  logic        release_ready;

  // Performance monitoring
  logic [31:0] barrier_count;
  logic [31:0] stalled_cycle_count;

  // Import barrier types
  import barrier_types::*;
  
  // Barrier controller instance
  barrier_controller #(
    .MAX_BARRIERS(MAX_BARRIERS),
    .MAX_BLOCKS(MAX_BLOCKS),
    .WARPS_PER_BLOCK(WARPS_PER_BLOCK),
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    // Barrier arrive interface
    .arrive_barrier_id(arrive_barrier_id),
    .arrive_thread_mask(arrive_thread_mask),
    .arrive_block_id(arrive_block_id),
    .arrive_warp_id(arrive_warp_id),
    .arrive_valid(arrive_valid),
    .arrive_ready(arrive_ready),
    
    // Barrier release interface
    .release_barrier_id(release_barrier_id),
    .release_block_id(release_block_id),
    .release_warp_mask(release_warp_mask),
    .release_valid(release_valid),
    .release_ready(release_ready),
    
    // Performance monitoring
    .barrier_count(barrier_count),
    .stalled_cycle_count(stalled_cycle_count)
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
    arrive_barrier_id = 0;
    arrive_thread_mask = '1;  // All threads active
    arrive_block_id = 0;
    arrive_warp_id = 0;
    arrive_valid = 0;
    release_ready = 1;
    
    // Apply reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
    
    $display("Starting barrier controller tests");
    
    // Test basic barrier operation
    test_basic_barrier();
    
    // Test multiple warps arriving at a barrier
    test_multiple_warps();
    
    // Test multiple blocks using separate barriers
    test_multiple_blocks();
    
    // Test barrier timeout handling
    // Note: This would require adding a timeout feature to the barrier controller
    // test_barrier_timeout();
    
    // End of test
    $display("Barrier controller tests completed:");
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
  task test_basic_barrier();
    $display("Testing basic barrier operation...");
    
    // Set up parameters for a basic barrier
    logic [15:0] barrier_id = 16'h0001;
    logic [9:0]  block_id = 10'h001;
    logic [WARPS_PER_BLOCK-1:0] expected_mask = 8'h03; // Warps 0 and 1
    
    // First warp arrives at barrier
    arrive_barrier_id = barrier_id;
    arrive_thread_mask = 32'hFFFFFFFF; // All threads
    arrive_block_id = block_id;
    arrive_warp_id = 0;
    arrive_valid = 1;
    
    // Wait for ready
    wait(arrive_ready);
    @(posedge clk);
    arrive_valid = 0;
    
    // Wait a few cycles
    repeat(5) @(posedge clk);
    
    // Second warp arrives at barrier
    arrive_barrier_id = barrier_id;
    arrive_thread_mask = 32'hFFFFFFFF; // All threads
    arrive_block_id = block_id;
    arrive_warp_id = 1;
    arrive_valid = 1;
    
    // Wait for ready
    wait(arrive_ready);
    @(posedge clk);
    arrive_valid = 0;
    
    // Wait for barrier release
    wait(release_valid);
    
    // Check release signals
    if (release_barrier_id == barrier_id &&
        release_block_id == block_id &&
        release_warp_mask == expected_mask) begin
      test_passes++;
      $display("PASS: Basic barrier release signals correct");
    end else begin
      test_fails++;
      $display("FAIL: Basic barrier release signals incorrect. Expected barrier %0h, block %0h, mask %0h. Got %0h, %0h, %0h",
              barrier_id, block_id, expected_mask,
              release_barrier_id, release_block_id, release_warp_mask);
    end
    
    // Acknowledge release
    @(posedge clk);
    release_ready = 1;
    
    // Verify barrier counter increased
    if (barrier_count == 1) begin
      test_passes++;
      $display("PASS: Barrier counter incremented");
    end else begin
      test_fails++;
      $display("FAIL: Barrier counter not incremented");
    end
    
    $display("PASS: Basic barrier test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_multiple_warps();
    $display("Testing multiple warps arriving at a barrier...");
    
    // Set up parameters
    logic [15:0] barrier_id = 16'h0002;
    logic [9:0]  block_id = 10'h002;
    logic [WARPS_PER_BLOCK-1:0] expected_mask = 8'h1F; // Warps 0-4
    
    // Five warps arrive at barrier sequentially
    for (int i = 0; i < 5; i++) begin
      arrive_barrier_id = barrier_id;
      arrive_thread_mask = 32'hFFFFFFFF; // All threads
      arrive_block_id = block_id;
      arrive_warp_id = i[5:0];
      arrive_valid = 1;
      
      // Wait for ready
      wait(arrive_ready);
      @(posedge clk);
      arrive_valid = 0;
      
      // Wait a few cycles between arrivals
      repeat(3) @(posedge clk);
    end
    
    // Wait for barrier release
    wait(release_valid);
    
    // Check release signals
    if (release_barrier_id == barrier_id &&
        release_block_id == block_id &&
        release_warp_mask == expected_mask) begin
      test_passes++;
      $display("PASS: Multiple warps barrier release signals correct");
    end else begin
      test_fails++;
      $display("FAIL: Multiple warps barrier release signals incorrect. Expected barrier %0h, block %0h, mask %0h. Got %0h, %0h, %0h",
              barrier_id, block_id, expected_mask,
              release_barrier_id, release_block_id, release_warp_mask);
    end
    
    // Acknowledge release
    @(posedge clk);
    release_ready = 1;
    
    // Verify barrier counter increased
    if (barrier_count == 2) begin
      test_passes++;
      $display("PASS: Barrier counter correctly at 2");
    end else begin
      test_fails++;
      $display("FAIL: Barrier counter incorrect, expected 2, got %0d", barrier_count);
    end
    
    $display("PASS: Multiple warps barrier test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_multiple_blocks();
    $display("Testing multiple blocks using separate barriers...");
    
    // Set up parameters for two different barriers in two different blocks
    logic [15:0] barrier_id_1 = 16'h0003;
    logic [9:0]  block_id_1 = 10'h003;
    logic [WARPS_PER_BLOCK-1:0] expected_mask_1 = 8'h03; // Warps 0 and 1
    
    logic [15:0] barrier_id_2 = 16'h0004;
    logic [9:0]  block_id_2 = 10'h004;
    logic [WARPS_PER_BLOCK-1:0] expected_mask_2 = 8'h03; // Warps 0 and 1
    
    // Block 1, Warp 0 arrives at barrier
    arrive_barrier_id = barrier_id_1;
    arrive_thread_mask = 32'hFFFFFFFF;
    arrive_block_id = block_id_1;
    arrive_warp_id = 0;
    arrive_valid = 1;
    
    // Wait for ready
    wait(arrive_ready);
    @(posedge clk);
    arrive_valid = 0;
    
    // Block 2, Warp 0 arrives at barrier
    arrive_barrier_id = barrier_id_2;
    arrive_thread_mask = 32'hFFFFFFFF;
    arrive_block_id = block_id_2;
    arrive_warp_id = 0;
    arrive_valid = 1;
    
    // Wait for ready
    wait(arrive_ready);
    @(posedge clk);
    arrive_valid = 0;
    
    // Check that no barrier release has happened yet
    repeat(5) @(posedge clk);
    if (!release_valid) begin
      test_passes++;
      $display("PASS: No barrier release before all warps arrive");
    end else begin
      test_fails++;
      $display("FAIL: Barrier released too early");
    end
    
    // Block 1, Warp 1 arrives at barrier - should complete barrier 1
    arrive_barrier_id = barrier_id_1;
    arrive_thread_mask = 32'hFFFFFFFF;
    arrive_block_id = block_id_1;
    arrive_warp_id = 1;
    arrive_valid = 1;
    
    // Wait for ready
    wait(arrive_ready);
    @(posedge clk);
    arrive_valid = 0;
    
    // Wait for barrier 1 release
    wait(release_valid);
    
    // Check release signals for barrier 1
    if (release_barrier_id == barrier_id_1 &&
        release_block_id == block_id_1 &&
        release_warp_mask == expected_mask_1) begin
      test_passes++;
      $display("PASS: Block 1 barrier release signals correct");
    end else begin
      test_fails++;
      $display("FAIL: Block 1 barrier release signals incorrect. Expected barrier %0h, block %0h, mask %0h. Got %0h, %0h, %0h",
              barrier_id_1, block_id_1, expected_mask_1,
              release_barrier_id, release_block_id, release_warp_mask);
    end
    
    // Acknowledge release
    @(posedge clk);
    release_ready = 1;
    
    // Wait a few cycles
    repeat(5) @(posedge clk);
    
    // Block 2, Warp 1 arrives at barrier - should complete barrier 2
    arrive_barrier_id = barrier_id_2;
    arrive_thread_mask = 32'hFFFFFFFF;
    arrive_block_id = block_id_2;
    arrive_warp_id = 1;
    arrive_valid = 1;
    
    // Wait for ready
    wait(arrive_ready);
    @(posedge clk);
    arrive_valid = 0;
    
    // Wait for barrier 2 release
    wait(release_valid);
    
    // Check release signals for barrier 2
    if (release_barrier_id == barrier_id_2 &&
        release_block_id == block_id_2 &&
        release_warp_mask == expected_mask_2) begin
      test_passes++;
      $display("PASS: Block 2 barrier release signals correct");
    end else begin
      test_fails++;
      $display("FAIL: Block 2 barrier release signals incorrect. Expected barrier %0h, block %0h, mask %0h. Got %0h, %0h, %0h",
              barrier_id_2, block_id_2, expected_mask_2,
              release_barrier_id, release_block_id, release_warp_mask);
    end
    
    // Acknowledge release
    @(posedge clk);
    release_ready = 1;
    
    // Verify barrier counter increased
    if (barrier_count == 4) begin
      test_passes++;
      $display("PASS: Barrier counter correctly at 4");
    end else begin
      test_fails++;
      $display("FAIL: Barrier counter incorrect, expected 4, got %0d", barrier_count);
    end
    
    $display("PASS: Multiple blocks barrier test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  // Additional test for barrier timeout
  // This would require adding timeout functionality to the barrier controller
  // task test_barrier_timeout();
  //   $display("Testing barrier timeout handling...");
  //   
  //   // Set up parameters
  //   logic [15:0] barrier_id = 16'h0005;
  //   logic [9:0]  block_id = 10'h005;
  //   
  //   // Only one warp arrives at barrier (not enough to release)
  //   arrive_barrier_id = barrier_id;
  //   arrive_thread_mask = 32'hFFFFFFFF;
  //   arrive_block_id = block_id;
  //   arrive_warp_id = 0;
  //   arrive_valid = 1;
  //   
  //   // Wait for ready
  //   wait(arrive_ready);
  //   @(posedge clk);
  //   arrive_valid = 0;
  //   
  //   // Wait for timeout to occur
  //   // This would need a significantly lower timeout value for testing
  //   repeat(1000) @(posedge clk);
  //   
  //   // Verify timeout occurred and barrier was released
  //   if (release_valid) begin
  //     test_passes++;
  //     $display("PASS: Barrier timeout correctly triggered release");
  //   end else begin
  //     test_fails++;
  //     $display("FAIL: Barrier timeout did not trigger release");
  //   }
  //   
  //   // Acknowledge release if it happened
  //   if (release_valid) begin
  //     @(posedge clk);
  //     release_ready = 1;
  //   end
  //   
  //   $display("PASS: Barrier timeout test completed");
  //   
  //   // Reset for next test
  //   repeat (5) @(posedge clk);
  // endtask

endmodule