`timescale 1ns / 1ps

module tb_apb_spi_bridge;

  // --- Signals ---
  reg PCLK;
  reg PRESETn;
  reg [31:0] PADDR;
  reg PWRITE;
  reg PSEL;
  reg PENABLE;
  reg [31:0] PWDATA;
  wire [31:0] PRDATA;
  wire PREADY;
  
  // SPI Interface
  wire spi_cs_l;
  wire spi_clk;
  wire spi_data;   // MOSI (Master Out)
  reg master_data; // MISO (Master In)
  
  // --- Instantiate the DUT ---
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
    
    .spi_cs_l(spi_cs_l),
    .spi_clk(spi_clk),
    .spi_data(spi_data),
    .master_data(master_data)
  );
  
  // --- Loopback Connection ---
  // Crucial: Connects Output to Input so we receive what we send
  always @(*) master_data = spi_data;

  // --- Clock Generation ---
  initial begin
    PCLK = 0;
    forever #5 PCLK = ~PCLK; // 100MHz (10ns period)
  end
  
  // --- Test Procedure ---
  initial begin
    // Waveform setup
    $dumpfile("apb_spi_wave.vcd");
    $dumpvars(0, tb_apb_spi_bridge);
    
    // Initialize Inputs
    PRESETn = 0;
    PSEL = 0; PENABLE = 0; PWRITE = 0; PADDR = 0; PWDATA = 0;
    
    // Reset Sequence
    #20;
    PRESETn = 1;
    #20;
    
    $display("--- Starting APB-SPI Loopback Test ---");
    
    // 1. Write Data 0xABCD to TX Register (Address 0x00)
    // The bridge logic triggers SPI start when writing to 0x00
    apb_write(32'h00, 32'hABCD);
    
    $display("--- SPI Transaction Started... Waiting ---");
    
    // 2. Poll Status Register (Address 0x04) until busy is 0
    // The SPI transaction takes time (16 bits * clock div), so we must wait.
    wait_spi_done();
    
    // 3. Read RX Data Register (Address 0x00)
    // Since we looped MOSI to MISO, we expect to read back 0xABCD.
    apb_read(32'h00);
    
    // Check Result
    if (PRDATA[15:0] == 16'hABCD)
       $display("SUCCESS: Loopback Data Matched (0xABCD)");
    else
       $display("FAILURE: Expected 0xABCD, got 0x%h", PRDATA);
       
    #100;
    $display("--- Simulation Finished ---");
    $finish;
  end
  
  // --- Task: APB Write Transaction ---
  task apb_write;
    input [31:0] addr;
    input [31:0] data;
    begin
      @(posedge PCLK);
      PADDR = addr;
      PWDATA = data;
      PSEL = 1;
      PWRITE = 1; // Write Mode
      
      @(posedge PCLK);
      PENABLE = 1; // Enable Phase
      
      // Wait for PREADY (Slave handshake)
      wait(PREADY);
      
      @(posedge PCLK);
      PSEL = 0;
      PENABLE = 0;
      PWRITE = 0;
      $display("APB WRITE: Addr=0x%h Data=0x%h", addr, data);
    end
  endtask
  
  // --- Task: APB Read Transaction ---
  task apb_read;
    input [31:0] addr;
    begin
      @(posedge PCLK);
      PADDR = addr;
      PSEL = 1;
      PWRITE = 0; // Read Mode
      
      @(posedge PCLK);
      PENABLE = 1; // Enable Phase
      
      // Wait for PREADY
      wait(PREADY);
      
      @(posedge PCLK);
      // Data is valid now, PREADY is high
      PSEL = 0;
      PENABLE = 0;
      $display("APB READ:  Addr=0x%h Data=0x%h", addr, PRDATA);
    end
  endtask
  
  // --- Task: Wait for SPI Busy to clear ---
  task wait_spi_done;
    reg busy;
    begin
       busy = 1;
       while (busy) begin
          apb_read(32'h04); // Read Status Register
          busy = PRDATA[0]; // Bit 0 is the busy flag
          if (busy) #50;    // Wait a bit before polling again to reduce log spam
       end
    end
  endtask

endmodule