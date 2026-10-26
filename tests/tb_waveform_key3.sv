`timescale 1ns/1ps
module tb_waveform_key3;
reg clk=0,rst=1,key3=1,hs=1,vs=0,de=0;
always #5 clk=~clk;
reg [23:0] rgb_in=0;
wire requested_visible,hs_out,vs_out,de_out;
wire panel_visible;
wire [23:0] rgb_out;
reg audio_valid=0;
reg [23:0] audio_left=0,audio_right=0;
integer sample_div=0,sample_number=0,request_changes=0;
reg previous_request=0;
waveform_key_control #(.CLK_HZ(1000),.DEBOUNCE_MS(5)) keys(.*);
audio_waveform_overlay dut(.*);
// The actual pre-existing controller stays idle while ONLY board KEY3 moves.
wire next_toggle,auto_toggle;
wire signed [8:0] brightness;
wire [2:0] contrast_q2;
wire [1:0] active_control;
display_key_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(3),.HOLD_MS(16),.REPEAT_MS(12),.INDICATOR_MS(80)) legacy(
    .clk(clk),.rst(rst),.vs(vs),.key1(1'b1),.key2(1'b1),
    .next_toggle(next_toggle),.auto_toggle(auto_toggle),.brightness(brightness),
    .contrast_q2(contrast_q2),.active_control(active_control));
always @(negedge clk) begin
    audio_valid=0;
    if(!rst) begin
        sample_div=sample_div+1;
        if(sample_div==32) begin
            sample_div=0; sample_number=sample_number+1; audio_valid=1;
            audio_left=(sample_number%128<64)?24'(2000000):24'(-2000000);
            audio_right=(sample_number%128<64)?24'(-2000000):24'(2000000);
        end
    end
end
integer xx=0,yy=0,phase=0,pixels=0,draw_x=0,draw_y=0;
reg raster=0,expected_visible=0;
reg [1:0] eh=0,ev=0,ed=0,er=0,show=0;
reg [23:0] rgb0=0,rgb1=0;
integer x0=0,x1=0,y0=0,y1=0;
always @(posedge clk) begin
    if(rst) begin eh=0; ev=0; ed=0; er=0; show=0; previous_request=0; end
    else begin
        if(requested_visible!==previous_request) begin
            request_changes=request_changes+1; previous_request=requested_visible;
        end
        if(next_toggle || auto_toggle || brightness!=0 || contrast_q2!=4 || active_control!=0)
            $fatal(1,"Board KEY3 changed another key function");
        if(raster && dut.visible_frame!==expected_visible) $fatal(1,"Visibility changed within active frame");
        eh={eh[0],hs}; ev={ev[0],vs}; ed={ed[0],de}; er={er[0],raster&&de}; show={show[0],expected_visible};
        rgb1=rgb0; rgb0=rgb_in; x1=x0; x0=draw_x; y1=y0; y0=draw_y;
        #1;
        if({hs_out,vs_out,de_out}!=={eh[1],ev[1],ed[1]}) $fatal(1,"KEY3 changed timing latency");
        if(!de_out && rgb_out!==0) $fatal(1,"Blanking mismatch");
        if(er[1]) begin
            pixels=pixels+1;
            if(!show[1] || x1<48 || x1>=592 || y1<238 || y1>=416) begin
                if(rgb_out!==rgb1) $fatal(1,"Hidden/outside pixel changed (%0d,%0d): %h/%h",x1,y1,rgb_out,rgb1);
            end else if(x1==48 || x1==591 || y1==238 || y1==415) begin
                if(rgb_out!==24'h60849A) $fatal(1,"Enabled panel border missing");
            end
        end
    end
end
task frame_edge;
    @(negedge clk); de=0; vs=0; repeat(4) @(negedge clk);
    vs=1; repeat(4) @(negedge clk);
endtask
initial begin
    repeat(5) @(negedge clk); rst=0;
    repeat(8) @(negedge clk);
    if(requested_visible || dut.visible_frame) $fatal(1,"Waveform not hidden at reset");
    // Sub-debounce press and release bounces must not toggle.
    repeat(4) begin
        key3=0; repeat(2) @(negedge clk); key3=1; repeat(3) @(negedge clk);
    end
    if(requested_visible || request_changes) $fatal(1,"Bounce toggled waveform");
    wait(dut.pending); frame_edge();
    if(!dut.display_valid || dut.visible_frame) $fatal(1,"Hidden capture is not live");
    for(phase=0;phase<3;phase=phase+1) begin
        expected_visible=(phase==1); raster=1;
        for(yy=0;yy<480;yy=yy+1) begin
            for(xx=0;xx<640;xx=xx+1) begin
                @(negedge clk); de=1; draw_x=xx; draw_y=yy;
                rgb_in={8'(xx),8'(yy),8'(xx^yy)}; hs=(xx>=96);
                // Press during an active frame. Hold until AFTER it ends.
                if(phase<2 && xx==100 && yy==100) key3=0;
            end
            @(negedge clk); de=0; repeat(5) @(negedge clk);
        end
        repeat(4) @(negedge clk); raster=0;
        if(phase<2) begin
            if(requested_visible!==(phase==0)) $fatal(1,"Stable press did not toggle exactly once");
            if(request_changes!=phase+1) $fatal(1,"Holding KEY3 retriggered");
            // Release bounce, then stable release: no extra toggle.
            repeat(3) begin key3=1; repeat(2) @(negedge clk); key3=0; repeat(2) @(negedge clk); end
            key3=1; repeat(12) @(negedge clk);
            if(request_changes!=phase+1) $fatal(1,"Release toggled waveform");
            frame_edge();
        end
    end
    if(pixels!=921600 || request_changes!=2 || dut.visible_frame)
        $fatal(1,"Toggle regression incomplete %0d pixels / %0d toggles",pixels,request_changes);
    // Reset overrides an enabled request and panel even without a frame edge.
    key3=0; repeat(12) @(negedge clk); frame_edge();
    if(!dut.visible_frame) $fatal(1,"Third press did not re-enable");
    rst=1; repeat(4) @(negedge clk);
    if(requested_visible || dut.visible_frame) $fatal(1,"Reset did not restore hidden default");
    $display("ALL KEY3 WAVEFORM TESTS PASSED: default hidden, bounce/hold/release, frame-atomic on/off, 921600 raster pixels, unchanged legacy controls and reset");
    $finish;
end
initial begin #15000000; $fatal(1,"KEY3 test timeout"); end
endmodule
