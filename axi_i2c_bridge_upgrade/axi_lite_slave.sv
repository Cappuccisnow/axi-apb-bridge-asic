`timescale 1ns/1ps

module axi_lite_slave(
  input logic clk, 
  input logic res_n,  

  // read address
  input logic arvalid, 
  input logic [4:0] araddr,
  output logic arready,

  // read data
  output logic [15:0] rdata,
  output logic [1:0] rresp, 
  input logic rready,
  output logic rvalid,

  // write address
  input logic awvalid,
  input logic [4:0] awaddr,
  output logic awready,

  // write data
  input logic wvalid,
  input logic [15:0] wdata,
  output logic wready,

  // write response
  input logic bready,
  output logic bvalid,
  output logic [1:0] bresp, 

  // i2c bridge interface
  output logic [7:0] i2c_addr_out,
  output logic [7:0] i2c_data_out,
  output logic start_pulse_out,
  output logic hold_bus_out,

  input logic [15:0] status_in,
  input logic [15:0] data_rx_in
);

  typedef enum logic [1:0] {
    IDLE,
    READ_ACCESS,
    WRITE_DATA,
    WRITE_RESP
  } state_t;  
  state_t current_state, next_state;
  
  // Address width matched to memory size [4:0]
  logic [4:0] addr; 
  logic [15:0] memory [0:31];

  //FSM
  always_comb begin
    next_state = current_state;

    case(current_state)

      //read cycle state transitions
      IDLE: begin
        //prioritize write over read
        if (awvalid)      next_state = WRITE_DATA;
        else if (arvalid) next_state = READ_ACCESS;
      end

      READ_ACCESS: begin
        if (rready)       next_state = IDLE;
      end 

      WRITE_DATA: begin
        if (wvalid)       next_state = WRITE_RESP;
      end     

      WRITE_RESP: begin
        if (bready)       next_state = IDLE;
      end 

      default: next_state = IDLE; 
    endcase
  end 
  
  //Reset + State Update + Memory Write
  always_ff @(posedge clk or negedge res_n) begin
    if (!res_n) begin
      current_state <= IDLE;
      i2c_addr_out <= 8'd0;
      i2c_data_out <= 8'd0;
      start_pulse_out <= 1'b0;
      hold_bus_out <= 1'b0;

      // Reset memory
      for (integer i = 0; i < 32; i++) begin
        memory[i] <= 16'd0;
      end
      memory[0] <= 16'hffff;
      memory[1] <= 16'h1111;
    end 
    else begin
      current_state <= next_state;
      start_pulse_out <= 1'b0;

      if(current_state == IDLE) begin
        if (awvalid)      addr <= awaddr;
        else if (arvalid) addr <= araddr;
      end 

      // Memory Write Logic: Only write when VALID data is present
      if (current_state == WRITE_DATA && wvalid) begin
        case (addr) 
          5'd0: i2c_addr_out <= wdata[7:0];
          5'd1: i2c_data_out <= wdata[7:0];
          5'd2: begin
            if (wdata[0]) start_pulse_out <= 1'b1;
            hold_bus_out <= wdata[1];
          end
          default: memory[addr] <= wdata;
        endcase
      end
    end
  end
  
  // Read Logic
  always_comb begin
    rdata = 16'd0;
    if (current_state == READ_ACCESS) begin
      case (addr)
        5'd0: rdata = {8'd0, i2c_addr_out};
        5'd1: rdata = {8'd0, i2c_data_out};
        5'd2: rdata = 16'd0;
        5'd3: rdata = status_in;
        5'd4: rdata = data_rx_in;
        default: rdata = memory[addr];
      endcase
    end
  end
  
  // Handshake Signals
  assign arready = (current_state == IDLE && !awvalid);
  assign awready = (current_state == IDLE);

  assign wready  = (current_state == WRITE_DATA);
  assign rvalid = (current_state == READ_ACCESS);
  assign bvalid = (current_state == WRITE_RESP);
  
  assign bresp = 2'b00; 
  assign rresp = 2'b00;

endmodule
