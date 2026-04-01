`timescale 1ns / 1ps
// for edaplayground
// `include "spi_core.sv"

module tb_apb_spi_bridge_loopback;

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
  
  // loopback 
  assign miso = mosi;

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
      PWRITE <= 1'b1; // Write Mode
      
      @(posedge PCLK);
      PENABLE <= 1'b1; // Enable Phase
      
      // Wait for PREADY (Slave handshake)
      wait(PREADY);
      
      @(posedge PCLK);
      PSEL <= 1'b0;
      PENABLE <= 1'b0;
      PWRITE <= 1'b0;
      $display("APB WRITE: Addr=0x%h Data=0x%h", addr, data);
    end
  endtask

  // APB Read Transaction
  task apb_read(input [31:0] addr);
    begin
      @(posedge PCLK);
      PADDR <= addr;
      PSEL <= 1'b1;
      PWRITE <= 1'b0; // Read Mode
      
      @(posedge PCLK);
      PENABLE <= 1'b1; // Enable Phase
      
      // Wait for PREADY
      wait(PREADY);
      
      @(posedge PCLK);
      // Data is valid now, PREADY is high
      PSEL <= 1'b0;
      PENABLE <= 1'b0;
      $display("APB READ:  Addr=0x%h Data=0x%h", addr, PRDATA);
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

  initial begin
    $dumpfile("apb_spi_wave.vcd");
    $dumpvars(0, tb_apb_spi_bridge_loopback);
    
    PRESETn = 0;
    PSEL = 0; 
    PENABLE = 0; 
    PWRITE = 0; 
    PADDR = 0; 
    PWDATA = 0;
    
    repeat(2) @(posedge PCLK);
    PRESETn = 1;
    repeat(2) @(posedge PCLK);
    
    $display("--- Starting APB-SPI Loopback Test ---");
    
    //Write Data 0xABCD to TX Register (Address 0x00)
    apb_write(32'h00, 32'hABCD);
    
    $display("--- SPI Transaction Started... Waiting for IRQ ---");
    
    // //Poll Status Register (Address 0x04) until busy is 0
    // wait_spi_done();
    @(posedge spi_interrupt);

    $display("--- IRQ detected, reading data ---");
    
    //Read RX Data Register (Address 0x00)
    // Since we looped MOSI to MISO, we expect to read back 0xABCD.
    apb_read(32'h00);
    
    if (PRDATA[15:0] == 16'hABCD)
       $display("SUCCESS: Loopback Data Matched (0xABCD)");
    else
       $display("FAILURE: Expected 0xABCD, got 0x%h", PRDATA);
       
    repeat(10) @(posedge PCLK);
    $display("--- Simulation Finished ---");
    $finish;
  end

endmodule
