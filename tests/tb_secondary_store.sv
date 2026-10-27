`timescale 1ns/1ps
module tb_secondary_store;
reg clk=0,rst=1,frame_tick=0,scene_clear=0;
always #20 clk=~clk;
reg [2:0] lesson=0;
reg lesson_valid=1,audio_valid=1;
reg [23:0] audio_left=24'h800000,audio_right=24'h400000;
reg capture_start=0,bin_valid=0,bin_channel=0;
reg [8:0] bin_number=0;
reg [16:0] bin_magnitude=0;
reg spectrum_write=0,result_done=0;
reg [7:0] spectrum_address=0;
reg [6:0] spectrum_height=0,read_column=0;
reg [5:0] read_band=0;
wire [3:0] heat_q;
wire [7:0] trace_q,peak_left,peak_right,average_left,average_right;
wire [6:0] shown_head,shown_count;
wire [79:0] shown_feature;
wire shown_right;
secondary_feature_store #(.NO_AUDIO_CYCLES(128)) dut(.*);
integer block_no,i,b,expected_head=0,expected_count=0,checks=0,distance;
integer lq,rq;
reg [6:0] old_head,old_count;
always @(posedge clk) if(!rst && dut.copying && shown_count>0) begin
    distance=(shown_head-dut.write_column)&127;
    if(distance>0 && distance<=shown_count) $fatal(1,"History copy touched visible columns");
end
task channel_data(input integer n,input integer ch,input integer sounding);
    for(i=0;i<512;i=i+1) begin
        @(negedge clk);bin_valid=1;bin_channel=1'(ch);bin_number=9'(i);
        bin_magnitude=!sounding ? 0 : (i==10 ? 4000 : i==9 ? 1000 : i==11 ? 1500 : 0);
        spectrum_write=i<64;spectrum_address=8'(ch*128+i);
        spectrum_height=7'((ch==0 ? i+n : 2*i+n)%67);
        @(negedge clk);bin_valid=0;spectrum_write=0;@(negedge clk);
    end
    repeat(220) @(negedge clk);
endtask
task commit_frame;
    @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;repeat(2) @(negedge clk);
endtask
task complete_block(input integer n,input integer left_on,input integer right_on);
    @(negedge clk);capture_start=1;@(negedge clk);capture_start=0;
    channel_data(n,0,left_on);
    // R completion is delayed until AFTER the original height result_done,
    // matching the actual FFT protocol. Do not let the task wait it away.
    for(i=0;i<512;i=i+1) begin
        @(negedge clk);bin_valid=1;bin_channel=1;bin_number=9'(i);
        bin_magnitude=!right_on ? 0 : (i==10 ? 4000 : i==9 ? 1000 : i==11 ? 1500 : 0);
        spectrum_write=i<64;spectrum_address=8'(128+i);spectrum_height=7'((2*i+n)%67);
        result_done=i==511;
        @(negedge clk);bin_valid=0;spectrum_write=0;result_done=0;@(negedge clk);
    end
    old_head=shown_head;old_count=shown_count;
    wait(dut.pending);@(negedge clk);
    if(shown_head!==old_head || shown_count!==old_count) $fatal(1,"History published before frame boundary");
    for(b=0;b<64;b=b+1) begin
        @(negedge clk);read_column=7'(n&127);read_band=6'(b);repeat(2) @(negedge clk);
        lq=((b+n)%67)/4;if(lq>15) lq=15;
        rq=((2*b+n)%67)/4;if(rq>15) rq=15;
        if(heat_q!==4'(lq>rq ? lq : rq)) $fatal(1,"Stereo compression/ring cell wrong n%0d b%0d",n,b);
        checks=checks+1;
    end
    commit_frame();expected_head=(expected_head+1)&127;if(expected_count<96) expected_count=expected_count+1;
    if(shown_head!==7'(expected_head) || shown_count!==7'(expected_count)) $fatal(1,"Ring head/count failed");
    if(!shown_feature[79] || shown_feature[78:64]!=471 || shown_right!==1'(!left_on && right_on)) $fatal(1,"Current pitch/channel snapshot wrong");
    if(trace_q[7:6]!=={1'b1,1'(!left_on && right_on)}) $fatal(1,"Trace valid/channel wrong");
endtask
initial begin
    repeat(5) @(negedge clk);rst=0;repeat(5) @(negedge clk);
    for(block_no=0;block_no<130;block_no=block_no+1) complete_block(block_no,1,1);
    complete_block(130,0,1);
    // Change lesson after the left FFT channel. Old right data cannot publish.
    @(negedge clk);capture_start=1;@(negedge clk);capture_start=0;channel_data(131,0,1);
    lesson=1;scene_clear=1;frame_tick=1;@(negedge clk);scene_clear=0;frame_tick=0;
    expected_head=0;expected_count=0;channel_data(131,1,1);
    result_done=1;@(negedge clk);result_done=0;repeat(300) @(negedge clk);
    if(shown_count!=0 || shown_feature!=0 || dut.pending || dut.copying) $fatal(1,"Old-page FFT leaked after scene change");
    complete_block(0,1,1);
    // Full signed negative peak and positive right channel: no abs overflow.
    repeat(1030) @(negedge clk);commit_frame();
    if({peak_left,peak_right,average_left,average_right}!==32'he070e070) $fatal(1,"Peak/mean/full-scale mapping wrong");
    audio_valid=0;repeat(140) @(negedge clk);commit_frame();
    if(shown_feature!=0 || peak_left!=0 || peak_right!=0 || average_left!=0 || average_right!=0) $fatal(1,"No-PCM timeout failed");
    rst=1;repeat(3) @(negedge clk);if(shown_count!=0 || dut.pending || dut.copying) $fatal(1,"Store reset failed");
    $display("ALL SECONDARY STORE TESTS PASSED: %0d stereo heat cells, 128-column wrap, 96-visible guard, frame publication, R-only, page-abort/recovery, peak/mean/full-negative, timeout/reset",checks);
    $finish;
end
initial begin #100000000;$fatal(1,"Store timeout");end
endmodule
