// Lightweight synthesizable OSD for 640x480 RGB video.
//
// Layers:
//   1. Supplied red/navy Anlogic graphic in a small white badge (all pages).
//   2. Running HH:MM:SS timestamp.
//   3. Page-bound theme ticker + PCM-reactive side bars (bottom band only).
//
// Other panels retain 4-bit Alpha blending and the compact 5x7 font. The logo
// is compiled from the user's BMP into two combinational masks, not a second
// frame buffer. No external initialization file or new pipeline stage.
module video_osd_overlay #(
    parameter integer PIXEL_CLK_HZ = 25_000_000
)(
    input             clk,
    input             rst,
    input             hs,
    input             vs,
    input             de,
    input      [23:0] rgb_in,
    input signed [8:0] brightness,
    input [2:0] contrast_q2,
    input [1:0] active_control,
    input [2:0] lesson_idx,
    input audio_valid,
    input [23:0] audio_left,audio_right,
    output reg [23:0] rgb_out
);

reg [9:0] x;
reg [9:0] y;
reg       de_d;
reg       vs_d;

reg [24:0] second_count;
reg [4:0]  hours;
reg [5:0]  minutes;
reg [5:0]  seconds;

reg [7:0]  glyph_char;
reg [4:0]  glyph_row_bits;
reg [4:0]  glyph_index;
reg [3:0]  glyph_col;
reg [3:0]  glyph_row;
reg [23:0] panel_color,text_color;
reg [4:0] panel_alpha;
wire [8:0] brightness_magnitude=brightness[8] ? -brightness : brightness;

wire frame_tick;
assign frame_tick = vs & ~vs_d;
wire [5:0] logo_x=x-10'd22;
wire [4:0] logo_y=y-10'd16;
wire [47:0] logo_red_bits=logo_red_row(logo_y);
wire [47:0] logo_blue_bits=logo_blue_row(logo_y);
wire logo_inside=x>=22 && x<70 && y>=16 && y<47;

wire footer_draw;
wire [23:0] footer_rgb;
sound_theme_footer u_sound_theme_footer(
    .clk(clk),.rst(rst),.vs(vs),.de(de),.x(x),.y(y),.lesson_idx(lesson_idx),
    .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
    .draw(footer_draw),.rgb(footer_rgb)
);

function [7:0] decimal_ascii;
    input [3:0] digit;
    begin
        decimal_ascii = 8'd48 + digit;
    end
endfunction

// LOGO_BITMAP_BEGIN
function [47:0] logo_red_row;
    input [4:0] row;
    begin
        case(row)
            5'd0: logo_red_row=48'h00003FFFFFFE;
            5'd1: logo_red_row=48'h00003FFFFFFE;
            5'd2: logo_red_row=48'h000000000000;
            5'd3: logo_red_row=48'h000000000000;
            5'd4: logo_red_row=48'h00001FFFFFFC;
            5'd5: logo_red_row=48'h00000FFFFFF8;
            5'd6: logo_red_row=48'h000000000000;
            5'd7: logo_red_row=48'h000007FFFFF0;
            5'd8: logo_red_row=48'h000007FFFFF0;
            5'd9: logo_red_row=48'h000000000000;
            5'd10: logo_red_row=48'h000000000000;
            5'd11: logo_red_row=48'h000001FFFFC0;
            5'd12: logo_red_row=48'h000001FFFF80;
            5'd13: logo_red_row=48'h000000000000;
            5'd14: logo_red_row=48'h000000000000;
            5'd15: logo_red_row=48'h0000007FFF00;
            5'd16: logo_red_row=48'h000000000000;
            5'd17: logo_red_row=48'h000000000000;
            5'd18: logo_red_row=48'h0000003FFC00;
            5'd19: logo_red_row=48'h0000001FFC00;
            5'd20: logo_red_row=48'h000000000000;
            5'd21: logo_red_row=48'h000000000000;
            5'd22: logo_red_row=48'h0000000FF800;
            5'd23: logo_red_row=48'h00000007F000;
            5'd24: logo_red_row=48'h000000000000;
            5'd25: logo_red_row=48'h00000003C000;
            5'd26: logo_red_row=48'h00000003C000;
            5'd27: logo_red_row=48'h000000000000;
            5'd28: logo_red_row=48'h000000000000;
            5'd29: logo_red_row=48'h000000008000;
            5'd30: logo_red_row=48'h000000000000;
            default: logo_red_row=48'd0;
        endcase
    end
