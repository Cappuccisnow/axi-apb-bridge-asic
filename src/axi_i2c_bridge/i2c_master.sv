`timescale 1ns/1ps

module i2c_master(
  inout   wire logic sda,  
  output  logic scl,
  output  logic clk2mhz_dummy,
  output  logic rw,
  input   logic clk100mhz,
  input   logic reset,
  input   logic [7:0] data_to_send, 
  input   logic [7:0] addr_to_send,
  input   logic new_cmd,
  output  logic busy,
  output  logic [7:0] read_data_out
);
  
  typedef enum logic [3:0] {
    IDLE, 
    START_INIT,
    START,
    ADDRESS_SEND,
    SLAVE_ACK,
    DATA_SEND_INIT,
    DATA_SEND,
    DATA_ACK, 
    STOP_INIT,
    STOP
  } state_t;
  state_t state;

  logic start_pending;
  logic sda_h;
  logic sda_mode; // 1 = Output mode, 0 = Input mode
  logic scl_h;
  // logic scl_mode;
  // logic scl_toggle;
  
  logic [6:0] count;
  logic [7:0] data_to_send_store;
  logic [7:0] addr_to_send_store;
  logic [3:0] bit_count;
  //logic [2:0] count_ack_wait;
  logic [1:0] count_sda_wait;
  logic [7:0] data_read_store;
  
  // tri-state buffer
  // When sda_mode is 1, we drive sda based on sda_h.
  // Standard I2C is Open Drain: Drive '0' or High-Z.
  // If sda_h is 0, drive 0. If sda_h is 1, release (z).
  assign sda = (sda_mode && !sda_h) ? 1'b0 : 1'bz;
  assign scl = (!scl_h)             ? 1'b0 : 1'bz;
  
  assign busy = (state != IDLE);
  assign read_data_out = data_read_store;
  assign rw = 1'b0; // Placeholder
  assign clk2mhz_dummy = count[6]; 

  //FSM
  always_ff @(posedge clk100mhz or posedge reset) begin
    if (reset) begin
      state <= IDLE;
      sda_h <= 1; 
      sda_mode <= 0;
      scl_h <= 1;
      count <= '0;
      bit_count <= '0;
      start_pending <= 1'b0;
      data_to_send_store <= '0;
      addr_to_send_store <= '0;
      data_read_store <= '0;
    end 
    else begin
      if (new_cmd) begin
        start_pending <= 1'b1;
        addr_to_send_store <= addr_to_send;
        data_to_send_store <= data_to_send;
      end

      count <= count + 7'd1;
      
      // clock divider tick 
      if (count == 7'd0) begin

        case (state)
        IDLE: begin
          sda_h <= 1; 
          sda_mode <= 0;
          scl_h <= 1; 
          if (new_cmd) begin
            start_pending <= 1;
            addr_to_send_store <= addr_to_send;
            data_to_send_store <= data_to_send;
          end
          else if (start_pending) begin
            state <= START_INIT;
            start_pending <= 1'b0;
          end
        end
        
        START_INIT: begin
          sda_mode <= 1'b1; 
          sda_h <= 1'b0; // Drive Start Condition
          state <= START;
        end
        
        START: begin
          scl_h <= 0; // Clock Low
          bit_count <= 4'd8;
          state <= ADDRESS_SEND;
        end
        
        ADDRESS_SEND: begin
          sda_mode <= 1'b1;
          if (scl_h == 1'b0) begin
            sda_h <= addr_to_send_store[bit_count - 1];
            scl_h <= 1'b1;
          end
          else begin
            scl_h <= 1'b0;
            if (bit_count == 4'd1) begin
              state <= SLAVE_ACK;
            end 
            else begin
              bit_count <= bit_count - 4'd1;
            end
          end
        end
        
        SLAVE_ACK: begin
          if (scl_h == 1'b0) begin
            sda_mode <= 0; // Release SDA for Slave to ACK
            scl_h <= 1'b1;
          end
          else begin
            scl_h <= 1'b0;
            state <= DATA_SEND_INIT;
          end
        end
        
        DATA_SEND_INIT: begin
            bit_count <= 4'd8;
            state <= DATA_SEND;
        end
        
        DATA_SEND: begin
          sda_mode <= 1'b1;
          if (scl_h == 1'b0) begin
            sda_h <= data_to_send_store[bit_count - 1];
            scl_h <= 1'b1;
          end
          else begin
            scl_h <= 1'b0;
            if (bit_count == 4'd1) begin
              state <= DATA_ACK;
            end 
            else begin
              bit_count <= bit_count - 4'd1;
            end
          end
        end
        
        DATA_ACK: begin
          if (scl_h == 1'b0) begin
            sda_mode <= 1'b0; // Release for ACK
            scl_h <= 1'b1;
          end
          else begin
            scl_h <= 1'b0;
            state <= STOP_INIT;
          end
        end
        
        STOP_INIT: begin
          sda_mode <= 1'b1;
          sda_h <= 1'b0;
          scl_h <= 1'b1; // Stop: SCL High
          count_sda_wait <= 2'd2;
          state <= STOP;
        end
        
        STOP: begin
          if (count_sda_wait == 2'd0) begin 
             sda_h <= 1'b1;
             state <= IDLE;
          end
          else begin
            count_sda_wait <= count_sda_wait - 2'd1;
          end
        end
        
        default: state <= IDLE;
        endcase
      end
    end
  end
endmodule
