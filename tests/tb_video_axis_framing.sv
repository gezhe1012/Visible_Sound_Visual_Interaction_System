`timescale 1ns/1ps
module tb_video_axis_framing;
reg clk=0,rst=1,vs=0,de=0;
reg [23:0] rgb=0;
always #5 clk=~clk;
wire user,valid,last;
wire [23:0] data;
integer f,y,x,valid_count=0,last_count=0,user_count=0;
video_rgb_to_axis_640x480 dut(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(rgb),
    .O_video_user(user),.O_video_valid(valid),.O_video_last(last),.O_video_data(data));
task pixel(input integer px,py,pf);
    @(negedge clk); de=1; rgb={8'(pf),8'(py),8'(px)};
    @(posedge clk); #1;
    if(!valid || data!==rgb || last!==(px==639) || user!==((px==0)&&(py==0)))
        $fatal(1,"AXIS f%0d (%0d,%0d): valid%0b last%0b sof%0b data%h/%h",pf,px,py,valid,last,user,data,rgb);
    valid_count=valid_count+1; if(last) last_count=last_count+1; if(user) user_count=user_count+1;
endtask
initial begin
    repeat(4) @(negedge clk); rst=0;
    for(f=0;f<2;f=f+1) begin
        vs=0; repeat(3) @(negedge clk); vs=1; repeat(3) @(negedge clk);
        for(y=0;y<480;y=y+1) begin
            for(x=0;x<640;x=x+1) pixel(x,y,f);
            @(negedge clk); de=0;
            repeat((y%7)+2) begin
                @(posedge clk); #1;
                if(valid || last || user) $fatal(1,"Blanking emitted AXIS flag");
                @(negedge clk);
            end
        end
    end
    if(valid_count!=614400 || last_count!=960 || user_count!=2) $fatal(1,"Frame totals incorrect");
    $display("ALL AXIS FRAMING TESTS PASSED: 2 full frames, 614400 RGB pixels, 960 aligned TLAST and 2 SOF");
    $finish;
end
endmodule