endfunction
function [47:0] logo_blue_row;
    input [4:0] row;
    begin
        case(row)
            5'd0: logo_blue_row=48'h000000000000;
            5'd1: logo_blue_row=48'h000100000000;
            5'd2: logo_blue_row=48'h000380000000;
            5'd3: logo_blue_row=48'h000380000000;
            5'd4: logo_blue_row=48'h0007C0000000;
            5'd5: logo_blue_row=48'h0007C0000000;
            5'd6: logo_blue_row=48'h000FE0000000;
            5'd7: logo_blue_row=48'h000FE0000000;
            5'd8: logo_blue_row=48'h001FF0000000;
            5'd9: logo_blue_row=48'h001FF0000000;
            5'd10: logo_blue_row=48'h003FF8000000;
            5'd11: logo_blue_row=48'h003FF8000000;
            5'd12: logo_blue_row=48'h007FFC000000;
            5'd13: logo_blue_row=48'h007FFC000000;
            5'd14: logo_blue_row=48'h00FFFE000000;
            5'd15: logo_blue_row=48'h00FEFE000000;
            5'd16: logo_blue_row=48'h01FC7F000000;
            5'd17: logo_blue_row=48'h01FC7F000000;
            5'd18: logo_blue_row=48'h03F83F800000;
            5'd19: logo_blue_row=48'h03F83F800000;
            5'd20: logo_blue_row=48'h07F01FC00000;
            5'd21: logo_blue_row=48'h07F01FC00000;
            5'd22: logo_blue_row=48'h0FE00FE00000;
            5'd23: logo_blue_row=48'h0FE00FE00000;
            5'd24: logo_blue_row=48'h1FC007F00000;
            5'd25: logo_blue_row=48'h1FFF83F80000;
            5'd26: logo_blue_row=48'h3FFFC3F80000;
            5'd27: logo_blue_row=48'h3FFFC1F80000;
            5'd28: logo_blue_row=48'h7FFFE1FC0000;
            5'd29: logo_blue_row=48'h7FFFE0FC0000;
            5'd30: logo_blue_row=48'h7FFFF0FE0000;
            default: logo_blue_row=48'd0;
        endcase
    end
endfunction
// LOGO_BITMAP_END

function [7:0] time_char;
    input [4:0] index;
    begin
        case (index)
            4'd0:  time_char = "T";
            4'd1:  time_char = "I";
            4'd2:  time_char = "M";
            4'd3:  time_char = "E";
            4'd4:  time_char = " ";
            4'd5:  time_char = decimal_ascii(hours / 10);
            4'd6:  time_char = decimal_ascii(hours % 10);
            4'd7:  time_char = ":";
            4'd8:  time_char = decimal_ascii(minutes / 10);
            4'd9:  time_char = decimal_ascii(minutes % 10);
            4'd10: time_char = ":";
            4'd11: time_char = decimal_ascii(seconds / 10);
            4'd12: time_char = decimal_ascii(seconds % 10);
            default: time_char = " ";
        endcase
    end
endfunction


