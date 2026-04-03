`timescale 1ns/1ps

module sync_ptr #(
    parameter ADDR_WIDTH = 4
)(
    input logic dest_clk,
    input logic dest_rst_n,
    input logic [ADDR_WIDTH:0] ptr_in, //gray ptr arriving from foreign clock domain
    output logic [ADDR_WIDTH:0] ptr_out_q2 //sync ptr for local domain
);

    logic [ADDR_WIDTH:0] ptr_q1;

    always_ff @(posedge dest_clk or negedge dest_rst_n) begin
        if (!dest_rst_n) begin
            ptr_q1 <= '0;
            ptr_out_q2 <= '0;
        end
        else begin
            ptr_q1 <= ptr_in;
            ptr_out_q2 <= ptr_q1;
        end 
    end

endmodule