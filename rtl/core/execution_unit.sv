// execution_unit.sv - Updated version
// GPU Execution Unit implementation with support for new components

import exec_types::*;
import atomic_types::*;
import texture_types::*;
import barrier_types::*;

module execution_unit #(
  parameter int THREADS_PER_WARP = 32,
  parameter int VECTOR_LANES = 8
)(
  input  logic clk,
  input  logic rst_n,
  
  // Instruction interface
  input  logic [31:0]        instruction_in,
  input  logic [31:0]        thread_mask,
  input  logic [5:0]         warp_id,
  input  logic               instruction_valid,
  output logic               execution_ready,
  
  // Register file interface
  output logic [4:0]         rs1_addr,
  output logic [4:0]         rs2_addr,
  input  logic [31:0]        rs1_data [THREADS_PER_WARP-1:0],
  input  logic [31:0]        rs2_data [THREADS_PER_WARP-1:0],
  output logic [4:0]         rd_addr,
  output logic [31:0]        rd_data [THREADS_PER_WARP-1:0],
  output logic               rd_write_en,
  
  // Memory interface
  output logic               mem_request,
  output logic [31:0]        mem_address,
  output logic               mem_write_en,
  output logic [31:0]        mem_write_data,
  input  logic               mem_ready,
  input  logic [31:0]        mem_read_data,
  
  // Shared memory interface
  output logic               shared_mem_request,
  output logic [31:0]        shared_mem_address [THREADS_PER_WARP-1:0],
  output logic [31:0]        shared_mem_write_data [THREADS_PER_WARP-1:0],
  output logic               shared_mem_write_en,
  input  logic               shared_mem_ready,
  input  logic [31:0]        shared_mem_read_data [THREADS_PER_WARP-1:0],
  
  // Texture interface
  output logic               texture_request,
  output logic [31:0]        texture_base_addr,
  output logic [11:0]        texture_u [THREADS_PER_WARP-1:0],
  output logic [11:0]        texture_v [THREADS_PER_WARP-1:0],
  input  logic               texture_ready,
  input  logic [31:0]        texture_read_data [4][THREADS_PER_WARP-1:0],
  
  // Atomic interface
  output logic               atomic_request,
  output atomic_op_e         atomic_op,
  output logic [31:0]        atomic_address,
  output logic [31:0]        atomic_data,
  input  logic               atomic_ready,
  input  logic [31:0]        atomic_result,
  
  // Barrier interface
  output logic               barrier_request,
  output logic [15:0]        barrier_id,
  input  logic               barrier_ready
);

  // Instruction decoder output
  decoded_instr_t decoded_instr;
  logic valid_instruction;

  // Instruction decoder instance
  instruction_decoder decoder (
    .instruction(instruction_in),
    .decoded_instr(decoded_instr),
    .valid_instruction(valid_instruction)
  );

  // Vector lane management
  logic [VECTOR_LANES-1:0] lane_active;
  logic [3:0] current_lane;
  logic processing_complete;

  // Operation type signals
  logic is_alu_op;
  logic is_memory_op;
  logic is_shared_memory_op;
  logic is_texture_op;
  logic is_atomic_op;
  logic is_barrier_op;

  // Decode operation type
  always_comb begin
    is_alu_op = (decoded_instr.instr_type == INSTR_ALU);
    is_memory_op = (decoded_instr.instr_type == INSTR_LOAD || decoded_instr.instr_type == INSTR_STORE);
    is_shared_memory_op = is_memory_op && (mem_address >= 32'h80000000 && mem_address < 32'h90000000); // Shared memory space
    is_texture_op = (decoded_instr.instr_type == INSTR_SPECIAL && decoded_instr.op.control_op[1:0] == 2'b01);
    is_atomic_op = (decoded_instr.instr_type == INSTR_SPECIAL && decoded_instr.op.control_op[1:0] == 2'b10);
    is_barrier_op = (decoded_instr.instr_type == INSTR_SYNC && decoded_instr.op.sync_op == SYNC_BARRIER);
  end

  // Vector lane management
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lane_active <= '0;
      current_lane <= '0;
      processing_complete <= 1'b1;
    end else if (instruction_valid && valid_instruction && processing_complete) begin
      lane_active <= '1;
      current_lane <= '0;
      processing_complete <= 1'b0;
    end else if (!processing_complete) begin
      if (current_lane == VECTOR_LANES-1 || 
          is_memory_op || is_shared_memory_op || is_texture_op || 
          is_atomic_op || is_barrier_op) begin
        processing_complete <= 1'b1;
        lane_active <= '0;
      end else begin
        current_lane <= current_lane + 1;
      end
    end
  end

  // ALU operation
  logic [31:0] alu_result [THREADS_PER_WARP-1:0];
  
  always_comb begin
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (thread_mask[i]) begin
        case (decoded_instr.op.alu_op)
          ALU_ADD: alu_result[i] = rs1_data[i] + (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_SUB: alu_result[i] = rs1_data[i] - (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_MUL: alu_result[i] = rs1_data[i] * (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_DIV: alu_result[i] = rs1_data[i] / (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_AND: alu_result[i] = rs1_data[i] & (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_OR:  alu_result[i] = rs1_data[i] | (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_XOR: alu_result[i] = rs1_data[i] ^ (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_SHL: alu_result[i] = rs1_data[i] << (decoded_instr.use_imm ? decoded_instr.imm[4:0] : rs2_data[i][4:0]);
          ALU_SHR: alu_result[i] = rs1_data[i] >> (decoded_instr.use_imm ? decoded_instr.imm[4:0] : rs2_data[i][4:0]);
          ALU_CMP: alu_result[i] = (rs1_data[i] < (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i])) ? 32'h1 : 32'h0;
          ALU_MIN: alu_result[i] = (rs1_data[i] < (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i])) ? rs1_data[i] : (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_MAX: alu_result[i] = (rs1_data[i] > (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i])) ? rs1_data[i] : (decoded_instr.use_imm ? decoded_instr.imm : rs2_data[i]);
          ALU_ABS: alu_result[i] = (rs1_data[i][31]) ? -rs1_data[i] : rs1_data[i];
          ALU_NEG: alu_result[i] = -rs1_data[i];
          default: alu_result[i] = '0;
        endcase
      end else begin
        alu_result[i] = '0;
      end
    end
  end

  // Memory operations
  logic [31:0] memory_address [THREADS_PER_WARP-1:0];
  
  always_comb begin
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      if (thread_mask[i] && is_memory_op) begin
        // Calculate memory address: base + offset
        memory_address[i] = rs1_data[i] + decoded_instr.imm;
      end else begin
        memory_address[i] = '0;
      end
    end
  end

  // Atomic operations
  always_comb begin
    // Default values
    atomic_request = 1'b0;
    atomic_op = ATOMIC_ADD;
    atomic_address = '0;
    atomic_data = '0;
    
    if (instruction_valid && is_atomic_op) begin
      atomic_request = 1'b1;
      
      // Map internal operation to atomic operation type
      case (decoded_instr.op.control_op[3:2])
        2'b00: atomic_op = ATOMIC_ADD;
        2'b01: atomic_op = ATOMIC_EXCH;
        2'b10: atomic_op = ATOMIC_CAS;
        2'b11: atomic_op = ATOMIC_AND;
      endcase
      
      // For simplicity, we'll just use the first active thread's address
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        if (thread_mask[i]) begin
          atomic_address = rs1_data[i] + decoded_instr.imm;
          atomic_data = rs2_data[i];
          break;
        end
      end
    end
  end

  // Texture operations
  always_comb begin
    // Default values
    texture_request = 1'b0;
    texture_base_addr = '0;
    
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      texture_u[i] = '0;
      texture_v[i] = '0;
    end
    
    if (instruction_valid && is_texture_op) begin
      texture_request = 1'b1;
      texture_base_addr = rs1_data[0]; // Base texture address from first thread
      
      // Extract u,v coordinates for each thread
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        if (thread_mask[i]) begin
          // Extract u,v from rs2_data
          // This is a simplification - real HW would have dedicated texture coordinate registers
          texture_u[i] = rs2_data[i][11:0];
          texture_v[i] = rs2_data[i][23:12];
        end
      end
    end
  end

  // Barrier operations
  always_comb begin
    // Default values
    barrier_request = 1'b0;
    barrier_id = '0;
    
    if (instruction_valid && is_barrier_op) begin
      barrier_request = 1'b1;
      barrier_id = decoded_instr.imm[15:0]; // Barrier ID from immediate
    end
  end

  // Register file interface
  assign rs1_addr = decoded_instr.rs1;
  assign rs2_addr = decoded_instr.rs2;
  assign rd_addr = decoded_instr.rd;
  
  // Write to destination register
  always_comb begin
    rd_write_en = 1'b0;
    
    if (instruction_valid && !processing_complete) begin
      if (is_alu_op) begin
        rd_write_en = 1'b1;
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
          rd_data[i] = alu_result[i];
        end
      end else if (is_memory_op && !decoded_instr.instr_type == INSTR_STORE) begin
        // Load operation - shared or global memory
        rd_write_en = 1'b1;
        if (is_shared_memory_op) begin
          for (int i = 0; i < THREADS_PER_WARP; i++) begin
            rd_data[i] = shared_mem_read_data[i];
          end
        end else begin
          // Regular memory load - simplified for now
          for (int i = 0; i < THREADS_PER_WARP; i++) begin
            rd_data[i] = mem_read_data;
          end
        end
      end else if (is_texture_op) begin
        // Texture read operation - store first channel (R) in destination register
        rd_write_en = 1'b1;
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
          rd_data[i] = texture_read_data[0][i]; // Just R channel
        end
      end else if (is_atomic_op) begin
        // Atomic operation - store result in destination register
        rd_write_en = 1'b1;
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
          rd_data[i] = atomic_result;
        end
      end else begin
        rd_write_en = 1'b0;
        for (int i = 0; i < THREADS_PER_WARP; i++) begin
          rd_data[i] = '0;
        end
      }
    end else begin
      rd_write_en = 1'b0;
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        rd_data[i] = '0;
      end
    end
  end

  // Memory interface connections
  always_comb begin
    // Default values
    mem_request = 1'b0;
    mem_address = '0;
    mem_write_en = 1'b0;
    mem_write_data = '0;
    
    if (instruction_valid && is_memory_op && !is_shared_memory_op) begin
      mem_request = 1'b1;
      mem_write_en = (decoded_instr.instr_type == INSTR_STORE);
      
      // For simplicity, we'll just use the first active thread's address
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        if (thread_mask[i]) begin
          mem_address = memory_address[i];
          mem_write_data = rs2_data[i]; // For store operations
          break;
        end
      end
    end
  end

  // Shared memory interface connections
  always_comb begin
    // Default values
    shared_mem_request = 1'b0;
    shared_mem_write_en = 1'b0;
    
    for (int i = 0; i < THREADS_PER_WARP; i++) begin
      shared_mem_address[i] = '0;
      shared_mem_write_data[i] = '0;
    end
    
    if (instruction_valid && is_memory_op && is_shared_memory_op) begin
      shared_mem_request = 1'b1;
      shared_mem_write_en = (decoded_instr.instr_type == INSTR_STORE);
      
      // Set address and data for each active thread
      for (int i = 0; i < THREADS_PER_WARP; i++) begin
        if (thread_mask[i]) begin
          shared_mem_address[i] = memory_address[i] & 32'h0FFFFFFF; // Remove shared memory flag bits
          shared_mem_write_data[i] = rs2_data[i]; // For store operations
        end
      end
    end
  end

  // Execution ready signal based on operation type
  always_comb begin
    if (is_memory_op && !is_shared_memory_op) begin
      execution_ready = mem_ready;
    end else if (is_shared_memory_op) begin
      execution_ready = shared_mem_ready;
    end else if (is_texture_op) begin
      execution_ready = texture_ready;
    end else if (is_atomic_op) begin
      execution_ready = atomic_ready;
    end else if (is_barrier_op) begin
      execution_ready = barrier_ready;
    end else begin
      execution_ready = processing_complete;
    end
  end

  // Performance monitoring
  logic [31:0] instructions_executed;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instructions_executed <= '0;
    end else if (processing_complete) begin
      instructions_executed <= instructions_executed + 1;
    end
  end

endmodule