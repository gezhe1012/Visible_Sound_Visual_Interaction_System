`timescale 1ns/1ps
module tb_six_page_player;
reg clk=0,vclk=0,rst=1,next_key=0,auto_key=0,finish=0;
always #5 clk=~clk;
always #20 vclk=~vclk;
wire [2:0] lesson,shown_lesson;
wire [1:0] buf_idx,shown_buf,write_buf,display_buf;
wire request,done,display_valid,shown_valid;
wire [4:0] fade;
reg vs=0;
integer cyc=0,age=-1,loads=0,i,round;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.KEY_EVENT_MODE(1),.SCAN_TARGET_COUNT(5),.AUTO_PLAY_SECONDS(1),.WAIT_MELODY_END(1),.LIVE_VOICE_PAGE(1)) dut(
    .clk(clk),.rst(rst),.key_next(next_key),.key_auto(auto_key),.melody_complete(1'b1),.state_code(),
    .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(display_valid),.transition_done_toggle(done),
    .transition_start_toggle(request),.transition_buf_idx(buf_idx),.transition_lesson_idx(lesson),
    .write_finish_toggle(finish),.write_buf_idx(write_buf),.disp_buf_idx(display_buf),
    .write_req(),.write_req_ack(1'b1),.write_ready(1'b1),.write_en(),.write_data(),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
video_fade_transition #(.FADE_FRAMES(3),.BLACK_HOLD_FRAMES(1)) transition(
    .clk(vclk),.rst(rst),.vs(vs),.request_toggle_async(request),.request_buf_idx_async(buf_idx),.request_lesson_idx_async(lesson),
    .display_lesson_idx(shown_lesson),.display_buf_idx(shown_buf),.display_valid(shown_valid),.fade_level(fade),.done_toggle(done));
always @(negedge vclk) if(!rst) begin cyc=cyc+1;vs=cyc%128>=4;end
always @(posedge clk) if(!rst) begin
    if(dut.load_start_pulse) begin
        age=0;loads=loads+1;
        if(dut.load_idx>4 || dut.load_sector!=1000+100*dut.load_idx) $fatal(1,"Virtual page attempted BMP lookup");
        if(display_valid && write_buf==display_buf) $fatal(1,"Active buffer overwritten");
    end else if(age>=0) age=age+1;
    if(age==35) begin finish<=~finish;age=-1;end
end
task page(input integer n);
    wait(display_valid && !dut.load_busy && !dut.transition_pending && dut.img_idx==n);
    repeat(3) @(negedge clk);
    if(shown_lesson!=n || shown_buf!=display_buf || fade!=16) $fatal(1,"Page/transition mismatch");
endtask
task step;
    @(negedge clk);next_key=~next_key;repeat(8) @(negedge clk);
endtask
initial begin
    repeat(8) @(negedge clk);rst=0;page(0);
    for(round=0;round<3;round=round+1) begin
        for(i=1;i<=5;i=i+1) begin step();page(i);end
        if(loads!=5+5*round) $fatal(1,"Sixth page performed a load");
        repeat(300) @(negedge clk);
        if(dut.img_idx!=5 || dut.load_busy) $fatal(1,"Live page unstable");
        step();page(0);
    end
    auto_key=~auto_key;wait(dut.auto_play_en);
    for(round=0;round<2;round=round+1) begin page(5);page(0);end
    auto_key=~auto_key;wait(!dut.auto_play_en);
    $display("ALL SIX PAGE PLAYER TESTS PASSED: three manual loops, two autoplay loops, five BMPs, virtual sixth page, two buffers, frame-bound fade and return");$finish;
end
initial begin #10000000;$fatal(1,"Six-page timeout");end
endmodule
