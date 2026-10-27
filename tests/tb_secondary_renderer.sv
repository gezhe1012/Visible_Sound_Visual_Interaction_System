`timescale 1ns/1ps
module tb_secondary_renderer;
reg clk=0,rst=1,lesson_valid=1,video_locked=1;
always #20 clk=~clk;
reg [2:0] lesson=0;
reg [3:0] heat_q=0;
reg [7:0] trace_q=0;
reg [6:0] shown_head=96,shown_count=96;
reg [79:0] shown_feature=0;
reg shown_right=0;
reg [29:0] harmonic_heights={6'd7,6'd0,6'd13,6'd0,6'd38};
reg harmonic_valid=1,xy_visible=1,xy_q=0;
wire [11:0] xy_read_address;
reg [7:0] peak_left=100,peak_right=60,average_left=50,average_right=30;
wire frame_tick,scene_clear;
wire [6:0] read_column;
wire [5:0] read_band;
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_data;
secondary_audio_renderer dut(.*);
wire old_user,old_valid,old_last,old_tick,old_clear;
wire [6:0] old_column;
wire [5:0] old_band;
reg [3:0] old_heat=0;
reg [7:0] old_trace=0;
wire [23:0] old_rgb;
enhanced_baseline_renderer baseline(.clk(clk),.rst(rst),.lesson(lesson),.lesson_valid(lesson_valid),.video_locked(video_locked),
    .heat_q(old_heat),.trace_q(old_trace),.shown_head(shown_head),.shown_count(shown_count),.shown_feature(shown_feature),
    .shown_right(shown_right),.peak_left(peak_left),.peak_right(peak_right),.average_left(average_left),.average_right(average_right),
    .frame_tick(old_tick),.scene_clear(old_clear),.read_column(old_column),.read_band(old_band),
    .axis_user(old_user),.axis_valid(old_valid),.axis_last(old_last),.axis_data(old_rgb));
always @(posedge clk) begin
    heat_q<=4'(read_column^read_band);
    trace_q<={1'b1,read_column[0],6'(read_column%48)};
    xy_q<=xy_read_address[5:0]==xy_read_address[11:6];
    old_heat<=4'(old_column^old_band);old_trace<={1'b1,old_column[0],6'(old_column%48)};
end
function [23:0] color(input integer n);
    case(n)
        0:color=24'h0D2637;1:color=24'h10364B;2:color=24'h12485E;3:color=24'h145A70;
        4:color=24'h176F84;5:color=24'h1B8594;6:color=24'h219BA4;7:color=24'h2AB1B0;
        8:color=24'h39C5B9;9:color=24'h55D8C4;10:color=24'h78E3CE;11:color=24'hA2E6CE;
        12:color=24'hCADFB2;13:color=24'hE5D493;14:color=24'hF0C676;15:color=24'hFFE1A0;
    endcase
endfunction
integer h=0,v=0,frames=0,xp[0:1],yp[0:1],px,py,cell_index,band,cy,prev_y;
integer pixels=0,lines=0,starts=0,heat_checks=0,trace_checks=0,level_checks=0,legacy_checks=0,xy_checks=0,harmonic_checks=0,hi;
reg [1:0] ev=0,eu=0,el=0;
reg [2:0] current_lesson;
reg [23:0] expected;
always @(posedge clk) if(!rst && (frames<5 || ev[0])) begin
    if(h==0 && v==0) current_lesson=lesson;
    xp[1]=xp[0];yp[1]=yp[0];xp[0]=h-160;yp[0]=v-45;
    ev={ev[0],h>=160 && v>=45};eu={eu[0],h==160 && v==45};el={el[0],h==799 && v>=45};
    #1;
    if({axis_valid,axis_user,axis_last}!=={ev[1],eu[1],el[1]}) $fatal(1,"Secondary renderer not exactly two clocks");
    if({axis_valid,axis_user,axis_last}!=={old_valid,old_user,old_last}) $fatal(1,"Original framing changed");
    if(dut.shown_lesson!==current_lesson) $fatal(1,"Page changed inside active raster");
    if(!axis_valid && axis_data!==0) $fatal(1,"Renderer blanking not black");
    if(axis_valid) begin
        pixels=pixels+1;if(axis_user) starts=starts+1;if(axis_last) lines=lines+1;px=xp[1];py=yp[1];
        if(!((current_lesson==2 && py>=384 && py<464) || (current_lesson==3 && py>=136 && py<376))) begin
            if(axis_data!==old_rgb) $fatal(1,"Protected page/region differs from board-verified renderer at page%0d %0d,%0d",current_lesson,px,py);
            legacy_checks=legacy_checks+1;
        end
        cell_index=(px-64)/(current_lesson==3 ? 3 : 5);
        if(px>=64 && px<(current_lesson==3 ? 352 : 544) && py>=160 && py<352) begin
            band=63-(py-160)/3;expected=24'h0A2030;
            if((px-64)%(current_lesson==3 ? 3 : 5)<(current_lesson==3 ? 2 : 4) && (py-160)%3<2) expected=color((cell_index^band)&15);
            if(axis_data!==expected) $fatal(1,"Waterfall address/RAM/RGB pipeline mismatch at %0d,%0d got%h want%h",px,py,axis_data,expected);
            heat_checks=heat_checks+1;
        end
        if((current_lesson==0 || current_lesson==4) && px>=64 && px<544 && py>=408 && py<=455) begin
            expected=24'h102A3B;
            if(py==408 || py==424 || py==440 || py==455 || (cell_index%32==0 && (px-64)%5==0)) expected=24'h244455;
            cy=455-cell_index%48;prev_y=455-(cell_index-1)%48;
            if(py==cy || ((px-64)%5==0 && cell_index!=0 && ((py>=cy && py<=prev_y) || (py>=prev_y && py<=cy))))
                expected=cell_index%2 ? 24'hE9C477 : 24'h5BDAC6;
            if(axis_data!==expected) $fatal(1,"Pitch trace RGB mismatch %0d,%0d",px,py);
            trace_checks=trace_checks+1;
        end
        if((current_lesson==1 || current_lesson==3) && ((px>=80 && px<304) || (px>=352 && px<576)) && ((py>=412 && py<424) || (py>=440 && py<448))) begin
            if(py<424) expected=(px<304 ? px-80<100 : px-352<60) ? 24'h5BDAC6 : 24'h244455;
            else expected=(px<304 ? px-80<50 : px-352<30) ? 24'hE9C477 : 24'h244455;
            if(axis_data!==expected) $fatal(1,"PCM level RGB mismatch");level_checks=level_checks+1;
        end
        if(current_lesson==3 && px>=432 && px<560 && py>=192 && py<320) begin
            expected=24'h0A2030;if(px==496 || py==256) expected=24'h294858;
            if((px-432)/2==(py-192)/2) expected=24'h5BDAC6;
            if(axis_data!==expected) $fatal(1,"XY RAM/RGB pipeline mismatch");xy_checks=xy_checks+1;
        end
        if(current_lesson==2 && px>=64 && px<544 && py>=408 && py<=448) begin
            expected=py==448 ? 24'h294858 : 24'h102A3B;
            for(hi=0;hi<5;hi=hi+1) if(px>=94+hi*96 && px<130+hi*96 && py>=448-harmonic_heights[hi*6+:6] && py<448)
                expected=hi==0 ? 24'hE9C477 : 24'h5BDAC6;
            if(axis_data!==expected) $fatal(1,"Harmonic RGB mismatch");harmonic_checks=harmonic_checks+1;
        end
    end
    if(h==799) begin h=0;if(v==524) begin v=0;frames=frames+1;end else v=v+1;end else h=h+1;
end
initial begin
    shown_feature[79]=1;shown_feature[78:64]=438;shown_feature[63:44]=20'h00438;
    shown_feature[43:40]=9;shown_feature[39:37]=4;shown_feature[36]=1;
    repeat(5) @(negedge clk);rst=0;
    repeat(100000) @(negedge clk);lesson=1;
    repeat(420000) @(negedge clk);lesson=3;
    repeat(420000) @(negedge clk);lesson=2;
    repeat(420000) @(negedge clk);lesson=4;
    wait(frames==5);repeat(3) @(negedge clk);
    if(pixels!=1536000 || lines!=2400 || starts!=5 || heat_checks!=423936 || trace_checks!=46080 || level_checks!=17920 || xy_checks!=16384 || harmonic_checks!=19680 || legacy_checks!=1331200) $fatal(1,"Incomplete renderer checks %0d %0d %0d %0d %0d %0d legacy%0d",pixels,lines,starts,heat_checks,trace_checks,level_checks,legacy_checks);
    $display("ALL SECONDARY RENDERER TESTS PASSED: five frames, 1536000 pixels, 1331200 exact protected pixels vs 8aea081, independent heat/trace/level/XY/harmonic pixels, unchanged two-clock framing");
    $finish;
end
initial begin #100000000;$fatal(1,"Renderer timeout");end
endmodule
