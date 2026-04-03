`timescale 1ns/1ps

module axi_i2c_bridge (
  input logic clk,
  input logic res_n,
  
  //AXI interface pins
  input logic arvalid, awvalid, wvalid, bready, rready,
  input logic [4:0] araddr, awaddr,
  input logic [15:0] wdata,
  
  output logic arready, awready, wready,
  output logic bvalid, rvalid,
  output logic [1:0] bresp, rresp,
  output logic [15:0] rdata,
  
  //I2C
  inout wire logic sda, 
  inout wire logic scl
);
  

  //internal registers
  logic [7:0] i2c_target_addr;
  logic [7:0] i2c_write_data;
  logic       i2c_start_trigger;

  logic i2c_busy_status;
  logic [7:0] i2c_rx_byte;
  logic i2c_ack_err_status;

  logic [15:0] status_register;
  logic [15:0] rx_data_register;

  assign status_register = {14'd0, i2c_ack_err_status, i2c_busy_status};
  assign rx_data_register = {8'd0, i2c_rx_byte};
  
  axi_lite_slave axi_lite_slave (
    .clk            (clk),
    .res_n          (res_n),
    .arvalid        (arvalid),
    .araddr         (araddr),
    .arready        (arready),
    .rdata          (rdata),
    .rresp          (rresp),
    .rready         (rready),
    .rvalid         (rvalid),
    .awvalid        (awvalid),
    .awaddr         (awaddr),
    .awready        (awready),
    .wvalid         (wvalid),
    .wdata          (wdata),
    .wready         (wready),
    .bready         (bready),
    .bvalid         (bvalid),
    .bresp          (bresp),

    .i2c_addr_out   (i2c_target_addr),
    .i2c_data_out   (i2c_write_data),
    .start_pulse_out(i2c_start_trigger),
    .status_in      (status_register),
    .data_rx_in     (rx_data_register)
  );

i2c_master #(
  .CLOCK_FREQ(100_000_000), 
  .I2C_FREQ(100_000)
 ) u_i2c (
  .clk100mhz(clk),
  .reset(~res_n),
  .sda(sda),
  .scl(scl),
  
  .addr_to_send(i2c_target_addr),
  .data_to_send(i2c_write_data),
  .new_cmd(i2c_start_trigger),
  .busy(i2c_busy_status),
  .ack_error(i2c_ack_err_status),
  .read_data_out(i2c_rx_byte)
);

endmodule
