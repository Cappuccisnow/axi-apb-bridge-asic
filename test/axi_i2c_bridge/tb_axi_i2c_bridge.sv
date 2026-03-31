`timescale 1ns / 1ps

module tb_axi_i2c_bridge;

  logic clk;
  logic res_n;

  logic arvalid, awvalid, wvalid, bready, rready;
  logic [4:0] araddr, awaddr;
  logic [15:0] wdata;
  logic [3:0] arlen, awlen;
  logic [2:0] arsize, awsize;
  logic [1:0] arburst, awburst;
  logic wlast;

  logic arready, awready, wready;
  logic bvalid, rvalid;
  logic [1:0] bresp, rresp;
  logic rlast;
  logic [15:0] rdata;

  tri1 sda;
  tri1 scl;

  // Pull-up resistors for I2C (Open Drain simulation)
  // pullup(sda);
  // pullup(scl);

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

  // drives SDA low on the 9th clock tick (ACK)
  logic slave_drive_sda = 0;
  logic i2c_active = 0;
  int bit_count;

  logic [7:0] rx_byte;
  
  // open drain assignment
  assign sda = slave_drive_sda ? 1'b0 : 1'bz;

  // Detect Start Condition
  always @(negedge sda) begin
    if (scl === 1'b1) begin
      i2c_active <= 1;
      bit_count <= 0;
      $display("\n[I2C monitor] START condition detected at time %0t\n", $time);
    end
  end

  // Detect Stop Condition
  always @(posedge sda) begin
    if (scl === 1'b1) begin
      i2c_active <= 0;
      slave_drive_sda <= 0;
      $display("\n[I2C monitor] STOP condition detected at time %0t\n", $time);
    end
  end

  // read the data line
  always @(posedge clk) begin
    if (i2c_active && bit_count < 8) begin
      rx_byte <= {rx_byte[6:0], sda};
    end
  end
  
  always @(negedge scl) begin
    if (i2c_active) begin
      bit_count <= bit_count + 1;
      if (bit_count == 8) begin
        slave_drive_sda <= 1'b1;
        $display("\n[I2C monitor] intercepted byte: 0x%h", rx_byte);
      end 
      else if (bit_count == 9) begin
        slave_drive_sda <= 1'b0;
        bit_count <= 0;
      end
    end 
    else begin
      bit_count <= 0;
      slave_drive_sda <= 1'b0;
    end
  end

  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock (10ns period)
  end

  task write_axi (input [4:0] addr, input [15:0] data);
    begin
      $display("AXI WRITE: Addr=0x%h Data=0x%h", addr, data);
      
      //Address Phase
      @(posedge clk);
      awvalid <= 1;
      awaddr <= addr;
      awlen <= 0; // Single beat
      awsize <= 1; // 2 bytes
      awburst <= 1; // INCR
      
      wait(awready);
      @(posedge clk);
      awvalid <= 0;
      
      wvalid <= 1;
      wdata <= data;
      wlast <= 1;
      
      wait(wready);
      @(posedge clk);
      wvalid <= 0;
      wlast <= 0;
      
      bready <= 1;
      
      wait(bvalid);
      @(posedge clk);
      bready <= 0;
      
      if (bresp == 0) $display("AXI WRITE SUCCESS: Response OKAY");
      else $display("AXI WRITE FAILURE: Response Error %b", bresp);
      
      #20;
    end
  endtask

  task read_axi (input [4:0] addr);
    begin
      $display("AXI READ: Addr=0x%h", addr);
      
      @(posedge clk);
      arvalid <= 1;
      araddr <= addr;
      arlen <= 0;
      arsize <= 1;
      arburst <= 1;
      
      wait(arready);
      @(posedge clk);
      arvalid <= 0;
      
      rready <= 1;
      
      wait(rvalid);
      @(posedge clk);
      $display("AXI READ DATA: 0x%h", rdata);
      rready <= 0;
      
      #20;
    end
  endtask

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

    // write i2c address to 0x50
    write_axi(5'd0, 16'h0050); 
    
    // write i2c data to 0xAA
    write_axi(5'd1, 16'h00AA); 
    
    // write start bit
    write_axi(5'd2, 16'h0001); 
    
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
endmodule

// i2c monitor not working yet