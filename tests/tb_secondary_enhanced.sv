`timescale 1ns/1ps
module tb_secondary_enhanced;
reg clk=0,rst=1,frame_tick=0,scene_clear=0,audio_stale=0,lesson_valid=1;
always #20 clk=~clk;
reg [2:0] lesson=2;
reg capture_start=0,bin_valid=0,bin_channel=0,analysis_ready=0;
reg [8:0] bin_number=0;
reg [16:0] bin_magnitude=0;
reg [79:0] shown_feature=0,analysis_feature=0;
wire [29:0] harmonic_heights;
wire harmonic_valid;
secondary_harmonics harmonics(.*);
reg audio_valid=0;
reg [23:0] audio_left=0,audio_right=0;
reg [11:0] xy_read_address=0;
wire xy_q,xy_visible;
secondary_lissajous xy(.*);
reg expected[0:4095];
integer targets[0:4],amplitudes[0:4];
integer i,j,k,case_no,checks=0,bar_checks=0,expected_height,px,py,l,r;
integer latency;
reg [29:0] previous_bars;
real phase;
always @(posedge clk) if(!rst && lesson==3 && xy_visible && (xy.state==0 || (xy.state==1 && audio_valid)))
    if(xy.write_bank===xy.front_bank) $fatal(1,"XY writing displayed plane");
task frame;
    @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;repeat(2) @(negedge clk);
endtask
task clear_scene;
    @(negedge clk);frame_tick=1;scene_clear=1;@(negedge clk);frame_tick=0;scene_clear=0;repeat(2) @(negedge clk);
endtask
task harmonic_frame(input integer hz,input integer current_hz,input integer sounding);
    previous_bars=harmonic_heights;
    shown_feature=0;shown_feature[79]=1;shown_feature[78:64]=15'(hz);
    analysis_feature=shown_feature;analysis_feature[78:64]=15'(current_hz);
    for(j=0;j<5;j=j+1) targets[j]=(current_hz*8*(j+1)+187)/375;
    @(negedge clk);capture_start=1;@(negedge clk);capture_start=0;
    repeat(40) @(negedge clk);
    for(i=0;i<512;i=i+1) begin
        @(negedge clk);bin_valid=1;bin_number=9'(i);bin_magnitude=i==400 ? 25000 : 0;
        for(j=0;j<5;j=j+1) if(i==targets[j]) bin_magnitude=sounding ? 17'(amplitudes[j]) : 0;
        @(negedge clk);bin_valid=0;
    end
    @(negedge clk);analysis_ready=1;@(negedge clk);analysis_ready=0;
    latency=0;while(!harmonics.pending) begin @(negedge clk);latency=latency+1;if(latency>650) $fatal(1,"Harmonic serial postprocessing latency");end
    repeat(2) @(negedge clk);
    if(harmonic_heights!==previous_bars) $fatal(1,"Harmonic bars published before frame");
    frame();
    if(harmonic_valid!==(sounding && current_hz>=100 && current_hz<=1000)) $fatal(1,"Harmonic validity/range guard");
    for(j=0;j<5;j=j+1) begin
        expected_height=harmonic_valid ? amplitudes[j]*38/amplitudes[0] : 0;
        if(expected_height>38) expected_height=38;
        if(harmonic_heights[j*6+:6]!==6'(expected_height)) $fatal(1,"Harmonic ratio/target mismatch h%0d",j+1);
        bar_checks=bar_checks+1;
    end
endtask
initial begin
    amplitudes[0]=4000;amplitudes[1]=40;amplitudes[2]=1200;amplitudes[3]=0;amplitudes[4]=720;
    repeat(5) @(negedge clk);rst=0;
    harmonic_frame(438,438,1);harmonic_frame(294,296,1);harmonic_frame(659,660,1);
    harmonic_frame(438,660,1);harmonic_frame(438,438,0);harmonic_frame(90,90,1);
    amplitudes[2]=12000;harmonic_frame(438,438,1);
    harmonic_frame(1000,1000,1);harmonic_frame(1001,1001,1);
    lesson=3;clear_scene();
    for(case_no=0;case_no<7;case_no=case_no+1) begin
        wait(xy.state==1);
        for(i=0;i<4096;i=i+1) expected[i]=0;
        for(i=0;i<512;i=i+1) begin
            phase=6.283185307179586*i/512;
            l=$rtoi(30*$sin(phase));r=$rtoi(30*$sin(phase));
            case(case_no)
                0:r=0;
                1:l=0;
                3:r=-l;
                4:r=$rtoi(30*$cos(phase));
                5:begin l=$rtoi(30*$sin(2*phase));r=$rtoi(30*$sin(3*phase));end
                6:begin l=i%2 ? 127 : -128;r=i%4<2 ? 127 : -128;end
            endcase
            px=32+(l>31 ? 31 : l< -31 ? -31 : l);py=32-(r>31 ? 31 : r< -31 ? -31 : r);
            expected[py*64+px]=1;
            @(negedge clk);audio_left=24'(l*65536);audio_right=24'(r*65536);audio_valid=1;
            @(negedge clk);audio_valid=0;repeat(2) @(negedge clk);
        end
        wait(xy.state==2);frame();if(!xy_visible) $fatal(1,"Completed XY plane invisible");
        for(i=0;i<4096;i=i+1) begin
            @(negedge clk);xy_read_address=12'(i);@(negedge clk);
            if(xy_q!==expected[i]) $fatal(1,"XY paired sample/clear/map mismatch case%0d address%0d",case_no,i);
            checks=checks+1;
        end
    end
    audio_stale=1;frame();if(xy_visible) $fatal(1,"Stale XY plane visible");
    audio_stale=0;wait(xy.state==1);
    for(i=0;i<512;i=i+1) begin
        @(negedge clk);audio_valid=1;audio_left=0;audio_right=0;
        @(negedge clk);audio_valid=0;
    end
    wait(xy.state==2);frame();if(!xy_visible) $fatal(1,"XY did not recover on valid silent PCM");
    for(i=0;i<4096;i=i+1) begin
        @(negedge clk);xy_read_address=12'(i);@(negedge clk);
        if(xy_q!==(i==2080)) $fatal(1,"Silent PCM recovery retained old XY points");
        checks=checks+1;
    end
    lesson=2;clear_scene();
    if(xy_visible || harmonic_valid) $fatal(1,"Scene clear/reset residue");
    @(negedge clk);rst=1;repeat(3) @(negedge clk);
    if(xy_visible || harmonic_valid) $fatal(1,"Reset output mask");
    $display("ALL ENHANCED UNIT TESTS PASSED: %0d harmonic ratios/guards and %0d exact XY bits, L-only/R-only/same/anti/quadrature/2:3/clipping/silent recovery, bank safety/frame/clear/stale/reset, bounded serial latency",bar_checks,checks);
    $finish;
end
initial begin #50000000;$fatal(1,"Enhanced unit timeout");end
endmodule
