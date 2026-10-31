`timescale 1ns/1ps
module tb_nature_controls;
reg clk=0,rst=1,vs=0,key3=1,next_toggle=0,auto_toggle=0;
always #5 clk=~clk;
reg assets_ready_async=0,owner_async=1,audio_ack_async=0,teaching_valid=0;
wire active,visible,exit_request,audio_request,autoplay,teaching_next,teaching_auto,teaching_key3;
wire [1:0] photo,audio_photo;
wire [5:0] slide;
wire panel;
nature_intro_controls #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.PHOTO_FRAMES(4)) dut(.*);
waveform_key_control #(.CLK_HZ(1000),.DEBOUNCE_MS(2)) original_panel(
    .clk(clk),.rst(rst),.key3(teaching_key3),.requested_visible(panel));
task cycles(input integer n);repeat(n) @(negedge clk);endtask
task frame; vs=0;cycles(2);vs=1;cycles(2);vs=0;cycles(2);endtask
task press;key3=0;cycles(8);key3=1;cycles(8);endtask
task start_photo(input integer expected);
    wait(audio_photo==expected && dut.waiting);
    if(panel || teaching_next || teaching_auto) $fatal(1,"Intro key leaked to teaching");
    audio_ack_async=audio_request;cycles(4);frame;
    if(!visible || photo!=expected) $fatal(1,"Photo/audio handshake mismatch");
    repeat(34) frame;
endtask
integer i;
initial begin
    cycles(4);rst=0;assets_ready_async=1;cycles(4);frame;
    if(visible) $fatal(1,"Displayed before PCM prefill acknowledgement");
    start_photo(0);
    // KEY3 is intro-next; legacy next also remains an intro-next gesture.
    press;frame;start_photo(1);
    next_toggle=~next_toggle;cycles(3);frame;start_photo(2);
    press;frame;start_photo(3);
    // Hold the final press through the entire page handoff.
    key3=0;cycles(8);frame;
    if(!exit_request || visible) $fatal(1,"Last photo did not enter black handoff");
    owner_async=0;teaching_valid=1;cycles(6);frame;cycles(10);
    if(active || !teaching_key3 || panel) $fatal(1,"Held KEY3 opened original FFT at handoff");
    key3=1;cycles(12);press;cycles(8);
    if(!panel) $fatal(1,"Original KEY3 panel toggle not restored");
    press;cycles(8);if(panel) $fatal(1,"Original KEY3 second press did not hide");
    next_toggle=~next_toggle;auto_toggle=~auto_toggle;cycles(4);
    if(!teaching_next || !teaching_auto) $fatal(1,"Original next/autoplay events not restored");
    // Autoplay independently advances every photo, then exits, never wraps intro.
    rst=1;cycles(4);rst=0;key3=1;next_toggle=0;auto_toggle=0;owner_async=1;teaching_valid=0;
    audio_ack_async=0;cycles(5);frame;start_photo(0);
    auto_toggle=1;cycles(4);
    frame;if(dut.waiting) $fatal(1,"Enabling autoplay after a long manual hold advanced immediately");
    for(i=1;i<4;i=i+1) begin
        repeat(6) frame;
        wait(dut.waiting);audio_ack_async=audio_request;cycles(4);frame;
        if(photo!=i) $fatal(1,"Autoplay skipped photo %0d",i);
        repeat(34) frame;
    end
    repeat(6) frame;
    if(!exit_request || panel) $fatal(1,"Autoplay exit or isolation failed");
    $display("ALL NATURE CONTROL TESTS PASSED: manual, autoplay, PCM ack, held-key quarantine, legacy keys");
    $finish;
end
initial begin #300000; $fatal(1,"Nature controller timeout");end
endmodule
