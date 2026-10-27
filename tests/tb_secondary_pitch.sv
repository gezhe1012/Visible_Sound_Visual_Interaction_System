`timescale 1ns/1ps
module tb_secondary_pitch;
reg clk=0,rst=1,clear=0,bin_valid=0,bin_channel=0;
always #20 clk=~clk;
reg [8:0] bin_number=0;
reg [16:0] bin_magnitude=0;
wire [79:0] left_feature,right_feature;
wire feature_done;
secondary_pitch_estimator dut(.*);
reg [16:0] inputs[0:20479];
reg [79:0] expected[0:39];
integer n,ch,i,latency,checked=0;
task feed(input integer which,input integer channel);
    for(i=0;i<512;i=i+1) begin
        @(negedge clk);bin_valid=1;bin_channel=1'(channel);bin_number=9'(i);bin_magnitude=inputs[which*1024+channel*512+i];
        @(negedge clk);bin_valid=0;
    end
endtask
initial begin
    $readmemh("secondary_audio_pitch_input.hex",inputs);$readmemh("secondary_audio_pitch_expected.hex",expected);
    repeat(5) @(negedge clk);rst=0;
    for(n=0;n<20;n=n+1) for(ch=0;ch<2;ch=ch+1) begin
        feed(n,ch);latency=0;
        while(dut.state!=0) begin @(negedge clk);latency=latency+1;if(latency>220) $fatal(1,"Pitch postprocessing >220 cycles");end
        if((ch ? right_feature : left_feature)!==expected[n*2+ch])
            $fatal(1,"Pitch packed mismatch case%0d ch%0d got%h expected%h",n,ch,ch ? right_feature : left_feature,expected[n*2+ch]);
        if(feature_done!==1'(ch)) $fatal(1,"Feature completion must follow right channel only");
        checked=checked+1;
    end
    feed(9,0);repeat(7) @(negedge clk);clear=1;@(negedge clk);clear=0;
    if(left_feature!=0 || right_feature!=0 || feature_done) $fatal(1,"Clear did not discard partial estimate");
    $display("ALL SECONDARY PITCH TESTS PASSED: %0d complete 80-bit summaries, independent frequency/note/trace/BCD/smoothing, noise/silence/edges, latency/clear",checked);
    $finish;
end
initial begin #10000000;$fatal(1,"Pitch timeout");end
endmodule
