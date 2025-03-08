// atomic_unit.sv
// Atomic operation unit for GPU simulator

package atomic_types;
  typedef enum logic [3:0] {
    ATOMIC_ADD  = 4'b0000,  // Atomic add
    ATOMIC_SUB  = 4'b0001,  // Atomic subtract
    ATOMIC_EXCH = 4'b0010,  // Atomic exchange
    ATOMIC_MIN  = 4'b0011,  // Atomic minimum
    ATOMIC_MAX  = 4'b0100,  // Atomic maximum
    ATOMIC_AND  = 4'b0101,  // Atomic AND
    ATOMIC_OR   = 4'b0110,  // Atomic OR
    ATOMIC_XOR  = 4'b0111,  // Atomic XOR
    ATOMIC_CAS  = 4'b1000,  // Compare and swap
    ATOMIC_INC  = 4'b1001,  // Atomic increment
    ATOMIC_DEC  = 4'b1010   // Atomic decrement
  } atomic_op_e;

  typedef struct packed {
    logic [31:0] address;       // Target address
    logic [31:0] data;          // Source data
    logic [31:0] compare_data;  // Compare data (for CAS)
    atomic_op_e  op;            // Operation type
    logic [5:0]  warp_id;       // Requesting warp
    logic [4:0]  lane_id;       // Requesting lane
    logic        valid;         // Request validity
  } atomic_request_t;

  typedef struct packed {
    logic [31:0] data;          // Result data
    logic [5:0]  warp_id;       // Requesting warp
    logic [4:0]  lane_id;       // Requesting lane
    logic        valid;         // Response validity
  } atomic_response_t;
endpackage

import atomic_types::*;

