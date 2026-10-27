// Same-block measured f0 + 128 real L FFT magnitudes; H1..H5 neighbourhoods.
// Serial constant subtraction and fractional accumulation avoid a wide divider.
// One small BRAM, no FFT/DSP/PLL duplication and absolutely no backpressure.
module secondary_harmonics(
    input clk,rst,frame_tick,scene_clear,audio_stale,
    input [2:0] lesson,
    input lesson_valid,capture_start,bin_valid,bin_channel,
    input [8:0] bin_number,
    input [16:0] bin_magnitude,
    input [79:0] shown_feature,analysis_feature,
    input analysis_ready,
    output reg [29:0] harmonic_heights,
    output reg harmonic_valid
);
localparam IDLE=0,LOCATE=1,WAIT_RAM=2,READ_RAM=3,NORM=4,SCALE=5,SAVE=6;
reg [2:0] state,index;
reg [16:0] magnitude_ram[0:127];
reg [6:0] read_address,locator_bin;
reg [16:0] magnitude_q,peak,fundamental,scale_remainder;
reg [1:0] neighbour;
reg pending,pending_valid;
reg [29:0] working_heights;
reg [15:0] frequency_step,frequency_multiple,locator_remainder;
reg [5:0] scale_count,height;
wire [16:0] next_peak=magnitude_q>peak ? magnitude_q : peak;
wire [17:0] scale_sum={1'b0,scale_remainder}+{1'b0,peak};
wire scale_take=scale_sum>={1'b0,fundamental};
always @(posedge clk) begin
    magnitude_q<=magnitude_ram[read_address];
    if(!rst && lesson_valid && lesson==2 && bin_valid && !bin_channel && bin_number<128)
        magnitude_ram[bin_number[6:0]]<=bin_magnitude;
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=IDLE;index<=0;pending<=0;pending_valid<=0;working_heights<=0;
        harmonic_heights<=0;harmonic_valid<=0;read_address<=0;peak<=0;fundamental<=0;neighbour<=0;
        frequency_step<=0;frequency_multiple<=0;locator_remainder<=0;locator_bin<=0;
        scale_remainder<=0;scale_count<=0;height<=0;
    end else begin
        if(frame_tick) begin
            if(pending) begin harmonic_heights<=working_heights;harmonic_valid<=pending_valid;pending<=0;end
            if(audio_stale || !lesson_valid || lesson!=2) begin harmonic_heights<=0;harmonic_valid<=0;end
        end
        case(state)
            IDLE: if(analysis_ready) begin
                working_heights<=0;index<=0;fundamental<=0;locator_bin<=0;
                pending_valid<=analysis_feature[79] && analysis_feature[78:64]>=100 && analysis_feature[78:64]<=1000;
                frequency_step<={3'd0,analysis_feature[73:64],3'd0};
                frequency_multiple<={3'd0,analysis_feature[73:64],3'd0};
                locator_remainder<={3'd0,analysis_feature[73:64],3'd0}+16'd187;
                if(analysis_feature[79] && analysis_feature[78:64]>=100 && analysis_feature[78:64]<=1000) state<=LOCATE;
                else pending<=1;
            end
            LOCATE: begin
                // nearest bin = floor((8*h*f_hz+187)/375), <=107 at H5.
                if(locator_remainder>=375) begin locator_remainder<=locator_remainder-16'd375;locator_bin<=locator_bin+7'd1;end
                else begin read_address<=locator_bin-7'd1;peak<=0;neighbour<=0;state<=WAIT_RAM;end
            end
            WAIT_RAM: state<=READ_RAM;
            READ_RAM: begin
                peak<=next_peak;
                if(neighbour==2) begin
                    if(index==0) fundamental<=next_peak;
                    state<=NORM;
                end else begin read_address<=read_address+7'd1;neighbour<=neighbour+2'd1;state<=WAIT_RAM;end
            end
            NORM: begin
                if(fundamental<32) begin working_heights<=0;pending_valid<=0;pending<=1;state<=IDLE;end
                else if(peak>=fundamental) begin height<=38;state<=SAVE;end
                else begin scale_remainder<=0;scale_count<=0;height<=0;state<=SCALE;end
            end
            SCALE: begin
                // 38 additions compute floor(38*peak/H1) exactly. Because
                // peak<H1, each addition emits at most one height increment.
                scale_remainder<=scale_take ? scale_sum-{1'b0,fundamental} : scale_sum[16:0];
                if(scale_take) height<=height+6'd1;
                if(scale_count==37) state<=SAVE;else scale_count<=scale_count+6'd1;
            end
            SAVE: begin
                working_heights[index*6+:6]<=height;
                if(index==4) begin pending<=1;state<=IDLE;end
                else begin
                    index<=index+3'd1;frequency_multiple<=frequency_multiple+frequency_step;
                    locator_remainder<=frequency_multiple+frequency_step+16'd187;locator_bin<=0;state<=LOCATE;
                end
            end
        endcase
        // Next PCM capture cannot overwrite the old FFT RAM until its entire
        // window/transform finishes. Finish this tiny postprocessing normally.
        if(scene_clear || !lesson_valid || lesson!=2) begin
            state<=IDLE;pending<=0;pending_valid<=0;working_heights<=0;
            if(scene_clear) begin harmonic_heights<=0;harmonic_valid<=0;end
        end
    end
end
endmodule
