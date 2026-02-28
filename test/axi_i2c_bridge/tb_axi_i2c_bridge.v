`timescale 1ns / 1ps

module tb_axi_i2c_bridge;

  reg clk;
  reg res_n;

  reg arvalid, awvalid, wvalid, bready, rready;
  reg [4:0] araddr, awaddr;
  reg [15:0] wdata;
  reg [3:0] arlen, awlen;
  reg [2:0] arsize, awsize;
  reg [1:0] arburst, awburst;
  reg wlast;

  wire arready, awready, wready;
  wire bvalid, rvalid;
  wire [1:0] bresp, rresp;
  wire rlast;
  wire [15:0] rdata;

  wire sda;
  wire scl;

  //Pull-up resistors for I2C (Open Drain simulation)
  pullup(sda);
  pullup(scl);

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

  //I2C Slave Simulation Model 
  //A very simple behavioral slave that detects a START condition and 
  //ACKs bytes so the I2C Master in the DUT doesn't hang waiting for an ACK.
  reg i2c_slave_active = 0;
  reg [3:0] slave_bit_cnt;
  
  // Detect Start Condition
  always @(negedge sda) begin
    if (scl) begin
      i2c_slave_active <= 1;
      slave_bit_cnt <= 0;
    end
  end

  // Detect Stop Condition
  always @(posedge sda) begin
    if (scl) begin
      i2c_slave_active <= 0;
    end
  end
  

  //forces SDA low during the 9th clock pulse of a byte transfer.
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
  
  //Release SDA when SCL goes low to high
  //ensures we only drive '0' during the low period of the ACK cycle
  always @(posedge scl) begin
     if (bit_counter == 0) release sda;
  end


  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock (10ns period)
  end

  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_axi_i2c_bridge);
    
    res_n = 0;
    arvalid = 0; awvalid = 0; wvalid = 0; bready = 0; rready = 0;
    araddr = 0; awaddr = 0; wdata = 0;
    arlen = 0; awlen = 0; arsize = 0; awsize = 0; arburst = 0; awburst = 0;
    wlast = 0;

    #100;
    res_n = 1;
    #20;

    $display("--- Starting AXI Write Tests ---");

    //Write I2C Address (Register 0)
    //Master sends Address 0x00
    write_axi(5'd0, 16'h0050); // Set I2C Addr to 0x50
    
    //Write I2C Data (Register 1)
    write_axi(5'd1, 16'h00AA); // Set Data to 0xAA
    
    //Write Control Register (Register 2) -> Start Pulse
    write_axi(5'd2, 16'h0001); // Bit 0 = Start
    
    $display("--- Wait for I2C Transaction ---");
    //Wait for slow I2C
    #60000; 

    $display("--- Starting AXI Read Test ---");
    //Read Status Register (Register 3) to see if Busy flag is set/cleared
    read_axi(5'd3);

    #1000;
    $display("--- Simulation Finished ---");
    $finish;
  end

  //AXI Write Task
  task write_axi;
    input [4:0] addr;
    input [15:0] data;
    begin
      $display("AXI WRITE: Addr=0x%h Data=0x%h", addr, data);
      
      //Address Phase
      @(posedge clk);
      awvalid <= 1;
      awaddr <= addr;
      awlen <= 0; // Single beat
      awsize <= 1; // 2 bytes
      awburst <= 1; // INCR
      
      //Wait for AWREADY
      wait(awready);
      @(posedge clk);
      awvalid <= 0;
      
      //Data Phase
      wvalid <= 1;
      wdata <= data;
      wlast <= 1;
      
      //Wait for WREADY
      wait(wready);
      @(posedge clk);
      wvalid <= 0;
      wlast <= 0;
      
      //Response Phase
      bready <= 1;
      
      // Wait for BVALID
      wait(bvalid);
      @(posedge clk);
      bready <= 0;
      
      if (bresp == 0) $display("AXI WRITE SUCCESS: Response OKAY");
      else $display("AXI WRITE FAILURE: Response Error %b", bresp);
      
      #20;
    end
  endtask

  //AXI Read Task
  task read_axi;
    input [4:0] addr;
    begin
      $display("AXI READ: Addr=0x%h", addr);
      
      //Address Phase
      @(posedge clk);
      arvalid <= 1;
      araddr <= addr;
      arlen <= 0;
      arsize <= 1;
      arburst <= 1;
      
      wait(arready);
      @(posedge clk);
      arvalid <= 0;
      
      //Data Phase
      rready <= 1;
      
      wait(rvalid);
      @(posedge clk);
      $display("AXI READ DATA: 0x%h", rdata);
      rready <= 0;
      
      #20;
    end
  endtask


endmodule
