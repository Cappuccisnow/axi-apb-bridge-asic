module apb_spi_bridge(
  input wire PCLK,
  input wire PRESETn,
  input wire [31:0] PADDR,
  input wire PWRITE,
  input wire PSEL,
  input wire PENABLE,
  input wire [31:0] PWDATA,
  output wire [31:0] PRDATA,
  output wire PREADY,
  
  output wire spi_cs_l,
  output wire spi_clk,
  output wire spi_data,
  input wire master_data
);
  
  // APB state machine
  localparam [1:0] IDLE = 2'b00, SETUP = 2'b01, ACCESS = 2'b10;
  reg [1:0] apb_st, nxt_st;
  
  reg [15:0] spi_tx_reg;
  wire [15:0] spi_rx_reg;
  reg spi_start;
  wire spi_busy;
  
  // APB FSM 
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) 
      apb_st <= IDLE;
    else 
      apb_st <= nxt_st;
  end
  
  always @(*) begin
    nxt_st = apb_st;
    case (apb_st) 
      IDLE: if (PSEL && !PENABLE) 
        nxt_st = SETUP;
      SETUP: if (PSEL && PENABLE)
        nxt_st = ACCESS;
      ACCESS: if (!PSEL)
        nxt_st = IDLE;
      else 
        nxt_st = ACCESS;
      default: nxt_st = IDLE;
    endcase
  end
  
  // APB Ready is high during ACCESS phase for 1 cycle response
  assign PREADY = (apb_st == ACCESS);
  
  // Write Logic (CPU writes to Bridge)
  always @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
      spi_start <= 0;
      spi_tx_reg <= 16'h0000;
    end
    else begin
      spi_start <= 0; // pulse default low
      
      // Write happens in SETUP check
      if (apb_st == SETUP && PWRITE && PSEL) begin
        if (PADDR[7:0] == 8'h00) begin
          spi_tx_reg <= PWDATA[15:0];   // load data
          spi_start <= 1;               // trigger SPI Start
        end
      end
    end
  end
  
  // Read Logic (CPU reads from Bridge)
  reg [31:0] read_data_mux;
  always @(*) begin
    read_data_mux = 32'd0;
    if (PSEL && !PWRITE) begin
       if (PADDR[7:0] == 8'h00)
          read_data_mux = {16'd0, spi_rx_reg}; // read RX Data (Addr 0x00)
       else if (PADDR[7:0] == 8'h04)
          read_data_mux = {31'd0, spi_busy};   // read status (Addr 0x04)
    end
  end
  
  assign PRDATA = (PSEL && PENABLE && !PWRITE) ? read_data_mux : 32'd0;
  
  // Instantiate SPI Core
  spi_core u_spi_core (
    .clk(PCLK),
    .reset(!PRESETn), // APB is active low, Core is active high
    .start(spi_start),
    .datain(spi_tx_reg),
    .dataout(spi_rx_reg),
    .spi_cs_l(spi_cs_l),
    .spi_clk(spi_clk),
    .spi_data(spi_data),
    .master_data(master_data),
    .busy(spi_busy)
  );

endmodule