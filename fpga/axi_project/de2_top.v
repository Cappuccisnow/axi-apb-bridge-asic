module de2_top(
    input  wire CLOCK_50, 
    input  wire [3:0] KEY, // [0]=reset, [3]=next step
    input  wire [10:0] SW, // [0]=start, [10]=mode select
    
    // status outputs
    output wire [17:0] LEDR, 
    output wire [6:0]  HEX0, HEX1, 
    
    // LCD 
    inout  wire [7:0] LCD_DATA, 
    output wire LCD_ON, LCD_BLON, LCD_RW, LCD_EN, LCD_RS,
    
    // I/O Header
    inout  wire [1:0] GPIO_0
);

    // reset
    wire DLY_RST;
    reset_delay u_rst_delay (
        .iCLK(CLOCK_50),
        .oRESET(DLY_RST)
    );

    wire sys_reset_n = KEY[0] & DLY_RST;

    // signals
    wire clk = CLOCK_50;
    wire res_n = sys_reset_n; 
    wire step_btn_n = KEY[3]; 
    wire start_btn = SW[0];   
    wire mode_auto = SW[10]; 
    
    // LCD 
    assign LCD_ON = 1'b1;
    assign LCD_BLON = 1'b1;
    
    // detects button press
    reg btn_prev;
    reg next_step_trig;
    always @(posedge clk or negedge res_n) begin
        if (!res_n) begin
            btn_prev <= 1; next_step_trig <= 0;
        end else begin
            btn_prev <= step_btn_n;
            if (btn_prev == 1 && step_btn_n == 0) next_step_trig <= 1;
            else next_step_trig <= 0;
        end
    end

    // AXI signals & bridge instantiation
    reg arvalid, awvalid, wvalid, bready, rready;
    reg [4:0] araddr, awaddr;
    reg [15:0] wdata;
    wire [3:0] arlen=0; wire [3:0] awlen=0;
    wire [2:0] arsize=1; wire [2:0] awsize=1; 
    wire [1:0] arburst=1; wire [1:0] awburst=1; 
    wire wlast=1; 
    wire arready, awready, wready, bvalid, rvalid, rlast;
    wire [1:0] bresp, rresp;
    wire [15:0] rdata;
    
    reg [3:0] state;
    localparam S_IDLE=0, S_W_ADDR=1, S_W_DATA=2, S_W_START=3, S_WAIT=4, S_R_STAT=5, S_DONE=6;
    reg [23:0] wait_timer; 
    reg [15:0] captured_data;
    reg [31:0] auto_timer;

    axi_i2c_bridge u_bridge (
        .clk(clk), .res_n(res_n),
        .arvalid(arvalid), .awvalid(awvalid), .wvalid(wvalid), 
        .bready(bready), .rready(rready),
        .araddr(araddr), .awaddr(awaddr), .wdata(wdata),
        .arlen(arlen), .awlen(awlen), .arsize(arsize), .awsize(awsize), 
        .arburst(arburst), .awburst(awburst), .wlast(wlast),
        .arready(arready), .awready(awready), .wready(wready),
        .bvalid(bvalid), .rvalid(rvalid), 
        .bresp(bresp), .rresp(rresp), .rlast(rlast), .rdata(rdata),
        .sda(GPIO_0[0]), .scl(GPIO_0[1])
    );

    wire advance;
    assign advance = (mode_auto && auto_timer == 0) || (!mode_auto && next_step_trig);

    // FSM
    always @(posedge clk or negedge res_n) begin
        if (!res_n) begin
            state <= S_IDLE;
            arvalid<=0; awvalid<=0; wvalid<=0; bready<=0; rready<=0;
            captured_data <= 16'h00FF; 
            wait_timer <= 0; auto_timer <= 0;
        end else begin
            awvalid <= 0; wvalid <= 0; bready <= 0; arvalid <= 0; rready <= 0;
            if (auto_timer != 0) auto_timer <= auto_timer - 1;

            case(state)
                S_IDLE: if (start_btn && advance) begin state <= S_W_ADDR; if(mode_auto) auto_timer <= 100000000; end
                S_W_ADDR: begin awvalid<=1; awaddr<=5'd0; wvalid<=1; wdata<=16'h0050; bready<=1; 
                          if (bvalid && advance) begin state <= S_W_DATA; if(mode_auto) auto_timer <= 100000000; end end
                S_W_DATA: begin awvalid<=1; awaddr<=5'd1; wvalid<=1; wdata<=16'h00AA; bready<=1;
                          if (bvalid && advance) begin state <= S_W_START; if(mode_auto) auto_timer <= 100000000; end end
                S_W_START: begin awvalid<=1; awaddr<=5'd2; wvalid<=1; wdata<=16'h0001; bready<=1;
                           if (bvalid) begin state <= S_WAIT; wait_timer <= 24'd15000000; end end
                S_WAIT: begin if (wait_timer == 0) begin if (advance) begin state <= S_R_STAT; if(mode_auto) auto_timer <= 100000000; end end else wait_timer <= wait_timer - 1; end
                S_R_STAT: begin arvalid<=1; araddr<=5'd4; rready<=1; if (rvalid) begin captured_data <= rdata; if (advance) state <= S_DONE; end end
                S_DONE: begin end
            endcase
        end
    end

    assign LEDR[3:0] = state; 
    assign LEDR[17] = start_btn; 
    assign LEDR[16] = mode_auto;
    
    hex_decoder h0 (.in(captured_data[3:0]), .out(HEX0));
    hex_decoder h1 (.in(captured_data[7:4]), .out(HEX1));

    // LCD displays
    wire [4:0] lcd_show_addr;
    wire [15:0] lcd_show_data;
    
    assign lcd_show_addr = (state == S_W_ADDR) ? 5'd0 :
                           (state == S_W_DATA) ? 5'd1 :
                           (state == S_W_START || state == S_WAIT) ? 5'd2 :
                           (state == S_R_STAT || state == S_DONE) ? 5'd4 : 5'd0;
                           
    assign lcd_show_data = (state == S_W_ADDR) ? 16'h0050 :
                           (state == S_W_DATA) ? 16'h00AA :
                           (state == S_W_START) ? 16'h0001 :
                           (state == S_WAIT) ? 16'hFFFF :
                           (state == S_R_STAT) ? rdata :
                           (state == S_DONE) ? captured_data : 16'h0000;

    lcd_controller u_lcd (
        .iCLK(clk),
        .iRST_N(sys_reset_n), 
        .state_val(state),
        .addr_val(lcd_show_addr),
        .data_val(lcd_show_data),
        .LCD_DATA(LCD_DATA),
        .LCD_RW(LCD_RW),
        .LCD_EN(LCD_EN),
        .LCD_RS(LCD_RS)
    );

