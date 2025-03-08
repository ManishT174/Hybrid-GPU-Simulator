// tb_register_file.sv
// Testbench for register file component

`timescale 1ns/1ps

module tb_register_file();

  // Parameters
  parameter int NUM_REGISTERS = 32;
  parameter int THREADS_PER_WARP = 32;
  parameter int NUM_WARPS = 8;  // Reduced number for testing

  // Clock and reset
  logic clk;
  logic rst_n;
  
  // Test control
  int test_cycles = 0;
  int test_passes = 0;
  int test_fails = 0;
  
  // Read port 1
  logic [4:0]  rs1_addr;
  logic [5:0]  rs1_warp_id;
  logic [31:0] rs1_data [THREADS_PER_WARP-1:0];

  // Read port 2
  logic [4:0]  rs2_addr;
  logic [5:0]  rs2_warp_id;
  logic [31:0] rs2_data [THREADS_PER_WARP-1:0];

  // Write port
  logic [4:0]  rd_addr;
  logic [5:0]  rd_warp_id;
  logic [31:0] rd_data [THREADS_PER_WARP-1:0];
  logic [31:0] rd_thread_mask;
  logic        rd_write_en;

  // Scoreboard interface
  logic [NUM_REGISTERS-1:0] register_busy [NUM_WARPS-1:0];
  logic [4:0]              clear_busy_reg;
  logic [5:0]              clear_busy_warp;
  logic                    clear_busy_en;

  // Register File instance
  register_file #(
    .NUM_REGISTERS(NUM_REGISTERS),
    .THREADS_PER_WARP(THREADS_PER_WARP),
    .NUM_WARPS(NUM_WARPS)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    
    // Read port 1
    .rs1_addr(rs1_addr),
    .rs1_warp_id(rs1_warp_id),
    .rs1_data(rs1_data),
    
    // Read port 2
    .rs2_addr(rs2_addr),
    .rs2_warp_id(rs2_warp_id),
    .rs2_data(rs2_data),
    
    // Write port
    .rd_addr(rd_addr),
    .rd_warp_id(rd_warp_id),
    .rd_data(rd_data),
    .rd_thread_mask(rd_thread_mask),
    .rd_write_en(rd_write_en),
    
    // Scoreboard interface
    .register_busy(register_busy),
    .clear_busy_reg(clear_busy_reg),
    .clear_busy_warp(clear_busy_warp),
    .clear_busy_en(clear_busy_en)
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
    rs1_addr = 0;
    rs1_warp_id = 0;
    rs2_addr = 0;
    rs2_warp_id = 0;
    rd_addr = 0;
    rd_warp_id = 0;
    rd_thread_mask = '1; // All threads active
    rd_write_en = 0;
    clear_busy_reg = 0;
    clear_busy_warp = 0;
    clear_busy_en = 0;
    
    // Initialize register write data
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      rd_data[i] = 32'h00000000;
    end
    
    // Apply reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
    
    $display("Starting register file tests");
    
    // Test basic write and read
    test_basic_write_read();
    
    // Test per-thread writes
    test_per_thread_writes();
    
    // Test multiple warp access
    test_multiple_warps();
    
    // Test zero register behavior
    test_zero_register();
    
    // Test scoreboard functionality
    test_scoreboard();
    
    // End of test
    $display("Register file tests completed:");
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
    
    // Write data to register 5 of warp 0
    rd_addr = 5;
    rd_warp_id = 0;
    rd_thread_mask = '1; // All threads active
    
    // Set different data for each thread
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      rd_data[i] = 32'hA0000000 + i;
    end
    
    // Perform write
    rd_write_en = 1;
    @(posedge clk);
    rd_write_en = 0;
    
    // Wait a cycle for register update
    @(posedge clk);
    
    // Read from the same register
    rs1_addr = 5;
    rs1_warp_id = 0;
    
    // Wait a cycle for read to complete
    @(posedge clk);
    
    // Verify read data matches written data
    int pass_count = 0;
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (rs1_data[i] == 32'hA0000000 + i) begin
        pass_count++;
      end else begin
        $display("FAIL: Thread %0d read data mismatch. Expected: %h, Got: %h", 
                i, 32'hA0000000 + i, rs1_data[i]);
      end
    end
    
    if (pass_count == THREADS_PER_WARP) begin
      test_passes++;
      $display("PASS: Basic write/read test passed for all threads");
    end else begin
      test_fails++;
      $display("FAIL: Basic write/read test failed for %0d threads", THREADS_PER_WARP - pass_count);
    end
    
    // Wait a few cycles before next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_per_thread_writes();
    $display("Testing per-thread write operations...");
    
    // Write data to register 10 of warp 1, but only for even threads
    rd_addr = 10;
    rd_warp_id = 1;
    rd_thread_mask = 32'h55555555; // Only even threads active
    
    // Set data for all threads (only even threads will be written)
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      rd_data[i] = 32'hB0000000 + i;
    end
    
    // Perform write
    rd_write_en = 1;
    @(posedge clk);
    rd_write_en = 0;
    
    // Wait a cycle for register update
    @(posedge clk);
    
    // Read from the same register
    rs1_addr = 10;
    rs1_warp_id = 1;
    
    // Wait a cycle for read to complete
    @(posedge clk);
    
    // Verify read data matches written data for even threads
    int pass_count = 0;
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (i % 2 == 0) {
        // Even threads should have new data
        if (rs1_data[i] == 32'hB0000000 + i) begin
          pass_count++;
        end else begin
          $display("FAIL: Even thread %0d read data mismatch. Expected: %h, Got: %h", 
                  i, 32'hB0000000 + i, rs1_data[i]);
        end
      }
    end
    
    if (pass_count == THREADS_PER_WARP/2) begin
      test_passes++;
      $display("PASS: Per-thread write test passed for all even threads");
    end else begin
      test_fails++;
      $display("FAIL: Per-thread write test failed for %0d even threads", THREADS_PER_WARP/2 - pass_count);
    end
    
    // Wait a few cycles before next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_multiple_warps();
    $display("Testing multiple warp access...");
    
    // Write data to register 15 of multiple warps
    for (int w = 0; w < NUM_WARPS; w++) begin
      rd_addr = 15;
      rd_warp_id = w[5:0];
      rd_thread_mask = '1; // All threads active
      
      // Set different data for each warp
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        rd_data[i] = 32'hC0000000 + (w << 16) + i;
      end
      
      // Perform write
      rd_write_en = 1;
      @(posedge clk);
      rd_write_en = 0;
      
      // Wait a cycle for register update
      @(posedge clk);
    end
    
    // Read from each warp and verify
    for (int w = 0; w < NUM_WARPS; w++) begin
      rs1_addr = 15;
      rs1_warp_id = w[5:0];
      
      // Wait a cycle for read to complete
      @(posedge clk);
      
      // Verify read data matches written data
      int pass_count = 0;
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        if (rs1_data[i] == 32'hC0000000 + (w << 16) + i) begin
          pass_count++;
        end else begin
          $display("FAIL: Warp %0d Thread %0d read data mismatch. Expected: %h, Got: %h", 
                  w, i, 32'hC0000000 + (w << 16) + i, rs1_data[i]);
        end
      end
      
      if (pass_count == THREADS_PER_WARP) begin
        test_passes++;
        $display("PASS: Multiple warp test passed for warp %0d", w);
      end else begin
        test_fails++;
        $display("FAIL: Multiple warp test failed for warp %0d", w);
      end
    end
    
    // Wait a few cycles before next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_zero_register();
    $display("Testing zero register behavior...");
    
    // Try to write to register 0
    rd_addr = 0;
    rd_warp_id = 0;
    rd_thread_mask = '1; // All threads active
    
    // Set non-zero data
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      rd_data[i] = 32'hD0000000 + i;
    end
    
    // Perform write
    rd_write_en = 1;
    @(posedge clk);
    rd_write_en = 0;
    
    // Wait a cycle for register update
    @(posedge clk);
    
    // Read from register 0
    rs1_addr = 0;
    rs1_warp_id = 0;
    
    // Wait a cycle for read to complete
    @(posedge clk);
    
    // Verify read data is always zero
    int pass_count = 0;
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (rs1_data[i] == 32'h00000000) begin
        pass_count++;
      end else begin
        $display("FAIL: Zero register Thread %0d read non-zero data: %h", i, rs1_data[i]);
      end
    end
    
    if (pass_count == THREADS_PER_WARP) begin
      test_passes++;
      $display("PASS: Zero register test passed for all threads");
    end else begin
      test_fails++;
      $display("FAIL: Zero register test failed for %0d threads", THREADS_PER_WARP - pass_count);
    }
    
    // Wait a few cycles before next test
    repeat (5) @(posedge clk);
  endtask
  
  task test_scoreboard();
    $display("Testing scoreboard functionality...");
    
    // Write to register 20 to set its busy bit
    rd_addr = 20;
    rd_warp_id = 2;
    rd_thread_mask = '1;
    
    // Set data
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      rd_data[i] = 32'hE0000000 + i;
    end
    
    // Perform write
    rd_write_en = 1;
    @(posedge clk);
    rd_write_en = 0;
    
    // Wait a cycle for register update
    @(posedge clk);
    
    // Check if the register is marked as busy
    if (register_busy[2][20]) begin
      test_passes++;
      $display("PASS: Register correctly marked as busy after write");
    end else begin
      test_fails++;
      $display("FAIL: Register not marked as busy after write");
    end
    
    // Clear the busy bit
    clear_busy_reg = 20;
    clear_busy_warp = 2;
    clear_busy_en = 1;
    @(posedge clk);
    clear_busy_en = 0;
    
    // Wait a cycle for update
    @(posedge clk);
    
    // Check if the register is no longer busy
    if (!register_busy[2][20]) begin
      test_passes++;
      $display("PASS: Register busy bit cleared successfully");
    end else begin
      test_fails++;
      $display("FAIL: Register busy bit not cleared");
    end
    
    // Wait a few cycles before next test
    repeat (5) @(posedge clk);
  endtask

endmodule