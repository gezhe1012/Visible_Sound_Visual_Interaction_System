// Dominant-peak MONOPHONIC estimate from the existing Hann-windowed FFT.
// No FFT duplication/RAM/DSP, no backpressure. |Re|+|Im| is not RMS/THD.
// Summary [79]valid [78:64]Hz [63:44]BCD [43:40]note class C..B
// [39:37]octave [36]note valid [35:19]peak [18:13]note index C2=0
// [12:7]trace position 0..47 representing 100..1000Hz [6:0]reserved.
module secondary_pitch_estimator(
    input clk,rst,clear,bin_valid,bin_channel,
    input [8:0] bin_number,
    input [16:0] bin_magnitude,
    output reg [79:0] left_feature,right_feature,
    output reg feature_done
);
localparam SCAN=0,INTERP=1,DIVIDE=2,RETURN=3,QBIN=4,HZ=5,SMOOTH=6,
    NOTE=7,SCALE=8,BCD_INIT=9,BCD_STEP=10,PUBLISH=11;
reg [3:0] state;
reg channel;
reg [16:0] peak,previous_mag,left_mag,right_mag;
reg [8:0] peak_bin;
reg [25:0] spectral_sum;
wire good_signal=peak>=32 && {9'd0,peak}>=(spectral_sum>>6);
reg negative_delta;
reg signed [9:0] delta_q8;
reg [17:0] qbin;
wire [18:0] twice_peak={1'b0,peak,1'b0};
wire [18:0] neighbors={2'b0,left_mag}+{2'b0,right_mag};
wire [16:0] neighbor_diff=right_mag>=left_mag ? right_mag-left_mag : left_mag-right_mag;
wire signed [18:0] adjusted_bin=$signed({2'd0,peak_bin,8'd0})+$signed({{9{delta_q8[9]}},delta_q8});
wire [26:0] qext={9'd0,qbin};
wire [26:0] hz_product=(qext<<8)+(qext<<6)+(qext<<5)+(qext<<4)+(qext<<2)+(qext<<1)+qext;
reg [14:0] raw_hz,frequency_hz,previous_left,previous_right;
reg previous_left_valid,previous_right_valid;
wire [14:0] prior_hz=channel ? previous_right : previous_left;
wire prior_valid=channel ? previous_right_valid : previous_left_valid;
wire [14:0] hz_difference=raw_hz>=prior_hz ? raw_hz-prior_hz : prior_hz-raw_hz;
reg [5:0] note_index,trace_position;
reg [3:0] note_class;
reg [2:0] octave;
reg note_valid;
wire [14:0] note_upper;
secondary_note_thresholds note_table(.index(note_index),.upper_hz(note_upper));
reg [23:0] numerator,denominator,remainder,quotient,answer;
reg [4:0] div_count;
reg scale_division;
wire [24:0] shifted={remainder,numerator[23]};
wire div_take=shifted>={1'b0,denominator};
wire [23:0] quotient_next={quotient[22:0],div_take};
wire [23:0] hz_offset={9'd0,frequency_hz}-24'd100;
reg [16:0] binary_value;
reg [19:0] bcd,adjusted_bcd;
reg [4:0] bcd_count;
integer digit;
always @* begin
    adjusted_bcd=bcd;
    for(digit=0;digit<5;digit=digit+1)
        if(bcd[digit*4+:4]>=5) adjusted_bcd[digit*4+:4]=bcd[digit*4+:4]+4'd3;
end
wire [19:0] bcd_next={adjusted_bcd[18:0],binary_value[16]};
wire [79:0] feature={good_signal,frequency_hz,bcd,note_class,octave,note_valid,peak,note_index,trace_position,7'd0};
always @(posedge clk or posedge rst) begin
    if(rst) begin
        state<=SCAN;channel<=0;peak<=0;previous_mag<=0;left_mag<=0;right_mag<=0;peak_bin<=0;spectral_sum<=0;
        negative_delta<=0;delta_q8<=0;qbin<=0;raw_hz<=0;frequency_hz<=0;
        previous_left<=0;previous_right<=0;previous_left_valid<=0;previous_right_valid<=0;
        note_index<=0;trace_position<=0;note_class<=0;octave<=2;note_valid<=0;
        numerator<=0;denominator<=1;remainder<=0;quotient<=0;answer<=0;div_count<=0;scale_division<=0;
        binary_value<=0;bcd<=0;bcd_count<=0;left_feature<=0;right_feature<=0;feature_done<=0;
    end else begin
        feature_done<=0;
        if(clear) begin
            state<=SCAN;peak<=0;previous_mag<=0;left_mag<=0;right_mag<=0;peak_bin<=0;spectral_sum<=0;
            left_feature<=0;right_feature<=0;previous_left_valid<=0;previous_right_valid<=0;
        end else case(state)
            SCAN: if(bin_valid) begin
                previous_mag<=bin_magnitude;
                if(bin_number==0) begin peak<=0;peak_bin<=0;left_mag<=0;right_mag<=0;spectral_sum<=0;end
                else begin
                    if(bin_number>=2) spectral_sum<=spectral_sum+{9'd0,bin_magnitude};
                    if(bin_number==peak_bin+9'd1) right_mag<=bin_magnitude;
                    if(bin_number>=2 && bin_magnitude>peak) begin
                        peak<=bin_magnitude;peak_bin<=bin_number;left_mag<=previous_mag;right_mag<=0;
                    end
                end
                if(bin_number==511) begin channel<=bin_channel;state<=INTERP;end
            end
            INTERP: begin
                numerator<={neighbor_diff,7'd0};denominator<={5'd0,twice_peak-neighbors};
                negative_delta<=right_mag<left_mag;quotient<=0;remainder<=0;div_count<=23;scale_division<=0;
                if(!good_signal || peak_bin==511 || twice_peak<=neighbors) begin delta_q8<=0;state<=QBIN;end
                else state<=DIVIDE;
            end
            DIVIDE: begin
                numerator<=numerator<<1;quotient<=quotient_next;
                remainder<=div_take ? shifted-{1'b0,denominator} : shifted[23:0];
                if(div_count==0) begin answer<=quotient_next;state<=RETURN;end
                else div_count<=div_count-5'd1;
            end
            RETURN: if(scale_division) begin trace_position<=answer[5:0];state<=BCD_INIT;end
            else begin
                if(answer>128) delta_q8<=negative_delta ? -10'sd128 : 10'sd128;
                else delta_q8<=negative_delta ? -$signed({2'd0,answer[7:0]}) : $signed({2'd0,answer[7:0]});
                state<=QBIN;
            end
            QBIN: begin qbin<=adjusted_bin[17:0];state<=HZ;end
            HZ: begin raw_hz<=good_signal ? ((hz_product+27'd1024)>>11) : 15'd0;state<=SMOOTH;end
            SMOOTH: begin
                // Two-frame averaging only for a stable tone; no averaging
                // across ordinary lesson/melody note changes or silence.
                if(good_signal && prior_valid && hz_difference<=10)
                    frequency_hz<=({1'b0,raw_hz}+{1'b0,prior_hz}+16'd1)>>1;
                else frequency_hz<=raw_hz;
                note_index<=0;note_class<=0;octave<=2;note_valid<=0;state<=NOTE;
            end
            NOTE: begin
                if(!good_signal || frequency_hz<64) state<=SCALE;
                else if(frequency_hz<=note_upper) begin note_valid<=1;state<=SCALE;end
                else if(note_index==59) state<=SCALE;
                else begin
                    note_index<=note_index+6'd1;
                    if(note_class==11) begin note_class<=0;octave<=octave+3'd1;end
                    else note_class<=note_class+4'd1;
                end
            end
            SCALE: begin
                scale_division<=1;numerator<=(hz_offset<<5)+(hz_offset<<3)+(hz_offset<<2)+(hz_offset<<1)+hz_offset;
                denominator<=900;quotient<=0;remainder<=0;div_count<=23;
                if(frequency_hz<=100) begin trace_position<=0;state<=BCD_INIT;end
                else if(frequency_hz>=1000) begin trace_position<=47;state<=BCD_INIT;end
                else state<=DIVIDE;
            end
            BCD_INIT: begin binary_value<={2'd0,frequency_hz};bcd<=0;bcd_count<=16;state<=BCD_STEP;end
            BCD_STEP: begin
                bcd<=bcd_next;binary_value<=binary_value<<1;
                if(bcd_count==0) state<=PUBLISH;else bcd_count<=bcd_count-5'd1;
            end
            PUBLISH: begin
                if(channel) begin right_feature<=feature;feature_done<=1;previous_right<=raw_hz;previous_right_valid<=good_signal;end
                else begin left_feature<=feature;previous_left<=raw_hz;previous_left_valid<=good_signal;end
                state<=SCAN;
            end
            default:state<=SCAN;
        endcase
    end
end
endmodule
