`timescale 1ns/1ps

module spi_core(
  input wire clk,
  input wire reset,
  input wire start,
  input wire [15:0] datain,
  output reg [15:0] dataout,
  output reg spi_cs_l,
  output reg spi_clk,
  output reg spi_data,
  input wire master_data,
  output reg busy
);

  reg [15:0] MOSI_reg;
  reg [15:0] MISO_reg;
  reg [4:0] count;
  
  // Internal state
  reg [1:0] state;
  localparam IDLE = 2'b00;
  localparam SHIFT = 2'b01;
  localparam NEXT = 2'b10;
  
  always @(posedge clk or posedge reset) begin
    if (reset) begin
      MOSI_reg <= 16'b0;
      MISO_reg <= 16'b0;
      dataout <= 16'b0;
      count <= 5'd16;
      spi_cs_l <= 1'b1;
      spi_clk <= 1'b0;
      spi_data <= 1'b0;
      state <= IDLE;
      busy <= 0;
    end
    else begin
      case (state)
        IDLE: begin
          spi_clk <= 1'b0;
          spi_cs_l <= 1'b1;
          busy <= 0;
          count <= 5'd16;
          
          if (start) begin
            MOSI_reg <= datain; //load Tx data
            state <= NEXT;
            busy <= 1;
            spi_cs_l <= 1'b0;   //select slave
            spi_data <= datain[15]; // Set MSB first
          end
        end
        
        NEXT: begin
          // check if we are done before toggling clock or sampling
          if (count == 0) begin
             state <= IDLE;
             busy <= 0;
             dataout <= MISO_reg;   //capture final result
             spi_cs_l <= 1'b1;    //detect slave
             spi_clk <= 1'b0;    
          end 
          else begin
             // Rising Edge: Sample MISO
             spi_clk <= 1'b1;
             MISO_reg <= {MISO_reg[14:0], master_data};
             state <= SHIFT;
          end
        end
        
        SHIFT: begin
          // Falling Edge: Shift Data
          spi_clk <= 1'b0;
          MOSI_reg <= {MOSI_reg[14:0], 1'b0};
          spi_data <= MOSI_reg[14];   //drive new bit
          count <= count - 1;
          state <= NEXT;
        end
        
        default: state <= IDLE;
      endcase
    end
  end
endmodule