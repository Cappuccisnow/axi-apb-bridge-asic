`timescale 1ns/1ps

module fifo_wptr #(
    parameter ADDR_WIDTH = 4
)(
    input logic wr_clk,
    input logic wr_rst_n,
    input logic wr_inc, //increment (from APB)
    input logic [ADDR_WIDTH:0] wq2_rdptr_gray, //synced read ptr from SPI domain

    output logic wr_full, //full flag
    output logic [ADDR_WIDTH - 1:0] wr_addr,
    output logic [ADDR_WIDTH:0] wrptr_gray
);

    logic [ADDR_WIDTH:0] wr_binary;
    logic [ADDR_WIDTH:0] wr_binary_next;
    logic [ADDR_WIDTH:0] wr_gray_next;

    logic wr_full_next;

    // binary counter
    always_comb begin
        wr_binary_next = wr_binary + (ADDR_WIDTH + 1)'(wr_inc & ~wr_full); // increment if requested and not full
    end

    assign wr_addr = wr_binary[ADDR_WIDTH - 1:0];

    // binary to gray logic
    always_comb begin
        wr_gray_next = wr_binary_next ^ (wr_binary_next >> 1);
    end

    // full logic
    always_comb begin
        wr_full_next = (wr_gray_next == (wq2_rdptr_gray ^ (2'b11 << (ADDR_WIDTH - 1))));
    end

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_binary <= '0;
            wrptr_gray <= '0;
            wr_full <= 1'b0;
        end
        else begin
            wr_binary <= wr_binary_next;
            wrptr_gray <= wr_gray_next;
            wr_full <= wr_full_next;
        end
    end
endmodule 