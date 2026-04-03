`timescale 1ns/1ps

module async_fifo #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 4
)(
    //write domain APB (100MHz)
    input logic wr_clk,
    input logic wr_rst_n,
    input logic wr_inc,
    input logic [DATA_WIDTH - 1:0] wr_data,
    output logic wr_full,

    //read domain SPI (50MHz)
    input logic rd_clk,
    input logic rd_rst_n,
    input logic rd_inc,
    output logic [DATA_WIDTH - 1:0] rd_data,
    output logic rd_empty
);

    logic [ADDR_WIDTH - 1:0] wr_addr, rd_addr;
    logic [ADDR_WIDTH:0] wrptr_gray, rdptr_gray;
    logic [ADDR_WIDTH:0] wq2_rdptr_gray, rq2_wrptr_gray;

    dual_port_ram #(
        .DATA_WIDTH(DATA_WIDTH /* default 16 */),
        .ADDR_WIDTH(ADDR_WIDTH /* default 4 */)
    ) u_ram (
        .wr_clk (wr_clk),
        .wr_en  (wr_inc & ~wr_full),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    // synchronize read ptr into write domain for full flag
    sync_ptr #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 4 */)
    ) u_sync_r2w (
        .dest_clk  (wr_clk),
        .dest_rst_n(wr_rst_n),
        .ptr_in    (rdptr_gray),
        .ptr_out_q2(wq2_rdptr_gray)
    );

    // synchronize write ptr into read domain for empty flag
    sync_ptr #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 4 */)
    ) u_sync_w2r (
        .dest_clk  (rd_clk),
        .dest_rst_n(rd_rst_n),
        .ptr_in    (wrptr_gray),
        .ptr_out_q2(rq2_wrptr_gray)
    );

    // write ptr and full flag logic
    fifo_wptr #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 4 */)
     ) fifo_wptr (
        .wr_clk        (wr_clk),
        .wr_rst_n      (wr_rst_n),
        .wr_inc        (wr_inc),
        .wq2_rdptr_gray(wq2_rdptr_gray),
        .wr_full       (wr_full),
        .wr_addr       (wr_addr),
        .wrptr_gray    (wrptr_gray)
    );

    // read ptr and empty flag logic
    fifo_rptr #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 4 */)
     ) fifo_rptr (
        .rd_clk        (rd_clk),
        .rd_rst_n      (rd_rst_n),
        .rd_inc        (rd_inc),
        .rq2_wrptr_gray(rq2_wrptr_gray),
        .rd_empty      (rd_empty),
        .rd_addr       (rd_addr),
        .rdptr_gray    (rdptr_gray)
    );

endmodule