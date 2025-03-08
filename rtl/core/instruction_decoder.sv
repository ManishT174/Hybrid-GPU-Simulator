// instruction_decoder.sv
// Instruction decoder for GPU simulator

package decoder_types;
  // Instruction types
  typedef enum logic [3:0] {
    INSTR_ALU      = 4'b0000,  // ALU operations
    INSTR_BRANCH   = 4'b0001,  // Branching instructions
    INSTR_LOAD     = 4'b0010,  // Memory load
    INSTR_STORE    = 4'b0011,  // Memory store
    INSTR_MOVE     = 4'b0100,  // Register move operations
    INSTR_SYNC     = 4'b0101,  // Synchronization operations
    INSTR_SPECIAL  = 4'b0110,  // Special operations
    INSTR_CONTROL  = 4'b0111   // Control operations
  } instr_type_e;

  // ALU operation types
  typedef enum logic [3:0] {
    ALU_ADD = 4'b0000,
    ALU_SUB = 4'b0001,
    ALU_MUL = 4'b0010,
    ALU_DIV = 4'b0011,
    ALU_AND = 4'b0100,
    ALU_OR  = 4'b0101,
    ALU_XOR = 4'b0110,
    ALU_SHL = 4'b0111,
    ALU_SHR = 4'b1000,
    ALU_CMP = 4'b1001,
    ALU_MIN = 4'b1010,
    ALU_MAX = 4'b1011,
    ALU_ABS = 4'b1100,
    ALU_NEG = 4'b1101
  } alu_op_e;

  // Branch operation types
  typedef enum logic [2:0] {
    BR_EQ  = 3'b000,  // Branch if equal
    BR_NE  = 3'b001,  // Branch if not equal
    BR_LT  = 3'b010,  // Branch if less than
    BR_LE  = 3'b011,  // Branch if less than or equal
    BR_GT  = 3'b100,  // Branch if greater than
    BR_GE  = 3'b101,  // Branch if greater than or equal
    BR_ALL = 3'b110,  // Branch all threads
    BR_ANY = 3'b111   // Branch if any thread condition met
  } branch_op_e;

  // Memory operation types
  typedef enum logic [1:0] {
    MEM_BYTE   = 2'b00,  // Byte operation
    MEM_HALF   = 2'b01,  // Half-word operation
    MEM_WORD   = 2'b10,  // Word operation
    MEM_GLOBAL = 2'b11   // Global memory operation
  } mem_op_e;

  // Synchronization operation types
  typedef enum logic [1:0] {
    SYNC_BARRIER = 2'b00,  // Warp barrier
    SYNC_ARRIVE  = 2'b01,  // Arrive at barrier
    SYNC_WAIT    = 2'b10,  // Wait at barrier
    SYNC_VOTE    = 2'b11   // Thread vote
  } sync_op_e;

  // Decoded instruction structure
  typedef struct packed {
    // Common fields
    instr_type_e instr_type;
    logic [5:0]  rd;          // Destination register
    logic [5:0]  rs1;         // Source register 1
    logic [5:0]  rs2;         // Source register 2
    logic [15:0] imm;         // Immediate value
    logic        use_imm;     // Use immediate instead of rs2
    
    // Operation-specific fields
    union packed {
      alu_op_e    alu_op;     // ALU operation
      branch_op_e branch_op;  // Branch operation
      mem_op_e    mem_op;     // Memory operation
      sync_op_e   sync_op;    // Synchronization operation
      logic [3:0] control_op; // Control operation
    } op;
    
    // Control flow
    logic        is_branch;        // Is branch instruction
    logic        is_barrier;       // Is barrier instruction
    logic        is_predicated;    // Instruction is predicated
    logic [3:0]  pred_reg;         // Predicate register
    logic        pred_complement;  // Complement predicate

    // Thread management
    logic        affects_pc;       // Affects program counter
    logic        thread_diverge;   // Causes thread divergence
    logic        thread_converge;  // Causes thread convergence
  } decoded_instr_t;
endpackage

import decoder_types::*;

