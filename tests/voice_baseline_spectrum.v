// Spectrum above the unchanged waveform. 128 bands, 2 pixels per channel.
// Bands [0..31]: 1 bin each, [32..63]:2, [64..95]:4, [96..127]:9.
// Thus full 0..24kHz is visible with extra resolution in the teaching range.
// Both stereo height banks swap ONLY at VS; the FFT waits for acknowledgement.
module voice_baseline_spectrum #(
    parameter integer NO_AUDIO_CYCLES=6250000
)(
    input clk,rst,hs,vs,de,
    input [23:0] rgb_in,
    input panel_visible,audio_valid,
    input spectrum_write,result_done,
    input [7:0] spectrum_address,
    input [6:0] spectrum_height,
    output reg result_ack,
    output hs_out,vs_out,de_out,
    output reg [23:0] rgb_out
);
reg [9:0] x,y;
reg de_d,vs_d,visible_frame;
wire frame_tick=vs && !vs_d;
reg write_bank,display_bank,display_valid,pending;
reg [22:0] no_audio_count;
wire stale=no_audio_count>=NO_AUDIO_CYCLES-1;
reg [6:0] left_ram[0:255],right_ram[0:255];
reg [6:0] left_q,right_q;
wire [9:0] graph_x=x-10'd64;
always @(posedge clk) begin
    left_q<=left_ram[{display_bank,graph_x[8:2]}];
    right_q<=right_ram[{display_bank,graph_x[8:2]}];
    if(spectrum_write && !rst) begin
        if(!spectrum_address[7]) left_ram[{write_bank,spectrum_address[6:0]}]<=spectrum_height;
        else right_ram[{write_bank,spectrum_address[6:0]}]<=spectrum_height;
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        x<=0; y<=0; de_d<=0; vs_d<=0; visible_frame<=0;
        write_bank<=0; display_bank<=1; display_valid<=0; pending<=0; result_ack<=0;
        no_audio_count<=NO_AUDIO_CYCLES-1;
    end else begin
        de_d<=de; vs_d<=vs; result_ack<=0;
        if(de) x<=x+10'd1; else x<=0;
        if(!vs) y<=0; else if(de_d && !de) y<=y+10'd1;
        if(audio_valid) no_audio_count<=0;
        else if(!stale) no_audio_count<=no_audio_count+23'd1;
        if(result_done) pending<=1;
        if(frame_tick) begin
            visible_frame<=panel_visible;
            if(stale && !audio_valid) display_valid<=0;
            if(pending) begin
                display_bank<=write_bank; write_bank<=~write_bank;
                display_valid<=!stale || audio_valid; pending<=0; result_ack<=1;
            end
        end
    end
end
reg [9:0] px,py;
reg [23:0] pixel_q;
reg valid_q,visible_q;
reg [1:0] hs_pipe,vs_pipe,de_pipe;
assign hs_out=hs_pipe[1];
assign vs_out=vs_pipe[1];
assign de_out=de_pipe[1];
always @(posedge clk or posedge rst) begin
    if(rst) begin
        px<=0; py<=0; pixel_q<=0; valid_q<=0; visible_q<=0;
        hs_pipe<=0; vs_pipe<=0; de_pipe<=0;
    end else begin
        px<=x; py<=y; pixel_q<=rgb_in; valid_q<=display_valid; visible_q<=visible_frame;
        hs_pipe<={hs_pipe[0],hs}; vs_pipe<={vs_pipe[0],vs}; de_pipe<={de_pipe[0],de};
    end
end
function [34:0] glyph;
    input [7:0] c;
    begin
        case(c)
            "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
            "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
            "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
            "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
            "5":glyph={5'b11111,5'b10000,5'b11110,5'b00001,5'b00001,5'b10001,5'b01110};
            "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
            "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
            "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
            "K":glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
            "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
            "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
            ".":glyph={30'd0,5'b00100};
            default:glyph=0;
        endcase
    end
endfunction
function [7:0] title_char;
    input [4:0] index;
    begin
        case(index)
            0,1:title_char="F"; 2:title_char="T";
            4:title_char="1"; 5:title_char="0"; 6:title_char="2"; 7:title_char="4";
            10:title_char="4"; 11:title_char="8"; 12:title_char="K";
            default:title_char=" ";
        endcase
    end
endfunction
function [7:0] axis_char;
    input [2:0] label_index;
    input [2:0] index;
    begin
        axis_char=" ";
        case(label_index)
            0: if(index==0) axis_char="0";
            1,2: case(index)
                0:axis_char=label_index==1 ? "1" : "4";
                1:axis_char="."; 2:axis_char="5"; 3:axis_char="K";
            endcase
            3: case(index)
                0:axis_char="1"; 1:axis_char="0"; 2:axis_char="."; 3:axis_char="5"; 4:axis_char="K";
            endcase
            4:case(index)
                0:axis_char="2"; 1:axis_char="4"; 2:axis_char="K";
            endcase
        endcase
    end
endfunction
reg [23:0] composed,text_color;
reg [34:0] text_bits;
reg [9:0] tx,ty,gx;
reg [2:0] label_index;
reg text_enable;
reg [6:0] bar_height;
always @* begin
    composed=pixel_q; text_bits=0; text_enable=0; tx=0; ty=0;
    text_color=24'hC8DDE8; label_index=0; gx=px-10'd64;
    bar_height=gx[1] ? right_q : left_q;
    if(visible_q && px>=48 && px<592 && py>=120 && py<236) begin
        composed={2'b0,pixel_q[23:18],2'b0,pixel_q[15:10],2'b0,pixel_q[7:2]};
        if(px==48 || px==591 || py==120 || py==235) composed=24'h60849A;
        if(px>=64 && px<576 && py>=148 && py<=214) begin
            if(px==64 || px==192 || px==320 || px==448 || px==575 || py==148 || py==170 || py==192 || py==214)
                composed=24'h294052;
            if(valid_q && bar_height!=0 && py>214-{3'd0,bar_height})
                composed=gx[1] ? 24'hFFE66D : 24'h52E3FF;
        end
        if(py>=130 && py<137) begin
            ty=py-10'd130;
            if(px>=64 && px<256) begin
                tx=px-10'd64; text_enable=1;
                text_bits=glyph(title_char(tx[7:3]));
            end else if(px>=488 && px<496) begin
                tx=px-10'd488; text_enable=1; text_bits=glyph("L"); text_color=24'h52E3FF;
            end else if(px>=536 && px<544) begin
                tx=px-10'd536; text_enable=1; text_bits=glyph("R"); text_color=24'hFFE66D;
            end
        end
        if(py>=222 && py<229) begin
            ty=py-10'd222;
            if(px>=64 && px<72) begin tx=px-10'd64; label_index=0; text_enable=1; end
            else if(px>=176 && px<208) begin tx=px-10'd176; label_index=1; text_enable=1; end
            else if(px>=304 && px<336) begin tx=px-10'd304; label_index=2; text_enable=1; end
            else if(px>=432 && px<472) begin tx=px-10'd432; label_index=3; text_enable=1; end
            else if(px>=552 && px<576) begin tx=px-10'd552; label_index=4; text_enable=1; end
            if(text_enable) text_bits=glyph(axis_char(label_index,tx[5:3]));
        end
        if(text_enable && tx[2:0]<5 && text_bits[34-(ty*5+tx[2:0])]) composed=text_color;
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) rgb_out<=0;
    else rgb_out<=de_pipe[0] ? composed : 24'd0;
end
endmodule

