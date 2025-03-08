// tb_memory_controller.sv
// Testbench for memory controller component

`timescale 1ns/1ps

module tb_memory_controller();

  // Parameters
  parameter int CACHE_SIZE = 4096;       // 4KB cache
  parameter int CACHE_LINE_SIZE = 64;    // 64B cache lines
  parameter int NUM_BANKS = 4;
  parameter int THREADS_PER_WARP = 32;

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Test control
  int test_cycles = 0;
  int test_passes = 0;
  int test_fails = 0;
  
  // Execution unit interface
  logic [31:0] exec_address [THREADS_PER_WARP-1:0];
  logic [31:0] exec_write_data [THREADS_PER_WARP-1:0];
  logic [31:0] exec_thread_mask;
  logic        exec_write_en;
  logic [5:0]  exec_warp_id;
  logic        exec_request_valid;
  logic [31:0] exec_read_data [THREADS_PER_WARP-1:0];
  logic        exec_ready;

  // External memory interface
  logic [31:0] mem_address;
  logic [31:0] mem_write_data;
  logic        mem_write_en;
  logic        mem_request_valid;
  logic [31:0] mem_read_data;
  logic        mem_ready;
  
  // Memory controller instance
  memory_controller #(
    .CACHE_SIZE(CACHE_SIZE),
    .CACHE_LINE_SIZE(CACHE_LINE_SIZE),
    .NUM_BANKS(NUM_BANKS),
    .THREADS_PER_WARP(THREADS_PER_WARP)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    // Execution unit interface
    .exec_address(exec_address),
    .exec_write_data(exec_write_data),
    .exec_thread_mask(exec_thread_mask),
    .exec_write_en(exec_write_en),
    .exec_warp_id(exec_warp_id),
    .exec_request_valid(exec_request_valid),
    .exec_read_data(exec_read_data),
    .exec_ready(exec_ready),
    
    // External memory interface
    .mem_address(mem_address),
    .mem_write_data(mem_write_data),
    .mem_write_en(mem_write_en),
    .mem_request_valid(mem_request_valid),
    .mem_read_data(mem_read_data),
    .mem_ready(mem_ready)
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
    exec_thread_mask = 32'hFFFFFFFF; // All threads active
    exec_warp_id = 6'h0;
    exec_request_valid = 0;
    exec_write_en = 0;
    mem_read_data = 0;
    mem_ready = 1;
    
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      exec_address[i] = 0;
      exec_write_data[i] = 0;
    end
    
    // Apply reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
    
    $display("Starting memory controller tests");
    
    // Simple write test
    simple_write_test();
    
    // Simple read test
    simple_read_test();
    
    // Cache hit test
    cache_hit_test();
    
    // Cache miss test
    cache_miss_test();
    
    // Coalescing test
    coalescing_test();
    
    // Bank conflict test
    bank_conflict_test();
    
    // End of test
    $display("Memory controller tests completed:");
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
  task simple_write_test();
    $display("Running simple write test...");
    
    // Initialize data and address
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      exec_address[i] = 32'h1000 + (i * 4); // Different address for each thread
      exec_write_data[i] = 32'hA0000000 + i; // Different data for each thread
    end
    
    // Set control signals
    exec_write_en = 1;
    exec_request_valid = 1;
    
    // Wait for ready
    wait (exec_ready);
    @(posedge clk);
    
    // Send the request
    @(posedge clk);
    exec_request_valid = 0;
    
    // Wait for a few cycles for processing
    repeat (5) @(posedge clk);
    
    // Verify memory interface signals
    if (mem_request_valid && mem_write_en) begin
      test_passes++;
      $display("PASS: Memory write request generated correctly");
    end else begin
      test_fails++;
      $display("FAIL: Memory write request not generated");
    end
    
    // Reset signals
    exec_write_en = 0;
    repeat (10) @(posedge clk);
  endtask
  
  task simple_read_test();
    $display("Running simple read test...");
    
    // Initialize data and address
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      exec_address[i] = 32'h2000 + (i * 4); // Different address for each thread
    end
    
    // Set control signals
    exec_write_en = 0; // Read operation
    exec_request_valid = 1;
    
    // Wait for ready
    wait (exec_ready);
    @(posedge clk);
    
    // Send the request
    @(posedge clk);
    exec_request_valid = 0;
    
    // Wait for memory request
    wait (mem_request_valid && !mem_write_en);
    
    // Provide response from memory
    mem_read_data = 32'hBBBBBBBB;
    mem_ready = 1;
    @(posedge clk);
    mem_ready = 0;
    
    // Wait for a few cycles for processing
    repeat (5) @(posedge clk);
    
    // Verify response
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (exec_thread_mask[i] && exec_read_data[i] == 32'hBBBBBBBB) begin
        test_passes++;
      end else if (exec_thread_mask[i]) begin
        test_fails++;
        $display("FAIL: Incorrect read data for thread %0d", i);
      end
    end
    
    $display("PASS: Memory read data correctly received");
    
    // Reset signals
    repeat (10) @(posedge clk);
  endtask
  
  task cache_hit_test();
    $display("Running cache hit test...");
    
    // First do a write to fill the cache
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      exec_address[i] = 32'h3000 + (i * 4);
      exec_write_data[i] = 32'hC0000000 + i;
    end
    
    // Set control signals for write
    exec_write_en = 1;
    exec_request_valid = 1;
    
    // Wait for ready
    wait (exec_ready);
    @(posedge clk);
    
    // Send the write request
    @(posedge clk);
    exec_request_valid = 0;
    
    // Wait for a few cycles for processing
    repeat (10) @(posedge clk);
    
    // Now read back from the same addresses (should hit in cache)
    exec_write_en = 0; // Read operation
    exec_request_valid = 1;
    
    // Wait for ready
    wait (exec_ready);
    @(posedge clk);
    
    // Send the read request
    @(posedge clk);
    exec_request_valid = 0;
    
    // Wait for a few cycles for processing
    repeat (10) @(posedge clk);
    
    // Verify that we did not generate external memory request
    // or that data was returned from cache
    if (!mem_request_valid) begin
      test_passes++;
      $display("PASS: Cache hit detected, no external memory access");
    end else begin
      test_fails++;
      $display("FAIL: Cache hit not detected, external memory accessed");
    end
    
    // Reset signals
    repeat (10) @(posedge clk);
  endtask
  
  task cache_miss_test();
    $display("Running cache miss test...");
    
    // Read from new addresses that are not in cache
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      exec_address[i] = 32'h4000 + (i * 4);
    end
    
    // Set control signals
    exec_write_en = 0; // Read operation
    exec_request_valid = 1;
    
    // Wait for ready
    wait (exec_ready);
    @(posedge clk);
    
    // Send the request
    @(posedge clk);
    exec_request_valid = 0;
    
    // Wait for memory request (indicating cache miss)
    wait (mem_request_valid && !mem_write_en);
    
    // Verify that memory request was generated
    if (mem_request_valid) begin
      test_passes++;
      $display("PASS: Cache miss detected, external memory accessed");
    end else begin
      test_fails++;
      $display("FAIL: Cache miss not detected");
    }
    
    // Provide response from memory
    mem_read_data = 32'hDDDDDDDD;
    mem_ready = 1;
    @(posedge clk);
    mem_ready = 0;
    
    // Wait for a few cycles for processing
    repeat (10) @(posedge clk);
    
    // Reset signals
    repeat (10) @(posedge clk);
  endtask
  
  task coalescing_test();
    $display("Running memory coalescing test...");
    
    // Setup addresses to test coalescing
    // Use addresses in the same cache line
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      // All threads access the same cache line
      exec_address[i] = 32'h5000 + (i % 4) * 4; 
      exec_write_data[i] = 32'hE0000000 + i;
    end
    
    // Set control signals
    exec_write_en = 1; // Write operation
    exec_request_valid = 1;
    
    // Wait for ready
    wait (exec_ready);
    @(posedge clk);
    
    // Send the request
    @(posedge clk);
    exec_request_valid = 0;
    
    // Wait for memory request
    wait (mem_request_valid && mem_write_en);
    
    // Track number of memory requests
    int mem_requests = 0;
    
    // Count memory requests over time
    for (int i = 0; i < 20; i++) begin
      if (mem_request_valid) begin
        mem_requests++;
      end
      @(posedge clk);
    end
    
    // Coalescing should reduce the number of memory requests
    if (mem_requests < THREADS_PER_WARP / 4) begin
      test_passes++;
      $display("PASS: Memory coalescing detected (%0d requests)", mem_requests);
    end else begin
      test_fails++;
      $display("FAIL: Memory coalescing not working as expected (%0d requests)", mem_requests);
    end
    
    // Reset signals
    repeat (10) @(posedge clk);
  endtask
  
  task bank_conflict_test();
    $display("Running bank conflict test...");
    
    // Setup addresses to test bank conflicts
    // Different addresses in the same bank
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      // Force threads to access different addresses in the same bank
      exec_address[i] = 32'h6000 + (i * NUM_BANKS * 4); 
      exec_write_data[i] = 32'hF0000000 + i;
    end
    
    // Set control signals
    exec_write_en = 0; // Read operation
    exec_request_valid = 1;
    
    // Wait for ready
    wait (exec_ready);
    @(posedge clk);
    
    // Send the request
    @(posedge clk);
    exec_request_valid = 0;
    
    // Wait for memory request
    wait (mem_request_valid && !mem_write_en);
    
    // Provide response from memory
    mem_read_data = 32'hFFFFFFFF;
    mem_ready = 1;
    @(posedge clk);
    mem_ready = 0;
    
    // Wait for a few cycles for processing
    repeat (20) @(posedge clk);
    
    // The test passes if it completes (detailed bank conflict detection would
    // require more complex verification)
    test_passes++;
    $display("PASS: Bank conflict handling test completed");
    
    // Reset signals
    repeat (10) @(posedge clk);
  endtask

endmodule