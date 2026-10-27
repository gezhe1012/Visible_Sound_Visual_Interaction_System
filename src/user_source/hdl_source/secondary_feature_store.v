// 128 physical columns (4 KiB) / 96 visible columns. The unused columns guard
// the displayed history from writes; publication is ONLY at the video frame.
// Spectrum: first 64 EXISTING log bands => 0..1.5k (32), 1.5..4.5k (32).
// L/R are combined by max, not a fabricated mono/stereo phase relationship.
module secondary_feature_store #(
    parameter integer NO_AUDIO_CYCLES=6250000
)(
    input clk,rst,frame_tick,scene_clear,
    input [2:0] lesson,
    input lesson_valid,audio_valid,
    input [23:0] audio_left,audio_right,
    input capture_start,bin_valid,bin_channel,
    input [8:0] bin_number,
    input [16:0] bin_magnitude,
    input spectrum_write,result_done,
    input [7:0] spectrum_address,
    input [6:0] spectrum_height,
    input [6:0] read_column,
    input [5:0] read_band,
    output reg [3:0] heat_q,
    output reg [7:0] trace_q,
    output reg [6:0] shown_head,shown_count,
    output reg [79:0] shown_feature,
    output reg shown_right,
    output reg [7:0] peak_left,peak_right,average_left,average_right,
    // Passive secondary-only observations; original store state is unchanged.
    output analysis_ready,audio_stale,
    output [79:0] analysis_feature
);
wire [79:0] left_feature,right_feature;
wire feature_done;
secondary_pitch_estimator estimator(.clk(clk),.rst(rst),.clear(scene_clear),
    .bin_valid(bin_valid),.bin_channel(bin_channel),.bin_number(bin_number),.bin_magnitude(bin_magnitude),
    .left_feature(left_feature),.right_feature(right_feature),.feature_done(feature_done));
reg [3:0] heat_ram[0:8191];
reg [7:0] trace_ram[0:127];
reg [255:0] column_levels;
reg [6:0] write_column;
reg [5:0] copy_band;
reg copying,pending,fft_ready,block_valid;
reg [2:0] captured_lesson,lesson_d;
reg valid_d;
reg [79:0] pending_feature;
reg pending_right;
wire choose_right=!left_feature[79] && right_feature[79];
wire [79:0] selected_feature=choose_right ? right_feature : left_feature;
wire [3:0] compressed=spectrum_height>=60 ? 4'd15 : spectrum_height[5:2];
wire [7:0] trace_word={pending_feature[79],pending_right,pending_feature[12:7]};
always @(posedge clk) begin
    heat_q<=heat_ram[{read_column,read_band}];
    trace_q<=trace_ram[read_column];
    if(copying && !rst && !scene_clear) begin
        heat_ram[{write_column,copy_band}]<=column_levels[copy_band*4+:4];
        if(copy_band==63) trace_ram[write_column]<=trace_word;
    end
