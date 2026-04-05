`timescale 1ns/1ps

module i2c_master #(
  parameter CLOCK_FREQ = 100_000_000,
  parameter I2C_FREQ = 100_000
)( 
  input  logic clk100mhz,
  input   logic reset,

  inout   wire logic sda,  
  inout   wire logic scl,

  // control interface
  input   logic [7:0] data_to_send, 
  input   logic [7:0] addr_to_send,
  input   logic new_cmd,

  // status interface
  output  logic busy,
  output  logic ack_error,
  output  logic [7:0] read_data_out
);
  
  localparam logic [15:0] PHASE_TICKS = (CLOCK_FREQ / I2C_FREQ) / 4;

  typedef enum logic [3:0] {
    IDLE, 
    START,
    ADDRESS_SEND,
    ACK_ADDR,
    DATA_SEND,
    ACK_DATA,
    DATA_RECEIVE,
    MASTER_ACK,
    STOP
  } state_t;
  state_t state;

  logic [15:0] tick_count;
  logic [1:0] phase;
  logic tick;
  logic start_pending;

  logic sda_h;
  logic scl_h;
  
  logic [7:0] data_to_send_store;
  logic [7:0] addr_to_send_store;
  logic [7:0] data_read_store;
  logic [2:0] bit_count;
  
  // tri-state buffer
  // When sda_mode is 1, we drive sda based on sda_h.
  // Standard I2C is Open Drain: Drive '0' or High-Z.
  // If sda_h is 0, drive 0. If sda_h is 1, release (z).
  assign sda = (!sda_h) ? 1'b0 : 1'bz;
  assign scl = (!scl_h) ? 1'b0 : 1'bz;
  
  assign busy = (state != IDLE) || start_pending;

  // phase tick generator
  always_ff @(posedge clk100mhz or posedge reset) begin
    if (reset) begin
      tick_count <= 0;
      tick <= 0;
    end
    else begin
      if (tick_count == PHASE_TICKS - 1) begin
        tick_count <= 0;
        tick <= 1'b1;
      end
      else begin
        tick_count <= tick_count + 1;
        tick <= 1'b0;
      end
    end
  end

    // fast clock command capture
  always_ff @(posedge clk100mhz or posedge reset) begin
    if (reset) begin
      start_pending <= 1'b0;
      addr_to_send_store <= 8'd0;
      data_to_send_store <= 8'd0;
    end
    else begin
      if (new_cmd && state == IDLE && !start_pending) begin
        start_pending <= 1'b1;
        addr_to_send_store <= addr_to_send;
        data_to_send_store <= data_to_send;
      end
      else if (tick && state == IDLE && start_pending) begin
        start_pending <= 1'b0;
      end
    end
  end

  //FSM
  always_ff @(posedge clk100mhz or posedge reset) begin
    if (reset) begin
      state <= IDLE;
      phase <= 2'b00;
      sda_h <= 1'b1;
      scl_h <= 1'b1;
      ack_error <= 1'b0;
    end 
    else if (tick) begin
      if (scl_h == 1'b1 && scl == 1'b0) begin

      end
      else begin
        phase <= phase + 2'd1;

        case (state)
        IDLE: begin
          sda_h <= 1'b1;
          scl_h <= 1'b1;
          phase <= 2'b00;
          if (new_cmd) begin
            ack_error <= 1'b0;
            state <= START;
          end
        end

        START: begin
          case (phase) 
            2'b00: begin 
              sda_h <= 1'b1; 
              scl_h <= 1'b1; 
            end
            2'b01: begin 
              sda_h <= 1'b0; 
              scl_h <= 1'b1; 
            end
            2'b10: begin 
              sda_h <= 1'b0; 
              scl_h <= 1'b1; 
            end
            2'b11: begin 
              sda_h <= 1'b0; 
              scl_h <= 1'b0;
              bit_count <= 3'd7;
              state <= ADDRESS_SEND;
            end
            default: phase <= 2'b00;
          endcase 
        end

        ADDRESS_SEND: begin
          case (phase) 
            2'b00: begin 
              sda_h <= addr_to_send_store[bit_count]; 
              scl_h <= 1'b0; 
            end
            2'b01: begin
              scl_h <= 1'b1; 
            end
            2'b10: begin
              scl_h <= 1'b1;
            end
            2'b11: begin
              scl_h <= 1'b0;
              if (bit_count == 3'd0) state <= ACK_ADDR;
              else bit_count <= bit_count - 3'd1;
            end
            default: phase <= 2'b00;
          endcase
        end

        ACK_ADDR: begin
          case (phase) 
            2'b00: begin 
              sda_h <= 1'b1;
              scl_h <= 1'b0;
            end
            2'b01: begin
              scl_h <= 1'b1;
            end
            2'b10: begin
              scl_h <= 1'b1;
              if (sda == 1'b1) ack_error <= 1'b1;
            end
            2'b11: begin
              scl_h <= 1'b0;
              bit_count <= 3'd7;
              if (addr_to_send_store[0] == 1'b1) state <= DATA_RECEIVE;
              else                               state <= DATA_SEND;
            end
            default: phase <= 2'b00;
          endcase
        end

        DATA_SEND: begin
          case (phase) 
            2'b00: begin 
              sda_h <= data_to_send_store[bit_count];
              scl_h <= 1'b0;
            end
            2'b01: begin
              scl_h <= 1'b1;
            end
            2'b10: begin
              scl_h <= 1'b1;
            end
            2'b11: begin
              scl_h <= 1'b0;
              if (bit_count == 3'd0) state <= ACK_DATA;
              else bit_count <= bit_count - 3'd1;
            end
            default: phase <= 2'b00;
          endcase
        end

        ACK_DATA: begin
          case (phase) 
            2'b00: begin 
              sda_h <= 1'b1;
              scl_h <= 1'b0;
            end
            2'b01: begin
              scl_h <= 1'b1;
            end
            2'b10: begin
              scl_h <= 1'b1;
              if (sda == 1'b1) ack_error <= 1'b1;
            end
            2'b11: begin
              scl_h <= 1'b0;
              state <= STOP;
            end
            default: phase <= 2'b00;
          endcase
        end

        DATA_RECEIVE: begin
          case (phase)
            2'b00: begin
              sda_h <= 1'b1;
              scl_h <= 1'b0;
            end
            2'b01: begin
              scl_h <= 1'b1;
            end
            2'b10: begin
              scl_h <= 1'b1;
              data_read_store[bit_count] <= sda;
            end
            2'b11: begin
              scl_h <= 1'b0;
              if (bit_count == 3'd0) state <= MASTER_ACK;
              else bit_count <= bit_count - 3'd1;
            end
            default: phase <= 2'b00;
          endcase 
        end 

        MASTER_ACK: begin
          case (phase) 
            2'b00: begin
              sda_h <= 1'b0; 
              scl_h <= 1'b0;
            end
            2'b01: begin
              scl_h <= 1'b1;
            end
            2'b10: begin
              scl_h <= 1'b1;
            end
            2'b11: begin
              scl_h <= 1'b0;
              read_data_out <= data_read_store;
              state <= STOP;
            end
            default: phase <= 2'b00;
          endcase
        end

        STOP: begin
          case (phase) 
            2'b00: begin
              sda_h <= 1'b0; 
              scl_h <= 1'b0;
            end
            2'b01: begin
              sda_h <= 1'b0; 
              scl_h <= 1'b1;
            end
            2'b10: begin
              sda_h <= 1'b1; 
              scl_h <= 1'b1;
            end
            2'b11: begin
              state <= IDLE;
            end
            default: phase <= 2'b00;
          endcase
        end

        default: begin
          state <= IDLE;
          phase <= 2'b00;
          sda_h <= 1'b1;
          scl_h <= 1'b1;
        end
        endcase
      end
    end
  end
  

endmodule
