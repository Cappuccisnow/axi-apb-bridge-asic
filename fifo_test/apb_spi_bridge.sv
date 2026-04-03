`timescale 1ns/1ps

module apb_spi_bridge(

  // APB
  input logic PCLK,
  input logic PRESETn,
  input logic [31:0] PADDR,
  input logic PWRITE,
  input logic PSEL,
  input logic PENABLE,
  input logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic PREADY,
  
  output logic spi_interrupt,
  
  // SPI
  input logic SPI_CLK_EXT, //new spi clock 
  output logic [3:0] cs_n,
  output logic sclk,
  output logic mosi,
  input logic miso
);
  
  logic [15:0] tx_fifo_rd_data, rx_fifo_rd_data;
  logic tx_fifo_empty, tx_fifo_full;
  logic rx_fifo_empty, rx_fifo_full;
  logic tx_fifo_rd_en, rx_fifo_wr_en;

  // dynamic control register (addr 0x08)
  logic [15:0] spi_ctrl_reg;

  // slave select register (addr 0x0C)
  logic [1:0] spi_ss_reg;
  logic core_cs_n;

  // SPI master and control logic
  logic [15:0] spi_rx_raw;
  logic spi_busy, spi_done;

  // APB handshake
  assign PREADY = 1'b1;

  // tx fifo: CPU -> SPI (100MHZ -> 50MHz)
  async_fifo #(
    .DATA_WIDTH(16),
    .ADDR_WIDTH(4)
   ) u_tx_fifo (
    .wr_clk  (PCLK),
    .wr_rst_n(PRESETn),
    .wr_inc  (PSEL && PENABLE && PWRITE && (PADDR[7:0] == 8'h00)),
    .wr_data (PWDATA[15:0]),
    .wr_full (tx_fifo_full),
    .rd_clk  (SPI_CLK_EXT),
    .rd_rst_n(PRESETn),
    .rd_inc  (tx_fifo_rd_en),
    .rd_data (tx_fifo_rd_data),
    .rd_empty(tx_fifo_empty)
  );
  
  // rx fifo: SPI -> CPU
  async_fifo #(
    .DATA_WIDTH(16),
    .ADDR_WIDTH(4)
  ) u_rx_fifo (
    .wr_clk  (SPI_CLK_EXT),
    .wr_rst_n(PRESETn),
    .wr_inc  (rx_fifo_wr_en),
    .wr_data (spi_rx_raw),
    .wr_full (rx_fifo_full),
    .rd_clk  (PCLK),
    .rd_rst_n(PRESETn),
    .rd_inc  (PSEL && PENABLE && !PWRITE && (PADDR[7:0] == 8'h00)),
    .rd_data (rx_fifo_rd_data),
    .rd_empty(rx_fifo_empty)
  );

  // apb write for control reg
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      // default reset state (divider = 2, CPOL = 0, CPHA = 0)
      spi_ctrl_reg <= 16'h0200;
      spi_ss_reg <= 2'b00;
    end
    else if (PSEL && PENABLE && PWRITE && PREADY) begin
      if (PADDR[7:0] == 8'h08) begin
        spi_ctrl_reg <= PWDATA[15:0];
      end
      else if (PADDR[7:0] == 8'h0C) begin
        spi_ss_reg <= PWDATA[1:0];
      end
    end
  end

  // apb read mux
  always_comb begin
    PRDATA = '0;
    if (PSEL && !PWRITE) begin
      case (PADDR[7:0])
        8'h00: PRDATA = {16'd0, rx_fifo_rd_data};
        8'h04: PRDATA = {28'd0, rx_fifo_full, rx_fifo_empty, tx_fifo_full, tx_fifo_empty};
        8'h08: PRDATA = {16'd0, spi_ctrl_reg};
        8'h0C: PRDATA = {30'd0, spi_ss_reg};
        default: PRDATA = '0;
      endcase
    end
  end
    
  assign tx_fifo_rd_en = !tx_fifo_empty && !spi_busy;

  spi_core u_spi_core (
    .clk(SPI_CLK_EXT),
    .reset(!PRESETn), // APB is active low, Core is active high
    .start(tx_fifo_rd_en),
    .datain(tx_fifo_rd_data),
    .dataout(spi_rx_raw),
    .busy(spi_busy),
    .done(spi_done),

    .clk_div(spi_ctrl_reg[15:8]),
    .cpol(spi_ctrl_reg[1]),
    .cpha(spi_ctrl_reg[0]),

    .cs_n(core_cs_n),
    .sclk(sclk),
    .mosi(mosi),
    .miso(miso)
  );

  // demux for slave select
  always_comb begin
    cs_n = 4'b1111;
    cs_n[spi_ss_reg] = core_cs_n;
  end

  assign rx_fifo_wr_en = spi_done;
  //assign spi_interrupt = spi_done;

  logic [2:0] interrupt_sync_shift;
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      interrupt_sync_shift <= 3'b000;
    end
    else begin
      interrupt_sync_shift <= {interrupt_sync_shift[1:0], spi_done};
    end
  end
  assign spi_interrupt = {interrupt_sync_shift[1] & ~interrupt_sync_shift[2]};

endmodule
