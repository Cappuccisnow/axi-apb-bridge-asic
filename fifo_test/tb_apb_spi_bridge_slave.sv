`timescale 1ns / 1ps
// for edaplayground
// `include "spi_core.sv"
// `include "async_fifo.sv"
// `include "dual_port_ram.sv"
// `include "fifo_rptr.sv"
// `include "fifo_wptr.sv"
// `include "sync_ptr.sv"

module tb_apb_spi_bridge_slave;

    logic PCLK;
    logic SPI_CLK_EXT; //new independent spi clock
    logic PRESETn;
    logic [31:0] PADDR;
    logic PWRITE;
    logic PSEL;
    logic PENABLE;
    logic [31:0] PWDATA;
    logic [31:0] PRDATA;
    logic PREADY;
    
    logic spi_interrupt;
    // SPI 
    logic cs_n;
    logic sclk;
    logic mosi;   
    logic miso; 
    
    //Instantiate the DUT 
    apb_spi_bridge u_dut (
        .PCLK(PCLK),
        .PRESETn(PRESETn),
        .PADDR(PADDR),
        .PWRITE(PWRITE),
        .PSEL(PSEL),
        .PENABLE(PENABLE),
        .PWDATA(PWDATA),
        .PRDATA(PRDATA),
        .PREADY(PREADY),
        
        .spi_interrupt(spi_interrupt),

        .SPI_CLK_EXT(SPI_CLK_EXT),
        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso)
    );

    //independent dummy SPI slave
    logic [15:0] slave_tx_payloads [0:3] = '{16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD};
    logic [15:0] slave_rx_captures [0:3];
    integer slave_packet_count = 0;
    integer bit_idx  = 15;

    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK; // 100MHz (10ns period)
    end
    
    initial begin
        SPI_CLK_EXT = 0;
        forever #20 SPI_CLK_EXT = ~SPI_CLK_EXT; // 25MHz (40ns period)
    end
    
    // APB Write Transaction
    task apb_write(input [31:0] addr, input [31:0] data);
        begin
        @(posedge PCLK);
        PADDR <= addr;
        PWDATA <= data;
        PSEL <= 1'b1;
        PENABLE <= 1'b0;
        PWRITE <= 1'b1; // Write Mode
        
        @(posedge PCLK);
        PENABLE <= 1'b1; // Enable Phase
        
        // Wait for PREADY (Slave handshake)
        wait(PREADY);
        
        @(posedge PCLK);
        PSEL <= 1'b0;
        PENABLE <= 1'b0;
        end
    endtask

    // APB Read Transaction
    task apb_read(input [31:0] addr);
        begin
        @(posedge PCLK);
        PADDR <= addr;
        PSEL <= 1'b1;
        PWRITE <= 1'b0; // Read Mode
        PENABLE <= 1'b0;
        
        @(posedge PCLK);
        PENABLE <= 1'b1; // Enable Phase
        
        // Wait for PREADY
        wait(PREADY);
        
        @(posedge PCLK);
        // Data is valid now, PREADY is high
        PSEL <= 1'b0;
        PENABLE <= 1'b0;
        end
    endtask

    initial miso = 1'b0;

    always @(negedge sclk or negedge cs_n) begin
        if (!cs_n && slave_packet_count < 4) begin
            miso <= slave_tx_payloads[slave_packet_count][bit_idx];
        end
    end
    always @(posedge sclk) begin
        if (!cs_n && slave_packet_count < 4) begin
            slave_rx_captures[slave_packet_count][bit_idx] <= mosi;
            if (bit_idx == 0) begin
                bit_idx <= 15;
                slave_packet_count <= slave_packet_count + 1;
            end
            else begin
                bit_idx <= bit_idx - 1;
            end
        end
    end

    initial begin

        PRESETn = 0;
        PSEL = 0; 
        PENABLE = 0; 
        PWRITE = 0; 
        PADDR = 0; 
        PWDATA = 0;
        
        repeat(2) @(posedge PCLK);
        PRESETn = 1;
        repeat(2) @(posedge PCLK);
        
        $display("--- Bursting 4 words into TX FIFO ---");
        
        apb_write(32'h00, 16'h1111);
        apb_write(32'h00, 16'h2222);
        apb_write(32'h00, 16'h3333);
        apb_write(32'h00, 16'h4444);
        
        apb_read(32'h04);

        $display("--- Status Register read after burst: 0x%h ---", PRDATA);

        $display("--- Waiting for SPI to transmit ---");
        for (int i = 0; i < 4; i++) begin
            @(posedge spi_interrupt);
            $display("--- Interrupt %0d received", i+1);
        end

        repeat(5) @(posedge PCLK);

        $display("--- Checking dummy captured data ---");
        for (int i = 0; i < 4; i++) begin
            $display("  Slave received word %0d: 0x%h", i, slave_rx_captures[i]);
        end

        $display("--- CPU popping 4 words from RX FIFO ---");

        apb_read(32'h00);
        $display("  CPU read word 1 (expected AAAA): 0x%h", PRDATA[15:0]);

        apb_read(32'h00);
        $display("  CPU read word 2 (expected BBBB): 0x%h", PRDATA[15:0]);

        apb_read(32'h00);
        $display("  CPU read word 3 (expected CCCC): 0x%h", PRDATA[15:0]);

        apb_read(32'h00);
        $display("  CPU read word 4 (expected DDDD): 0x%h", PRDATA[15:0]);

        apb_read(32'h04);
        $display("--- Final Status register read (expected empty): 0x%h", PRDATA);
        // should output 0x00000005 
        // 28'd0, rx_fifo_full, rx_fifo_empty, tx_fifo_full, tx_fifo_empty
        // rx_fifo_full = 0 | rx_fifo_empty = 1 | tx_fifo_full = 0 | tx_fifo_empty = 1  (0101 = 5)

        repeat(10) @(posedge PCLK);
        $display("--- Simulation Finished ---");
        $finish;
    end

endmodule