endmodule

// reset delay module
module reset_delay (
    input iCLK,
    output reg oRESET
);
    reg [20:0] Cont;
    always @(posedge iCLK) begin
        if (Cont != 21'h1FFFFF) begin
            Cont <= Cont + 1;
            oRESET <= 1'b0;
        end else begin
            oRESET <= 1'b1;
        end
    end
endmodule

// lcd controller
module lcd_controller (
    input iCLK,
    input iRST_N,
    input [3:0] state_val,
    input [4:0] addr_val,
    input [15:0] data_val,
    output [7:0] LCD_DATA,
    output LCD_RW,
    output reg LCD_EN,
    output reg LCD_RS
);
    // ASCII Helper
    function [7:0] to_hex_ascii;
        input [3:0] val;
        begin
            if (val <= 9) to_hex_ascii = {4'h3, val};
            else to_hex_ascii = {4'h4, val - 4'd9};
        end
    endfunction

    reg [5:0] state;
    reg [31:0] timer;
    reg [7:0] data_out;
    
    assign LCD_RW = 1'b0; // Always Write
    assign LCD_DATA = data_out; // Direct drive

    // Timings
    localparam DLY_CHAR = 5000;   // 100us (Standard char delay)
    localparam DLY_INIT = 50000;  // 1ms (Init command delay)
    
    always @(posedge iCLK or negedge iRST_N) begin
        if (!iRST_N) begin
            state <= 0;
            timer <= 0;
            LCD_EN <= 0;
            LCD_RS <= 0;
            data_out <= 0;
        end else begin
            if (timer != 0) begin
                timer <= timer - 1;
            end else begin
                case(state)
                    // Initialization (Standard HD44780 Sequence)
                    0: begin LCD_EN<=0; timer<=2500000; state<=1; end // 50ms Power-on wait
                    1: begin LCD_RS<=0; data_out<=8'h38; LCD_EN<=1; timer<=DLY_INIT; state<=2; end // Function Set
                    2: begin LCD_EN<=0; timer<=DLY_INIT; state<=3; end
                    3: begin LCD_RS<=0; data_out<=8'h38; LCD_EN<=1; timer<=DLY_INIT; state<=4; end // Function Set again
                    4: begin LCD_EN<=0; timer<=DLY_INIT; state<=5; end
                    5: begin LCD_RS<=0; data_out<=8'h0C; LCD_EN<=1; timer<=DLY_INIT; state<=6; end // Display ON
                    6: begin LCD_EN<=0; timer<=DLY_INIT; state<=7; end
                    7: begin LCD_RS<=0; data_out<=8'h01; LCD_EN<=1; timer<=DLY_INIT; state<=8; end // Clear Display
                    8: begin LCD_EN<=0; timer<=100000;   state<=9; end // Clear needs ~2ms (using 2ms)
                    9: begin LCD_RS<=0; data_out<=8'h06; LCD_EN<=1; timer<=DLY_INIT; state<=10; end // Entry Mode
                    10:begin LCD_EN<=0; timer<=DLY_INIT; state<=11; end

                    // --- REFRESH LOOP ---
                    // Line 1 Command (0x80)
                    11: begin LCD_RS<=0; data_out<=8'h80; LCD_EN<=1; timer<=DLY_CHAR; state<=12; end
                    12: begin LCD_EN<=0; timer<=DLY_CHAR; state<=13; end
                    
                    // "St:X "
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
                    
                    // "Ad:XX"
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

                    // Line 2 Command (0xC0)
                    33: begin LCD_RS<=0; data_out<=8'hC0; LCD_EN<=1; timer<=DLY_CHAR; state<=34; end
                    34: begin LCD_EN<=0; timer<=DLY_CHAR; state<=35; end
                    
                    // "Data:"
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
                    
                    // "XXXX"
                    45: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[15:12]); LCD_EN<=1; timer<=DLY_CHAR; state<=46; end
                    46: begin LCD_EN<=0; timer<=DLY_CHAR; state<=47; end
                    47: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[11:8]); LCD_EN<=1; timer<=DLY_CHAR; state<=48; end
                    48: begin LCD_EN<=0; timer<=DLY_CHAR; state<=49; end
                    49: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[7:4]); LCD_EN<=1; timer<=DLY_CHAR; state<=50; end
                    50: begin LCD_EN<=0; timer<=DLY_CHAR; state<=51; end
                    51: begin LCD_RS<=1; data_out<=to_hex_ascii(data_val[3:0]); LCD_EN<=1; timer<=DLY_CHAR; state<=52; end
                    
                    // REFRESH PAUSE: wait 50ms before rewriting screen
                    52: begin LCD_EN<=0; timer<=2500000; state<=11; end // Go to Line 1 command
                endcase
            end
        end
    end
endmodule

module hex_decoder(input [3:0] in, output reg [6:0] out);
    always @(*) begin
        case(in)
            4'h0: out = 7'b1000000;
            4'h1: out = 7'b1111001;
            4'h2: out = 7'b0100100;
            4'h3: out = 7'b0110000;
            4'h4: out = 7'b0011001;
            4'h5: out = 7'b0010010;
            4'h6: out = 7'b0000010;
            4'h7: out = 7'b1111000;
            4'h8: out = 7'b0000000;
            4'h9: out = 7'b0010000;
            4'hA: out = 7'b0001000;
            4'hB: out = 7'b0000011;
            4'hC: out = 7'b1000110;
            4'hD: out = 7'b0100001;
            4'hE: out = 7'b0000110;
            4'hF: out = 7'b0001110;
            default: out = 7'b1111111;
        endcase
    end
endmodule