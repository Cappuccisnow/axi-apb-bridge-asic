`timescale 1ns/1ps

module axi_slave(
  input logic clk, 
  input logic res_n,  

  input logic arvalid, 
  input logic [1:0] arburst,
  input logic [2:0] arsize,
  input logic [3:0] arlen,
  input logic [4:0] araddr,
  output logic arready,

  input logic awvalid,
  input logic [4:0] awaddr,
  output logic awready,
  input logic [3:0] awlen,
  input logic [1:0] awburst,
  input logic [2:0] awsize,

  input logic wvalid,
  input logic [15:0] wdata,
  output logic wready,
  input logic wlast,

  input logic bready,
  output logic bvalid,
  output logic [1:0] bresp, 

  output logic [15:0] rdata,
  output logic [1:0] rresp, 
  output logic rlast,
  input logic rready,
  output logic rvalid,

  output logic [7:0] i2c_addr_out,
  output logic [7:0] i2c_data_out,
  output logic start_pulse_out,

  input logic [15:0] status_in,
  input logic [15:0] data_rx_in
);

  typedef enum logic [3:0] {
    IDLE,  
    SETUP,
    SETUPW,
    PREACCESS,
    PREACCESSW,
    ACCESS,
    ACCESSW,
    WTERMINATE
  } state_t;  
  state_t current_state, next_state;

  logic [1:0] burst;
  logic [2:0] size;
  logic [3:0] len;
  
  // Address width matched to memory size [4:0]
  logic [4:0] addr; 
  
  logic last;
  logic [15:0] memory [0:31];

  //FSM
  always_comb begin
    next_state = current_state;

    case(current_state)
      //read cycle state transitions
      IDLE: begin
        if (arvalid)      next_state = SETUP;
        else if (awvalid) next_state = SETUPW;
        else              next_state = IDLE;
      end
      SETUP: begin //latch read address
        if (arvalid)      next_state = PREACCESS;
        else              next_state = IDLE;
      end
      PREACCESS: begin
        // wait cycle for memory data availability
        if (rready)       next_state = ACCESS;
        else              next_state = PREACCESS;
      end
      ACCESS: begin
        // present data and wait for master acceptance rready
        if (rready) 
        begin
          if (len == 4'd1)  next_state = IDLE;
          else              next_state = PREACCESS;
        end
        else 
        begin
          next_state = ACCESS; 
        end
      end
      
      //write 
      SETUPW: begin
        if (awvalid)    next_state = PREACCESSW;
        else            next_state = IDLE;
      end
      PREACCESSW: begin
        if (wvalid)     next_state = ACCESSW;
        else            next_state = PREACCESSW;
      end
      ACCESSW: begin
        // Burst Logic
        if(len != 4'd0) begin
          if (wlast)    next_state = WTERMINATE;
          else          next_state = PREACCESSW;
        end
        else            next_state = WTERMINATE;
      end
      WTERMINATE: begin
        // Handshake: Wait for bready
        if (bready)     next_state = IDLE;
        else            next_state = WTERMINATE;
      end
      default: next_state = IDLE; 
    endcase
  end 
  
  //Reset + State Update + Memory Write
  always_ff @(posedge clk or negedge res_n) begin
    if (!res_n) begin
      current_state <= IDLE;

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

      // Memory Write Logic: Only write when VALID data is present
      if (current_state == ACCESSW && wvalid) begin
        case (addr) 
          5'd0: i2c_addr_out <= wdata[7:0];
          5'd1: i2c_data_out <= wdata[7:0];
          5'd2: if (wdata[0]) start_pulse_out <= 1'b1;
          default: memory[addr] <= wdata;
        endcase
      end
    end
  end

  // address/control latching
  always_ff @(posedge clk) begin
    if (current_state == SETUP) begin
      burst <= arburst;
      size <= arsize;
      len <= arlen + 4'd1;
      addr <= araddr;
    end
    else if (current_state == SETUPW) begin
      burst <= awburst;
      size <= awsize;
      len <= awlen + 1;
      addr <= awaddr;
    end
    else if (current_state == ACCESS || current_state == ACCESSW) begin
      // READ Increment: Only when Master accepts data (rready)
      if (current_state == ACCESS && rready && len != 0) begin
         len <= len - 4'd1;
         if (burst == 2'b01) addr <= addr + 5'd1;
      end
      // WRITE Increment: Only when Master provides valid data (wvalid)
      else if (current_state == ACCESSW && wvalid && len != 0) begin
         len <= len - 4'd1;
         if (burst == 2'b01) addr <= addr + 5'd1;
      end
    end
  end
  
  // Read Logic
  always_comb begin
    rdata = 16'd0;
    last = 1'b0;
    if (current_state == ACCESS) begin
      if (len == 1) last = 1;
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
  assign arready = (current_state == SETUP);
  assign awready = (current_state == SETUPW);
  assign wready  = (current_state == ACCESSW);
  
  // Hardcoded OKAY response to prevent Deadlock
  assign bresp = 2'b00; 
  assign rresp = 2'b00;
  
  assign rvalid = (current_state == ACCESS);
  assign rlast  = (rvalid && last);
  assign bvalid = (current_state == WTERMINATE);
    
endmodule
