module axi_i2c_bridge (
  input wire clk,
  input wire res_n,
  
  //AXI interface pins
  input wire arvalid, awvalid, wvalid, bready, rready,
  input wire [4:0] araddr, awaddr,
  input wire [15:0] wdata,
  input wire [3:0] arlen, awlen,
  input wire [2:0] arsize, awsize,
  input wire [1:0] arburst, awburst,
  input wire wlast,
  
  output wire arready, awready, wready,
  output wire bvalid, rvalid,
  output wire [1:0] bresp,
  output wire [1:0] rresp,
  output wire rlast,
  output wire [15:0] rdata,
  
  //I2C
  inout wire sda, 
  output wire scl
);
  
  //Register decode
  wire write_addr = (awvalid && wvalid && awaddr == 5'd0);
  wire write_data = (awvalid && wvalid && awaddr == 5'd1);
  wire write_ctrl = (awvalid && wvalid && awaddr == 5'd2);
  
  //internal registers
  reg [7:0] i2c_addr;
  reg [7:0] i2c_data;
  reg       start_pulse;
  
  always @(posedge clk or negedge res_n) begin
      if (!res_n) begin
        i2c_addr <= 8'h00;
        i2c_data <= 8'h00;
        start_pulse <= 1'b0;
      end 
      else begin
        start_pulse <= 1'b0; //one cycle pulse
        if (write_addr)
          i2c_addr <= wdata[7:0];
        if (write_data)
          i2c_data <= wdata[7:0];
        if (write_ctrl && wdata[0])
          start_pulse <= 1'b1;
      end
    end  
  
  wire [15:0] status_sig;
  wire [15:0] rx_data_sig;
  wire i2c_busy_flag;
  wire [7:0] i2c_read_byte;
  
  wire dummy_clk2;
  wire unused_rw;
  wire _unused_ok = &{1'b0, dummy_clk2, unused_rw, 1'b0};
  //connecting internal status signals
  assign status_sig = {15'd0, i2c_busy_flag};
  assign rx_data_sig = {8'd0, i2c_read_byte};
  
  axi_slave u_axi(    //
    .clk(clk), .res_n(res_n), 
    .arvalid(arvalid), .araddr(araddr), .arlen(arlen), .arsize(arsize), 
    .arburst(arburst), .arready(arready), 
    .awvalid(awvalid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), 
    .awburst(awburst), .awready(awready), 
    .wvalid(wvalid), .wdata(wdata), .wlast(wlast), .wready(wready),
    .bready(bready), .bvalid(bvalid), .bresp(bresp),
    .rready(rready), .rvalid(rvalid), .rresp(rresp), .rlast(rlast), .rdata(rdata),
    .status_in(status_sig), .data_rx_in(rx_data_sig)
  );
      
  i2c_master u_i2c(
    .clk100mhz(clk),
    .res(~res_n),
    .addr_to_send(i2c_addr), .data_to_send(i2c_data),
    .sda(sda), .scl(scl), .clk2mhz_dummy(dummy_clk2), .rw(unused_rw),
    .new_cmd(start_pulse),
    
    .busy(i2c_busy_flag),           
    .read_data_out(i2c_read_byte)   
  );
endmodule
