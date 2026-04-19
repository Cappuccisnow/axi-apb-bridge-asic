`timescale 1ns/1ps

module ahb_lite_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic HCLK,
    input logic HRESETn,

    input logic ctrl_start,
    input logic ctrl_write, //1 = write, 0 = read
    input logic [ADDR_WIDTH - 1:0] ctrl_addr,
    input logic [DATA_WIDTH - 1:0] ctrl_wdata,
    input logic [2:0] ctrl_size,
    
    output logic ctrl_busy,
    output logic ctrl_done,
    output logic [DATA_WIDTH - 1:0] ctrl_rdata,
    output logic ctrl_error,

    // ahb master interface
    output logic [ADDR_WIDTH - 1:0] HADDR,
    output logic HWRITE,
    output logic [1:0] HTRANS,
    output logic [2:0] HSIZE,
    output logic [2:0] HBURST,
    output logic [3:0] HPROT,
    output logic [DATA_WIDTH - 1:0] HWDATA,

    input logic HREADY,
    input logic HRESP,
    input logic [DATA_WIDTH - 1:0] HRDATA
);

    localparam IDLE = 2'b00;
    localparam NONSEQ = 2'b10;

    assign HBURST = 3'b000; //single burst
    assign HPROT = 4'b0011; //non cacheable privileged access

    typedef enum logic [1:0] {
        S_IDLE,
        S_ADDR_PHASE,
        S_DATA_PHASE    
    } state_t;
    state_t state;
    logic [DATA_WIDTH - 1:0] wdata_reg;

    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state <= S_IDLE;
            HTRANS <= IDLE;
            HADDR <= '0;
            HWRITE <= 1'b0;
            HSIZE <= 3'b010;
            HWDATA <= '0;
            wdata_reg <= '0;
            ctrl_done <=1'b0;
            ctrl_error <= 1'b0;
            ctrl_rdata <= '0;
        end
        else begin
            ctrl_done <= 1'b0;

            case (state) 
                S_IDLE: begin
                    if (ctrl_start) begin
                        //enter addr phase
                        HTRANS <= NONSEQ;
                        HADDR <= ctrl_addr;
                        HWRITE <= ctrl_write;
                        HSIZE <= ctrl_size;
                        wdata_reg <= ctrl_wdata;
                        state <= S_ADDR_PHASE;
                    end
                    else begin
                        HTRANS <= IDLE;
                    end
                end

                S_ADDR_PHASE: begin
                    if (HREADY) begin
                        HTRANS <= IDLE;
                    end
                    //enter data phase
                    if (HWRITE) begin
                        HWDATA <= wdata_reg;
                    end
                    state <= S_DATA_PHASE;
                end

                S_DATA_PHASE: begin
                    if (HREADY) begin
                        if (!HWRITE) begin
                            ctrl_rdata <= HRDATA;
                        end
                        ctrl_error <= HRESP;
                        ctrl_done <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end 
    end

    assign ctrl_busy = (state != S_IDLE);
endmodule