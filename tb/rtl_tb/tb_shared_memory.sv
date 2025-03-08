// tb_shared_memory.sv
// Testbench for shared memory component

`timescale 1ns/1ps

module tb_shared_memory();

  // Parameters
  parameter int SHARED_MEM_SIZE = 4096;  // 4KB shared memory
  parameter int NUM_BANKS = 8;           // 8 banks
  parameter int THREADS_PER_WARP = 32;
  parameter int MAX_WARPS = 8;           // Reduced for testing

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Test control
  int test_cycles = 0;
  int test_passes = 0;
  int test_fails = 0;
  
  // Request interface
  logic [31:0] req_address [THREADS_PER_WARP-1:0];
  logic [31:0] req_write_data [THREADS_PER_WARP-1:0];
  logic [3:0]  req_byte_enable [THREADS_PER_WARP-1:0];
  logic [31:0] req_thread_mask;
  logic        req_write_en;
  logic [5:0]  req_warp_id;
  logic        req_valid;
  logic        req_ready;

  // Response interface
  logic [31:0] resp_read_data [THREADS_PER_WARP-1:0];
  logic [31:0] resp_thread_mask;
  logic [5:0]  resp_warp_id;
  logic        resp_valid;
  logic        resp_ready;

  // Performance counters
  logic [31:0] bank_conflict_count;
  logic [31:0] access_count;

  // Shared memory instance
  shared_memory #(
    .SHARED_MEM_SIZE(SHARED_MEM_SIZE),
    .NUM_BANKS(NUM_BANKS),
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .MAX_WARPS(MAX_WARPS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    // Request interface
    .req_address(req_address),
    .req_write_data(req_write_data),
    .req_byte_enable(req_byte_enable),
    .req_thread_mask(req_thread_mask),
    .req_write_en(req_write_en),
    .req_warp_id(req_warp_id),
    .req_valid(req_valid),
    .req_ready(req_ready),
    
    // Response interface
    .resp_read_data(resp_read_data),
    .resp_thread_mask(resp_thread_mask),
    .resp_warp_id(resp_warp_id),
    .resp_valid(resp_valid),
    .resp_ready(resp_ready),
    
    // Performance counters
    .bank_conflict_count(bank_conflict_count),
    .access_count(access_count)
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
    req_thread_mask = 32'hFFFFFFFF; // All threads active
    req_warp_id = 6'h0;
    req_valid = 0;
    req_write_en = 0;
    resp_ready = 1;
    
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      req_address[i] = 0;
      req_write_data[i] = 0;
      req_byte_enable[i] = 4'hF; // All bytes enabled
    end
    
    // Apply reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
    
    $display("Starting shared memory tests");
    
    // Test basic write and read operations
    test_basic_write_read();
    
    // Test bank conflicts
    test_bank_conflicts();
    
    // Test byte-level access
    test_byte_access();
    
    // Test thread masking
    test_thread_masking();
    
    // Test multiple warps
    test_multiple_warps();
    
    // End of test
    $display("Shared memory tests completed:");
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
  task test_basic_write_read();
    $display("Testing basic write and read operations...");
    
    // Set up addresses - sequential to avoid bank conflicts
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      req_address[i] = i * 4;
      req_write_data[i] = 32'hA0000000 + i;
      req_byte_enable[i] = 4'hF; // All bytes enabled
    end
    
    // Write operation
    req_write_en = 1;
    req_valid = 1;
    req_warp_id = 0;
    req_thread_mask = '1; // All threads active
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for operation to complete
    repeat(5) @(posedge clk);
    
    // Read operation from same addresses
    req_write_en = 0;
    req_valid = 1;
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify data
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (resp_read_data[i] == 32'hA0000000 + i) begin
        test_passes++;
      end else begin
        test_fails++;
        $display("FAIL: Thread %0d data mismatch. Expected: %h, Got: %h", 
                i, 32'hA0000000 + i, resp_read_data[i]);
      end
    end
    
    @(posedge clk);
    resp_ready = 1;
    
    $display("PASS: Basic write/read test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_bank_conflicts();
    $display("Testing bank conflicts...");
    
    // Setup addresses to cause bank conflicts (same bank, different addresses)
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      // For 8 banks, addresses with the same [4:2] bits map to the same bank
      // We'll map multiple threads to the same bank
      req_address[i] = (i % NUM_BANKS) + (i / NUM_BANKS) * NUM_BANKS * 4;
      req_write_data[i] = 32'hB0000000 + i;
    end
    
    // Write operation
    req_write_en = 1;
    req_valid = 1;
    req_warp_id = 1;
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for operation to complete
    repeat(10) @(posedge clk); // Extra cycles for bank conflict resolution
    
    // Read operation from same addresses
    req_write_en = 0;
    req_valid = 1;
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify data
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (resp_read_data[i] == 32'hB0000000 + i) begin
        test_passes++;
      end else begin
        test_fails++;
        $display("FAIL: Thread %0d data mismatch in bank conflict test. Expected: %h, Got: %h", 
                i, 32'hB0000000 + i, resp_read_data[i]);
      end
    end
    
    @(posedge clk);
    resp_ready = 1;
    
    // Verify bank conflict counter increased
    if (bank_conflict_count > 0) begin
      test_passes++;
      $display("PASS: Bank conflicts detected: %0d", bank_conflict_count);
    end else begin
      test_fails++;
      $display("FAIL: No bank conflicts detected when expected");
    end
    
    $display("PASS: Bank conflict test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_byte_access();
    $display("Testing byte-level access...");
    
    // Setup addresses for byte access
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      req_address[i] = i * 4 + 1024; // Different region from previous tests
      req_write_data[i] = 32'hCCCCCCCC; // Same pattern for all threads
      
      // Different byte enables for different threads
      case (i % 4)
        0: req_byte_enable[i] = 4'b0001; // Only lowest byte
        1: req_byte_enable[i] = 4'b0010; // Only second byte
        2: req_byte_enable[i] = 4'b0100; // Only third byte
        3: req_byte_enable[i] = 4'b1000; // Only highest byte
      endcase
    end
    
    // Write operation
    req_write_en = 1;
    req_valid = 1;
    req_warp_id = 2;
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for operation to complete
    repeat(5) @(posedge clk);
    
    // Now write complementary bytes
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      req_write_data[i] = 32'h33333333; // Different pattern
      
      // Complementary byte enables
      case (i % 4)
        0: req_byte_enable[i] = 4'b1110; // All except lowest byte
        1: req_byte_enable[i] = 4'b1101; // All except second byte
        2: req_byte_enable[i] = 4'b1011; // All except third byte
        3: req_byte_enable[i] = 4'b0111; // All except highest byte
      endcase
    end
    
    // Write operation
    req_valid = 1;
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for operation to complete
    repeat(5) @(posedge clk);
    
    // Read operation from same addresses
    req_write_en = 0;
    req_valid = 1;
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      req_byte_enable[i] = 4'hF; // Read all bytes
    end
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify data - should be a mixture of CCCC and 3333 depending on byte enables
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      logic [31:0] expected;
      
      case (i % 4)
        0: expected = 32'h333333CC; // Lowest byte is CC, rest is 33
        1: expected = 32'h3333CC33; // Second byte is CC, rest is 33
        2: expected = 32'h33CC3333; // Third byte is CC, rest is 33
        3: expected = 32'hCC333333; // Highest byte is CC, rest is 33
      endcase
      
      if (resp_read_data[i] == expected) begin
        test_passes++;
      end else begin
        test_fails++;
        $display("FAIL: Thread %0d byte access data mismatch. Expected: %h, Got: %h", 
                i, expected, resp_read_data[i]);
      end
    end
    
    @(posedge clk);
    resp_ready = 1;
    
    $display("PASS: Byte access test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_thread_masking();
    $display("Testing thread masking...");
    
    // Setup addresses
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      req_address[i] = i * 4 + 2048; // Different region
      req_write_data[i] = 32'hD0000000 + i;
      req_byte_enable[i] = 4'hF; // All bytes enabled
    end
    
    // Write only even threads
    req_write_en = 1;
    req_valid = 1;
    req_warp_id = 3;
    req_thread_mask = 32'h55555555; // Only even threads
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for operation to complete
    repeat(5) @(posedge clk);
    
    // Write odd threads with different data
    req_valid = 1;
    req_thread_mask = 32'hAAAAAAAA; // Only odd threads
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      req_write_data[i] = 32'hE0000000 + i;
    end
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for operation to complete
    repeat(5) @(posedge clk);
    
    // Read all threads
    req_write_en = 0;
    req_valid = 1;
    req_thread_mask = 32'hFFFFFFFF; // All threads
    
    // Wait for ready
    wait(req_ready);
    @(posedge clk);
    
    // Complete request
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify data - should be D000... for even threads and E000... for odd threads
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      logic [31:0] expected = (i % 2 == 0) ? 32'hD0000000 + i : 32'hE0000000 + i;
      
      if (resp_read_data[i] == expected) begin
        test_passes++;
      end else begin
        test_fails++;
        $display("FAIL: Thread %0d masked data mismatch. Expected: %h, Got: %h", 
                i, expected, resp_read_data[i]);
      end
    end
    
    @(posedge clk);
    resp_ready = 1;
    
    $display("PASS: Thread masking test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_multiple_warps();
    $display("Testing multiple warps...");
    
    // Test multiple warps accessing different regions
    for (int w = 0; w < 4; w++) begin
      // Setup addresses for this warp
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        req_address[i] = i * 4 + w * 1024 + 3072; // Different region for each warp
        req_write_data[i] = 32'hF0000000 + (w << 16) + i;
        req_byte_enable[i] = 4'hF; // All bytes enabled
      end
      
      // Write operation
      req_write_en = 1;
      req_valid = 1;
      req_warp_id = w;
      req_thread_mask = 32'hFFFFFFFF; // All threads
      
      // Wait for ready
      wait(req_ready);
      @(posedge clk);
      
      // Complete request
      req_valid = 0;
      
      // Wait for operation to complete
      repeat(5) @(posedge clk);
    end
    
    // Read back data from each warp
    for (int w = 0; w < 4; w++) begin
      // Setup addresses for this warp
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        req_address[i] = i * 4 + w * 1024 + 3072; // Same addresses used for write
      end
      
      // Read operation
      req_write_en = 0;
      req_valid = 1;
      req_warp_id = w;
      
      // Wait for ready
      wait(req_ready);
      @(posedge clk);
      
      // Complete request
      req_valid = 0;
      
      // Wait for response
      wait(resp_valid);
      
      // Verify data
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        logic [31:0] expected = 32'hF0000000 + (w << 16) + i;
        
        if (resp_read_data[i] == expected) begin
          test_passes++;
        end else begin
          test_fails++;
          $display("FAIL: Warp %0d Thread %0d data mismatch. Expected: %h, Got: %h", 
                  w, i, expected, resp_read_data[i]);
        end
      }
      
      @(posedge clk);
      resp_ready = 1;
      
      // Wait between warps
      repeat(2) @(posedge clk);
    end
    
    $display("PASS: Multiple warps test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask

endmodule