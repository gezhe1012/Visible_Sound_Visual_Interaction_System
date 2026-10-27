// Stage-1 HDMI_A electrical/display compatibility test, deliberately NOT a
// spectrogram or pitch tracker. Its moving cursor is explicitly a link test.
// Same documented 800x525 / 25MHz cadence as the original vendor video source.
// Continuous 640-pixel rows. Ready may only deassert during line blanking per
// APUG092; as in the original main source, it does not stretch video timing.
module secondary_link_pattern(
    input clk,rst,
    input [2:0] lesson,
    input lesson_valid,video_locked,
    output reg axis_user,axis_valid,axis_last,
    output reg [23:0] axis_data
);
reg [9:0] col,line;
reg [7:0] frame;
reg [2:0] shown_lesson;
reg shown_valid,shown_locked;
reg [23:0] composed,ink;
wire active=col>=160 && line>=45;
wire [9:0] x=col-10'd160,y=line-10'd45;
wire [9:0] cursor=10'd64+{1'b0,frame,1'b0};
always @(posedge clk or posedge rst) begin
    if(rst) begin
        col<=0;line<=0;frame<=0;shown_lesson<=0;shown_valid<=0;shown_locked<=0;
        axis_user<=0;axis_valid<=0;axis_last<=0;axis_data<=0;
    end else begin
        if(col==799) begin
            col<=0;
            if(line==524) begin line<=0;frame<=frame+8'd1;end
            else line<=line+10'd1;
        end else col<=col+10'd1;
        if(col==0 && line==0) begin
            shown_lesson<=lesson;shown_valid<=lesson_valid;shown_locked<=video_locked;
        end
        axis_valid<=active;
        axis_user<=col==160 && line==45;
        axis_last<=active && col==799;
        axis_data<=active ? composed : 24'd0;
    end
end
function [34:0] glyph;
    input [7:0] c;
    begin
        case(c)
            "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
            "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
            "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
            "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
            "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
            "5":glyph=35'b11111_10000_11110_00001_00001_10001_01110;
            "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
            "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
            "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
            "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
            "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
            "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
            "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
            "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
            "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
            "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
            "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
            "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
            "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
            "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
            "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
            "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
            "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
            "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
            "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
            "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
            "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
            "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
            "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
            "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
            "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
            "Z":glyph=35'b11111_00001_00010_00100_01000_10000_11111;
            ".":glyph=35'b00000_00000_00000_00000_00000_00110_00110;
            "/":glyph=35'b00001_00010_00010_00100_01000_01000_10000;
            default:glyph=0;
        endcase
    end
endfunction
function [7:0] character;
    input [175:0] text;
    input [4:0] index;
    begin character=index<22 ? text[175-index*8-:8] : " ";end
endfunction
reg [34:0] bits;
reg [9:0] tx,ty,bar_x;
reg [7:0] ch;
reg text_on,font2x;
always @* begin
    composed=24'h071622;ink=24'hD7E5EF;bits=0;tx=0;ty=0;bar_x=x-64;
    ch=" ";text_on=0;font2x=0;
    // Rounded cards, restrained teal/gold palette, no full-screen framebuffer.
    if(x>=24 && x<616 && y>=96 && y<356 &&
        ((x>=32 && x<608) || (y>=104 && y<348))) composed=24'h102A3B;
    if(x>=24 && x<616 && y>=380 && y<444 &&
        ((x>=32 && x<608) || (y>=388 && y<436))) composed=24'h102A3B;
    if(y==72 && x>=24 && x<616) composed=24'h294858;
    if(x>=64 && x<576 && y>=160 && y<288) begin
        case(bar_x[8:6])
            0:composed=24'hE4F0F4;
            1:composed=24'hE9C477;
            2:composed=24'h5BDAC6;
            3:composed=24'h32AEB2;
            4:composed=24'h31778F;
            5:composed=24'h244B68;
            6:composed=24'h16364D;
            7:composed=24'h0A1B2D;
        endcase
        if(y[4:0]==0) composed={1'b0,composed[23:17],1'b0,composed[15:9],1'b0,composed[7:1]};
    end
    if(y>=336 && y<340 && x>=64 && x<576) composed=24'h294858;
    if(y>=332 && y<344 && x>=cursor && x<cursor+4 && x<576) composed=24'h5BDAC6;
    if(x>=592 && x<600 && y>=32 && y<40) composed=shown_locked ? 24'h5BDAC6 : 24'hE9C477;
    if(x>=24 && x<312 && y>=28 && y<42) begin
        tx=x-24;ty=y-28;font2x=1;text_on=1;
        ch=character("SOUND LAB             ",tx[8:4]);
    end else if(x>=480 && x<584 && y>=30 && y<37) begin
        tx=x-480;ty=y-30;text_on=1;ch=character("HDMI A                ",tx[7:3]);
    end else if(x>=48 && x<400 && y>=116 && y<130) begin
        tx=x-48;ty=y-116;font2x=1;text_on=1;
        ch=character("DISPLAY LINK TEST     ",tx[8:4]);
    end else if(x>=64 && x<240 && y>=304 && y<311) begin
        tx=x-64;ty=y-304;text_on=1;ch=character("640X480 / 59.52 HZ    ",tx[7:3]);
    end else if(x>=440 && x<576 && y>=304 && y<311) begin
        tx=x-440;ty=y-304;text_on=1;ch=character("VIDEO ONLY            ",tx[7:3]);ink=24'h91ADBD;
    end else if(x>=48 && x<392 && y>=400 && y<414) begin
        tx=x-48;ty=y-400;font2x=1;text_on=1;
        ch=character(shown_valid ? "PAGE 1                " : "WAIT                  ",tx[8:4]);
        if(shown_valid && tx[8:4]==5) ch="1"+{5'd0,shown_lesson};
        ink=24'h5BDAC6;
    end
    if(x>=504 && x<604 && y>=402 && y<410) begin
        if((x>=504 && x<512 && shown_lesson==0) || (x>=524 && x<532 && shown_lesson==1) ||
           (x>=544 && x<552 && shown_lesson==2) || (x>=564 && x<572 && shown_lesson==3) ||
           (x>=584 && x<592 && shown_lesson==4)) composed=shown_valid ? 24'hE9C477 : 24'h294858;
    end
    bits=glyph(ch);
    if(text_on) begin
        if(font2x) begin if(tx[3:0]<10 && bits[34-(ty[3:1]*5+tx[3:1])]) composed=ink;end
        else if(tx[2:0]<5 && bits[34-(ty*5+tx[2:0])]) composed=ink;
    end
end
endmodule