end
// Independent 1024-valid-PCM-sample peak and MEAN ABSOLUTE amplitude, not RMS.
wire [15:0] abs_left=audio_left[23] ? (~audio_left[23:8]+16'd1) : audio_left[23:8];
wire [15:0] abs_right=audio_right[23] ? (~audio_right[23:8]+16'd1) : audio_right[23:8];
reg [9:0] level_count;
reg [25:0] sum_left,sum_right;
reg [15:0] level_peak_l,level_peak_r;
wire [25:0] next_sum_l=sum_left+{10'd0,abs_left},next_sum_r=sum_right+{10'd0,abs_right};
wire [15:0] next_peak_l=abs_left>level_peak_l ? abs_left : level_peak_l;
wire [15:0] next_peak_r=abs_right>level_peak_r ? abs_right : level_peak_r;
reg [7:0] latest_peak_l,latest_peak_r,latest_average_l,latest_average_r;
reg [22:0] no_audio_count;
wire stale=no_audio_count>=NO_AUDIO_CYCLES-1;
assign audio_stale=stale;
assign analysis_feature=selected_feature;
assign analysis_ready=feature_done && (fft_ready || result_done) && block_valid && captured_lesson==lesson && lesson_valid && !copying && !pending;
function [7:0] bar_length;
    input [15:0] amplitude;
    reg [18:0] value;
    begin value=({3'd0,amplitude}<<2)+({3'd0,amplitude}<<1)+{3'd0,amplitude};bar_length=value[17:10];end
endfunction
always @(posedge clk or posedge rst) begin
    if(rst) begin
        column_levels<=0;write_column<=0;copy_band<=0;copying<=0;pending<=0;fft_ready<=0;block_valid<=0;
        captured_lesson<=0;lesson_d<=0;valid_d<=0;pending_feature<=0;pending_right<=0;
        shown_head<=0;shown_count<=0;shown_feature<=0;shown_right<=0;
        peak_left<=0;peak_right<=0;average_left<=0;average_right<=0;
        level_count<=0;sum_left<=0;sum_right<=0;level_peak_l<=0;level_peak_r<=0;
        latest_peak_l<=0;latest_peak_r<=0;latest_average_l<=0;latest_average_r<=0;no_audio_count<=NO_AUDIO_CYCLES-1;
    end else begin
        lesson_d<=lesson;valid_d<=lesson_valid;
        if(audio_valid) no_audio_count<=0;else if(!stale) no_audio_count<=no_audio_count+23'd1;
        if(audio_valid) begin
            if(level_count==1023) begin
                latest_peak_l<=bar_length(next_peak_l);latest_peak_r<=bar_length(next_peak_r);
                latest_average_l<=bar_length(next_sum_l[25:10]);latest_average_r<=bar_length(next_sum_r[25:10]);
                level_count<=0;sum_left<=0;sum_right<=0;level_peak_l<=0;level_peak_r<=0;
            end else begin
                level_count<=level_count+10'd1;sum_left<=next_sum_l;sum_right<=next_sum_r;
                level_peak_l<=next_peak_l;level_peak_r<=next_peak_r;
            end
        end
        if(capture_start) begin
            // capture_start is registered in the FFT; its sample was accepted
            // one clock ago. Tag the SAME lesson from that clock, not preload.
            captured_lesson<=lesson_d;block_valid<=valid_d && lesson_valid && lesson_d==lesson && !copying;fft_ready<=0;
        end else if(captured_lesson!=lesson || !lesson_valid) block_valid<=0;
        if(spectrum_write && !copying && spectrum_address[6:0]<64) begin
            if(!spectrum_address[7]) column_levels[spectrum_address[5:0]*4+:4]<=compressed;
            else if(compressed>column_levels[spectrum_address[5:0]*4+:4])
                column_levels[spectrum_address[5:0]*4+:4]<=compressed;
        end
        if(result_done) fft_ready<=1;
        if(feature_done && (fft_ready || result_done) && block_valid && captured_lesson==lesson && lesson_valid && !copying && !pending) begin
            pending_feature<=selected_feature;pending_right<=choose_right;copying<=1;copy_band<=0;
        end
        if(copying) begin
            if(copy_band==63) begin copying<=0;pending<=1;write_column<=write_column+7'd1;end
            else copy_band<=copy_band+6'd1;
        end
        if(frame_tick) begin
            peak_left<=stale ? 8'd0 : latest_peak_l;peak_right<=stale ? 8'd0 : latest_peak_r;
            average_left<=stale ? 8'd0 : latest_average_l;average_right<=stale ? 8'd0 : latest_average_r;
            if(stale) shown_feature<=0;
            if(pending) begin
                shown_head<=write_column;if(shown_count<96) shown_count<=shown_count+7'd1;
                shown_feature<=stale ? 80'd0 : pending_feature;shown_right<=pending_right;pending<=0;
            end
        end
        if(scene_clear) begin
            write_column<=0;copy_band<=0;copying<=0;pending<=0;fft_ready<=0;block_valid<=0;
            shown_head<=0;shown_count<=0;shown_feature<=0;shown_right<=0;pending_feature<=0;
            peak_left<=0;peak_right<=0;average_left<=0;average_right<=0;
            level_count<=0;sum_left<=0;sum_right<=0;level_peak_l<=0;level_peak_r<=0;
            latest_peak_l<=0;latest_peak_r<=0;latest_average_l<=0;latest_average_r<=0;
        end
    end
end
endmodule
