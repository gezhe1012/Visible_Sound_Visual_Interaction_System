// Four SDRAM-resident photographs, one memory read per output pixel.
// Foreground assets contain an offline-bilinear 512x384 card in a 640x480
// canvas. Keep four consecutive, aligned addresses inside EVERY BL4 group;
// the existing vendor controller does not accept arbitrary per-word addresses.
// Geometry is stable for a frame and captured during the existing FIFO reset.
module nature_intro_address(
    input clk,rst,frame_clear,enabled,
    input [1:0] photo_async,
    input [5:0] slide_async,
    input request,
    output reg mapped_request,
    output reg [20:0] address
);
reg [1:0] p0,p1,p;
reg [5:0] s0,s1,s;
reg [9:0] x,y;
reg signed [11:0] left1,top1,left2,top2,left3,top3;
reg signed [11:0] sx,sy,lx,ly;
reg [1:0] owner;
reg [10:0] source_x,source_y;
reg valid0,valid1;
reg [20:0] row_address;
reg [10:0] source_x_q;
reg [1:0] owner_q;
reg [20:0] base_q;
reg [20:0] pixel_q;
always @* begin
    // Cards enter from left, right and above; settled layers remain visible.
    left1=24;top1=24;left2=104;top2=40;left3=64;top3=8;
    if(p==1) left1=-12'sd512+$signed({1'b0,s,4'd0})+$signed(({6'd0,s}*12'd3)>>2);
    if(p==2) left2=12'sd640-$signed({1'b0,s,4'd0})-$signed(({6'd0,s}*12'd3)>>2);
    if(p==3) top3=-12'sd384+$signed({2'd0,s,3'd0})+$signed({3'd0,s,2'd0})+$signed({6'd0,s[5:2]});
    left1={left1[11:2],2'b00};left2={left2[11:2],2'b00};
    sx=$signed({2'd0,x});sy=$signed({2'd0,y});lx=sx;ly=sy;owner=0;
    if(p>=1 && sx>=left1 && sx<left1+512 && sy>=top1 && sy<top1+384) begin
        lx=sx-left1;ly=sy-top1;owner=1;
    end
    if(p>=2 && sx>=left2 && sx<left2+512 && sy>=top2 && sy<top2+384) begin
        lx=sx-left2;ly=sy-top2;owner=2;
    end
    if(p>=3 && sx>=left3 && sx<left3+512 && sy>=top3 && sy<top3+384) begin
        lx=sx-left3;ly=sy-top3;owner=3;
    end
    source_x=lx[10:0];source_y=ly[10:0];
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        p0<=0;p1<=0;p<=0;s0<=32;s1<=32;s<=32;x<=0;y<=0;
        valid0<=0;valid1<=0;mapped_request<=0;row_address<=0;source_x_q<=0;owner_q<=0;base_q<=0;pixel_q<=0;address<=0;
    end else begin
        p0<=photo_async;p1<=p0;s0<=slide_async;s1<=s0;
        if(frame_clear) begin x<=0;y<=0;p<=p1;s<=s1;end
        else if(request) begin
            if(x==639) begin x<=0;y<=y==479 ? 0 : y+1'b1;end
            else x<=x+1'b1;
        end
        valid0<=request && enabled;valid1<=valid0;mapped_request<=valid1;
        row_address<=({10'd0,source_y}<<9)+({10'd0,source_y}<<7);
        source_x_q<=source_x;owner_q<=owner;
        case(owner_q)
            0:base_q<=0;1:base_q<=307200;2:base_q<=614400;3:base_q<=921600;
        endcase
        // owner base selection is split from the row calculation for 40 MHz.
        pixel_q<=row_address+source_x_q;
        address<=pixel_q+base_q;
        // Three registered stages; request alignment includes all three.
    end
end
endmodule
