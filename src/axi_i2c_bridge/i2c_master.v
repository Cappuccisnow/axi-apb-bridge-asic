module i2c_master(
  inout   wire sda,  // Bidirectional for I2C
  output  wire scl,
  output  wire clk2mhz_dummy,
  output  wire rw,
  input   wire clk100mhz,
  input   wire res,
  input   wire [7:0] data_to_send, 
  input   wire [7:0] addr_to_send,
  input   wire new_cmd,
  output  wire busy,
  output  wire [7:0] read_data_out
);
    
  localparam [3:0] idle = 4'b0000, start_init = 4'b0001, start = 4'b0010, 
  address_send = 4'b0011, slave_ack = 4'b0101, 
  data_send_init_wait = 4'b0110, data_send_init = 4'b0111, data_send = 4'b1000,
  data_ack = 4'b1010, stop_init = 4'b1011, 
  stop = 4'b1100, data_read_init = 4'b1101, data_read = 4'b1110;
      
  reg [3:0] state;
  reg start_pending;
  
  reg sda_h;
  reg sda_mode; // 1 = Output mode, 0 = Input mode
  reg scl_h;
  reg scl_mode;
  reg scl_toggle;
  
  reg [6:0] count;
  reg [7:0] data_to_send_store;
  reg [7:0] addr_to_send_store;
  reg [3:0] bit_count;
  reg [2:0] count_ack_wait;
  reg [1:0] count_sda_wait;
  
  reg [7:0] data_read_store;
  
  // tri-state buffer
  // When sda_mode is 1, we drive sda based on sda_h.
  // Standard I2C is Open Drain: Drive '0' or High-Z.
  // If sda_h is 0, drive 0. If sda_h is 1, release (z).
  assign sda = (sda_mode && !sda_h) ? 1'b0 : 1'bz;

  assign scl = (scl_toggle) ? (scl_h ? 1'bz : 1'b0) : 1'bz; // SCL also open drain-ish or driven
  
  assign busy = (state != idle);
  assign read_data_out = data_read_store;
  assign rw = 0; // Placeholder
  assign clk2mhz_dummy = count[6]; // Just for debug/observation

  // State Machine Logic
  always @(posedge clk100mhz or posedge res) begin
    if (res) begin
      state <= idle;
      sda_h <= 1; sda_mode <= 0;
      scl_h <= 1; scl_mode <= 0; scl_toggle <= 0;
      count <= 0;
      bit_count <= 0;
      start_pending <= 0;
      data_to_send_store <= 0;
      addr_to_send_store <= 0;
      data_read_store <= 0;
    end else begin
      count <= count + 1;
      
      // Slow down the state machine (Simple clock divider effect)
      if (count == 0) begin
        case(state)
        idle : begin
          sda_h <= 1; sda_mode <= 0;
          scl_h <= 1; scl_toggle <= 0;
          if (new_cmd) begin
            start_pending <= 1;
            addr_to_send_store <= addr_to_send;
            data_to_send_store <= data_to_send;
          end
          else if (start_pending) begin
            state <= start_init;
            start_pending <= 0;
          end
        end
        
        start_init : begin
          sda_mode <= 1; sda_h <= 0; // Drive Start Condition
          state <= start;
        end
        
        start : begin
          scl_toggle <= 1; scl_h <= 0; // Clock Low
          bit_count <= 8;
          state <= address_send;
        end
        
        address_send : begin
          sda_mode <= 1;
          sda_h <= addr_to_send_store[bit_count - 1];
          bit_count <= bit_count - 1;
          if (bit_count == 1) begin
             state <= slave_ack;
             count_ack_wait <= 3; // Wait a few cycles for ACK
          end
        end
        
        slave_ack : begin
          sda_mode <= 0; // Release SDA for Slave to ACK
          count_ack_wait <= count_ack_wait - 1;
          if (count_ack_wait == 0) begin
             // Ideally check if sda is low (ACK received)
             state <= data_send_init_wait;
          end
        end
        
        data_send_init_wait : begin
           // Wait state or setup
           state <= data_send_init;
        end

        data_send_init : begin
           bit_count <= 8;
           state <= data_send;
        end
        
        data_send : begin
          sda_mode <= 1;
          sda_h <= data_to_send_store[bit_count - 1];
          bit_count <= bit_count - 1;
          if (bit_count == 1) begin
             state <= data_ack;
             count_ack_wait <= 3;
          end
        end
        
        data_ack : begin
          sda_mode <= 0; // Release for ACK
          count_ack_wait <= count_ack_wait - 1;
          if (count_ack_wait == 0) begin
             state <= stop_init;
             count_sda_wait <= 2; 
          end
        end
        
        // READ STATES (Simplified placeholder)
        data_read_init : begin
          state <= idle; // Not fully implemented in this snippet
        end
        data_read : begin
           state <= idle;
        end
        
        stop_init : begin
          scl_toggle <= 0; scl_h <= 1; // Stop: SCL High
          state <= stop;
        end
        
        stop : begin
          sda_mode <= 1; sda_h <= 1; // Stop: SDA Low -> High while SCL High
          count_sda_wait <= count_sda_wait - 1;
          if (count_sda_wait == 0) 
             state <= idle;
        end
        
        default : state <= idle;
        endcase
      end
    end
  end
    
endmodule