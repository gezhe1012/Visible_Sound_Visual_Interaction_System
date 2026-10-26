`timescale 1ns/1ps
module tb_display_key_controls;
reg clk=0,rst=1,vs=0,key1=1,key2=1;
always #5 clk=~clk;
reg sd_clk=0;
always #4 sd_clk=~sd_clk;
wire next_toggle,auto_toggle;
wire signed [8:0] brightness;
wire [2:0] contrast_q2;
wire [1:0] active_control;
integer cycles=0,next_events=0,auto_events=0,sd_next_events=0,sd_auto_events=0;
integer i,old_bri,old_con;
reg old_next=0,old_auto=0;
reg signed [8:0] old_applied_bri=0;
reg [2:0] old_applied_con=4;
reg [1:0] old_status=0;
reg frame_commit;
display_key_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(3),.HOLD_MS(16),
    .REPEAT_MS(12),.INDICATOR_MS(80)) dut(.*);
sd_card_bmp #(.CLK_FREQ_HZ(1000),.KEY_EVENT_MODE(1)) receiver(
    .clk(sd_clk),.rst(rst),.key_next(next_toggle),.key_auto(auto_toggle),
    .bmp_width(16'd640),.bmp_height(16'd480),.transition_done_toggle(1'b0),
    .write_finish_toggle(1'b0),.write_req_ack(1'b0),.write_ready(1'b1),.SD_MISO(1'b1),
    .state_code(),.display_valid(),.transition_start_toggle(),.transition_buf_idx(),
    .transition_lesson_idx(),
    .melody_complete(1'b1),
    .write_buf_idx(),.disp_buf_idx(),.write_req(),.write_en(),.write_data(),
    .SD_nCS(),.SD_DCLK(),.SD_MOSI());
always @(posedge sd_clk) begin
    if(!rst && receiver.key_next_press) sd_next_events=sd_next_events+1;
    if(!rst && receiver.key_auto_press) sd_auto_events=sd_auto_events+1;
end
always @(negedge clk) begin
    cycles=cycles+1;
    vs=(cycles%32>=2);
end
always @(posedge clk) begin
    frame_commit=vs && !dut.vs_d;
    #1;
    if(!rst) begin
        if(next_toggle!=old_next) next_events=next_events+1;
        if(auto_toggle!=old_auto) auto_events=auto_events+1;
        if((brightness!==old_applied_bri || contrast_q2!==old_applied_con || active_control!==old_status) && !frame_commit)
            $fatal(1,"Parameters changed away from frame boundary");
    end
    old_next=next_toggle; old_auto=auto_toggle;
    old_applied_bri=brightness; old_applied_con=contrast_q2; old_status=active_control;
end
task settle(input integer n);
    repeat(n) @(negedge clk);
endtask
task short_key(input integer which);
    @(negedge clk); if(which==1) key1=0; else key2=0;
    settle(9);
    if(which==1) key1=1; else key2=1;
    settle(12);
endtask
initial begin
    settle(5); rst=0; settle(5);
    // Sub-debounce bounce must not register as a press.
    key1=0; settle(1); key1=1; settle(6);
    if(next_events!=0) $fatal(1,"Bounce produced short action");
    short_key(1); short_key(2); settle(8);
    if(next_events!=1 || auto_events!=1 || sd_next_events!=1 || sd_auto_events!=1)
        $fatal(1,"Short actions or CDC duplicated/dropped");
    key1=0; wait(dut.requested_brightness==16); @(negedge clk); key1=1; settle(40);
    if(brightness!=16 || next_events!=1 || active_control!=1) $fatal(1,"KEY1 hold failed");
    key2=0; wait(dut.requested_contrast==5); @(negedge clk); key2=1; settle(40);
    if(contrast_q2!=5 || auto_events!=1 || active_control!=2) $fatal(1,"KEY2 hold failed");
    // Both-key restore, then staggered release: no repeat or short action.
    key1=0; key2=0; wait(dut.chord_done); settle(35);
    if(brightness!=0 || contrast_q2!=4 || active_control!=3) $fatal(1,"Chord restore failed");
    key1=1; settle(40); key2=1; settle(40);
    if(next_events!=1 || auto_events!=1 || brightness!=0 || contrast_q2!=4)
        $fatal(1,"Staggered chord release produced action");
    // Full brightness wrap: 0 -> 16 .. 64 -> -64 .. -16 -> 0.
    key1=0; old_bri=0;
    for(i=0;i<9;i=i+1) begin
        wait($signed(dut.requested_brightness)!=old_bri);
        #1; old_bri=$signed(dut.requested_brightness);
    end
    @(negedge clk); key1=1; settle(40);
    if(brightness!=0 || next_events!=1) $fatal(1,"Brightness repeat/wrap failed");
    key2=0; old_con=4;
    for(i=0;i<5;i=i+1) begin
        wait(dut.requested_contrast!=old_con);
        #1; old_con=dut.requested_contrast;
    end
    @(negedge clk); key2=1; settle(40);
    if(contrast_q2!=4 || auto_events!=1) $fatal(1,"Contrast repeat/wrap failed");
    settle(120);
    if(active_control!=0) $fatal(1,"Indicator did not expire");
    if(sd_next_events!=1 || sd_auto_events!=1) $fatal(1,"Hold leaked short events through CDC");
    $display("ALL KEY CONTROL TESTS PASSED: debounce, short/hold, repeat/wrap, chord, frame snapshot, indicator and asynchronous CDC");
    $finish;
end
initial begin #100000; $fatal(1,"Timeout"); end
endmodule