function [7:0] parameter_char;
    input [4:0] index;
    begin
        case(index)
            0: parameter_char="B"; 1: parameter_char="R"; 2: parameter_char="I";
            3,11: parameter_char=":";
            4: parameter_char=brightness[8] ? "-" : "+";
            5: parameter_char=decimal_ascii(brightness_magnitude/10);
            6: parameter_char=decimal_ascii(brightness_magnitude%10);
            8: parameter_char="C"; 9: parameter_char="O"; 10: parameter_char="N";
            12: parameter_char=(contrast_q2>=4) ? "1" : "0";
            13: case(contrast_q2)
                2,6: parameter_char="5";
                3: parameter_char="7";
                5: parameter_char="2";
                default: parameter_char="0";
            endcase
            14: parameter_char=(contrast_q2==3 || contrast_q2==5) ? "5" : "0";
            15: parameter_char="%";
            default: parameter_char=" ";
        endcase
    end
endfunction

function [4:0] font5x7;
    input [7:0] ch;
    input [2:0] row;
    begin
        font5x7 = 5'b00000;
        case (ch)
            "B": case (row)
                0: font5x7=5'b11110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b11110; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b11110; default: font5x7=0; endcase
            "R": case (row)
                0: font5x7=5'b11110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b11110; 4: font5x7=5'b10100; 5: font5x7=5'b10010;
                6: font5x7=5'b10001; default: font5x7=0; endcase
            "K": case (row)
                0: font5x7=5'b10001; 1: font5x7=5'b10010; 2: font5x7=5'b10100;
                3: font5x7=5'b11000; 4: font5x7=5'b10100; 5: font5x7=5'b10010;
                6: font5x7=5'b10001; default: font5x7=0; endcase
            "+": case (row)
                1,2,4,5: font5x7=5'b00100; 3: font5x7=5'b11111;
                default: font5x7=0; endcase
            "-": if(row==3) font5x7=5'b11111;
            "%": case (row)
                0: font5x7=5'b11001; 1: font5x7=5'b11010; 2: font5x7=5'b00010;
                3: font5x7=5'b00100; 4: font5x7=5'b01000; 5: font5x7=5'b01011;
                6: font5x7=5'b10011; default: font5x7=0; endcase
            "A": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b11111; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b10001; default: font5x7=5'b00000; endcase
            "C": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b10000;
                3: font5x7=5'b10000; 4: font5x7=5'b10000; 5: font5x7=5'b10001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "D": case (row)
                0: font5x7=5'b11110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b10001; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b11110; default: font5x7=5'b00000; endcase
            "E": case (row)
                0: font5x7=5'b11111; 1: font5x7=5'b10000; 2: font5x7=5'b10000;
                3: font5x7=5'b11110; 4: font5x7=5'b10000; 5: font5x7=5'b10000;
                6: font5x7=5'b11111; default: font5x7=5'b00000; endcase
            "F": case (row)
                0: font5x7=5'b11111; 1: font5x7=5'b10000; 2: font5x7=5'b10000;
                3: font5x7=5'b11110; 4: font5x7=5'b10000; 5: font5x7=5'b10000;
                6: font5x7=5'b10000; default: font5x7=5'b00000; endcase
            "G": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b10000;
                3: font5x7=5'b10111; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "H": case (row)
                0: font5x7=5'b10001; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b11111; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b10001; default: font5x7=5'b00000; endcase
            "I": case (row)
                0: font5x7=5'b11111; 1: font5x7=5'b00100; 2: font5x7=5'b00100;
                3: font5x7=5'b00100; 4: font5x7=5'b00100; 5: font5x7=5'b00100;
                6: font5x7=5'b11111; default: font5x7=5'b00000; endcase
            "L": case (row)
                0: font5x7=5'b10000; 1: font5x7=5'b10000; 2: font5x7=5'b10000;
                3: font5x7=5'b10000; 4: font5x7=5'b10000; 5: font5x7=5'b10000;
                6: font5x7=5'b11111; default: font5x7=5'b00000; endcase
            "M": case (row)
                0: font5x7=5'b10001; 1: font5x7=5'b11011; 2: font5x7=5'b10101;
                3: font5x7=5'b10101; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b10001; default: font5x7=5'b00000; endcase
            "N": case (row)
                0: font5x7=5'b10001; 1: font5x7=5'b11001; 2: font5x7=5'b10101;
                3: font5x7=5'b10011; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b10001; default: font5x7=5'b00000; endcase
            "O": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b10001; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "P": case (row)
                0: font5x7=5'b11110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b11110; 4: font5x7=5'b10000; 5: font5x7=5'b10000;
                6: font5x7=5'b10000; default: font5x7=5'b00000; endcase
            "T": case (row)
                0: font5x7=5'b11111; 1: font5x7=5'b00100; 2: font5x7=5'b00100;
                3: font5x7=5'b00100; 4: font5x7=5'b00100; 5: font5x7=5'b00100;
                6: font5x7=5'b00100; default: font5x7=5'b00000; endcase
            "U": case (row)
                0: font5x7=5'b10001; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b10001; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "0": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b10011;
                3: font5x7=5'b10101; 4: font5x7=5'b11001; 5: font5x7=5'b10001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "1": case (row)
                0: font5x7=5'b00100; 1: font5x7=5'b01100; 2: font5x7=5'b00100;
                3: font5x7=5'b00100; 4: font5x7=5'b00100; 5: font5x7=5'b00100;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "2": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b00001;
                3: font5x7=5'b00010; 4: font5x7=5'b00100; 5: font5x7=5'b01000;
                6: font5x7=5'b11111; default: font5x7=5'b00000; endcase
            "3": case (row)
                0: font5x7=5'b11110; 1: font5x7=5'b00001; 2: font5x7=5'b00001;
                3: font5x7=5'b01110; 4: font5x7=5'b00001; 5: font5x7=5'b00001;
                6: font5x7=5'b11110; default: font5x7=5'b00000; endcase
            "4": case (row)
                0: font5x7=5'b00010; 1: font5x7=5'b00110; 2: font5x7=5'b01010;
                3: font5x7=5'b10010; 4: font5x7=5'b11111; 5: font5x7=5'b00010;
                6: font5x7=5'b00010; default: font5x7=5'b00000; endcase
            "5": case (row)
                0: font5x7=5'b11111; 1: font5x7=5'b10000; 2: font5x7=5'b10000;
                3: font5x7=5'b11110; 4: font5x7=5'b00001; 5: font5x7=5'b00001;
                6: font5x7=5'b11110; default: font5x7=5'b00000; endcase
            "6": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10000; 2: font5x7=5'b10000;
                3: font5x7=5'b11110; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "7": case (row)
                0: font5x7=5'b11111; 1: font5x7=5'b00001; 2: font5x7=5'b00010;
                3: font5x7=5'b00100; 4: font5x7=5'b01000; 5: font5x7=5'b01000;
                6: font5x7=5'b01000; default: font5x7=5'b00000; endcase
            "8": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b01110; 4: font5x7=5'b10001; 5: font5x7=5'b10001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            "9": case (row)
                0: font5x7=5'b01110; 1: font5x7=5'b10001; 2: font5x7=5'b10001;
                3: font5x7=5'b01111; 4: font5x7=5'b00001; 5: font5x7=5'b00001;
                6: font5x7=5'b01110; default: font5x7=5'b00000; endcase
            ":": case (row)
                1: font5x7=5'b00100; 2: font5x7=5'b00100;
                4: font5x7=5'b00100; 5: font5x7=5'b00100;
                default: font5x7=5'b00000; endcase
            default: font5x7 = 5'b00000;
        endcase
    end
