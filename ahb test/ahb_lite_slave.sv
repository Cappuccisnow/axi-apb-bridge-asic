`timescale 1ns/1ps

module ahb_lite_slave #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic HCLK,
    input logic HRESETn,

    // address/control phase 
    input logic HSEL,
    input logic [ADDR_WIDTH - 1:0] HADDR,
    input logic HWRITE,
    input logic [1:0] HTRANS, //00=IDLE, 01=BUSY, 10=NONSEQ, 11=SEQ
    input logic [2:0] HSIZE,
    input logic HREADY,

    // data phase
    input logic [DATA_WIDTH - 1:0] HWDATA,

    // slave output 
    output logic HREADYOUT,
    output logic HRESP,
    output logic [DATA_WIDTH - 1:0] HRDATA
);

    logic [DATA_WIDTH - 1:0] memory [0:1023];

    logic [ADDR_WIDTH - 1:0] haddr_reg;
    logic active_write_phase;
    logic [2:0] hsize_reg;


    // address phase capture
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            haddr_reg <= '0;
            active_write_phase <= 1'b0;
            hsize_reg <= 3'b010; // default to 32 bit word
        end
        else if (HREADY) begin
            // HTRANS[1] = 1 means valid transfer -> capture data
            if (HSEL && HTRANS[1]) begin
                haddr_reg <= HADDR;
                active_write_phase <= HWRITE;
                hsize_reg <= HSIZE;
            end
            else begin
                active_write_phase <= 1'b0;
            end
        end
    end

    // data phase
    logic [9:0] word_addr;
    logic [3:0] write_mask;
    logic [1:0] byte_offset;

    assign word_addr = haddr_reg[11:2];
    assign byte_offset = haddr_reg[1:0];

    always_comb begin
        write_mask = 4'b0000;

        if (active_write_phase && HREADY) begin
            case (hsize_reg)
                3'b000: write_mask[byte_offset] = 1'b1;
                3'b001: write_mask[{byte_offset[1], 1'b0} +: 2] = 2'b11;
                3'b010: write_mask = 4'b1111;
                default: write_mask = 4'b1111;
            endcase
        end
    end

    // mem write 
    always_ff @(posedge HCLK) begin
        if (write_mask[0]) memory[word_addr][7:0]   <= HWDATA[7:0];
        if (write_mask[1]) memory[word_addr][15:8]  <= HWDATA[15:8];
        if (write_mask[2]) memory[word_addr][23:16]  <= HWDATA[23:16];
        if (write_mask[3]) memory[word_addr][31:24]  <= HWDATA[31:24];
    end

    //mem read
    assign HRDATA = memory[word_addr];

    // slave status (zero wait state)
    assign HREADYOUT = 1'b1;
    assign HRESP = 1'b0;

endmodule