module instruction_decoder (
  input  logic [31:0]        instruction,
  output decoded_instr_t     decoded_instr,
  output logic               valid_instruction
);

  // Instruction format:
  // [31:28] - Instruction type
  // [27:22] - Destination register (rd)
  // [21:16] - Source register 1 (rs1)
  // [15:10] - Source register 2 (rs2)
  // [9]     - Use immediate flag
  // [8:5]   - Operation type
  // [4:1]   - Predicate register
  // [0]     - Predicate complement
  
  // For immediate format:
  // [15:0]  - Immediate value (when use_imm is set)
  
  // Extract basic fields
  logic [3:0] instr_type_bits;
  logic [5:0] rd_bits;
  logic [5:0] rs1_bits;
  logic [5:0] rs2_bits;
  logic       use_imm_bit;
  logic [3:0] op_bits;
  logic [3:0] pred_bits;
  logic       pred_comp_bit;
  logic [15:0] imm_bits;
  
  assign instr_type_bits = instruction[31:28];
  assign rd_bits         = instruction[27:22];
  assign rs1_bits        = instruction[21:16];
  assign rs2_bits        = instruction[15:10];
  assign use_imm_bit     = instruction[9];
  assign op_bits         = instruction[8:5];
  assign pred_bits       = instruction[4:1];
  assign pred_comp_bit   = instruction[0];
  assign imm_bits        = instruction[15:0]; // When use_imm_bit is set

  // Decode instruction type
  always_comb begin
    // Default values
    decoded_instr.instr_type      = instr_type_e'(instr_type_bits);
    decoded_instr.rd              = rd_bits;
    decoded_instr.rs1             = rs1_bits;
    decoded_instr.rs2             = rs2_bits;
    decoded_instr.use_imm         = use_imm_bit;
    decoded_instr.imm             = use_imm_bit ? imm_bits : 16'h0000;
    decoded_instr.is_branch       = 1'b0;
    decoded_instr.is_barrier      = 1'b0;
    decoded_instr.is_predicated   = pred_bits != 4'h0;
    decoded_instr.pred_reg        = pred_bits;
    decoded_instr.pred_complement = pred_comp_bit;
    decoded_instr.affects_pc      = 1'b0;
    decoded_instr.thread_diverge  = 1'b0;
    decoded_instr.thread_converge = 1'b0;
    valid_instruction             = 1'b1;

    // Type-specific decoding
    case (instr_type_bits)
      INSTR_ALU: begin
        decoded_instr.op.alu_op = alu_op_e'(op_bits);
      end
      
      INSTR_BRANCH: begin
        decoded_instr.op.branch_op = branch_op_e'(op_bits[2:0]);
        decoded_instr.is_branch    = 1'b1;
        decoded_instr.affects_pc   = 1'b1;
        decoded_instr.thread_diverge = op_bits[2:0] != BR_ALL;
      end
      
      INSTR_LOAD: begin
        decoded_instr.op.mem_op = mem_op_e'(op_bits[1:0]);
      end
      
      INSTR_STORE: begin
        decoded_instr.op.mem_op = mem_op_e'(op_bits[1:0]);
      end
      
      INSTR_MOVE: begin
        // Register to register move operations
      end
      
      INSTR_SYNC: begin
        decoded_instr.op.sync_op  = sync_op_e'(op_bits[1:0]);
        decoded_instr.is_barrier  = op_bits[1:0] == SYNC_BARRIER;
        decoded_instr.thread_converge = op_bits[1:0] == SYNC_BARRIER;
      end
      
      INSTR_SPECIAL: begin
        // Special operations like system calls
        decoded_instr.affects_pc = op_bits[0]; // affects PC if bit 0 set
      end
      
      INSTR_CONTROL: begin
        // Control operations like thread management
        decoded_instr.thread_converge = op_bits[1:0] == 2'b01; // Thread converge
        decoded_instr.thread_diverge  = op_bits[1:0] == 2'b10; // Thread diverge
      end
      
      default: begin
        valid_instruction = 1'b0;
      end
    endcase
  end

  // Detailed instruction decoding helper functions
  function automatic string instr_to_string(decoded_instr_t instr);
    case (instr.instr_type)
      INSTR_ALU: begin
        return $sformatf("ALU: %s r%0d, r%0d, %s", 
                        alu_op_to_string(instr.op.alu_op),
                        instr.rd,
                        instr.rs1,
                        instr.use_imm ? $sformatf("0x%0h", instr.imm) : $sformatf("r%0d", instr.rs2));
      end
      
      INSTR_BRANCH: begin
        return $sformatf("BR: %s r%0d, r%0d, PC+%0d",
                        branch_op_to_string(instr.op.branch_op),
                        instr.rs1,
                        instr.rs2,
                        instr.imm);
      end
      
      INSTR_LOAD: begin
        return $sformatf("LD: r%0d, [r%0d+%0d]", instr.rd, instr.rs1, instr.imm);
      end
      
      INSTR_STORE: begin
        return $sformatf("ST: [r%0d+%0d], r%0d", instr.rs1, instr.imm, instr.rs2);
      end
      
      INSTR_SYNC: begin
        return $sformatf("SYNC: %s", sync_op_to_string(instr.op.sync_op));
      end
      
      default: begin
        return "UNKNOWN";
      end
    endcase
  endfunction
  
  function automatic string alu_op_to_string(alu_op_e op);
    case (op)
      ALU_ADD: return "ADD";
      ALU_SUB: return "SUB";
      ALU_MUL: return "MUL";
      ALU_DIV: return "DIV";
      ALU_AND: return "AND";
      ALU_OR:  return "OR";
      ALU_XOR: return "XOR";
      ALU_SHL: return "SHL";
      ALU_SHR: return "SHR";
      ALU_CMP: return "CMP";
      ALU_MIN: return "MIN";
      ALU_MAX: return "MAX";
      ALU_ABS: return "ABS";
      ALU_NEG: return "NEG";
      default: return "???";
    endcase
  endfunction
  
  function automatic string branch_op_to_string(branch_op_e op);
    case (op)
      BR_EQ:  return "BEQ";
      BR_NE:  return "BNE";
      BR_LT:  return "BLT";
      BR_LE:  return "BLE";
      BR_GT:  return "BGT";
      BR_GE:  return "BGE";
      BR_ALL: return "BALL";
      BR_ANY: return "BANY";
      default: return "B???";
    endcase
  endfunction
  
  function automatic string sync_op_to_string(sync_op_e op);
    case (op)
      SYNC_BARRIER: return "BARRIER";
      SYNC_ARRIVE:  return "ARRIVE";
      SYNC_WAIT:    return "WAIT";
      SYNC_VOTE:    return "VOTE";
      default:      return "SYNC???";
    endcase
  endfunction

endmodule