endfunction

function [7:0] alpha_mix_channel;
    input [7:0] background;
    input [7:0] foreground;
    input [4:0] alpha;
    reg [12:0] mixed;
    begin
        mixed = background * (5'd16 - alpha) + foreground * alpha;
        alpha_mix_channel = mixed[11:4];
    end
endfunction

function [23:0] alpha_mix_rgb;
    input [23:0] background;
    input [23:0] foreground;
    input [4:0] alpha;
    begin
        alpha_mix_rgb = {
            alpha_mix_channel(background[23:16], foreground[23:16], alpha),
            alpha_mix_channel(background[15:8],  foreground[15:8],  alpha),
            alpha_mix_channel(background[7:0],   foreground[7:0],   alpha)
        };
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        x    <= 10'd0;
        y    <= 10'd0;
        de_d <= 1'b0;
        vs_d <= 1'b0;
    end else begin
        de_d <= de;
        vs_d <= vs;

        if (de)
            x <= x + 10'd1;
        else
            x <= 10'd0;

        if (!vs)
            y <= 10'd0;
        else if (de_d && !de)
            y <= y + 10'd1;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        second_count <= 25'd0;
        hours        <= 5'd0;
        minutes      <= 6'd0;
        seconds      <= 6'd0;
    end else if (second_count >= PIXEL_CLK_HZ - 1) begin
        second_count <= 25'd0;
        if (seconds == 6'd59) begin
            seconds <= 6'd0;
            if (minutes == 6'd59) begin
                minutes <= 6'd0;
                if (hours == 5'd23)
                    hours <= 5'd0;
                else
                    hours <= hours + 5'd1;
            end else begin
                minutes <= minutes + 6'd1;
            end
        end else begin
            seconds <= seconds + 6'd1;
        end
    end else begin
        second_count <= second_count + 25'd1;
    end
end


always @* begin
    rgb_out        = 24'h000000;
    glyph_char     = " ";
    glyph_row_bits = 5'b00000;
    glyph_index    = 5'd0;
    glyph_col      = 4'd0;
    glyph_row      = 4'd0;
    panel_color    = 24'd0;
    panel_alpha    = 5'd0;
    text_color     = 24'hFFFFFF;
    if(de) begin
        // Select one background, then use one shared Alpha mixer.
        if(x>=420 && x<622 && y>=14 && y<50) begin
            panel_color=24'h101820; panel_alpha=10;
        end else if(x>=18 && x<338 && y>=62 && y<92) begin
            panel_color=(active_control==3) ? 24'h095A32 : 24'h101820;
            panel_alpha=11;
        end

        if(x>=432 && x<588 && y>=25 && y<39) begin
            glyph_index=(x-10'd432)/12;
            glyph_col=((x-10'd432)%12)/2;
            glyph_row=(y-10'd25)/2;
            glyph_char=time_char(glyph_index);
            text_color=24'hFFE66D;
        end else if(x>=24 && x<280 && y>=70 && y<84) begin
            glyph_index=(x-10'd24)>>4;
            glyph_col=((x-10'd24)&10'd15)>>1;
            glyph_row=(y-10'd70)>>1;
            glyph_char=parameter_char(glyph_index);
            if((active_control==1 && glyph_index<7) ||
               (active_control==2 && glyph_index>=8))
                text_color=24'hFFE66D;
        end
        glyph_row_bits=font5x7(glyph_char,glyph_row[2:0]);
        rgb_out=alpha_mix_rgb(rgb_in,panel_color,panel_alpha);
        if(glyph_col<5 && glyph_row<7 && glyph_row_bits[4-glyph_col])
            rgb_out=text_color;
        // Preserve native white/red/navy contrast, especially on the dark
        // voice page. Old blue text panel outside this badge is transparent.
        if(x>=18 && x<74 && y>=14 && y<50) begin
            rgb_out=24'hFFFFFF;
            if(logo_inside && logo_red_bits[6'd47-logo_x]) rgb_out=24'hED1C24;
            else if(logo_inside && logo_blue_bits[6'd47-logo_x]) rgb_out=24'h1C2D4E;
        end
        if(footer_draw) rgb_out=footer_rgb;
    end
end
endmodule
