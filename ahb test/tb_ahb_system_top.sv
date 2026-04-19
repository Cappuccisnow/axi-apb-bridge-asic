`timescale 1ns/1ps

module tb_ahb_system_top;
    logic HCLK;
    logic HRESETn;

    logic ctrl_start;
    logic ctrl_write;
    logic [31:0] ctrl_addr;
    logic [31:0] ctrl_wdata;
    logic [2:0] ctrl_size;

    logic ctrl_busy;
    logic ctrl_done;
    logic [31:0] ctrl_rdata;
    logic ctrl_error;

    ahb_system_top u_dut (
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
        .ctrl_error(ctrl_error)
    );

    initial begin
        HCLK = 0;
        forever #5 HCLK = ~HCLK;
    end

    task system_write(input [31:0] addr, input [31:0] data, input [2:0] size);
        begin
            if (ctrl_busy) begin
                $display("[ERROR] Attempted to write while master was busy");
            end

            @(posedge HCLK);
            ctrl_start <= 1'b1;
            ctrl_write <= 1'b1;
            ctrl_addr <= addr;
            ctrl_wdata <= data;
            ctrl_size <= size;

            @(posedge HCLK);
            ctrl_start <= 1'b0;

            wait(ctrl_done == 1'b1);

            if (ctrl_error) begin
                $display("[AHB bus error] Write failed at addr: 0x%08h", addr);
            end
            @(posedge HCLK);
        end
    endtask

    task system_read(input [31:0] addr, input [2:0] size);
        begin
            if (ctrl_busy) begin
                $display("[ERROR] Attempted to read while master was busy");
            end
            
            @(posedge HCLK);
            ctrl_start <= 1'b1;
            ctrl_write <= 1'b0;
            ctrl_addr <= addr;
            ctrl_size <= size;

            @(posedge HCLK);
            ctrl_start <= 1'b0;

            wait(ctrl_done == 1'b1);
            @(posedge HCLK);

            if (ctrl_error) begin
                $display("[AHB bus error] Read failed at addr: 0x%08h", addr);
            end
            else begin
                $display("[System read] Addr: 0x%08h | Data: 0x0%08h", addr, ctrl_rdata);
            end
        end
    endtask

    initial begin
        HRESETn = 0;
        ctrl_start = 0;
        ctrl_write = 0;
        ctrl_addr = 0;
        ctrl_wdata = 0;
        ctrl_size = 3'b010;

        repeat(5) @(posedge HCLK);
        HRESETn = 1;
        repeat(5) @(posedge HCLK);

        $display("--- Standard word writes ---");
        system_write(32'h0000_0010, 32'hDEAD_BEEF, 3'b010);
        system_write(32'h0000_0014, 32'hCAFE_F00D, 3'b010);

        $display("--- Read back data ---");
        system_read(32'h0000_0010, 3'b010);
        system_read(32'h0000_0014, 3'b010);

        $display("--- Byte overwrite through master ---");
        //overwrite 2nd byte of 0x10 with 0x99
        //need to +1 address: 0x10 + 1 = 0x11
        system_write(32'h0000_0011, 32'h0000_9900, 3'b000);
    
        system_read(32'h0000_0010, 3'b010);

        repeat(10) @(posedge HCLK);
        $display("--- Simulation finished");
        $finish;
    end
endmodule