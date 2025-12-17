module de2_top_apb(
    input  wire CLOCK_50, 
    input  wire [3:0] KEY, // [0]=reset, [3]=next step
    input  wire [10:0] SW, // [0]=start, [1]=loopback En, [10]=mode select
    
    // status outputs
    output wire [17:0] LEDR, 
    output wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
    
    // LCD 
    inout  wire [7:0] LCD_DATA, 
    output wire LCD_ON, LCD_BLON, LCD_RW, LCD_EN, LCD_RS,
    
    // I/O Header (SPI Interface)
    inout  wire [3:0] GPIO_0 // [0]=SCLK, [1]=CS_N, [2]=MOSI, [3]=MISO
);

    // --- 1. Power-On Reset ---
    wire DLY_RST;
    reset_delay u_rst_delay ( .iCLK(CLOCK_50), .oRESET(DLY_RST) );
    wire rst_n = KEY[0] & DLY_RST; 

    // signals
    wire clk = CLOCK_50;
    wire step_btn_n = KEY[3]; 
    wire start_btn = SW[0];
    wire internal_loopback = SW[1];
    wire mode_auto = SW[10]; 

    // LCD defaults
    assign LCD_ON = 1'b1;
    assign LCD_BLON = 1'b1;

    // clean up HEX displays
    assign HEX4 = 7'b1111111;
    assign HEX5 = 7'b1111111;
    assign HEX6 = 7'b1111111;
    assign HEX7 = 7'b1111111;

    // detects button press
    reg btn_prev;
    reg next_step_trig;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_prev <= 1; next_step_trig <= 0;
        end else begin
            btn_prev <= step_btn_n;
            if (btn_prev == 1 && step_btn_n == 0) next_step_trig <= 1;
            else next_step_trig <= 0;
        end
    end

    // APB signals
    reg psel, penable, pwrite;
    reg [31:0] paddr, pwdata;
    wire [31:0] prdata;
    wire pready;
    
    // SPI signals
    wire spi_clk, spi_cs_l, spi_mosi;
    wire spi_miso_in;
    
    assign GPIO_0[0] = spi_clk;
    assign GPIO_0[1] = spi_cs_l;
    assign GPIO_0[2] = spi_mosi;
    assign spi_miso_in = internal_loopback ? spi_mosi : GPIO_0[3];

    // instantiate the bridge
    apb_spi_bridge u_bridge (
        .PCLK(clk), .PRESETn(rst_n),
        .PADDR(paddr), .PWRITE(pwrite), .PSEL(psel), .PENABLE(penable), .PWDATA(pwdata),
        .PRDATA(prdata), .PREADY(pready),
        .spi_clk(spi_clk), .spi_cs_l(spi_cs_l), .spi_data(spi_mosi), .master_data(spi_miso_in)
    );

    // test driver fsm
    reg [3:0] state;
    localparam S_IDLE=0, S_W_SETUP=1, S_W_ENABLE=2, S_POLL_SETUP=3, S_POLL_ENABLE=4, 
               S_READ_SETUP=5, S_READ_ENABLE=6, S_DONE=7;
               
    reg [31:0] auto_timer;
    reg [15:0] captured_data;
    
    wire advance;
    assign advance = (mode_auto && auto_timer == 0) || (!mode_auto && next_step_trig);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            psel<=0; penable<=0; pwrite<=0; paddr<=0; pwdata<=0;
            captured_data <= 16'h00FF; 
            auto_timer <= 0;
        end else begin
            if (auto_timer != 0) auto_timer <= auto_timer - 1;

            case(state)
                S_IDLE: begin
                    if (start_btn && advance) begin 
                        state <= S_W_SETUP; 
                        if(mode_auto) auto_timer <= 50000000; 
                    end
                end
                S_W_SETUP: begin
                    if (advance) begin
                        paddr <= 32'h00; pwdata <= 32'hABCD; psel <= 1; pwrite <= 1; penable <= 0;
                        state <= S_W_ENABLE;
                    end
                end
                S_W_ENABLE: begin
                    penable <= 1;
                    if (pready) begin
                        state <= S_POLL_SETUP;
                        psel <= 0; penable <= 0; pwrite <= 0;
                        if(mode_auto) auto_timer <= 50000000; 
                    end
                end
                S_POLL_SETUP: begin
                    if (advance) begin
                        paddr <= 32'h04; psel <= 1; pwrite <= 0; penable <= 0;
                        state <= S_POLL_ENABLE;
                    end
                end
                S_POLL_ENABLE: begin
                    penable <= 1;
                    if (pready) begin
                        psel <= 0; penable <= 0;
                        if (prdata[0] == 1'b1) begin // Busy?
                            state <= S_POLL_SETUP; 
                            if(mode_auto) auto_timer <= 5000000; 
                        end else begin
                            state <= S_READ_SETUP; 
                            if(mode_auto) auto_timer <= 50000000; 
                        end
                    end
                end
                S_READ_SETUP: begin
                    if (advance) begin
                        paddr <= 32'h00; psel <= 1; pwrite <= 0; penable <= 0;
                        state <= S_READ_ENABLE;
                    end
                end
                S_READ_ENABLE: begin
                    penable <= 1;
                    if (pready) begin
                        captured_data <= prdata[15:0];
                        psel <= 0; penable <= 0;
                        state <= S_DONE;
                    end
                end
                S_DONE: begin end
            endcase
        end
    end

    assign LEDR[3:0] = state;
    assign LEDR[17] = start_btn;
    assign LEDR[16] = mode_auto;
    assign LEDR[15] = internal_loopback;

    // HEX displays mapping (shows full ABCD)
    hex_decoder h0 (.in(captured_data[3:0]), .out(HEX0));   // D
    hex_decoder h1 (.in(captured_data[7:4]), .out(HEX1));   // C
    hex_decoder h2 (.in(captured_data[11:8]), .out(HEX2));  // B
    hex_decoder h3 (.in(captured_data[15:12]), .out(HEX3)); // A

    // LCD
    wire [15:0] lcd_show_data;
    // Show PWDATA during write/poll phases.
    // Show Captured Data during Read/Done phases.
    assign lcd_show_data = (state == S_READ_SETUP || state == S_READ_ENABLE || state == S_DONE) ? captured_data :
                           pwdata[15:0];

    lcd_controller u_lcd (
        .iCLK(clk), .iRST_N(rst_n),
        .state_val(state),
        .addr_val(paddr[4:0]), 
        .data_val(lcd_show_data),
        .LCD_DATA(LCD_DATA), .LCD_RW(LCD_RW), .LCD_EN(LCD_EN), .LCD_RS(LCD_RS)
    );

endmodule

// modules: reset_delay, lcd_controller, hex_decoder 
module reset_delay (input iCLK, output reg oRESET);
    reg [20:0] Cont;
    always @(posedge iCLK) begin
        if (Cont != 21'h1FFFFF) begin Cont <= Cont + 1; oRESET <= 1'b0; end 
        else oRESET <= 1'b1;
    end
endmodule

module lcd_controller (
    input iCLK, input iRST_N, input [3:0] state_val, input [4:0] addr_val, input [15:0] data_val,
    output [7:0] LCD_DATA, output LCD_RW, output reg LCD_EN, output reg LCD_RS
);
    function [7:0] to_hex_ascii;
        input [3:0] val;
        begin if (val <= 9) to_hex_ascii = {4'h3, val}; else to_hex_ascii = {4'h4, val - 4'd9}; end
    endfunction
    reg [5:0] state; reg [31:0] timer; reg [7:0] data_out;
    assign LCD_RW = 1'b0; assign LCD_DATA = data_out;
    localparam DLY_CHAR = 5000;
    always @(posedge iCLK or negedge iRST_N) begin
        if (!iRST_N) begin state <= 0; timer <= 0; LCD_EN <= 0; end else begin
            if (timer != 0) timer <= timer - 1; else begin
                case(state)
                    0: begin LCD_EN<=0; timer<=2500000; state<=1; end 
                    1: begin LCD_RS<=0; data_out<=8'h38; LCD_EN<=1; timer<=50000; state<=2; end
                    2: begin LCD_EN<=0; timer<=50000; state<=3; end
                    3: begin LCD_RS<=0; data_out<=8'h38; LCD_EN<=1; timer<=50000; state<=4; end
                    4: begin LCD_EN<=0; timer<=50000; state<=5; end
                    5: begin LCD_RS<=0; data_out<=8'h0C; LCD_EN<=1; timer<=50000; state<=6; end
                    6: begin LCD_EN<=0; timer<=50000; state<=7; end
                    7: begin LCD_RS<=0; data_out<=8'h01; LCD_EN<=1; timer<=50000; state<=8; end
                    8: begin LCD_EN<=0; timer<=100000;   state<=9; end
                    9: begin LCD_RS<=0; data_out<=8'h06; LCD_EN<=1; timer<=50000; state<=10; end
                    10:begin LCD_EN<=0; timer<=50000; state<=11; end
                    // Line 1: "St:X Adr:XX"
                    11: begin LCD_RS<=0; data_out<=8'h80; LCD_EN<=1; timer<=DLY_CHAR; state<=12; end
                    12: begin LCD_EN<=0; timer<=DLY_CHAR; state<=13; end
                    13: begin LCD_RS<=1; data_out<="S"; LCD_EN<=1; timer<=DLY_CHAR; state<=14; end
                    14: begin LCD_EN<=0; timer<=DLY_CHAR; state<=15; end
                    15: begin LCD_RS<=1; data_out<="t"; LCD_EN<=1; timer<=DLY_CHAR; state<=16; end
                    16: begin LCD_EN<=0; timer<=DLY_CHAR; state<=17; end
                    17: begin LCD_RS<=1; data_out<=":"; LCD_EN<=1; timer<=DLY_CHAR; state<=18; end
                    18: begin LCD_EN<=0; timer<=DLY_CHAR; state<=19; end
                    19: begin LCD_RS<=1; data_out<=to_hex_ascii(state_val); LCD_EN<=1; timer<=DLY_CHAR; state<=20; end
                    20: begin LCD_EN<=0; timer<=DLY_CHAR; state<=21; end
                    21: begin LCD_RS<=1; data_out<=" "; LCD_EN<=1; timer<=DLY_CHAR; state<=22; end
                    22: begin LCD_EN<=0; timer<=DLY_CHAR; state<=23; end
                    23: begin LCD_RS<=1; data_out<="A"; LCD_EN<=1; timer<=DLY_CHAR; state<=24; end
                    24: begin LCD_EN<=0; timer<=DLY_CHAR; state<=25; end
                    25: begin LCD_RS<=1; data_out<="d"; LCD_EN<=1; timer<=DLY_CHAR; state<=26; end
                    26: begin LCD_EN<=0; timer<=DLY_CHAR; state<=27; end
                    27: begin LCD_RS<=1; data_out<=":"; LCD_EN<=1; timer<=DLY_CHAR; state<=28; end
                    28: begin LCD_EN<=0; timer<=DLY_CHAR; state<=29; end
                    29: begin LCD_RS<=1; data_out<=to_hex_ascii({3'b0, addr_val[4]}); LCD_EN<=1; timer<=DLY_CHAR; state<=30; end
                    30: begin LCD_EN<=0; timer<=DLY_CHAR; state<=31; end
                    31: begin LCD_RS<=1; data_out<=to_hex_ascii(addr_val[3:0]); LCD_EN<=1; timer<=DLY_CHAR; state<=32; end
                    32: begin LCD_EN<=0; timer<=DLY_CHAR; state<=33; end
                    // Line 2: "Data: XXXX"
                    33: begin LCD_RS<=0; data_out<=8'hC0; LCD_EN<=1; timer<=DLY_CHAR; state<=34; end
                    34: begin LCD_EN<=0; timer<=DLY_CHAR; state<=35; end
                    35: begin LCD_RS<=1; data_out<="D"; LCD_EN<=1; timer<=DLY_CHAR; state<=36; end
                    36: begin LCD_EN<=0; timer<=DLY_CHAR; state<=37; end
                    37: begin LCD_RS<=1; data_out<="a"; LCD_EN<=1; timer<=DLY_CHAR; state<=38; end
                    38: begin LCD_EN<=0; timer<=DLY_CHAR; state<=39; end
                    39: begin LCD_RS<=1; data_out<="t"; LCD_EN<=1; timer<=DLY_CHAR; state<=40; end
                    40: begin LCD_EN<=0; timer<=DLY_CHAR; state<=41; end
                    41: begin LCD_RS<=1; data_out<="a"; LCD_EN<=1; timer<=DLY_CHAR; state<=42; end
                    42: begin LCD_EN<=0; timer<=DLY_CHAR; state<=43; end
                    43: begin LCD_RS<=1; data_out<=":"; LCD_EN<=1; timer<=DLY_CHAR; state<=44; end
                    44: begin LCD_EN<=0; timer<=DLY_CHAR; state<=45; end
                    45: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[15:12]); LCD_EN<=1; timer<=DLY_CHAR; state<=46; end
                    46: begin LCD_EN<=0; timer<=DLY_CHAR; state<=47; end
                    47: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[11:8]); LCD_EN<=1; timer<=DLY_CHAR; state<=48; end
                    48: begin LCD_EN<=0; timer<=DLY_CHAR; state<=49; end
                    49: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[7:4]); LCD_EN<=1; timer<=DLY_CHAR; state<=50; end
                    50: begin LCD_EN<=0; timer<=DLY_CHAR; state<=51; end
                    51: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[3:0]); LCD_EN<=1; timer<=DLY_CHAR; state<=52; end
                    // Refresh loop
                    52: begin LCD_EN<=0; timer<=2500000; state<=11; end
                endcase
            end
        end
    end
endmodule

module hex_decoder(input [3:0] in, output reg [6:0] out);
    always @(*) begin
        case(in)
            4'h0: out = 7'b1000000; 4'h1: out = 7'b1111001; 4'h2: out = 7'b0100100; 4'h3: out = 7'b0110000;
            4'h4: out = 7'b0011001; 4'h5: out = 7'b0010010; 4'h6: out = 7'b0000010; 4'h7: out = 7'b1111000;
            4'h8: out = 7'b0000000; 4'h9: out = 7'b0010000; 4'hA: out = 7'b0001000; 4'hB: out = 7'b0000011;
            4'hC: out = 7'b1000110; 4'hD: out = 7'b0100001; 4'hE: out = 7'b0000110; 4'hF: out = 7'b0001110;
            default: out = 7'b1111111;
        endcase
    end
endmodule