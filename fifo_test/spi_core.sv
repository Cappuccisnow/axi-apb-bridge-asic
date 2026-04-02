`timescale 1ns/1ps

module spi_core(
  input logic clk,
  input logic reset,
  input logic start,
  input logic [15:0] datain,
  output logic [15:0] dataout,

  output logic busy,
  output logic done,

  // spi pins
  output logic cs_n,
  output logic sclk,
  output logic mosi,
  input logic miso
);

  logic [15:0] mosi_reg;
  logic [15:0] miso_reg;
  logic [4:0] count;
  
  typedef enum logic [1:0] {
    IDLE,
    SHIFT,
    NEXT
  } state_t;
  state_t state;
  
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      mosi_reg <= 16'b0;
      miso_reg <= 16'b0;
      dataout <= 16'b0;
      count <= 5'd16;
      cs_n <= 1'b1;
      sclk <= 1'b0;
      mosi <= 1'b0;
      state <= IDLE;
      busy <= 1'b0;
      done <= 1'b0;
    end
    else begin
      done <= 1'b0;

      case (state)
        IDLE: begin
          sclk <= 1'b0;
          cs_n <= 1'b1;
          busy <= 1'b0;
          count <= 5'd16;
          
          if (start) begin
            mosi_reg <= datain; //load Tx data
            mosi <= datain[15]; // Set MSB first
            cs_n <= 1'b0;   //select slave
            busy <= 1'b1;  
            state <= NEXT;                     
          end
        end
        
        NEXT: begin
          // check if we are done before toggling clock or sampling
          if (count == 0) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b1;
            dataout <= miso_reg;   //capture final result
            cs_n <= 1'b1;    //detect slave
            sclk <= 1'b0;    
          end 
          else begin
            // Rising Edge: Sample MISO
            sclk <= 1'b1;
            miso_reg <= {miso_reg[14:0], miso};
            state <= SHIFT;
          end
        end
        
        SHIFT: begin
          // Falling Edge: Shift Data
          sclk <= 1'b0;
          mosi_reg <= {mosi_reg[14:0], 1'b0};
          mosi <= mosi_reg[14];   //drive new bit
          count <= count - 5'd1;
          state <= NEXT;
        end
        
        default: state <= IDLE;
      endcase
    end
  end
endmodule