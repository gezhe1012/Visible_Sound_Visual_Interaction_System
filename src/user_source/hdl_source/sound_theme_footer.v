// Bottom-only theme ticker: x=8..631, y=430..463; no RGB/timing registers.
// Same video domain as decoded PCM. Stereo peak/envelope and bars update at VS.
// Horizontal glyph cursor uses counters, NOT per-pixel division or new DSPs.
module sound_theme_footer(
    input clk,rst,vs,de,
    input [9:0] x,y,
    input [2:0] lesson_idx,
    input audio_valid,
    input [23:0] audio_left,audio_right,
    output reg draw,
    output reg [23:0] rgb
);
reg vs_d;
wire frame_tick=vs && !vs_d;
reg [2:0] caption_page;
reg [6:0] scroll_char,cursor_char;
reg [3:0] scroll_pixel,cursor_pixel;
reg [23:0] peak_left,peak_right;
reg [12:0] envelope_left,envelope_right;
reg [4:0] bars_left[0:6],bars_right[0:6];
reg [2:0] motion_phase,motion_div;
wire [23:0] abs_left=audio_left[23] ? (~audio_left+24'd1) : audio_left;
wire [23:0] abs_right=audio_right[23] ? (~audio_right+24'd1) : audio_right;
wire [23:0] peak_left_next=(audio_valid && abs_left>peak_left) ? abs_left : peak_left;
wire [23:0] peak_right_next=(audio_valid && abs_right>peak_right) ? abs_right : peak_right;
function [5:0] caption_length;
    input [2:0] page;
    begin case(page)
        0:caption_length=27; 1:caption_length=24; 2:caption_length=28;
        3:caption_length=20; 4:caption_length=23; 5:caption_length=26; default:caption_length=27;
    endcase end
endfunction
function [4:0] accent_start;
    input [2:0] page;
    begin case(page)
        1,3:accent_start=15; 2,5:accent_start=19; default:accent_start=18;
    endcase end
endfunction
function [7:0] voice_caption;
    input [4:0] index;
    reg [207:0] word;
    begin word="YOUR VOICE BECOMES VISIBLE";voice_caption=word[207-index*8-:8];end
endfunction
function [7:0] caption_char;
    input [2:0] page;
    input [4:0] index;
    begin
        caption_char=" ";
        case(page)
            3'd5: caption_char=voice_caption(index);
            3'd0: case(index)
                5'd0: caption_char="E";
                5'd1: caption_char="X";
                5'd2: caption_char="P";
                5'd3: caption_char="L";
                5'd4: caption_char="O";
                5'd5: caption_char="R";
                5'd6: caption_char="E";
                5'd8: caption_char="P";
                5'd9: caption_char="I";
                5'd10: caption_char="T";
                5'd11: caption_char="C";
                5'd12: caption_char="H";
                5'd14: caption_char="A";
                5'd15: caption_char="N";
                5'd16: caption_char="D";
                5'd18: caption_char="F";
                5'd19: caption_char="R";
                5'd20: caption_char="E";
                5'd21: caption_char="Q";
                5'd22: caption_char="U";
                5'd23: caption_char="E";
                5'd24: caption_char="N";
                5'd25: caption_char="C";
                5'd26: caption_char="Y";
                default: caption_char=" ";
            endcase
            3'd1: case(index)
                5'd0: caption_char="D";
                5'd1: caption_char="I";
                5'd2: caption_char="S";
                5'd3: caption_char="C";
                5'd4: caption_char="O";
                5'd5: caption_char="V";
                5'd6: caption_char="E";
                5'd7: caption_char="R";
                5'd9: caption_char="S";
                5'd10: caption_char="O";
                5'd11: caption_char="U";
                5'd12: caption_char="N";
                5'd13: caption_char="D";
                5'd15: caption_char="A";
                5'd16: caption_char="M";
                5'd17: caption_char="P";
                5'd18: caption_char="L";
                5'd19: caption_char="I";
                5'd20: caption_char="T";
                5'd21: caption_char="U";
                5'd22: caption_char="D";
                5'd23: caption_char="E";
                default: caption_char=" ";
            endcase
            3'd2: case(index)
                5'd0: caption_char="E";
                5'd1: caption_char="X";
                5'd2: caption_char="P";
                5'd3: caption_char="L";
                5'd4: caption_char="O";
                5'd5: caption_char="R";
                5'd6: caption_char="E";
                5'd8: caption_char="T";
                5'd9: caption_char="I";
                5'd10: caption_char="M";
                5'd11: caption_char="B";
                5'd12: caption_char="R";
                5'd13: caption_char="E";
                5'd15: caption_char="A";
                5'd16: caption_char="N";
                5'd17: caption_char="D";
                5'd19: caption_char="H";
                5'd20: caption_char="A";
                5'd21: caption_char="R";
                5'd22: caption_char="M";
                5'd23: caption_char="O";
                5'd24: caption_char="N";
                5'd25: caption_char="I";
                5'd26: caption_char="C";
                5'd27: caption_char="S";
                default: caption_char=" ";
            endcase
            3'd3: case(index)
                5'd0: caption_char="E";
                5'd1: caption_char="X";
                5'd2: caption_char="P";
                5'd3: caption_char="L";
                5'd4: caption_char="O";
                5'd5: caption_char="R";
                5'd6: caption_char="E";
                5'd8: caption_char="S";
                5'd9: caption_char="T";
                5'd10: caption_char="E";
                5'd11: caption_char="R";
                5'd12: caption_char="E";
                5'd13: caption_char="O";
                5'd15: caption_char="S";
                5'd16: caption_char="O";
                5'd17: caption_char="U";
                5'd18: caption_char="N";
                5'd19: caption_char="D";
                default: caption_char=" ";
            endcase
            3'd4: case(index)
                5'd0: caption_char="F";
                5'd1: caption_char="R";
                5'd2: caption_char="O";
                5'd3: caption_char="M";
                5'd5: caption_char="W";
                5'd6: caption_char="A";
                5'd7: caption_char="V";
                5'd8: caption_char="E";
                5'd9: caption_char="F";
                5'd10: caption_char="O";
                5'd11: caption_char="R";
                5'd12: caption_char="M";
                5'd13: caption_char="S";
                5'd15: caption_char="T";
                5'd16: caption_char="O";
                5'd18: caption_char="M";
                5'd19: caption_char="U";
                5'd20: caption_char="S";
                5'd21: caption_char="I";
                5'd22: caption_char="C";
                default: caption_char=" ";
            endcase
            default: caption_char=" ";
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
            "Q": case(row)
                0: font5x7=5'b01110;
                1: font5x7=5'b10001;
                2: font5x7=5'b10001;
                3: font5x7=5'b10001;
                4: font5x7=5'b10101;
                5: font5x7=5'b10010;
                6: font5x7=5'b01101;
                default: font5x7=0; endcase
            "S": case(row)
                0: font5x7=5'b01111;
                1: font5x7=5'b10000;
                2: font5x7=5'b10000;
                3: font5x7=5'b01110;
                4: font5x7=5'b00001;
                5: font5x7=5'b00001;
                6: font5x7=5'b11110;
                default: font5x7=0; endcase
            "V": case(row)
                0: font5x7=5'b10001;
                1: font5x7=5'b10001;
                2: font5x7=5'b10001;
                3: font5x7=5'b10001;
                4: font5x7=5'b01010;
                5: font5x7=5'b01010;
                6: font5x7=5'b00100;
                default: font5x7=0; endcase
            "W": case(row)
                0: font5x7=5'b10001;
                1: font5x7=5'b10001;
                2: font5x7=5'b10001;
                3: font5x7=5'b10101;
                4: font5x7=5'b10101;
                5: font5x7=5'b11011;
                6: font5x7=5'b10001;
                default: font5x7=0; endcase
            "X": case(row)
                0: font5x7=5'b10001;
                1: font5x7=5'b10001;
                2: font5x7=5'b01010;
                3: font5x7=5'b00100;
                4: font5x7=5'b01010;
                5: font5x7=5'b10001;
                6: font5x7=5'b10001;
                default: font5x7=0; endcase
            "Y": case(row)
                0: font5x7=5'b10001;
                1: font5x7=5'b10001;
                2: font5x7=5'b01010;
                3: font5x7=5'b00100;
                4: font5x7=5'b00100;
                5: font5x7=5'b00100;
                6: font5x7=5'b00100;
                default: font5x7=0; endcase
            default: font5x7 = 5'b00000;
        endcase
    end
endfunction
function [23:0] footer_color;
    input [4:0] alpha;
    input gold;
    begin
        case({gold,alpha})
            6'd0: footer_color=24'h0f1e30;
            6'd1: footer_color=24'h122939;
            6'd2: footer_color=24'h163543;
            6'd3: footer_color=24'h1a414d;
            6'd4: footer_color=24'h1e4d57;
            6'd5: footer_color=24'h225961;
            6'd6: footer_color=24'h26646b;
            6'd7: footer_color=24'h2a7075;
            6'd8: footer_color=24'h2e7c7f;
            6'd9: footer_color=24'h318889;
            6'd10: footer_color=24'h359493;
            6'd11: footer_color=24'h399f9d;
            6'd12: footer_color=24'h3daba7;
            6'd13: footer_color=24'h41b7b1;
            6'd14: footer_color=24'h45c3bb;
            6'd15: footer_color=24'h49cfc5;
            6'd16: footer_color=24'h4ddbcf;
            6'd32: footer_color=24'h0f1e30;
            6'd33: footer_color=24'h1c2835;
            6'd34: footer_color=24'h2a333a;
            6'd35: footer_color=24'h383d3f;
            6'd36: footer_color=24'h464844;
            6'd37: footer_color=24'h545349;
            6'd38: footer_color=24'h625d4f;
            6'd39: footer_color=24'h706854;
            6'd40: footer_color=24'h7e7359;
            6'd41: footer_color=24'h8c7d5e;
            6'd42: footer_color=24'h9a8863;
            6'd43: footer_color=24'ha89269;
            6'd44: footer_color=24'hb69d6e;
            6'd45: footer_color=24'hc4a873;
            6'd46: footer_color=24'hd2b278;
            6'd47: footer_color=24'he0bd7d;
            6'd48: footer_color=24'heec883;
            default: footer_color=24'h0F1E30;
        endcase
    end
endfunction

function [12:0] peak_target;
    input [23:0] peak;
    begin peak_target=(peak>=24'h1F0000) ? 13'd7936 : peak[20:8]; end
endfunction
function [12:0] follow_envelope;
    input [12:0] old_value,target;
    begin
        if(target>old_value) follow_envelope=old_value+((target-old_value+13'd3)>>2);
        else follow_envelope=old_value-((old_value-target+13'd15)>>4);
    end
endfunction
function [4:0] bar_target;
    input [4:0] level;
    input [2:0] shape;
    begin
        case(shape)
            0,4:bar_target=5'd3+(level>>2);
            1,6:bar_target=5'd3+(level>>1);
            2,5:bar_target=5'd3+(level>>1)+(level>>2);
            default:bar_target=5'd3+(level>>1)+(level>>3);
        endcase
    end
endfunction
function [4:0] approach;
    input [4:0] old_value,target;
    begin
        if(target>old_value) approach=old_value+5'd1;
        else if(target<old_value) approach=old_value-5'd1;
        else approach=old_value;
    end
endfunction
wire [12:0] next_envelope_left=follow_envelope(envelope_left,peak_target(peak_left_next));
wire [12:0] next_envelope_right=follow_envelope(envelope_right,peak_target(peak_right_next));
integer i;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        vs_d<=0; caption_page<=0; scroll_char<=0; scroll_pixel<=0;
        cursor_char<=0; cursor_pixel<=0;
        peak_left<=0; peak_right<=0; envelope_left<=0; envelope_right<=0;
        motion_phase<=0; motion_div<=0;
        for(i=0;i<7;i=i+1) begin bars_left[i]<=3; bars_right[i]<=3; end
    end else begin
        vs_d<=vs;
        peak_left<=peak_left_next; peak_right<=peak_right_next;
        if(frame_tick) begin
            peak_left<=0; peak_right<=0;
            envelope_left<=next_envelope_left; envelope_right<=next_envelope_right;
            motion_div<=motion_div+3'd1;
            if(motion_div==7) motion_phase<=motion_phase+3'd1;
            for(i=0;i<7;i=i+1) begin
                bars_left[i]<=approach(bars_left[i],bar_target(next_envelope_left[12:8],motion_phase+i[2:0]));
                bars_right[i]<=approach(bars_right[i],bar_target(next_envelope_right[12:8],motion_phase+3'd6-i[2:0]));
            end
            if(lesson_idx!=caption_page) begin
                caption_page<=(lesson_idx<=5) ? lesson_idx : 3'd0;
                scroll_char<=0; scroll_pixel<=0;
            end else if(scroll_pixel==11) begin
                scroll_pixel<=0;
                if(scroll_char==7'd38+caption_length(caption_page)-1) scroll_char<=0;
                else scroll_char<=scroll_char+7'd1;
            end else scroll_pixel<=scroll_pixel+4'd1;
        end
        // x=91 preloads the cursor for the very first clipped pixel x=92.
        if(de && x==91) begin cursor_char<=scroll_char; cursor_pixel<=scroll_pixel; end
        else if(de && x>=92 && x<548) begin
            if(cursor_pixel==11) begin cursor_pixel<=0; cursor_char<=cursor_char+7'd1; end
            else cursor_pixel<=cursor_pixel+4'd1;
        end
    end
end
reg [4:0] corner_distance;
reg [3:0] corner_cut;
reg [9:0] side_x,edge_distance;
reg [2:0] bar_index,bar_column;
reg [4:0] height,edge_alpha,breath_alpha,alpha;
reg [6:0] text_index;
reg [4:0] font_bits;
reg [3:0] font_row,font_column;
reg is_right,gold;
reg [12:0] env;
always @* begin
    draw=0; rgb=24'h0F1E30;
    corner_distance=0; corner_cut=0; side_x=0; edge_distance=0;
    bar_index=0; bar_column=0; height=0; edge_alpha=16; breath_alpha=9; alpha=0;
    text_index=cursor_char-7'd38; font_bits=0; font_row=(y-10'd440)>>1;
    font_column={1'b0,cursor_pixel[3:1]}; is_right=0; gold=0; env=0;
    if(de && y>=430 && y<464 && x>=8 && x<632) begin
        corner_distance=(y<447) ? y-10'd430 : 10'd463-y;
        case(corner_distance)
            0:corner_cut=8; 1:corner_cut=4; 2,3:corner_cut=2;
            4,5:corner_cut=1; default:corner_cut=0;
        endcase
        draw=(x>=10'd8+corner_cut && x<10'd632-corner_cut);
        if((x>=22 && x<78) || (x>=566 && x<622)) begin
            is_right=x>=566; side_x=is_right ? x-10'd566 : x-10'd22;
            bar_index=side_x[5:3]; bar_column=side_x[2:0];
            if(bar_index<7) begin
                height=is_right ? bars_right[bar_index] : bars_left[bar_index];
                env=is_right ? envelope_right : envelope_left;
                breath_alpha=5'd9+{2'b0,env[12:10]};
                if(bar_column<4 && y<=458 && y>10'd458-height &&
                   ((y!=458 && y!=10'd459-height) || (bar_column!=0 && bar_column!=3))) begin
                    gold=(bar_index==0 || bar_index==3 || bar_index==6);
                    rgb=footer_color(breath_alpha,gold);
                end
            end
        end
        if(x>=92 && x<548 && y>=440 && y<454 &&
           cursor_char>=38 && text_index<caption_length(caption_page)) begin
            edge_distance=(x<320) ? x-10'd92 : 10'd547-x;
            edge_alpha=(edge_distance>=32) ? 5'd16 : edge_distance[5:1];
            env=(envelope_left>envelope_right) ? envelope_left : envelope_right;
            breath_alpha=5'd9+{2'b0,env[12:10]};
            alpha=(edge_alpha<breath_alpha) ? edge_alpha : breath_alpha;
            font_bits=font5x7(caption_char(caption_page,text_index[4:0]),font_row[2:0]);
            gold=text_index>=accent_start(caption_page);
            if(font_column<5 && font_bits[4-font_column]) rgb=footer_color(alpha,gold);
        end
    end
end
endmodule
