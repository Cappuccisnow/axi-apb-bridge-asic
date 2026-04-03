`timescale 1ns/1ps

module spi_core(
  input logic clk,
  input logic reset,
  input logic start,
  input logic [15:0] datain,
  output logic [15:0] dataout,

  output logic busy,
  output logic done,

  input logic [7:0] clk_div,
  input logic cpol,
  input logic cpha,

  // spi pins
  output logic cs_n,
  output logic sclk,
  output logic mosi,
  input logic miso
);

  logic [15:0] mosi_reg;  //tx
  logic [15:0] miso_reg;  //rx

  logic [5:0] edge_count;
  logic [7:0] baud_count;
  
  typedef enum logic [1:0] {
    IDLE,
    TRANSFER,
    DONE_STATE
  } state_t;
  state_t state;
  
  always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
      mosi_reg <= 16'b0;
      miso_reg <= 16'b0;
      dataout <= 16'b0;
      edge_count <= 6'd0;
      baud_count <= 8'd0;
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
          sclk <= cpol;
          cs_n <= 1'b1;
          busy <= 1'b0;
          baud_count <= 8'b0;
          
          if (start) begin
            mosi_reg <= datain; //load Tx data
            mosi <= datain[15]; // Set MSB first
            edge_count <= 6'b0;
            cs_n <= 1'b0;   //select slave
            busy <= 1'b1;            
            state <= TRANSFER;                     
          end
        end
        
        TRANSFER: begin
          // check if we are done before toggling clock or sampling
          if (baud_count == clk_div) begin
            baud_count <= 8'b0;
            edge_count <= edge_count + 1;
            sclk <= ~sclk;

            // if edge_count is even -> transition to leading edge
            // if odd -> to trailing edge
            if (cpha == 0) begin
              // mode 0 & 2: sample on leading, shift on trailing
              if (edge_count[0] == 0) begin
                miso_reg <= {miso_reg[14:0], miso};
              end
              else begin
                if (edge_count != 31) begin
                  mosi <= mosi_reg[14]; 
                  mosi_reg <= {mosi_reg[14:0], 1'b0};
                end
              end
            end

            else begin
              // mode 1 & 3: shift on leading, sample on trailing
              if (edge_count[0] == 0) begin
                if (edge_count != 0) begin
                  mosi <= mosi_reg[14];
                  mosi_reg <= {mosi_reg[14:0], 1'b0};
                end
              end
              else begin
                miso_reg <= {miso_reg[14:0], miso};
              end
            end

            if (edge_count == 31) begin
              state <= DONE_STATE;
            end
          end
          else begin
            baud_count <= baud_count + 1;
          end
        end
        
        DONE_STATE: begin
          if (baud_count == clk_div) begin
            cs_n <= 1'b1;
            done <= 1'b1;
            busy <= 1'b0;
            dataout <= miso_reg;
            state <= IDLE;
          end 
          else begin
            baud_count <= baud_count + 1;
          end
        end
        
        default: state <= IDLE;
      endcase
    end
  end
endmodule