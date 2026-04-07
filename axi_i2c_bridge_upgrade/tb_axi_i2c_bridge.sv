`timescale 1ns / 1ps

module tb_axi_i2c_bridge;

  logic clk;
  logic res_n;

  logic [4:0] awaddr, araddr;
  logic [15:0] wdata, rdata;
  logic awvalid, awready;
  logic wvalid, wready;
  logic arvalid, arready;
  logic rvalid, rready;
  logic [1:0] bresp, rresp;
  logic bvalid, bready;

  tri1 sda;
  tri1 scl;

  assign (weak1, weak0) sda = 1'b1;
  assign (weak1, weak0) scl = 1'b1;  

  axi_i2c_bridge u_dut (
    .clk(clk),
    .res_n(res_n),
    
    // AXI
    .arvalid(arvalid), .awvalid(awvalid), .wvalid(wvalid), 
    .bready(bready), .rready(rready),
    .araddr(araddr), .awaddr(awaddr), 
    .wdata(wdata), 
    
    .arready(arready), .awready(awready), .wready(wready),
    .bvalid(bvalid), .rvalid(rvalid), 
    .bresp(bresp), .rresp(rresp), 
    .rdata(rdata),
    
    // I2C
    .sda(sda), 
    .scl(scl)
  );

  // drives SDA low on the 9th clock tick (ACK)
  logic slave_drive_sda = 0;
  logic i2c_active = 0;
  int bit_count;
  logic [7:0] shift_reg = 8'd0;
  // open drain assignment
  assign sda = slave_drive_sda ? 1'b0 : 1'bz;

  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100MHz clock (10ns period)
  end

  // Detect Start Condition
  always @(negedge sda) begin
    if (scl !== 1'b0 && $time > 0) begin
      i2c_active <= 1;
      bit_count <= 0;
      slave_drive_sda <= 1'b0;
      $display("\n[I2C monitor] START condition detected at time %0t\n", $time);
    end
  end

  // Detect Stop Condition
  always @(posedge sda) begin
    if (scl !== 1'b0 && $time > 0) begin
      i2c_active <= 0;
      $display("\n[I2C monitor] STOP condition detected at time %0t\n", $time);
    end
  end

  logic is_read_txn = 0;
  logic [7:0] dummy_sensor_data = 8'hAB;

  // read the data line
  always @(posedge scl) begin
    if (i2c_active) begin 
      if ((bit_count >= 1 && bit_count <= 8) || (bit_count >= 10 && bit_count <= 17 && !is_read_txn)) begin
        shift_reg <= {shift_reg[6:0], sda};
      end
    end
  end
  
  //fsm
  always @(negedge scl) begin
    if (i2c_active) begin
      bit_count <= bit_count + 1;

      if (bit_count == 8) begin
        slave_drive_sda <= 1'b1;
        is_read_txn <= shift_reg[0];
      end
      else if (bit_count == 9) begin
        $display("[I2C slave] ACK address complete. Read mode: %b", is_read_txn);
        if (shift_reg[0]) begin
          slave_drive_sda <= ~dummy_sensor_data[7];
        end
        else begin
          slave_drive_sda <= 1'b0;
        end
      end
      else if (bit_count >= 10 && bit_count <= 16) begin
        if (is_read_txn) begin
          slave_drive_sda <= ~dummy_sensor_data[16 - bit_count];
        end      
      end
      else if (bit_count == 17) begin
        slave_drive_sda <= 1'b0;
        if (!is_read_txn) begin
          slave_drive_sda <= 1'b1;
        end 
        else begin
          slave_drive_sda <= 1'b0;
        end
      end
      else if (bit_count == 18) begin
        if (!is_read_txn) $display("[I2C slave] Master wrote data: 0x%h", shift_reg);
        slave_drive_sda <= 1'b0;
        bit_count <= 9;
      end
    end
  end

  task write_axi (input [4:0] addr, input [15:0] data);
    begin
      
      @(posedge clk);
      awaddr <= addr;
      awvalid <= 1'b1;
      wdata <= data;
      wvalid <= 1'b1;

      wait (awready);
      @(posedge clk);
      awvalid <= 1'b0;

      wait (wready);
      @(posedge clk);
      wvalid <= 1'b0;

      bready <= 1'b1;
      wait (bvalid);
      @(posedge clk);

      bready <= 1'b0;
      
      $display("AXI write: Addr: 0x%h, Data: 0x%h, Resp: %b", addr, data, bresp);
    end
  endtask

  task read_axi (input [4:0] addr, input logic quiet = 1'b0);
    begin
      @(posedge clk);

      araddr <= addr;
      arvalid <= 1'b1;

      wait (arready);
      @(posedge clk);

      arvalid <= 1'b0;
      rready <= 1'b1;

      wait (rvalid);
      @(posedge clk);

      if (!quiet)
        $display("AXI read: Addr: 0x%h, Data: 0x%h, Error code = %b", addr, rdata, rresp);
      rready <= 1'b0;
    end
  endtask

  initial begin
    
    res_n = 0;
    arvalid = 0; awvalid = 0; wvalid = 0; bready = 0; rready = 0;
    araddr = 0; awaddr = 0; wdata = 0;

    repeat(10) @(posedge clk);
    res_n = 1;
    repeat(5) @(posedge clk);


    $display("--- Starting AXI Write Tests ---");

    // write i2c address to 0x50
    write_axi(5'd0, 16'h0050); 
    
    // write i2c data to 0xAA
    write_axi(5'd1, 16'h00AA); 
    
    // write start bit
    write_axi(5'd2, 16'h0001); 
    
    $display("--- Wait for I2C Transaction ---");
    //Wait for slow I2C
    repeat(1000) begin
      read_axi(5'd3, 1'b1);
      if  (rdata[0] == 0) break;
      repeat(5000) @(posedge clk);
    end

    $display("--- Starting AXI Read Test ---");
    // read new data from 0x50, last bit is set to 1 (0x51) to indicate read transaction
    write_axi(5'd0, 16'h0051);
    // write start bit
    write_axi(5'd2, 16'h0001);

    $display("--- Polling status ---");
    //Wait for slow I2C
    repeat(1000) begin
      read_axi(5'd3, 1'b1);
      if  (rdata[0] == 0) break;
      repeat(5000) @(posedge clk);
    end

    $display("--- Fetching captured data ---");
    read_axi(5'd4);

    $display("--- Testing repeated START test ---");
    write_axi(5'd0, 16'h0050);
    //write internal memory address 0xBB
    write_axi(5'd1, 16'h00BB);

    //send start bit, but set bit 1 to hold the bus (0x0003 instead of 0x0001) 
    write_axi(5'd2, 16'h0003);

    $display("--- Waiting for the first half to finish ---");
    repeat(1000) begin
      read_axi(5'd3, 1'b1);
      if   (rdata[0] == 0) break;
      repeat(5000) @(posedge clk);
    end

    write_axi(5'd0, 16'h0051);
    write_axi(5'd2, 16'h0001);

    repeat(1000) begin
      read_axi(5'd3, 1'b1);
      if   (rdata[0] == 0) break;
      repeat(5000) @(posedge clk);
    end

    read_axi(5'd4, 1'b1);

    repeat(10000) @(posedge clk);
    $display("--- Simulation Finished ---");
    $finish;
  end
endmodule

