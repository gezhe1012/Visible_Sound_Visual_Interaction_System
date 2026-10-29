// Procedural sixth page; no sixth BMP, image load, RAM, DSP, or video latency.
// Existing OSD/logo/clock/footer and KEY3 analysis panel are composed downstream.
module live_voice_background(
    input clk,rst,vs,de,ready,active,clipped,panel_visible,
    output reg [23:0] rgb
);
reg [9:0] x,y;
reg de_d;
reg [9:0] tx,ty;
reg [7:0] character;
reg [23:0] ink;
wire [34:0] glyph;
secondary_font5x7 font(.character(character),.bits(glyph));
always @(posedge clk or posedge rst) begin
    if(rst) begin x<=0;y<=0;de_d<=0;end
    else begin
        de_d<=de;
        if(de) x<=x+10'd1;else x<=0;
        if(!vs) y<=0;else if(de_d && !de) y<=y+10'd1;
    end
end
function [7:0] char_at;
    input [255:0] word;
    input [4:0] index;
    begin char_at=word[255-index*8-:8];end
endfunction
always @* begin
    rgb=24'h102A3B;tx=0;ty=0;character=" ";ink=24'hD7E5EF;
    if(x>=24 && x<616 && y>=78 && y<418) rgb=24'h0A2030;
    if(y==116 && x>=48 && x<592) rgb=24'h294858;
    if(x>=48 && x<368 && y>=98 && y<112) begin
        tx=x-48;ty=y-98;character=char_at("LIVE VOICE                      ",tx[8:4]);ink=24'h5BDAC6;
    end else if(x>=400 && x<592 && y>=98 && y<112) begin
        tx=x-400;ty=y-98;
        character=char_at(!ready ? "WARMUP                          " : clipped ? "LIMIT                           " : active ? "VOICE                           " : "LISTEN                          ",tx[8:4]);
        ink=active ? 24'h5BDAC6 : 24'hE9C477;
    end else if(!panel_visible && x>=96 && x<544 && y>=204 && y<218) begin
        tx=x-96;ty=y-204;character=char_at("KEY3  WAVE / FFT                ",tx[8:4]);
    end else if(!panel_visible && x>=96 && x<544 && y>=246 && y<260) begin
        tx=x-96;ty=y-246;character=char_at("SPEAK AND WATCH                 ",tx[8:4]);ink=24'h91ADBD;
    end
    if(tx[3:1]<5 && ty[3:1]<7 && glyph[34-(ty[3:1]*5+tx[3:1])]) rgb=ink;
end
endmodule
