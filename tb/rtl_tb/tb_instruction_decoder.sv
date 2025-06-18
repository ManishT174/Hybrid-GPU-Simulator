// tb_instruction_decoder.sv
// Testbench for instruction decoder component

`timescale 1ns/1ps

module tb_instruction_decoder();

  // Clock and reset (not strictly needed for combinational module, but included for consistency)
  logic clk;
  logic rst_n;
  
  // Test control
  int test_cycles = 0;
  int test_passes = 0;
  int test_fails = 0;
  
  // Import instruction decoder types
  import decoder_types::*;
  
  // Instruction decoder interface
  logic [31:0]     instruction;
  decoded_instr_t  decoded_instr;
  logic            valid_instruction;

  // Instruction decoder instance
  instruction_decoder dut (
    .instruction(instruction),
    .decoded_instr(decoded_instr),
    .valid_instruction(valid_instruction)
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
    instruction = 0;
    
    // Apply reset
    repeat (10) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
    
    $display("Starting instruction decoder tests");
    
    // Test ALU instructions
    test_alu_instructions();
    
    // Test branch instructions
    test_branch_instructions();
    
    // Test memory instructions
    test_memory_instructions();
    
    // Test synchronization instructions
    test_sync_instructions();
    
    // Test special and control instructions
    test_special_instructions();
    
    // Test invalid instructions
    test_invalid_instructions();
    
    // End of test
    $display("Instruction decoder tests completed:");
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
  
  // Helper function to generate ALU instruction
  function logic [31:0] gen_alu_instr(
  logic [5:0] rd,
  logic [5:0] rs1,
  logic [5:0] rs2,
  logic       use_imm,
  alu_op_e    alu_op,
  logic [3:0] pred_reg,
  logic       pred_comp,
  logic [15:0] imm = 16'h0000
);
  logic [31:0] instr;  // DECLARE the variable at the beginning
  
  instr[31:28] = INSTR_ALU;
  instr[27:22] = rd;
  instr[21:16] = rs1;
  
  if (use_imm) begin
    instr[15:0] = imm;
  end else begin
    instr[15:10] = rs2;
    instr[9:0] = {1'b0, 4'b0000, 1'b0, 4'b0000};
  end
  
  instr[9] = use_imm;
  instr[8:5] = alu_op;
  instr[4:1] = pred_reg;
  instr[0] = pred_comp;
  
  return instr;
endfunction
  
  // Helper function to generate branch instruction
  function logic [31:0] gen_branch_instr(
    logic [5:0] rs1,
    logic [5:0] rs2,
    branch_op_e branch_op,
    logic [3:0] pred_reg,
    logic       pred_comp,
    logic [15:0] imm
  );
    logic [31:0] instr;
    instr[31:28] = INSTR_BRANCH;
    instr[27:22] = 6'b000000; // rd field not used
    instr[21:16] = rs1;
    instr[15:10] = rs2;
    instr[9] = 1'b1; // Always use immediate for branch
    instr[8:5] = {1'b0, branch_op};
    instr[4:1] = pred_reg;
    instr[0] = pred_comp;
    instr[15:0] = imm; // Branch target offset
    
    return instr;
  endfunction
  
  // Helper function to generate memory instruction
  function logic [31:0] gen_mem_instr(
    logic is_load,  // 1 for load, 0 for store
    logic [5:0] rd_or_rs2,  // rd for load, rs2 for store
    logic [5:0] rs1,
    mem_op_e    mem_op,
    logic [3:0] pred_reg,
    logic       pred_comp,
    logic [15:0] imm
  );
    logic [31:0] instr;
    instr[31:28] = is_load ? INSTR_LOAD : INSTR_STORE;
    instr[27:22] = rd_or_rs2;
    instr[21:16] = rs1;
    instr[15:0] = imm;
    instr[9] = 1'b1; // Always use immediate for memory
    instr[8:5] = {2'b00, mem_op};
    instr[4:1] = pred_reg;
    instr[0] = pred_comp;
    
    return instr;
  endfunction
  
  // Helper function to generate sync instruction
  function logic [31:0] gen_sync_instr(
    sync_op_e   sync_op,
    logic [3:0] pred_reg,
    logic       pred_comp,
    logic [15:0] imm
  );
    logic [31:0] instr;
    instr[31:28] = INSTR_SYNC;
    instr[27:22] = 6'b000000; // rd field not used
    instr[21:16] = 6'b000000; // rs1 field not used
    instr[15:0] = imm;        // Barrier ID or other sync parameter
    instr[9] = 1'b1;          // Always use immediate for sync
    instr[8:5] = {2'b00, sync_op};
    instr[4:1] = pred_reg;
    instr[0] = pred_comp;
    
    return instr;
  endfunction
  
  // Test implementations
  task test_alu_instructions();
    $display("Testing ALU instructions...");
    
    // Test different ALU operations
    test_single_alu_op(ALU_ADD, "ADD");
    test_single_alu_op(ALU_SUB, "SUB");
    test_single_alu_op(ALU_MUL, "MUL");
    test_single_alu_op(ALU_DIV, "DIV");
    test_single_alu_op(ALU_AND, "AND");
    test_single_alu_op(ALU_OR, "OR");
    test_single_alu_op(ALU_XOR, "XOR");
    test_single_alu_op(ALU_SHL, "SHL");
    test_single_alu_op(ALU_SHR, "SHR");
    test_single_alu_op(ALU_CMP, "CMP");
    test_single_alu_op(ALU_MIN, "MIN");
    test_single_alu_op(ALU_MAX, "MAX");
    test_single_alu_op(ALU_ABS, "ABS");
    test_single_alu_op(ALU_NEG, "NEG");
    
    // Test ALU with immediate
    test_alu_immediate();
    
    // Test ALU with predication
    test_alu_predication();
    
    $display("PASS: ALU instructions test completed");
  endtask
  
  task test_single_alu_op(alu_op_e op, string op_name);
    // Generate ALU instruction
    instruction = gen_alu_instr(
      6'd1,     // rd = r1
      6'd2,     // rs1 = r2
      6'd3,     // rs2 = r3
      1'b0,     // use_imm = false
      op,       // ALU operation
      4'd0,     // pred_reg = 0 (no predication)
      1'b0      // pred_comp = false
    );
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_ALU &&
        decoded_instr.op.alu_op == op &&
        decoded_instr.rd == 6'd1 &&
        decoded_instr.rs1 == 6'd2 &&
        decoded_instr.rs2 == 6'd3 &&
        decoded_instr.use_imm == 1'b0) begin
      test_passes++;
      $display("PASS: ALU %s instruction decoded correctly", op_name);
    end else begin
      test_fails++;
      $display("FAIL: ALU %s instruction not decoded correctly", op_name);
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_ALU);
      $display("      alu_op = %h, expected %h", decoded_instr.op.alu_op, op);
      $display("      rd = %d, expected %d", decoded_instr.rd, 1);
      $display("      rs1 = %d, expected %d", decoded_instr.rs1, 2);
      $display("      rs2 = %d, expected %d", decoded_instr.rs2, 3);
      $display("      use_imm = %b, expected %b", decoded_instr.use_imm, 0);
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_alu_immediate();
    // Generate ALU immediate instruction
    instruction = gen_alu_instr(
      6'd1,        // rd = r1
      6'd2,        // rs1 = r2
      6'd0,        // rs2 = not used
      1'b1,        // use_imm = true
      ALU_ADD,     // ADD operation
      4'd0,        // pred_reg = 0 (no predication)
      1'b0,        // pred_comp = false
      16'h1234     // imm = 0x1234
    );
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_ALU &&
        decoded_instr.op.alu_op == ALU_ADD &&
        decoded_instr.rd == 6'd1 &&
        decoded_instr.rs1 == 6'd2 &&
        decoded_instr.use_imm == 1'b1 &&
        decoded_instr.imm == 16'h1234) begin
      test_passes++;
      $display("PASS: ALU immediate instruction decoded correctly");
    end else begin
      test_fails++;
      $display("FAIL: ALU immediate instruction not decoded correctly");
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_ALU);
      $display("      alu_op = %h, expected %h", decoded_instr.op.alu_op, ALU_ADD);
      $display("      rd = %d, expected %d", decoded_instr.rd, 1);
      $display("      rs1 = %d, expected %d", decoded_instr.rs1, 2);
      $display("      use_imm = %b, expected %b", decoded_instr.use_imm, 1);
      $display("      imm = %h, expected %h", decoded_instr.imm, 16'h1234);
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_alu_predication();
    // Generate ALU instruction with predication
    instruction = gen_alu_instr(
      6'd1,     // rd = r1
      6'd2,     // rs1 = r2
      6'd3,     // rs2 = r3
      1'b0,     // use_imm = false
      ALU_ADD,  // ADD operation
      4'd5,     // pred_reg = 5 (predicated on p5)
      1'b1      // pred_comp = true (complement predicate)
    );
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_ALU &&
        decoded_instr.op.alu_op == ALU_ADD &&
        decoded_instr.is_predicated == 1'b1 &&
        decoded_instr.pred_reg == 4'd5 &&
        decoded_instr.pred_complement == 1'b1) begin
      test_passes++;
      $display("PASS: ALU predicated instruction decoded correctly");
    end else begin
      test_fails++;
      $display("FAIL: ALU predicated instruction not decoded correctly");
      $display("      is_predicated = %b, expected %b", decoded_instr.is_predicated, 1);
      $display("      pred_reg = %d, expected %d", decoded_instr.pred_reg, 5);
      $display("      pred_complement = %b, expected %b", decoded_instr.pred_complement, 1);
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_branch_instructions();
    $display("Testing branch instructions...");
    
    // Test different branch types
    test_single_branch_op(BR_EQ, "BEQ");
    test_single_branch_op(BR_NE, "BNE");
    test_single_branch_op(BR_LT, "BLT");
    test_single_branch_op(BR_LE, "BLE");
    test_single_branch_op(BR_GT, "BGT");
    test_single_branch_op(BR_GE, "BGE");
    test_single_branch_op(BR_ALL, "BALL");
    test_single_branch_op(BR_ANY, "BANY");
    
    $display("PASS: Branch instructions test completed");
  endtask
  
  task test_single_branch_op(branch_op_e op, string op_name);
    // Generate branch instruction
    instruction = gen_branch_instr(
      6'd1,     // rs1 = r1
      6'd2,     // rs2 = r2
      op,       // Branch operation
      4'd0,     // pred_reg = 0 (no predication)
      1'b0,     // pred_comp = false
      16'h0100  // imm = 0x0100 (branch offset)
    );
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_BRANCH &&
        decoded_instr.op.branch_op == op &&
        decoded_instr.rs1 == 6'd1 &&
        decoded_instr.rs2 == 6'd2 &&
        decoded_instr.imm == 16'h0100 &&
        decoded_instr.is_branch == 1'b1 &&
        decoded_instr.affects_pc == 1'b1) begin
      test_passes++;
      $display("PASS: Branch %s instruction decoded correctly", op_name);
    end else begin
      test_fails++;
      $display("FAIL: Branch %s instruction not decoded correctly", op_name);
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_BRANCH);
      $display("      branch_op = %h, expected %h", decoded_instr.op.branch_op, op);
      $display("      rs1 = %d, expected %d", decoded_instr.rs1, 1);
      $display("      rs2 = %d, expected %d", decoded_instr.rs2, 2);
      $display("      imm = %h, expected %h", decoded_instr.imm, 16'h0100);
      $display("      is_branch = %b, expected %b", decoded_instr.is_branch, 1);
      $display("      affects_pc = %b, expected %b", decoded_instr.affects_pc, 1);
    end
    
    // Special check for thread divergence
    if (op == BR_ALL) begin
      if (decoded_instr.thread_diverge == 1'b0) begin
        test_passes++;
        $display("PASS: BR_ALL correctly marks no thread divergence");
      end else begin
        test_fails++;
        $display("FAIL: BR_ALL incorrectly marks thread divergence");
      end
    end else begin
      if (decoded_instr.thread_diverge == 1'b1) begin
        test_passes++;
        $display("PASS: %s correctly marks thread divergence", op_name);
      end else begin
        test_fails++;
        $display("FAIL: %s incorrectly doesn't mark thread divergence", op_name);
      end
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_memory_instructions();
    $display("Testing memory instructions...");
    
    // Test load instructions with different memory operation types
    test_load_op(MEM_BYTE, "BYTE");
    test_load_op(MEM_HALF, "HALF");
    test_load_op(MEM_WORD, "WORD");
    test_load_op(MEM_GLOBAL, "GLOBAL");
    
    // Test store instructions
    test_store_op(MEM_BYTE, "BYTE");
    test_store_op(MEM_HALF, "HALF");
    test_store_op(MEM_WORD, "WORD");
    test_store_op(MEM_GLOBAL, "GLOBAL");
    
    $display("PASS: Memory instructions test completed");
  endtask
  
  task test_load_op(mem_op_e op, string op_name);
    // Generate load instruction
    instruction = gen_mem_instr(
      1'b1,     // is_load = true
      6'd1,     // rd = r1
      6'd2,     // rs1 = r2 (base address)
      op,       // Memory operation
      4'd0,     // pred_reg = 0 (no predication)
      1'b0,     // pred_comp = false
      16'h0040  // imm = 0x0040 (offset)
    );
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_LOAD &&
        decoded_instr.op.mem_op == op &&
        decoded_instr.rd == 6'd1 &&
        decoded_instr.rs1 == 6'd2 &&
        decoded_instr.imm == 16'h0040) begin
      test_passes++;
      $display("PASS: Load %s instruction decoded correctly", op_name);
    end else begin
      test_fails++;
      $display("FAIL: Load %s instruction not decoded correctly", op_name);
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_LOAD);
      $display("      mem_op = %h, expected %h", decoded_instr.op.mem_op, op);
      $display("      rd = %d, expected %d", decoded_instr.rd, 1);
      $display("      rs1 = %d, expected %d", decoded_instr.rs1, 2);
      $display("      imm = %h, expected %h", decoded_instr.imm, 16'h0040);
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_store_op(mem_op_e op, string op_name);
    // Generate store instruction
    instruction = gen_mem_instr(
      1'b0,     // is_load = false
      6'd1,     // rs2 = r1 (data to store)
      6'd2,     // rs1 = r2 (base address)
      op,       // Memory operation
      4'd0,     // pred_reg = 0 (no predication)
      1'b0,     // pred_comp = false
      16'h0040  // imm = 0x0040 (offset)
    );
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_STORE &&
        decoded_instr.op.mem_op == op &&
        decoded_instr.rs2 == 6'd1 &&
        decoded_instr.rs1 == 6'd2 &&
        decoded_instr.imm == 16'h0040) begin
      test_passes++;
      $display("PASS: Store %s instruction decoded correctly", op_name);
    end else begin
      test_fails++;
      $display("FAIL: Store %s instruction not decoded correctly", op_name);
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_STORE);
      $display("      mem_op = %h, expected %h", decoded_instr.op.mem_op, op);
      $display("      rs2 = %d, expected %d", decoded_instr.rs2, 1);
      $display("      rs1 = %d, expected %d", decoded_instr.rs1, 2);
      $display("      imm = %h, expected %h", decoded_instr.imm, 16'h0040);
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_sync_instructions();
    $display("Testing synchronization instructions...");
    
    // Test different synchronization operations
    test_single_sync_op(SYNC_BARRIER, "BARRIER");
    test_single_sync_op(SYNC_ARRIVE, "ARRIVE");
    test_single_sync_op(SYNC_WAIT, "WAIT");
    test_single_sync_op(SYNC_VOTE, "VOTE");
    
    $display("PASS: Synchronization instructions test completed");
  endtask
  
  task test_single_sync_op(sync_op_e op, string op_name);
    // Generate sync instruction
    instruction = gen_sync_instr(
      op,       // Sync operation
      4'd0,     // pred_reg = 0 (no predication)
      1'b0,     // pred_comp = false
      16'h0003  // imm = 0x0003 (e.g., barrier ID)
    );
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_SYNC &&
        decoded_instr.op.sync_op == op &&
        decoded_instr.imm == 16'h0003) begin
      test_passes++;
      $display("PASS: Sync %s instruction decoded correctly", op_name);
    end else begin
      test_fails++;
      $display("FAIL: Sync %s instruction not decoded correctly", op_name);
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_SYNC);
      $display("      sync_op = %h, expected %h", decoded_instr.op.sync_op, op);
      $display("      imm = %h, expected %h", decoded_instr.imm, 16'h0003);
    end
    
    // Check barrier specific properties
    if (op == SYNC_BARRIER) begin
      if (decoded_instr.is_barrier == 1'b1 && decoded_instr.thread_converge == 1'b1) begin
        test_passes++;
        $display("PASS: BARRIER correctly sets is_barrier and thread_converge flags");
      end else begin
        test_fails++;
        $display("FAIL: BARRIER flags incorrect. is_barrier=%b, thread_converge=%b, expected both 1",
                decoded_instr.is_barrier, decoded_instr.thread_converge);
      end
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_special_instructions();
    $display("Testing special and control instructions...");
    
    // Test special instruction
    test_special_instruction();
    
    // Test control instruction
    test_control_instruction();
    
    $display("PASS: Special and control instructions test completed");
  endtask
  
  task test_special_instruction();
    // Create a special instruction (e.g., system call)
    logic [31:0] instr;
    instr = 32'h0;
    instr[31:28] = INSTR_SPECIAL;
    instr[27:22] = 6'd0;       // rd field
    instr[21:16] = 6'd0;       // rs1 field
    instr[15:10] = 6'd0;       // rs2 field
    instr[9] = 1'b1;           // use_imm
    instr[8:5] = 4'b0001;      // control_op with bit 0 set (affects PC)
    instr[4:0] = 5'b00000;     // other fields
    
    instruction = instr;
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_SPECIAL &&
        decoded_instr.affects_pc == 1'b1) begin
      test_passes++;
      $display("PASS: Special instruction decoded correctly");
    end else begin
      test_fails++;
      $display("FAIL: Special instruction not decoded correctly");
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_SPECIAL);
      $display("      affects_pc = %b, expected %b", decoded_instr.affects_pc, 1);
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_control_instruction();
    // Test control instruction for thread convergence
    logic [31:0] instr;
    instr = 32'h0;
    instr[31:28] = INSTR_CONTROL;
    instr[27:22] = 6'd0;       // rd field
    instr[21:16] = 6'd0;       // rs1 field
    instr[15:10] = 6'd0;       // rs2 field
    instr[9] = 1'b1;           // use_imm
    instr[8:5] = 4'b0001;      // control_op with bits[1:0] = 01 (thread converge)
    instr[4:0] = 5'b00000;     // other fields
    
    instruction = instr;
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_CONTROL &&
        decoded_instr.thread_converge == 1'b1 &&
        decoded_instr.thread_diverge == 1'b0) begin
      test_passes++;
      $display("PASS: Control instruction (converge) decoded correctly");
    end else begin
      test_fails++;
      $display("FAIL: Control instruction (converge) not decoded correctly");
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_CONTROL);
      $display("      thread_converge = %b, expected %b", decoded_instr.thread_converge, 1);
      $display("      thread_diverge = %b, expected %b", decoded_instr.thread_diverge, 0);
    end
    
    // Test control instruction for thread divergence
    instr[8:5] = 4'b0010;      // control_op with bits[1:0] = 10 (thread diverge)
    instruction = instr;
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction decoded correctly
    if (valid_instruction &&
        decoded_instr.instr_type == INSTR_CONTROL &&
        decoded_instr.thread_converge == 1'b0 &&
        decoded_instr.thread_diverge == 1'b1) begin
      test_passes++;
      $display("PASS: Control instruction (diverge) decoded correctly");
    end else begin
      test_fails++;
      $display("FAIL: Control instruction (diverge) not decoded correctly");
      $display("      instr_type = %h, expected %h", decoded_instr.instr_type, INSTR_CONTROL);
      $display("      thread_converge = %b, expected %b", decoded_instr.thread_converge, 0);
      $display("      thread_diverge = %b, expected %b", decoded_instr.thread_diverge, 1);
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask
  
  task test_invalid_instructions();
    $display("Testing invalid instructions...");
    
    // Create an invalid instruction (invalid opcode)
    logic [31:0] instr;
    instr = 32'h0;
    instr[31:28] = 4'b1111;    // Invalid instruction type
    instruction = instr;
    
    // Wait a cycle for combinational logic
    @(posedge clk);
    
    // Verify instruction is flagged as invalid
    if (!valid_instruction) begin
      test_passes++;
      $display("PASS: Invalid instruction correctly detected");
    end else begin
      test_fails++;
      $display("FAIL: Invalid instruction not detected");
    end
    
    // Wait a cycle between tests
    @(posedge clk);
  endtask

endmodule