module atomic_unit #(
  parameter int THREADS_PER_WARP = 32,
  parameter int MAX_PENDING_REQS = 16
)(
  input  logic        clk,
  input  logic        rst_n,

  // Request interface (from execution unit)
  input  atomic_op_e  req_op,
  input  logic [31:0] req_address,
  input  logic [31:0] req_data,
  input  logic [31:0] req_compare_data,
  input  logic [5:0]  req_warp_id,
  input  logic [4:0]  req_lane_id,
  input  logic        req_valid,
  output logic        req_ready,

  // Response interface (to execution unit)
  output logic [31:0] resp_data,
  output logic [5:0]  resp_warp_id,
  output logic [4:0]  resp_lane_id,
  output logic        resp_valid,
  input  logic        resp_ready,

  // Memory interface (to memory controller)
  output logic [31:0] mem_address,
  output logic [31:0] mem_write_data,
  output logic        mem_write_en,
  output logic        mem_atomic_en,
  output atomic_op_e  mem_atomic_op,
  output logic        mem_request_valid,
  input  logic [31:0] mem_read_data,
  input  logic        mem_response_valid,
  input  logic        mem_ready,

  // Performance counters
  output logic [31:0] atomic_op_count,
  output logic [31:0] atomic_contention_count
);

  // Request queue
  atomic_request_t pending_reqs [$:MAX_PENDING_REQS-1];
  atomic_request_t current_req;
  
  // State machine
  typedef enum logic [2:0] {
    IDLE,
    READ_MEM,
    COMPUTE,
    WRITE_MEM,
    RESPOND
  } atomic_state_e;
  
  atomic_state_e current_state;
  
  // Temporary data storage
  logic [31:0] temp_data;
  logic [31:0] orig_data;
  
  // Address tracking for contention detection
  logic [31:0] active_addresses [MAX_PENDING_REQS-1:0];
  logic [MAX_PENDING_REQS-1:0] address_valid;
  
  // Check if there's contention for an address
  function automatic logic check_contention(logic [31:0] address);
    logic contention = 1'b0;
    
    for (int i = 0; i < MAX_PENDING_REQS; i++) begin
      if (address_valid[i] && active_addresses[i] == address) begin
        contention = 1'b1;
        break;
      end
    end
    
    return contention;
  endfunction
  
  // Add address to tracking
  function automatic void add_address(logic [31:0] address);
    for (int i = 0; i < MAX_PENDING_REQS; i++) begin
      if (!address_valid[i]) begin
        active_addresses[i] = address;
        address_valid[i] = 1'b1;
        break;
      end
    end
  endfunction
  
  // Remove address from tracking
  function automatic void remove_address(logic [31:0] address);
    for (int i = 0; i < MAX_PENDING_REQS; i++) begin
      if (address_valid[i] && active_addresses[i] == address) begin
        address_valid[i] = 1'b0;
        break;
      end
    end
  endfunction
  
  // Perform atomic operation on data
  function automatic logic [31:0] perform_atomic_op(
    atomic_op_e op,
    logic [31:0] orig_val,
    logic [31:0] new_val,
    logic [31:0] compare_val
  );
    logic [31:0] result;
    
    case (op)
      ATOMIC_ADD:  result = orig_val + new_val;
      ATOMIC_SUB:  result = orig_val - new_val;
      ATOMIC_EXCH: result = new_val;
      ATOMIC_MIN:  result = (orig_val < new_val) ? orig_val : new_val;
      ATOMIC_MAX:  result = (orig_val > new_val) ? orig_val : new_val;
      ATOMIC_AND:  result = orig_val & new_val;
      ATOMIC_OR:   result = orig_val | new_val;
      ATOMIC_XOR:  result = orig_val ^ new_val;
      ATOMIC_CAS:  result = (orig_val == compare_val) ? new_val : orig_val;
      ATOMIC_INC:  result = orig_val + 1;
      ATOMIC_DEC:  result = orig_val - 1;
      default:     result = orig_val;
    endcase
    
    return result;
  endfunction
  
  // Main control logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= IDLE;
      atomic_op_count <= '0;
      atomic_contention_count <= '0;
      address_valid <= '0;
      resp_valid <= 1'b0;
      
      // Clear the queue
      while (pending_reqs.size() > 0) begin
        void'(pending_reqs.pop_front());
      end
    end else begin
      case (current_state)
        IDLE: begin
          resp_valid <= 1'b0;
          
          // Accept new request
          if (req_valid && req_ready) begin
            atomic_request_t new_req;
            new_req.address = req_address;
            new_req.data = req_data;
            new_req.compare_data = req_compare_data;
            new_req.op = req_op;
            new_req.warp_id = req_warp_id;
            new_req.lane_id = req_lane_id;
            new_req.valid = 1'b1;
            
            // Check for address contention
            if (check_contention(req_address)) begin
              // Contention detected, queue request
              pending_reqs.push_back(new_req);
              atomic_contention_count <= atomic_contention_count + 1;
            end else begin
              // No contention, process immediately
              current_req = new_req;
              add_address(req_address);
              current_state <= READ_MEM;
              atomic_op_count <= atomic_op_count + 1;
            end
          end else if (pending_reqs.size() > 0) begin
            // Process queued request
            current_req = pending_reqs.pop_front();
            add_address(current_req.address);
            current_state <= READ_MEM;
            atomic_op_count <= atomic_op_count + 1;
          end
        end
        
        READ_MEM: begin
          // Read original value from memory
          if (mem_ready) begin
            mem_address <= current_req.address;
            mem_write_en <= 1'b0;
            mem_atomic_en <= 1'b1;
            mem_atomic_op <= current_req.op;
            mem_request_valid <= 1'b1;
            current_state <= COMPUTE;
          end
        end
        
        COMPUTE: begin
          // Wait for memory read response
          if (mem_response_valid) begin
            mem_request_valid <= 1'b0;
            orig_data <= mem_read_data;
            
            // Compute new value
            temp_data <= perform_atomic_op(
              current_req.op,
              mem_read_data,
              current_req.data,
              current_req.compare_data
            );
            
            current_state <= WRITE_MEM;
          end
        end
        
        WRITE_MEM: begin
          // Write new value to memory
          if (mem_ready) begin
            mem_address <= current_req.address;
            mem_write_data <= temp_data;
            mem_write_en <= 1'b1;
            mem_atomic_en <= 1'b1;
            mem_atomic_op <= current_req.op;
            mem_request_valid <= 1'b1;
            current_state <= RESPOND;
          end
        end
        
        RESPOND: begin
          // Wait for memory write to complete
          if (mem_response_valid) begin
            mem_request_valid <= 1'b0;
            
            // Prepare response
            resp_data <= orig_data;  // Return original value
            resp_warp_id <= current_req.warp_id;
            resp_lane_id <= current_req.lane_id;
            resp_valid <= 1'b1;
            
            // Remove address from tracking
            remove_address(current_req.address);
            
            // Return to idle state
            current_state <= IDLE;
          end
        end
      endcase
    end
  end
  
  // Output assignments
  assign req_ready = (current_state == IDLE) && (pending_reqs.size() < MAX_PENDING_REQS);

endmodule