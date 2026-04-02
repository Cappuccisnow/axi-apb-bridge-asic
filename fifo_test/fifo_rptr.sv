`timescale 1ns/1ps

module fifo_rptr #(
    parameter ADDR_WIDTH = 4
)(
    input logic rd_clk,
    input logic rd_rst_n,
    input logic rd_inc, //increment (from APB)
    input logic [ADDR_WIDTH:0] rq2_wrptr_gray, //synced read ptr from SPI domain

    output logic rd_empty, //empty flag
    output logic [ADDR_WIDTH - 1:0] rd_addr,
    output logic [ADDR_WIDTH:0] rdptr_gray
);

    logic [ADDR_WIDTH:0] rd_binary;
    logic [ADDR_WIDTH:0] rd_binary_next;
    logic [ADDR_WIDTH:0] rd_gray_next;

    logic rd_empty_next;

    // binary counter
    always_comb begin
        rd_binary_next = rd_binary + (ADDR_WIDTH + 1)'(rd_inc & ~rd_empty); // increment if requested and not full
    end

    assign rd_addr = rd_binary[ADDR_WIDTH - 1:0];

    // binary to gray logic
    always_comb begin
        rd_gray_next = rd_binary_next ^ (rd_binary_next >> 1);
    end

    // empty logic
    always_comb begin
        rd_empty_next = (rd_gray_next == rq2_wrptr_gray);
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_binary <= '0;
            rdptr_gray <= '0;
            rd_empty <= 1'b1;
        end
        else begin
            rd_binary <= rd_binary_next;
            rdptr_gray <= rd_gray_next;
            rd_empty <= rd_empty_next;
        end
    end
endmodule 