`timescale 1ns/1ps
module tb_ahb_lite_slave;
    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 32;

    logic HCLK;
    logic HRESETn;
    logic HSEL;
    logic [31:0] HADDR;
    logic HWRITE;
    logic [1:0] HTRANS;
    logic [2:0] HSIZE;
    logic HREADY;
    logic [31:0] HWDATA;
    logic HREADYOUT;
    logic HRESP;
    logic [31:0] HRDATA;

    localparam IDLE = 2'b00;
    localparam BUSY = 2'b01;
    localparam NONSEQ = 2'b10;
    localparam SEQ = 2'b11;

    localparam SIZE_8 = 3'b000;
    localparam SIZE_16 = 3'b001;
    localparam SIZE_32 = 3'b010;

    ahb_lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 32 */)
     ) ahb_lite_slave (
        .HCLK     (HCLK),
        .HRESETn  (HRESETn),
        .HSEL     (HSEL),
        .HADDR    (HADDR),
        .HWRITE   (HWRITE),
        .HTRANS   (HTRANS),
        .HSIZE    (HSIZE),
        .HREADY   (HREADY),
        .HWDATA   (HWDATA),
        .HREADYOUT(HREADYOUT),
        .HRESP    (HRESP),
        .HRDATA   (HRDATA)
    );

    // master's HREADY connects to slave's HREADYOUT
    assign HREADY = HREADYOUT;

    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK; //100 MHz
    end

    task ahb_single_write(input [31:0] addr, input [31:0] data, input [2:0] size);
        begin
            //address phase
            @(posedge HCLK);
            HSEL <= 1'b1;
            HTRANS <= NONSEQ;
            HADDR <= addr;
            HWRITE <= 1'b1;
            HSIZE <= size;

            //data phase
            @(posedge HCLK);
            HTRANS <= IDLE;
            HSEL <= 1'b0;
            HWDATA <= data;

            @(posedge HCLK);
        end
    endtask

    task ahb_single_read(input [31:0] addr, input [2:0] size);
        begin
            //address phase
            @(posedge HCLK);
            HSEL <= 1'b1;
            HTRANS <= NONSEQ;
            HADDR <= addr;
            HWRITE <= 1'b0;
            HSIZE <= size;

            //data phase
            @(posedge HCLK);
            HTRANS <= IDLE;
            HSEL <= 1'b0;

            @(posedge HCLK);
            $display("[AHB read] Addr: 0x%08h | Data: 0x%08h", addr, HRDATA);
        end
    endtask

    initial begin
        HRESETn = 0;
        HSEL = 0;
        HADDR = 0;
        HWRITE = 0;
        HTRANS = IDLE;
        HSIZE = SIZE_32;
        HWDATA = 0;

        repeat(5) @(posedge HCLK);
        HRESETn = 1;
        repeat(2) @(posedge HCLK);

        $display("--- Pipelined burst write (3 words) ---");
        @(posedge HCLK);
        HSEL <= 1'b1;
        HTRANS <= NONSEQ;
        HWRITE <= 1'b1;
        HSIZE <= SIZE_32;
        HADDR <= 32'h0000_0000;

        @(posedge HCLK);
        HWDATA <= 32'hAAAA_1111;
        HTRANS <= SEQ;
        HADDR <= 32'h0000_0004;

        @(posedge HCLK);
        HWDATA <= 32'hBBBB_2222;
        HTRANS <= SEQ;
        HADDR <= 32'h0000_0008;

        @(posedge HCLK);
        HWDATA <= 32'hCCCC_3333;
        HTRANS <= IDLE;
        HSEL <= 1'b0;

        @(posedge HCLK);

        $display("--- Byte and half-word masking ---");

        //write 32 bit word
        ahb_single_write(32'h0000_000C, 32'hFFFF_FFFF, SIZE_32);

        //overwrite lower 16 bits 
        ahb_single_write(32'h0000_000C, 32'h0000_4444, SIZE_16);

        //overwrite only the third byte (8 bit)
        //skip to the third byte by +2 address: 0x0C + 2 = 0x0E
        ahb_single_write(32'h0000_000E, 32'h0099_0000, SIZE_8);

        $display("--- Results read ---");
        ahb_single_read(32'h0000_0000, SIZE_32);
        ahb_single_read(32'h0000_0004, SIZE_32);
        ahb_single_read(32'h0000_0008, SIZE_32);

        ahb_single_read(32'h0000_000C, SIZE_32);

        repeat(5) @(posedge HCLK);
        $display("--- Simulation complete ---");
        $finish;
    end

endmodule