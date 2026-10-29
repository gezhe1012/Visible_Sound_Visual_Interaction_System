// Microphone-only conditioning, no extra RAM/DSP/clock. DC tracker is Q24.8,
// pole 1-1/1024 (~7.5Hz); saturated 24-bit output, gain powers of two 8..128.
// A 256-sample mean-absolute detector ignores isolated peaks. Quiet background
// tracking is bounded (128..1024 raw LSB), freezes on strong voice and while
// the gate is open. Open: max(768,3*noise), close: max(384,2*noise).
// Two attack blocks (<=10.67ms), 18 release blocks (96ms) preserve word tails.
// Quiet gain is FIXED at 16; only qualified voice may increase it to 128.
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
reg [7:0] block_count;
reg [32:0] block_sum;
wire [32:0] next_sum=block_sum+{8'd0,absolute};
wire [24:0] block_mean=next_sum[32:8];
reg [11:0] noise_floor;
wire [13:0] triple_noise={2'd0,noise_floor}+{1'd0,noise_floor,1'b0};
wire [13:0] double_noise={1'd0,noise_floor,1'b0};
wire [13:0] open_level=triple_noise<14'd768 ? 14'd768 : triple_noise;
wire [13:0] close_level=double_noise<14'd384 ? 14'd384 : double_noise;
wire [11:0] noise_target=block_mean>1024 ? 12'd1024 :
                                block_mean<128 ? 12'd128 : block_mean[11:0];
wire signed [13:0] noise_error=$signed({2'd0,noise_target})-$signed({2'd0,noise_floor});
reg attack;
reg [4:0] release_count;
reg [1:0] gain_count;
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
        dc<=0;block_peak<=0;block_count<=0;block_sum<=0;gain_shift<=4;gate_open<=0;
        noise_floor<=256;attack<=0;release_count<=0;gain_count<=0;
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
            block_sum<=next_sum;
            if(block_count==255) begin
                block_count<=0;block_peak<=0;block_sum<=0;
                clipped<=gate_open && amplified_peak>8388607;
                if(!gate_open) begin
                    gain_shift<=4;gain_count<=0;release_count<=0;active<=0;
                    // Never learn a strong first syllable as background. Slow
                    // bounded tracking remains live even outside page 6.
                    if(block_mean<({11'd0,noise_floor,2'b0}) || block_mean<768)
                        noise_floor<=$signed({2'd0,noise_floor})+(noise_error>>>3);
                    if(block_mean>=open_level) begin
                        if(attack) begin gate_open<=1;active<=1;gain_shift<=5;attack<=0;end
                        else attack<=1;
                    end else attack<=0;
                end else begin
                    attack<=0;
                    if(block_mean>=close_level) release_count<=0;
                    else if(release_count==17) begin
                        gate_open<=0;active<=0;gain_shift<=4;release_count<=0;
                    end else release_count<=release_count+5'd1;
                    // AGC attacks overload quickly, but only raises gain once
                    // per 1024 voiced samples. Never chase background upward.
                    gain_count<=gain_count+2'd1;
                    if(block_mean>=close_level || release_count!=17) begin
                        if(amplified_peak>4194304 && gain_shift>3) gain_shift<=gain_shift-4'd1;
                        else if(gain_count==3 && block_mean>=close_level && amplified_peak<1048576 && gain_shift<7)
                            gain_shift<=gain_shift+4'd1;
                    end
                end
            end else block_count<=block_count+8'd1;
        end
    end
end
endmodule
