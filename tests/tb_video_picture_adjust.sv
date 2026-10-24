`timescale 1ns/1ps
module tb_video_picture_adjust;
reg clk=0,rst=1,hs=0,vs=0,de=0;
always #5 clk=~clk;
reg [23:0] rgb_in=0;
reg signed [8:0] brightness=0;
reg [2:0] contrast_q2=4;
wire hs_out,vs_out,de_out;
wire [23:0] rgb_out;
reg [23:0] expected0=0,expected1=0,expected2=0;
reg [2:0] timing0=0,timing1=0,timing2=0;
integer b,c,v,checked=0;
video_picture_adjust dut(.*);
function [7:0] channel_expected(input integer value,bri,contrast);
    integer scaled,result;
    begin
        scaled=(value-128)*contrast+2;
        // Explicit floor division, including negative intermediate values.
        result=((scaled>=0) ? scaled/4 : -((-scaled+3)/4))+128+bri;
        channel_expected=(result<0) ? 0 : ((result>255) ? 255 : result);
    end
endfunction
always @(posedge clk) begin
    if(rst) begin
        expected0=0; expected1=0; expected2=0;
        timing0=0; timing1=0; timing2=0;
    end else begin
        expected2=expected1; expected1=expected0;
        expected0=de ? {channel_expected(rgb_in[23:16],$signed(brightness),contrast_q2),
                       channel_expected(rgb_in[15:8],$signed(brightness),contrast_q2),
                       channel_expected(rgb_in[7:0],$signed(brightness),contrast_q2)} : 24'd0;
        timing2=timing1; timing1=timing0; timing0={hs,vs,de};
        #1;
        if(rgb_out!==expected2 || {hs_out,vs_out,de_out}!==timing2)
            $fatal(1,"Pipeline mismatch rgb=%h expected=%h timing=%b expected=%b",rgb_out,expected2,{hs_out,vs_out,de_out},timing2);
        checked=checked+1;
    end
end
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(b=-64;b<=64;b=b+16)
        for(c=2;c<=6;c=c+1)
            for(v=0;v<256;v=v+1) begin
                @(negedge clk);
                brightness=b; contrast_q2=c;
                rgb_in={8'(v),8'(255-v),8'((v*37)&255)};
                de=(v%7!=0); hs=(v%11<5); vs=(v%29<3);
            end
    repeat(5) @(negedge clk);
    rst=1; repeat(4) @(negedge clk);
    rst=0; brightness=0; contrast_q2=4; de=1; rgb_in=24'h0080FF;
    repeat(8) @(negedge clk);
    $display("ALL PICTURE ADJUST TESTS PASSED: 45 parameter pairs, 256 values/channel, saturation, neutral, timing, reset (%0d cycles)",checked);
    $finish;
end
initial begin #500000; $fatal(1,"Timeout"); end
endmodule
