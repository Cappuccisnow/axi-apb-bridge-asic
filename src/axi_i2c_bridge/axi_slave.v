module axi_slave(
  input wire clk, arvalid, res_n,  
  input wire [1:0] arburst,
  input wire [2:0] arsize,
  input wire [3:0] arlen,
  input wire [4:0] araddr,
  output wire arready,

  input wire awvalid,
  input wire [4:0] awaddr,
  output wire awready,
  input wire [3:0] awlen,
  input wire [1:0] awburst,
  input wire [2:0] awsize,

  input wire wvalid,
  input wire [15:0] wdata,
  output wire wready,
  input wire wlast,

  input wire bready,
  output wire bvalid,
  output wire [1:0] bresp, 

  output reg [15:0] rdata,
  output wire [1:0] rresp, 
  output wire rlast,
  input wire rready,
  output wire rvalid,

  input wire [15:0] status_in,
  input wire [15:0] data_rx_in
);
    
  localparam [3:0] IDLE = 4'b0001, SETUP = 4'b0010, PREACCESS = 4'b0100, ACCESS = 4'b1000, 
                   SETUPW = 4'b0011, PREACCESSW = 4'b0111, ACCESSW = 4'b1111, WTERMINATE = 4'b0101;
  
  reg [3:0] current_state, next_state;
  reg [1:0] burst;
  reg [2:0] size;
  reg [3:0] len;
  
  // Address width matched to memory size [4:0]
  reg [4:0] addr; 
  
  reg last;
  reg [15:0] memory [0:31];
  integer i;
  
  // COMBINED LOGIC: Reset + State Update + Memory Write
  always @(posedge clk or negedge res_n) begin
    if (!res_n) begin
      current_state <= IDLE;
      // Reset memory
      for (i = 0; i < 32; i = i + 1) memory[i] <= 16'd0;
      memory[0] <= 16'hffff;
      memory[1] <= 16'h1111;
    end else begin
      current_state <= next_state;
      
      // Memory Write Logic: Only write when VALID data is present
      if (current_state == ACCESSW && wvalid) begin
        memory[addr] <= wdata;
      end
    end
  end

  // Next State Logic
  always @(*) begin
    next_state = current_state;
    case(current_state)
      //read cycle state transitions
      IDLE : begin
        if(arvalid) next_state = SETUP;
        else if(awvalid) next_state = SETUPW;
        else next_state = IDLE;
      end
      SETUP : begin //latch read address
        if(arvalid) next_state = PREACCESS;
        else next_state = IDLE;
      end
      PREACCESS : begin
        // wait cycle for memory data availability
        if(rready) next_state = ACCESS;
        else next_state = PREACCESS;
      end
      ACCESS : begin
        // present data and wait for master acceptance rready
        if (rready) begin
            if (len == 4'd1) next_state = IDLE;
            else next_state = PREACCESS;
        end
        else begin
            next_state = ACCESS; 
        end
      end
      
      SETUPW : begin
        if (awvalid) next_state = PREACCESSW;
        else next_state = IDLE;
      end
      PREACCESSW : begin
        if(wvalid) next_state = ACCESSW;
        else next_state = PREACCESSW;
      end
      ACCESSW : begin
        // Burst Logic
        if(len != 4'd0) begin
          if(wlast) next_state = WTERMINATE;
          else next_state = PREACCESSW;
        end
        else next_state = WTERMINATE;
      end
      WTERMINATE : begin
        // Handshake: Wait for bready
        if(bready) next_state = IDLE;
        else next_state = WTERMINATE;
      end


      default : next_state = IDLE; 
    endcase
  end 
  
  // address/control latching
  always @(posedge clk) begin
    if (current_state == SETUP) begin
       burst <= arburst;
      size <= arsize;
      len <= arlen + 1;
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
         len <= len - 1;
         if (burst == 2'b01) addr <= addr + 1;
      end
      // WRITE Increment: Only when Master provides valid data (wvalid)
      else if (current_state == ACCESSW && wvalid && len != 0) begin
         len <= len - 1;
         if (burst == 2'b01) addr <= addr + 1;
      end
    end
  end
  
  // Read Logic (Combinational)
  always @(*) begin
    rdata = 16'd0;
    last = 0;
    if (current_state == ACCESS) begin
      if (len == 1) last = 1;
      case (addr)
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