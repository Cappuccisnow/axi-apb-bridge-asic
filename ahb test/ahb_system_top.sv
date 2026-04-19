`timescale 1ns/1ps

module ahb_system_top #(
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
    output logic ctrl_error
);

    logic [ADDR_WIDTH - 1:0] haddr_wire;
    logic hwrite_wire;
    logic [1:0] htrans_wire;
    logic [2:0] hsize_wire;
    logic [DATA_WIDTH - 1:0] hwdata_wire;

    logic [DATA_WIDTH - 1:0] hrdata_wire;
    logic hresp_wire;
    logic hready_wire;

    ahb_lite_master #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 32 */)
     ) ahb_lite_master (
        .HCLK      (HCLK),
        .HRESETn   (HRESETn),
        .ctrl_start(ctrl_start),
        .ctrl_write(ctrl_write),
        .ctrl_addr (ctrl_addr),
        .ctrl_wdata(ctrl_wdata),
        .ctrl_size (ctrl_size),
        .ctrl_busy (ctrl_busy),
        .ctrl_done (ctrl_done),
        .ctrl_rdata(ctrl_rdata),
        .ctrl_error(ctrl_error),
        .HADDR     (haddr_wire),
        .HWRITE    (hwrite_wire),
        .HTRANS    (htrans_wire),
        .HSIZE     (hsize_wire),
        .HBURST    (),
        .HPROT     (),
        .HWDATA    (hwdata_wire),
        .HREADY    (hready_wire),
        .HRESP     (hresp_wire),
        .HRDATA    (hrdata_wire)
    );

    ahb_lite_slave #(
        .ADDR_WIDTH(ADDR_WIDTH /* default 32 */),
        .DATA_WIDTH(DATA_WIDTH /* default 32 */)
     ) ahb_lite_slave (
        .HCLK     (HCLK),
        .HRESETn  (HRESETn),
        .HSEL     (1'b1),
        .HADDR    (haddr_wire),
        .HWRITE   (hwrite_wire),
        .HTRANS   (htrans_wire),
        .HSIZE    (hsize_wire),
        .HREADY   (hready_wire),
        .HWDATA   (hwdata_wire),
        .HREADYOUT(hready_wire),
        .HRESP    (hresp_wire),
        .HRDATA   (hrdata_wire)
    );

endmodule