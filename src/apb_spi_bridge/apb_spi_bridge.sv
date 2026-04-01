`timescale 1ns/1ps
module apb_spi_bridge(
  input logic PCLK,
  input logic PRESETn,
  input logic [31:0] PADDR,
  input logic PWRITE,
  input logic PSEL,
  input logic PENABLE,
  input logic [31:0] PWDATA,
  output logic [31:0] PRDATA,
  output logic PREADY,
  
  output logic spi_interrupt,
  
  output logic cs_n,
  output logic sclk,
  output logic mosi,
  input logic miso
);
  
  typedef enum logic [1:0] {
    IDLE, 
    SETUP,
    ACCESS
  } state_t;
  // APB state machine
  state_t state, next_state;
  
  logic [15:0] spi_tx_reg;
  logic [15:0] spi_rx_reg;
  logic spi_start;
  logic spi_busy;
  
  // APB FSM 
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) 
      state <= IDLE;
    else 
      state <= next_state;
  end
  
  always_comb begin
    next_state = state;
    
    case (state) 
      IDLE: 
        if (PSEL && !PENABLE) next_state = SETUP;
      
      SETUP: 
        if (PSEL && PENABLE) next_state = ACCESS;
      
      ACCESS: 
        if (!PSEL) next_state = IDLE;
        else       next_state = ACCESS;
      
      default: next_state = IDLE;
    endcase
  end
  
  // APB Ready is high during ACCESS phase for 1 cycle response
  assign PREADY = (state == ACCESS);
  
  // Write Logic (CPU writes to Bridge)
  always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      spi_start <= 1'b0;
      spi_tx_reg <= 16'h0000;
    end
    else begin
      spi_start <= 1'b0; // pulse default low
      
      // Write happens in SETUP check
      if (state == SETUP && PWRITE) begin
        if (PADDR[7:0] == 8'h00) begin
          spi_tx_reg <= PWDATA[15:0];   // load data
          spi_start <= 1'b1;            // trigger SPI Start
        end
      end
    end
  end
  
  // Read Logic (CPU reads from Bridge)
  always_comb begin
    PRDATA = '0;

    if (state == ACCESS && !PWRITE) begin
      case (PADDR[7:0])
        8'h00: PRDATA = {16'd0, spi_rx_reg};
        8'h04: PRDATA = {16'd0, spi_busy};
        default: PRDATA = '0;
      endcase
    end
  end
    
  // Instantiate SPI Core
  spi_core u_spi_core (
    .clk(PCLK),
    .reset(!PRESETn), // APB is active low, Core is active high
    .start(spi_start),
    .datain(spi_tx_reg),
    .dataout(spi_rx_reg),
    .busy(spi_busy),
    .done(spi_interrupt),

    .cs_n(cs_n),
    .sclk(sclk),
    .mosi(mosi),
    .miso(miso)
  );

endmodule
