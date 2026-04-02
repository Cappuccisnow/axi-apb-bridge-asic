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

        .cs_n(cs_n),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso)
    );
  
//   // loopback 
//   assign miso = mosi;

    //independent dummy SPI slave
    logic [15:0] slave_tx_payloads [0:3] = {16'hAAAA, 16'hBBBB, 16'hCCCC, 16'hDDDD};
    logic [15:0] slave_rx_captures [0:3];
    integer slave_packet_count = 0;

    initial begin
        PCLK = 0;
        forever #5 PCLK = ~PCLK; // 100MHz (10ns period)
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
        //PWRITE <= 1'b0;
        //$display("APB WRITE: Addr=0x%h Data=0x%h", addr, data);
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
        //$display("APB READ:  Addr=0x%h Data=0x%h", addr, PRDATA);
        end
    endtask

    // // Wait for SPI Busy to clear
    // task wait_spi_done();
    //   logic busy;
    //   begin
    //     busy = 1'b1;
    //     while (busy) begin
    //       apb_read(32'h04); // Read Status Register
    //       busy = PRDATA[0]; // Bit 0 is the busy flag
    //       if (busy) repeat(5) @(posedge PCLK);
    //   // Wait a bit before polling again to reduce log spam
    //     end
    //   end
    // endtask

    initial miso = 1'b0;
    always @(negedge cs_n) begin
        if (slave_packet_count < 4) begin
            logic [15:0] current_tx;
            current_tx = slave_tx_payloads[slave_packet_count];

            for (int i = 15; i >= 0; i--) begin
                miso <= current_tx[i];
                @(posedge sclk);
                slave_rx_captures[slave_packet_count][i] = mosi;

                if (i > 0) @(negedge sclk);

                slave_packet_count++;
            end
        end
    end

    initial begin
        $dumpfile("apb_spi_wave.vcd");
        $dumpvars(0, tb_apb_spi_bridge_slave);
        
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
        
        apb_read(32'h00);

        $display("--- Status Register read: 0x%h ---", PRDATA);

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
        $display("--- Final Status Register (expected empty): 0x%h", PRDATA);

        repeat(10) @(posedge PCLK);
        $display("--- Simulation Finished ---");
        $finish;
    end

endmodule
