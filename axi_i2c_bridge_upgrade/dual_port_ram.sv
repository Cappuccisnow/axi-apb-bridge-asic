`timescale 1ns/1ps

module dual_port_ram #(
    parameter DATA_WIDTH = 16, 
    parameter ADDR_WIDTH = 4
)(
    //write port (apb clock domain)
    input logic wr_clk,
    input logic wr_en,
    input logic [ADDR_WIDTH - 1:0] wr_addr,
    input logic [DATA_WIDTH - 1:0] wr_data,

    //read port (spi clock domain)
    input logic [ADDR_WIDTH - 1:0] rd_addr,
    output logic [DATA_WIDTH - 1:0] rd_data
);

    logic [DATA_WIDTH - 1:0] mem [0:(1 << ADDR_WIDTH) - 1];

    always_ff @(posedge wr_clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

    assign rd_data = mem[rd_addr];

endmodule