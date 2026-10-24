// Three-cycle RGB pipeline. Neutral brightness=0, contrast_q2=4 is bit exact.
// out = clamp(round((in-128)*contrast_q2/4)+128+brightness, 0, 255).
module video_picture_adjust(
    input clk,rst,hs,vs,de,
    input [23:0] rgb_in,
    input signed [8:0] brightness,
    input [2:0] contrast_q2,
    output hs_out,vs_out,de_out,
    output reg [23:0] rgb_out
);
reg [2:0] hs_pipe,vs_pipe,de_pipe;
reg signed [8:0] centered_r,centered_g,centered_b;
reg signed [12:0] product_r,product_g,product_b;
reg signed [8:0] brightness0,brightness1;
reg [2:0] contrast0;
wire signed [13:0] value_r=((product_r+14'sd2)>>>2)+14'sd128+brightness1;
wire signed [13:0] value_g=((product_g+14'sd2)>>>2)+14'sd128+brightness1;
wire signed [13:0] value_b=((product_b+14'sd2)>>>2)+14'sd128+brightness1;
assign hs_out=hs_pipe[2];
assign vs_out=vs_pipe[2];
assign de_out=de_pipe[2];
function [7:0] saturate;
    input signed [13:0] value;
    begin
        if(value<0) saturate=0;
        else if(value>255) saturate=255;
        else saturate=value[7:0];
    end
endfunction
always @(posedge clk or posedge rst) begin
    if(rst) begin
        hs_pipe<=0; vs_pipe<=0; de_pipe<=0;
        centered_r<=0; centered_g<=0; centered_b<=0;
        product_r<=0; product_g<=0; product_b<=0;
        brightness0<=0; brightness1<=0; contrast0<=4; rgb_out<=0;
    end else begin
        hs_pipe<={hs_pipe[1:0],hs}; vs_pipe<={vs_pipe[1:0],vs}; de_pipe<={de_pipe[1:0],de};
        centered_r<=$signed({1'b0,rgb_in[23:16]})-9'sd128;
        centered_g<=$signed({1'b0,rgb_in[15:8]})-9'sd128;
        centered_b<=$signed({1'b0,rgb_in[7:0]})-9'sd128;
        contrast0<=contrast_q2; brightness0<=brightness;
        product_r<=centered_r*$signed({1'b0,contrast0});
        product_g<=centered_g*$signed({1'b0,contrast0});
        product_b<=centered_b*$signed({1'b0,contrast0});
        brightness1<=brightness0;
        rgb_out<=de_pipe[1] ? {saturate(value_r),saturate(value_g),saturate(value_b)} : 24'd0;
    end
end
endmodule
