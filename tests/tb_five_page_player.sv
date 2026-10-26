`timescale 1ns/1ps
// Real SD controller, real async fade payload, real DDS melody completion.
// Only the sector/pixel source and SDRAM write-finish are controllable stubs.
module tb_five_page_player;
reg clk=0,video_clk=0,rst=1,key_next=0,key_auto=0;
always #5 clk=~clk;
always #20 video_clk=~video_clk;
wire [3:0] state_code;
wire [1:0] write_buf_idx,disp_buf_idx,transition_buf_idx,video_buf;
wire [2:0] transition_lesson_idx,video_lesson;
wire display_valid,transition_start_toggle,write_req,write_en;
wire [31:0] write_data;
wire SD_nCS,SD_DCLK,SD_MOSI,done_toggle,video_valid,melody_complete;
reg write_req_ack=0,write_finish_toggle=0;
wire [4:0] fade_level;
reg vs=0;
integer vcycle=0,loads=0,load_age=-1,wraps=0,round,requested;
reg manual_override=0;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.KEY_EVENT_MODE(1),.SCAN_TARGET_COUNT(3'd5),
    .AUTO_PLAY_SECONDS(1),.WAIT_MELODY_END(1)) dut(
    .clk(clk),.rst(rst),.key_next(key_next),.key_auto(key_auto),.melody_complete(melody_complete),
    .state_code(state_code),.bmp_width(16'd640),.bmp_height(16'd480),.display_valid(display_valid),
    .transition_done_toggle(done_toggle),.transition_start_toggle(transition_start_toggle),
    .transition_buf_idx(transition_buf_idx),.transition_lesson_idx(transition_lesson_idx),
    .write_finish_toggle(write_finish_toggle),.write_buf_idx(write_buf_idx),.disp_buf_idx(disp_buf_idx),
    .write_req(write_req),.write_req_ack(write_req_ack),.write_ready(1'b1),.write_en(write_en),.write_data(write_data),
    .SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(1'b1));
video_fade_transition #(.FADE_FRAMES(3),.BLACK_HOLD_FRAMES(1)) fade(
    .clk(video_clk),.rst(rst),.vs(vs),.request_toggle_async(transition_start_toggle),
    .request_buf_idx_async(transition_buf_idx),.request_lesson_idx_async(transition_lesson_idx),
    .display_buf_idx(video_buf),.display_lesson_idx(video_lesson),.display_valid(video_valid),
    .fade_level(fade_level),.done_toggle(done_toggle));
science_audio_i2s #(.NOTE_UNIT_SAMPLES(128),.MELODY_ATTACK_SHIFT(0),.MELODY_RELEASE_SHIFT(0)) audio(
    .clk(video_clk),.rst(rst),.enabled(video_valid),.lesson(video_lesson),
    .bclk(),.lrck(),.dout(),.sample_tick(),.pcm_left(),.pcm_right(),.lesson_step(),.melody_complete(melody_complete));
always @(negedge video_clk) if(!rst) begin vcycle=vcycle+1; vs=(vcycle%128>=4); end
always @(posedge clk) if(!rst) begin
    write_req_ack<=write_req;
    if(dut.load_start_pulse) begin
        loads=loads+1; load_age=0;
        if(dut.load_idx>4 || dut.load_sector!=1000+100*dut.load_idx) $fatal(1,"Five-page sector LUT mismatch");
        if(display_valid && write_buf_idx==disp_buf_idx) $fatal(1,"Fifth page overwrote active SDRAM buffer");
        if(display_valid && dut.img_idx==4 && dut.load_idx==0) begin
            if(!manual_override && !dut.melody_done_sync[2]) $fatal(1,"Autoplay cut the final melody note");
            wraps=wraps+1;
        end
    end else if(load_age>=0) load_age=load_age+1;
    if(load_age==35) begin write_finish_toggle<=~write_finish_toggle; load_age=-1; end
end
task page(input integer index);
    wait(display_valid && !dut.load_busy && !dut.transition_pending && dut.img_idx==index);
    repeat(3) @(negedge clk);
    if(video_lesson!=index || video_buf!=disp_buf_idx || fade_level!=16) $fatal(1,"Picture/audio page not synchronized");
endtask
task next_page;
    @(negedge clk); key_next=~key_next;
    repeat(8) @(negedge clk);
endtask
initial begin
    repeat(8) @(negedge clk); rst=0; page(0);
    if(dut.img_found_count!=5 || dut.img_sector4!=1400) $fatal(1,"Fifth address not scanned/stored");
    for(requested=1;requested<5;requested=requested+1) begin next_page(); page(requested); end
    if(melody_complete) $fatal(1,"New music already marked finished");
    manual_override=1; next_page(); page(0); manual_override=0;
    if(melody_complete) $fatal(1,"Manual music exit failed");
    for(requested=1;requested<5;requested=requested+1) begin next_page(); page(requested); end
    key_auto=~key_auto; wait(dut.auto_play_en); wait(dut.auto_cnt==999);
    repeat(2000) @(negedge clk);
    if(dut.img_idx!=4 || dut.load_busy || dut.auto_cnt!=999 || melody_complete)
        $fatal(1,"Autoplay timer did not wait at threshold for complete phrase");
    wait(melody_complete); page(0);
    for(round=0;round<2;round=round+1) begin
        page(4); wait(melody_complete); page(0);
    end
    key_auto=~key_auto; wait(!dut.auto_play_en);
    if(wraps!=4 || loads!=21) $fatal(1,"Five-page loop coverage incomplete wraps=%0d loads=%0d",wraps,loads);
    $display("ALL FIVE PAGE PLAYER TESTS PASSED: scan/store five, unchanged two buffers, manual 5->1, 3 complete autoplay phrases/loops, timer wait, async image/audio binding");
    $finish;
end
initial begin #400000000; $fatal(1,"Five-page timeout page%0d loads%0d",dut.img_idx,loads); end
endmodule

module bmp_bilinear_reader(
    input clk,rst,output reg ready,input scan_start,input [31:0] scan_start_sector,scan_max_sector,
    input [2:0] scan_target_count,output reg scan_done,scan_found_valid,
    output reg [31:0] scan_found_sector,output reg [2:0] scan_found_total,
    input load_start,input [31:0] load_sector,input sd_init_done,output [3:0] state_code,
    input [15:0] bmp_width,bmp_height,output write_req,input write_req_ack,write_ready,
    output load_error,sd_sec_read,output [31:0] sd_sec_read_addr,input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid,sd_sec_read_end,output bmp_data_wr_en,output [23:0] bmp_data
);
integer scan_age=-1,load_age=-1;
assign state_code=0; assign write_req=load_age>=0 && load_age<5;
assign load_error=0; assign sd_sec_read=0; assign sd_sec_read_addr=0;
assign bmp_data_wr_en=0; assign bmp_data=0;
always @(posedge clk) begin
    if(rst) begin ready<=1; scan_done<=0; scan_found_valid<=0; scan_found_sector<=0; scan_found_total<=0; scan_age=-1; load_age=-1; end
    else begin
        scan_found_valid<=0;
        if(scan_start) begin ready<=0; scan_age=0; end
        if(scan_age>=0) begin
            scan_age=scan_age+1;
            if(scan_age<=10 && scan_age%2==0) begin
                scan_found_valid<=1; scan_found_sector<=900+50*scan_age; scan_found_total<=scan_found_total+3'd1;
            end
            if(scan_age==12) begin ready<=1; scan_done<=1; scan_age=-1; end
        end
        if(load_start) begin ready<=0; load_age=0; end
        if(load_age>=0) begin load_age=load_age+1; if(load_age==20) begin ready<=1; load_age=-1; end end
    end
end
endmodule
module sd_card_top(
    input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,output sd_init_done,
    input sd_sec_read,input [31:0] sd_sec_read_addr,output [7:0] sd_sec_read_data,
    output sd_sec_read_data_valid,sd_sec_read_end,input sd_sec_write,input [31:0] sd_sec_write_addr,
    input [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end
);
assign SD_nCS=1; assign SD_DCLK=0; assign SD_MOSI=0; assign sd_init_done=!rst;
assign sd_sec_read_data=0; assign sd_sec_read_data_valid=0; assign sd_sec_read_end=0;
assign sd_sec_write_data_req=0; assign sd_sec_write_end=0;
endmodule
