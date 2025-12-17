`timescale 1ns / 1ps

module tb_axi_i2c_bridge;

  // --- Clock & Reset ---
  reg clk;
  reg res_n;

  // --- AXI Interface Signals (Simulated Master) ---
  reg arvalid, awvalid, wvalid, bready, rready;
  reg [4:0] araddr, awaddr;
  reg [15:0] wdata;
  reg [3:0] arlen, awlen;
  reg [2:0] arsize, awsize;
  reg [1:0] arburst, awburst;
  reg wlast;

  // --- AXI Interface Signals (Outputs from DUT) ---
  wire arready, awready, wready;
  wire bvalid, rvalid;
  wire [1:0] bresp, rresp;
  wire rlast;
  wire [15:0] rdata;

  // --- I2C Interface ---
  wire sda;
  wire scl;

  // Pull-up resistors for I2C (Open Drain simulation)
  // This is CRITICAL: I2C relies on pull-ups. Without these, the bus floats.
  pullup(sda);
  pullup(scl);

  // --- Instantiate the DUT (Device Under Test) ---
  axi_i2c_bridge u_dut (
    .clk(clk),
    .res_n(res_n),
    
    // AXI
    .arvalid(arvalid), .awvalid(awvalid), .wvalid(wvalid), 
    .bready(bready), .rready(rready),
    .araddr(araddr), .awaddr(awaddr), 
    .wdata(wdata), 
    .arlen(arlen), .awlen(awlen), 
    .arsize(arsize), .awsize(awsize), 
    .arburst(arburst), .awburst(awburst), 
    .wlast(wlast),
    
    .arready(arready), .awready(awready), .wready(wready),
    .bvalid(bvalid), .rvalid(rvalid), 
    .bresp(bresp), .rresp(rresp), 
    .rlast(rlast), .rdata(rdata),
    
    // I2C
    .sda(sda), 
    .scl(scl)
  );

  // --- I2C Slave Simulation Model ---
  // A very simple behavioral slave that detects a START condition and 
  // ACKs bytes so the I2C Master in the DUT doesn't hang waiting for an ACK.
  reg i2c_slave_active = 0;
  reg [3:0] slave_bit_cnt;
  
  // Detect Start Condition (SDA falling while SCL is high)
  always @(negedge sda) begin
    if (scl) begin
      i2c_slave_active <= 1;
      slave_bit_cnt <= 0;
    end
  end

  // Detect Stop Condition (SDA rising while SCL is high)
  always @(posedge sda) begin
    if (scl) begin
      i2c_slave_active <= 0;
    end
  end
  
  // Simple ACK logic:
  // This block forces SDA low during the 9th clock pulse of a byte transfer.
  // It's a "dumb" slave that ACKs everything.
  reg [3:0] bit_counter = 0;
  
  always @(negedge scl) begin
    if (i2c_slave_active) begin
       if (bit_counter == 8) begin
          bit_counter <= 0;
          // Drive ACK (Low) on SDA
          force sda = 1'b0; 
       end else begin
          bit_counter <= bit_counter + 1;
          release sda;
       end
    end else begin
       bit_counter <= 0;
       release sda;
    end
  end
  
  // Release SDA when SCL goes low to high (sampling edge)
  // This ensures we only drive '0' during the low period of the ACK cycle
  always @(posedge scl) begin
     if (bit_counter == 0) release sda;
  end

  // --- Clock Generation ---
  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock (10ns period)
  end

  // --- Test Procedure ---
  initial begin
    // Setup Waveform dumping for GTKWave / ModelSim
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_axi_i2c_bridge);
    
    // Initialize Inputs
    res_n = 0;
    arvalid = 0; awvalid = 0; wvalid = 0; bready = 0; rready = 0;
    araddr = 0; awaddr = 0; wdata = 0;
    arlen = 0; awlen = 0; arsize = 0; awsize = 0; arburst = 0; awburst = 0;
    wlast = 0;

    // Reset Sequence
    #100;
    res_n = 1;
    #20;

    $display("--- Starting AXI Write Tests ---");

    // 1. Write I2C Address (Register 0)
    // Master sends Address 0x00
    write_axi(5'd0, 16'h0050); // Set I2C Addr to 0x50
    
    // 2. Write I2C Data (Register 1)
    write_axi(5'd1, 16'h00AA); // Set Data to 0xAA
    
    // 3. Write Control Register (Register 2) -> Start Pulse
    // This should trigger the I2C Master state machine
    write_axi(5'd2, 16'h0001); // Bit 0 = Start
    
    $display("--- Wait for I2C Transaction ---");
    // Wait enough time for I2C to do something (I2C is slow!)
    // Typically I2C is 100kHz or 400kHz. Our system clock is 100MHz.
    // The bridge logic has a divider.
    #60000; 

    $display("--- Starting AXI Read Test ---");
    // Read Status Register (Register 3) to see if Busy flag is set/cleared
    read_axi(5'd3);

    #1000;
    $display("--- Simulation Finished ---");
    $finish;
  end

  // --- AXI Write Task ---
  task write_axi;
    input [4:0] addr;
    input [15:0] data;
    begin
      $display("AXI WRITE: Addr=0x%h Data=0x%h", addr, data);
      
      // 1. Address Phase
      @(posedge clk);
      awvalid <= 1;
      awaddr <= addr;
      awlen <= 0; // Single beat
      awsize <= 1; // 2 bytes
      awburst <= 1; // INCR
      
      // Wait for AWREADY
      wait(awready);
      @(posedge clk);
      awvalid <= 0;
      
      // 2. Data Phase
      wvalid <= 1;
      wdata <= data;
      wlast <= 1;
      
      // Wait for WREADY
      wait(wready);
      @(posedge clk);
      wvalid <= 0;
      wlast <= 0;
      
      // 3. Response Phase
      bready <= 1;
      
      // Wait for BVALID (Crucial check for Deadlock!)
      // If deadlock exists, simulation will hang here or timeout.
      wait(bvalid);
      @(posedge clk);
      bready <= 0;
      
      if (bresp == 0) $display("AXI WRITE SUCCESS: Response OKAY");
      else $display("AXI WRITE FAILURE: Response Error %b", bresp);
      
      #20;
    end
  endtask

  // --- AXI Read Task ---
  task read_axi;
    input [4:0] addr;
    begin
      $display("AXI READ: Addr=0x%h", addr);
      
      // 1. Address Phase
      @(posedge clk);
      arvalid <= 1;
      araddr <= addr;
      arlen <= 0;
      arsize <= 1;
      arburst <= 1;
      
      wait(arready);
      @(posedge clk);
      arvalid <= 0;
      
      // 2. Data Phase
      rready <= 1;
      
      wait(rvalid);
      @(posedge clk);
      $display("AXI READ DATA: 0x%h", rdata);
      rready <= 0;
      
      #20;
    end
  endtask

endmodule