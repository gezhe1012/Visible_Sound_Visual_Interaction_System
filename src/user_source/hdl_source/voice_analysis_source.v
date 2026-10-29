// Microphone conditioning uses only bounded add/shift arithmetic. DC tracker
// Q24.8, pole 1-1/1024 (~7.5Hz), gain powers of two 8..128, 24-bit saturation.
// Gate and gain update per 1024 valid raw samples, not per video clock.
module voice_analysis_source(
    input clk,rst,
    input [2:0] lesson,
    input lesson_valid,dds_valid,mic_valid,
    input [23:0] dds_left,dds_right,
    input signed [23:0] mic_pcm,
    output analysis_valid,
    output [23:0] analysis_left,analysis_right,
    output reg source_clear,
    output reg active,clipped,
    output reg [3:0] gain_shift
);
reg signed [31:0] dc;
wire signed [31:0] raw_q8={mic_pcm,8'd0};
wire signed [32:0] dc_error=$signed({raw_q8[31],raw_q8})-$signed({dc[31],dc});
wire signed [24:0] centered=$signed({mic_pcm[23],mic_pcm})-$signed({dc[31],dc[31:8]});
wire [24:0] absolute=centered[24] ? -centered : centered;
wire signed [32:0] amplified=$signed({{8{centered[24]}},centered})<<<gain_shift;
reg [24:0] block_peak;
wire [24:0] next_peak=absolute>block_peak ? absolute : block_peak;
reg [9:0] block_count;
reg gate_open,conditioned_valid,selected_d;
reg [23:0] conditioned;
wire selected=lesson_valid && lesson==5;
wire [31:0] amplified_peak={7'd0,next_peak}<<gain_shift;
assign analysis_valid=selected ? (conditioned_valid && !source_clear) : (dds_valid && !source_clear);
assign analysis_left=selected ? conditioned : dds_left;
// Same mono word in both FFT slots. Renderer explicitly identifies MONO;
// page 6 never enables the stereo XY module.
assign analysis_right=selected ? conditioned : dds_right;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        dc<=0;block_peak<=0;block_count<=0;gain_shift<=5;gate_open<=0;
        conditioned<=0;conditioned_valid<=0;active<=0;clipped<=0;selected_d<=0;source_clear<=0;
    end else begin
        selected_d<=selected;source_clear<=selected!=selected_d;
        conditioned_valid<=mic_valid;
        if(mic_valid) begin
            dc<=dc+(dc_error>>>10);
            if(!gate_open) conditioned<=0;
            else if(amplified>33'sd8388607) conditioned<=24'h7fffff;
            else if(amplified< -33'sd8388608) conditioned<=24'h800000;
            else conditioned<=amplified[23:0];
            block_peak<=next_peak;
            if(block_count==1023) begin
                block_count<=0;block_peak<=0;gate_open<=next_peak>=256;
                active<=next_peak>=1024;clipped<=amplified_peak>8388607;
                if(amplified_peak>4194304 && gain_shift>3) gain_shift<=gain_shift-4'd1;
                else if(amplified_peak<1048576 && gain_shift<7) gain_shift<=gain_shift+4'd1;
            end else block_count<=block_count+10'd1;
        end
    end
end
endmodule
