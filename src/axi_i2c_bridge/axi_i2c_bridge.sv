`timescale 1ns/1ps

module axi_i2c_bridge (
  input logic clk,
  input logic res_n,
  
  //AXI interface pins
  input logic arvalid, awvalid, wvalid, bready, rready,
  input logic [4:0] araddr, awaddr,
  input logic [15:0] wdata,
  input logic [3:0] arlen, awlen,
  input logic [2:0] arsize, awsize,
  input logic [1:0] arburst, awburst,
  input logic wlast,
  
  output logic arready, awready, wready,
  output logic bvalid, rvalid,
  output logic [1:0] bresp,
  output logic [1:0] rresp,
  output logic rlast,
  output logic [15:0] rdata,
  
  //I2C
  inout wire logic sda, 
  output logic scl
);
  
  //Register decode
  // logic write_addr = (awvalid && wvalid && awaddr == 5'd0);
  // logic write_data = (awvalid && wvalid && awaddr == 5'd1);
  // logic write_ctrl = (awvalid && wvalid && awaddr == 5'd2);
  
  //internal registers
  logic [7:0] i2c_addr;
  logic [7:0] i2c_data;
  logic       start_pulse;

  logic i2c_busy_flag;
  logic [7:0] i2c_read_byte;
  logic dummy_clk2;
  logic unused_rw;

  logic [15:0] status_sig;
  logic [15:0] rx_data_sig;
  assign status_sig = {15'd0, i2c_busy_flag};
  assign rx_data_sig = {8'd0, i2c_read_byte};
  
  axi_slave u_axi(    
    .clk(clk), .res_n(res_n), 
    .arvalid(arvalid), .araddr(araddr), .arlen(arlen), .arsize(arsize), 
    .arburst(arburst), .arready(arready), 
    .awvalid(awvalid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize), 
    .awburst(awburst), .awready(awready), 
    .wvalid(wvalid), .wdata(wdata), .wlast(wlast), .wready(wready),
    .bready(bready), .bvalid(bvalid), .bresp(bresp),
    .rready(rready), .rvalid(rvalid), .rresp(rresp), .rlast(rlast), .rdata(rdata),
    
    .i2c_addr_out(i2c_addr),
    .i2c_data_out(i2c_data),
    .start_pulse_out(start_pulse),

    .status_in(status_sig), 
    .data_rx_in(rx_data_sig)
  );

  i2c_master u_i2c(
    .clk100mhz(clk),
    .reset(~res_n),
    .addr_to_send(i2c_addr), .data_to_send(i2c_data),
    .sda(sda), .scl(scl), .clk2mhz_dummy(dummy_clk2), .rw(unused_rw),
    .new_cmd(start_pulse),
    
    .busy(i2c_busy_flag),           
    .read_data_out(i2c_read_byte)   
  );

endmodule
