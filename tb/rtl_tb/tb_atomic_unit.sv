// tb_atomic_unit.sv
// Testbench for atomic operation unit

`timescale 1ns/1ps

module tb_atomic_unit();

  // Parameters
  parameter int THREADS_PER_WARP = 32;
  parameter int MAX_PENDING_REQS = 8;

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Test control
  int test_cycles = 0;
  int test_passes = 0;
  int test_fails = 0;
  
  // Import atomic types
  import atomic_types::*;
  
  // Request interface
  atomic_op_e  req_op;
  logic [31:0] req_address;
  logic [31:0] req_data;
  logic [31:0] req_compare_data;
  logic [5:0]  req_warp_id;
  logic [4:0]  req_lane_id;
  logic        req_valid;
  logic        req_ready;

  // Response interface
  logic [31:0] resp_data;
  logic [5:0]  resp_warp_id;
  logic [4:0]  resp_lane_id;
  logic        resp_valid;
  logic        resp_ready;

  // Memory interface
  logic [31:0] mem_address;
  logic [31:0] mem_write_data;
  logic        mem_write_en;
  logic        mem_atomic_en;
  atomic_op_e  mem_atomic_op;
  logic        mem_request_valid;
  logic [31:0] mem_read_data;
  logic        mem_response_valid;
  logic        mem_ready;

  // Performance counters
  logic [31:0] atomic_op_count;
  logic [31:0] atomic_contention_count;

  // Atomic unit instance
  atomic_unit #(
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .MAX_PENDING_REQS(MAX_PENDING_REQS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    // Request interface
    .req_op(req_op),
    .req_address(req_address),
    .req_data(req_data),
    .req_compare_data(req_compare_data),
    .req_warp_id(req_warp_id),
    .req_lane_id(req_lane_id),
    .req_valid(req_valid),
    .req_ready(req_ready),
    
    // Response interface
    .resp_data(resp_data),
    .resp_warp_id(resp_warp_id),
    .resp_lane_id(resp_lane_id),
    .resp_valid(resp_valid),
    .resp_ready(resp_ready),
    
    // Memory interface
    .mem_address(mem_address),
    .mem_write_data(mem_write_data),
    .mem_write_en(mem_write_en),
    .mem_atomic_en(mem_atomic_en),
    .mem_atomic_op(mem_atomic_op),
    .mem_request_valid(mem_request_valid),
    .mem_read_data(mem_read_data),
    .mem_response_valid(mem_response_valid),
    .mem_ready(mem_ready),
    
    // Performance counters
    .atomic_op_count(atomic_op_count),
    .atomic_contention_count(atomic_contention_count)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz clock
  end
  
  // Memory simulation
  logic [31:0] memory [0:1023]; // Small memory array for testing
  
  // Test sequence
  initial begin
    // Initialize signals
    rst_n = 0;
    req_op = ATOMIC_ADD;
    req_address = 0;
    req_data = 0;
    req_compare_data = 0;
    req_warp_id = 0;
    req_lane_id = 0;
    req_valid = 0;
    resp_ready = 1;
    mem_read_data = 0;
    mem_response_valid = 0;
    mem_ready = 1;
    
    // Initialize memory
    for (int i = 0; i < 1024; i++) begin
      memory[i] = i;
    end
    
    // Apply reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
    
    $display("Starting atomic unit tests");
    
    // Test atomic add
    test_atomic_add();
    
    // Test atomic exchange
    test_atomic_exchange();
    
    // Test atomic compare and swap
    test_atomic_cas();
    
    // Test multiple requests
    test_multiple_requests();
    
    // Test request contention
    test_request_contention();
    
    // End of test
    $display("Atomic unit tests completed:");
    $display("  %0d tests passed", test_passes);
    $display("  %0d tests failed", test_fails);
    
    if (test_fails == 0) begin
      $display("ALL TESTS PASSED");
    end else begin
      $display("SOME TESTS FAILED");
    end
    
    $finish;
  end
  
  // Memory response logic
  always @(posedge clk) begin
    if (rst_n) begin
      if (mem_request_valid && mem_ready) begin
        if (!mem_write_en) begin
          // Read request
          mem_read_data <= memory[mem_address[11:2]];
          mem_response_valid <= 1;
        end else begin
          // Write request
          memory[mem_address[11:2]] <= mem_write_data;
          mem_response_valid <= 1;
        end
      end else begin
        mem_response_valid <= 0;
      end
    end
  end
  
  // Cycle counter
  always @(posedge clk) begin
    if (rst_n) begin
      test_cycles <= test_cycles + 1;
    end
  end
  
  // Test implementations
  task test_atomic_add();
    $display("Testing atomic ADD operation...");
    
    // Set up request
    req_op = ATOMIC_ADD;
    req_address = 32'h100; // Address 0x100
    req_data = 10; // Add 10
    req_warp_id = 0;
    req_lane_id = 0;
    req_valid = 1;
    
    // Store original value
    int original_value = memory[req_address[11:2]];
    
    // Wait for request to be accepted
    wait(req_ready);
    @(posedge clk);
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify original value is returned
    if (resp_data == original_value) begin
      test_passes++;
      $display("PASS: Atomic ADD returned correct original value: %0d", original_value);
    end else begin
      test_fails++;
      $display("FAIL: Atomic ADD returned incorrect original value. Expected: %0d, Got: %0d", 
              original_value, resp_data);
    end
    
    // Verify memory has been updated
    if (memory[req_address[11:2]] == original_value + 10) begin
      test_passes++;
      $display("PASS: Atomic ADD updated memory correctly: %0d", memory[req_address[11:2]]);
    end else begin
      test_fails++;
      $display("FAIL: Atomic ADD did not update memory correctly. Expected: %0d, Got: %0d", 
              original_value + 10, memory[req_address[11:2]]);
    end
    
    // Complete response
    @(posedge clk);
    resp_ready = 1;
    
    $display("PASS: Atomic ADD test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_atomic_exchange();
    $display("Testing atomic EXCH operation...");
    
    // Set up request
    req_op = ATOMIC_EXCH;
    req_address = 32'h200; // Address 0x200
    req_data = 32'hDEADBEEF; // Exchange with this value
    req_warp_id = 1;
    req_lane_id = 1;
    req_valid = 1;
    
    // Store original value
    int original_value = memory[req_address[11:2]];
    
    // Wait for request to be accepted
    wait(req_ready);
    @(posedge clk);
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify original value is returned
    if (resp_data == original_value) begin
      test_passes++;
      $display("PASS: Atomic EXCH returned correct original value: %0h", original_value);
    end else begin
      test_fails++;
      $display("FAIL: Atomic EXCH returned incorrect original value. Expected: %0h, Got: %0h", 
              original_value, resp_data);
    end
    
    // Verify memory has been updated
    if (memory[req_address[11:2]] == 32'hDEADBEEF) begin
      test_passes++;
      $display("PASS: Atomic EXCH updated memory correctly: %0h", memory[req_address[11:2]]);
    end else begin
      test_fails++;
      $display("FAIL: Atomic EXCH did not update memory correctly. Expected: %0h, Got: %0h", 
              32'hDEADBEEF, memory[req_address[11:2]]);
    end
    
    // Complete response
    @(posedge clk);
    resp_ready = 1;
    
    $display("PASS: Atomic EXCH test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_atomic_cas();
    $display("Testing atomic CAS operation...");
    
    // Set up memory for test
    logic [31:0] test_addr = 32'h300; // Address 0x300
    memory[test_addr[11:2]] = 32'h12345678; // Initialize with known value
    
    // Test successful CAS
    req_op = ATOMIC_CAS;
    req_address = test_addr;
    req_compare_data = 32'h12345678; // Compare value (matches)
    req_data = 32'h87654321; // Swap value
    req_warp_id = 2;
    req_lane_id = 2;
    req_valid = 1;
    
    // Wait for request to be accepted
    wait(req_ready);
    @(posedge clk);
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify original value is returned
    if (resp_data == 32'h12345678) begin
      test_passes++;
      $display("PASS: Atomic CAS (success) returned correct original value: %0h", resp_data);
    end else begin
      test_fails++;
      $display("FAIL: Atomic CAS (success) returned incorrect original value. Expected: %0h, Got: %0h", 
              32'h12345678, resp_data);
    end
    
    // Verify memory has been updated (swap occurred)
    if (memory[test_addr[11:2]] == 32'h87654321) begin
      test_passes++;
      $display("PASS: Atomic CAS (success) updated memory correctly: %0h", memory[test_addr[11:2]]);
    end else begin
      test_fails++;
      $display("FAIL: Atomic CAS (success) did not update memory correctly. Expected: %0h, Got: %0h", 
              32'h87654321, memory[test_addr[11:2]]);
    end
    
    // Complete response
    @(posedge clk);
    resp_ready = 1;
    
    // Wait a bit before next CAS
    repeat (5) @(posedge clk);
    
    // Test failed CAS (compare value doesn't match)
    req_op = ATOMIC_CAS;
    req_address = test_addr;
    req_compare_data = 32'h12345678; // Compare value (doesn't match)
    req_data = 32'hAABBCCDD; // Swap value - should not be used
    req_warp_id = 2;
    req_lane_id = 3;
    req_valid = 1;
    
    // Wait for request to be accepted
    wait(req_ready);
    @(posedge clk);
    req_valid = 0;
    
    // Wait for response
    wait(resp_valid);
    
    // Verify current value is returned
    if (resp_data == 32'h87654321) begin
      test_passes++;
      $display("PASS: Atomic CAS (fail) returned correct current value: %0h", resp_data);
    end else begin
      test_fails++;
      $display("FAIL: Atomic CAS (fail) returned incorrect current value. Expected: %0h, Got: %0h", 
              32'h87654321, resp_data);
    end
    
    // Verify memory has NOT been updated (swap should not occur)
    if (memory[test_addr[11:2]] == 32'h87654321) begin
      test_passes++;
      $display("PASS: Atomic CAS (fail) correctly kept memory unchanged: %0h", memory[test_addr[11:2]]);
    end else begin
      test_fails++;
      $display("FAIL: Atomic CAS (fail) incorrectly modified memory. Expected: %0h, Got: %0h", 
              32'h87654321, memory[test_addr[11:2]]);
    end
    
    // Complete response
    @(posedge clk);
    resp_ready = 1;
    
    $display("PASS: Atomic CAS test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_multiple_requests();
    $display("Testing multiple atomic requests...");
    
    // Send multiple requests in sequence
    for (int i = 0; i < 5; i++) begin
      logic [31:0] addr = 32'h400 + i*4;
      logic [31:0] original_value = memory[addr[11:2]];
      
      // Set up request
      req_op = ATOMIC_ADD;
      req_address = addr;
      req_data = i + 1; // Add different values
      req_warp_id = 3;
      req_lane_id = i[4:0];
      req_valid = 1;
      
      // Wait for request to be accepted
      wait(req_ready);
      @(posedge clk);
      req_valid = 0;
      
      // Wait for response
      wait(resp_valid);
      
      // Verify original value is returned
      if (resp_data == original_value) begin
        test_passes++;
      end else begin
        test_fails++;
        $display("FAIL: Multiple requests - request %0d returned incorrect value. Expected: %0d, Got: %0d",
                i, original_value, resp_data);
      end
      
      // Verify memory has been updated
      if (memory[addr[11:2]] == original_value + i + 1) begin
        test_passes++;
      end else begin
        test_fails++;
        $display("FAIL: Multiple requests - request %0d did not update memory correctly. Expected: %0d, Got: %0d",
                i, original_value + i + 1, memory[addr[11:2]]);
      end
      
      // Complete response
      @(posedge clk);
      resp_ready = 1;
      
      // Small delay between requests
      repeat (2) @(posedge clk);
    end
    
    $display("PASS: Multiple requests test completed with %0d operations", atomic_op_count);
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_request_contention();
    $display("Testing request contention...");
    
    // Initialize a specific memory location
    logic [31:0] contention_addr = 32'h500;
    memory[contention_addr[11:2]] = 0;
    
    // Send multiple requests to the same address simultaneously
    fork
      begin
        req_op = ATOMIC_ADD;
        req_address = contention_addr;
        req_data = 5;
        req_warp_id = 4;
        req_lane_id = 0;
        req_valid = 1;
        
        wait(req_ready);
        @(posedge clk);
        req_valid = 0;
        
        wait(resp_valid && resp_warp_id == 4 && resp_lane_id == 0);
        @(posedge clk);
        resp_ready = 1;
      end
      
      begin
        // Slight delay for second request
        @(posedge clk);
        
        req_op = ATOMIC_ADD;
        req_address = contention_addr;
        req_data = 10;
        req_warp_id = 4;
        req_lane_id = 1;
        req_valid = 1;
        
        wait(req_ready);
        @(posedge clk);
        req_valid = 0;
        
        wait(resp_valid && resp_warp_id == 4 && resp_lane_id == 1);
        @(posedge clk);
        resp_ready = 1;
      end
      
      begin
        // Larger delay for third request
        repeat(2) @(posedge clk);
        
        req_op = ATOMIC_ADD;
        req_address = contention_addr;
        req_data = 15;
        req_warp_id = 4;
        req_lane_id = 2;
        req_valid = 1;
        
        wait(req_ready);
        @(posedge clk);
        req_valid = 0;
        
        wait(resp_valid && resp_warp_id == 4 && resp_lane_id == 2);
        @(posedge clk);
        resp_ready = 1;
      end
    join
    
    // Wait for all operations to complete
    repeat(10) @(posedge clk);
    
    // Verify final memory value (5 + 10 + 15 = 30)
    if (memory[contention_addr[11:2]] == 30) begin
      test_passes++;
      $display("PASS: Contention test - final memory value correct: %0d", memory[contention_addr[11:2]]);
    end else begin
      test_fails++;
      $display("FAIL: Contention test - final memory value incorrect. Expected: 30, Got: %0d",
              memory[contention_addr[11:2]]);
    end
    
    // Verify contention counter increased
    if (atomic_contention_count > 0) begin
      test_passes++;
      $display("PASS: Contention counter incremented: %0d", atomic_contention_count);
    end else begin
      test_fails++;
      $display("FAIL: Contention counter not incremented when expected");
    end
    
    $display("PASS: Request contention test completed");
    
    // Reset for next test
    repeat (5) @(posedge clk);
  endtask