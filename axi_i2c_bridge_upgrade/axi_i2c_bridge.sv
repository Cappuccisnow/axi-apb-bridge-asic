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
  inout wire logic scl,

  // interrupt
  output logic i2c_interrupt
);
  

  //internal registers
  logic [7:0] i2c_target_addr;
  //logic [7:0] i2c_write_data;
  logic       i2c_start_trigger;
  logic       i2c_hold_bus;
  logic i2c_busy_status;
  logic i2c_ack_err_status;
  logic busy_q;
  logic ack_error_q;

  //logic [7:0] i2c_rx_byte;

  // fifo wires
  logic tx_wr_en, tx_rd_en;
  logic tx_full, tx_empty;
  logic [7:0] tx_data_in, tx_data_out;

  logic rx_wr_en, rx_rd_en;
  logic rx_full, rx_empty;
  logic [7:0] rx_data_in, rx_data_out;

  logic [15:0] status_register;
  logic [15:0] rx_data_register;

  assign status_register = {10'd0, rx_empty, rx_full, tx_empty, tx_full, i2c_ack_err_status, i2c_busy_status};
  assign rx_data_register = {8'd0, rx_data_out};
  
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
    .start_pulse_out(i2c_start_trigger),
    .hold_bus_out   (i2c_hold_bus),

    .tx_data_out    (tx_data_in),
    .tx_wr_en       (tx_wr_en),
    .rx_rd_en       (rx_rd_en),

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
    .data_to_send(tx_data_out),
    .new_cmd(i2c_start_trigger),
    .hold_bus(i2c_hold_bus),
    .busy(i2c_busy_status),
    .ack_error(i2c_ack_err_status),
    .read_data_out(rx_data_in),
    .tx_empty(tx_empty),
    .tx_rd_en(tx_rd_en),
    .rx_wr_en(rx_wr_en)
  );

  // tx fifo (cpu writes i2c reads)
  async_fifo #(
    .DATA_WIDTH(8),
    .ADDR_WIDTH(4)
   ) u_tx_fifo (
    .wr_clk  (clk),
    .wr_rst_n(res_n),
    .wr_inc  (tx_wr_en),
    .wr_data (tx_data_in),
    .wr_full (tx_full),
    .rd_clk  (clk),
    .rd_rst_n(res_n),
    .rd_inc  (tx_rd_en),
    .rd_data (tx_data_out),
    .rd_empty(tx_empty)
  );

  // rx fifo (i2c writes, cpu reads)
  async_fifo #(
    .DATA_WIDTH(8),
    .ADDR_WIDTH(4)
  ) u_rx_fifo (
    .wr_clk  (clk),
    .wr_rst_n(res_n),
    .wr_inc  (rx_wr_en),
    .wr_data (rx_data_in),
    .wr_full (rx_full), 
    .rd_clk  (clk),
    .rd_rst_n(res_n),
    .rd_inc  (rx_rd_en),
    .rd_data (rx_data_out),
    .rd_empty(rx_empty)
  );

  // irq generation
  always_ff @(posedge clk or negedge res_n) begin
    if (!res_n) begin
      busy_q <= 1'b0;
      ack_error_q <= 1'b0;
    end
    else begin
      busy_q <= i2c_busy_status;
      ack_error_q <= i2c_ack_err_status;
    end
  end

  assign i2c_interrupt = (busy_q && !i2c_busy_status) || (!ack_error_q && i2c_ack_err_status);
endmodule
