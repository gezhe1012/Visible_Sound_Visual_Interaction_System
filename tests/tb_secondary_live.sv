`timescale 1ns/1ps
// Real 25MHz / rational 48K / serial I2S. Only lesson/note durations shortened.
// Main VS owns FFT acknowledgement. Secondary has NO connection to that logic.
module tb_secondary_live;
reg clk=0,rst=1,enabled=0,lesson_valid=1;
always #20 clk=~clk;
reg [2:0] lesson=0;
wire bclk,lrck,dout,sample_tick,melody_complete;
wire [23:0] pcm_left,pcm_right,audio_left,audio_right;
wire [1:0] lesson_step;
science_audio_i2s #(.STEP_SAMPLES(4096),.NOTE_UNIT_SAMPLES(2048)) source(.*);
wire audio_valid;
I2S_receiver rx(.I_clk(clk),.I_rst(rst),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
    .O_audio_valid(audio_valid),.O_audio_left_data(audio_left),.O_audio_right_data(audio_right));
wire capture_start,bin_valid,bin_channel,spectrum_write,result_done;
wire [8:0] bin_number;
wire [16:0] bin_magnitude;
wire [7:0] spectrum_address;
wire [6:0] spectrum_height;
reg result_ack=0,main_pending=0;
integer clocks=0,samples=0,blocks=0,publications=0,last_sample=-1,last_capture=-1,cadences=0;
always @(posedge clk) begin
    result_ack<=0;
    if(rst) begin clocks<=0;main_pending<=0;end
    else begin
        clocks<=clocks+1;
        if(result_done) begin main_pending<=1;blocks=blocks+1;end
        if(clocks%420000==1000 && main_pending) begin result_ack<=1;main_pending<=0;end
        if(audio_valid) begin
            samples=samples+1;
            if(last_sample>=0 && clocks-last_sample!=520 && clocks-last_sample!=521) $fatal(1,"Actual PCM sample cadence changed");
            last_sample=clocks;
        end
        if(capture_start) begin
            if(last_capture>=0 && cadences>1 && (clocks-last_capture<839400 || clocks-last_capture>840600)) $fatal(1,"Secondary stalled/changed the original FFT capture cadence: %0d clocks",clocks-last_capture);
            last_capture=clocks;cadences=cadences+1;
        end
    end
end
audio_fft1024 fft(.*);
wire frame_tick,scene_clear,shown_right;
wire [6:0] read_column,shown_head,shown_count;
wire [5:0] read_band;
wire [3:0] heat_q;
wire [7:0] trace_q,peak_left,peak_right,average_left,average_right;
wire [79:0] shown_feature;
secondary_feature_store features(.*);
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_data;
secondary_audio_renderer renderer(.video_locked(1'b1),.*);
integer page,old_head=0,first_frequency=-1,music_changes=0,last_music=-1,target,valid_checks=0;
reg [1:0] captured_step=0;
reg [4:0] captured_note=0;
reg [2:0] captured_page=0;
reg [3:0] pitch_steps=0,stereo_steps=0;
always @(posedge clk) if(!rst) begin
    if(capture_start) begin captured_step=lesson_step;captured_note=source.melody_note;captured_page=lesson;end
    #1;
    if(shown_head!=old_head) begin
        if(renderer.col!=1 || renderer.line!=0) $fatal(1,"Live history published away from frame origin");
        old_head=shown_head;
        if(shown_count>0) begin
            publications=publications+1;
            if(renderer.shown_lesson!==lesson) $fatal(1,"Secondary scene metadata contradicts main page");
            if(captured_page==lesson && captured_step==lesson_step && shown_feature[79]) begin
                if(lesson==0) begin
                    case(captured_step) 0:target=220;1:target=330;2:target=440;3:target=660;endcase
                    if(shown_feature[78:64]<target-20 || shown_feature[78:64]>target+20) $fatal(1,"Actual pitch tracker does not follow DDS/I2S tone");
                    pitch_steps[captured_step]=1;valid_checks=valid_checks+1;
                end else if(lesson==1 || lesson==2) begin
                    if(shown_feature[78:64]<420 || shown_feature[78:64]>460) $fatal(1,"Actual level/timbre pitch changed");
                    valid_checks=valid_checks+1;
                end else if(lesson==3) begin
                    if(shown_right!==(captured_step==1)) $fatal(1,"Actual L-only/R-only/stereo selection wrong");
                    target=captured_step==1 ? 660 : 440;
                    if(shown_feature[78:64]<target-20 || shown_feature[78:64]>target+20) $fatal(1,"Actual stereo frequency wrong");
                    stereo_steps[captured_step]=1;valid_checks=valid_checks+1;
                end else if(lesson==4 && captured_note==source.melody_note) begin
                    if(last_music>=0 && last_music!=shown_feature[78:64]) music_changes=music_changes+1;
                    last_music=shown_feature[78:64];
                    if(!shown_feature[36]) $fatal(1,"Actual melody note name invalid");
                    valid_checks=valid_checks+1;
                end
            end
        end
    end
end
initial begin
    repeat(5) @(negedge clk);rst=0;enabled=1;
    for(page=0;page<5;page=page+1) begin
        @(negedge clk);lesson=3'(page);repeat(9300000) @(negedge clk);
        if(shown_count<8 || renderer.shown_lesson!==3'(page)) $fatal(1,"Missing live page history");
        $display("PASS actual 48K/I2S secondary page%0d: %0d published columns",page,shown_count);
    end
    if(pitch_steps!=15 || stereo_steps!=15 || music_changes<2 || valid_checks<30 || samples<85000 || blocks<50 || publications<45) $fatal(1,"Incomplete live coverage steps%h/%h changes%0d checks%0d PCM%0d FFT%0d histories%0d",pitch_steps,stereo_steps,music_changes,valid_checks,samples,blocks,publications);
    $display("ALL SECONDARY LIVE TESTS PASSED: real 25MHz/48K I2S, %0d samples, %0d FFT blocks, %0d original capture cadences, %0d frame-atomic columns, five scenes, all pitch/stereo stages, %0d music changes",samples,blocks,cadences,publications,music_changes);
    $finish;
end
initial begin #2200000000;$fatal(1,"Live secondary timeout");end
endmodule
