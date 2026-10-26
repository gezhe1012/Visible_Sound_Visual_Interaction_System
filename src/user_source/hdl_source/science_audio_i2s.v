// Five-page science audio, all logic in video_clk (25MHz).
// Rational clock-enable: 12.288M enables per 25M clocks, /256 = EXACT average 48K.
// This is a clock enable, NOT a fabric-generated clock. Existing I2S_receiver
// still decodes the 24-bit stereo PCM before HDMI/ACR/waveform consumption.
module science_audio_i2s #(
    parameter integer STEP_SAMPLES=48000,
    parameter integer NOTE_UNIT_SAMPLES=12000, // eighth note, 120 BPM
    parameter integer MELODY_ATTACK_SHIFT=2,  // 64<<2 = 256 samples
    parameter integer MELODY_RELEASE_SHIFT=3 // 64<<3 = 512 samples
)(
    input clk,rst,enabled,
    input [2:0] lesson,
    output reg bclk,lrck,dout,sample_tick,
    output reg [23:0] pcm_left,pcm_right,
    output reg [1:0] lesson_step,
    output reg melody_complete
);
reg [24:0] tick_acc;
wire [25:0] tick_sum={1'b0,tick_acc}+26'd12288000;
wire mclk_enable=tick_sum>=26'd25000000;
reg [5:0] bit_count;
reg [63:0] shift_reg;
reg [31:0] phase_left,phase_right;
reg [15:0] step_count;
reg [2:0] active_lesson;
reg [4:0] melody_note;
reg [15:0] melody_position;
function [31:0] phase_increment;
    input [2:0] page;
    input [1:0] step;
    input right;
    begin
        if(page==0) case(step)
            0: phase_increment=32'd19685267;
            1: phase_increment=32'd29527900;
            2: phase_increment=32'd39370534;
            3: phase_increment=32'd59055800;
        endcase
        else if(page==3 && right) phase_increment=32'd59055800;
        else phase_increment=32'd39370534;
    end
endfunction
function signed [15:0] sine8;
    input [7:0] angle;
    reg [6:0] index;
    reg signed [15:0] positive;
    begin
        index=angle[6] ? 7'd64-{1'b0,angle[5:0]} : {1'b0,angle[5:0]};
        case(index)
            7'd0: positive=16'sd0;
            7'd1: positive=16'sd804;
            7'd2: positive=16'sd1608;
            7'd3: positive=16'sd2410;
            7'd4: positive=16'sd3212;
            7'd5: positive=16'sd4011;
            7'd6: positive=16'sd4808;
            7'd7: positive=16'sd5602;
            7'd8: positive=16'sd6393;
            7'd9: positive=16'sd7179;
            7'd10: positive=16'sd7962;
            7'd11: positive=16'sd8739;
            7'd12: positive=16'sd9512;
            7'd13: positive=16'sd10278;
            7'd14: positive=16'sd11039;
            7'd15: positive=16'sd11793;
            7'd16: positive=16'sd12539;
            7'd17: positive=16'sd13279;
            7'd18: positive=16'sd14010;
            7'd19: positive=16'sd14732;
            7'd20: positive=16'sd15446;
            7'd21: positive=16'sd16151;
            7'd22: positive=16'sd16846;
            7'd23: positive=16'sd17530;
            7'd24: positive=16'sd18204;
            7'd25: positive=16'sd18868;
            7'd26: positive=16'sd19519;
            7'd27: positive=16'sd20159;
            7'd28: positive=16'sd20787;
            7'd29: positive=16'sd21403;
            7'd30: positive=16'sd22005;
            7'd31: positive=16'sd22594;
            7'd32: positive=16'sd23170;
            7'd33: positive=16'sd23731;
            7'd34: positive=16'sd24279;
            7'd35: positive=16'sd24811;
            7'd36: positive=16'sd25329;
            7'd37: positive=16'sd25832;
            7'd38: positive=16'sd26319;
            7'd39: positive=16'sd26790;
            7'd40: positive=16'sd27245;
            7'd41: positive=16'sd27683;
            7'd42: positive=16'sd28105;
            7'd43: positive=16'sd28510;
            7'd44: positive=16'sd28898;
            7'd45: positive=16'sd29268;
            7'd46: positive=16'sd29621;
            7'd47: positive=16'sd29956;
            7'd48: positive=16'sd30273;
            7'd49: positive=16'sd30571;
            7'd50: positive=16'sd30852;
            7'd51: positive=16'sd31113;
            7'd52: positive=16'sd31356;
            7'd53: positive=16'sd31580;
            7'd54: positive=16'sd31785;
            7'd55: positive=16'sd31971;
            7'd56: positive=16'sd32137;
            7'd57: positive=16'sd32285;
            7'd58: positive=16'sd32412;
            7'd59: positive=16'sd32521;
            7'd60: positive=16'sd32609;
            7'd61: positive=16'sd32678;
            7'd62: positive=16'sd32728;
            7'd63: positive=16'sd32757;
            7'd64: positive=16'sd32767;
            default: positive=0;
        endcase
        sine8=angle[7] ? -positive : positive;
    end
endfunction
function signed [15:0] triangle8;
    input [7:0] angle;
    reg [6:0] magnitude;
    reg signed [15:0] positive;
    begin
        magnitude=angle[6] ? 7'd64-{1'b0,angle[5:0]} : {1'b0,angle[5:0]};
        positive=(magnitude==64) ? 16'sd32767 : $signed({1'b0,magnitude[5:0],9'd0});
        triangle8=angle[7] ? -positive : positive;
    end
endfunction
function [23:0] render_pcm;
    input [31:0] phase;
    input [2:0] page;
    input [1:0] step;
    input [15:0] position;
    input right;
    reg signed [15:0] base;
    reg signed [23:0] amplitude;
    reg signed [31:0] shaped;
    reg [6:0] envelope;
    begin
        base=sine8(phase[31:24]);
        if(page==2) case(step)
            1: base=triangle8(phase[31:24]);
            2: base=phase[31] ? -16'sd32767 : 16'sd32767;
            default: base=sine8(phase[31:24]);
        endcase
        if(page==1) case(step)
            0: base=base>>>2;
            1,3: base=base>>>1;
            default: base=base;
        endcase
        if(page==3 && ((step==0 && right) || (step==1 && !right))) base=0;
        // Peak <2M/8M full-scale. 64-sample ramps suppress step/shape clicks.
        if(position<64) envelope=position[6:0];
        else if(position>=STEP_SAMPLES-64) envelope=STEP_SAMPLES-1-position;
        else envelope=7'd64;
        amplitude=$signed(base)*24'sd60;
        shaped=amplitude*$signed({1'b0,envelope});
        render_pcm=shaped>>>6;
    end
endfunction
// Original 4-bar phrase in C major: 32 eighth-note units = exactly 8s.
// C4 E4 G4 A4 G4 | E4 D4 E4 G4 | A4 C5 B4 G4 | F4 E4 D4 C4
// Note records contain pitch, duration and gain; no WAV/ROM audio playback.
function [31:0] melody_increment;
    input [4:0] note;
    begin
        case(note)
            0,16: melody_increment=32'd23409859;
            6,15: melody_increment=32'd26276679;
            1,5,7,14: melody_increment=32'd29494575;
            13: melody_increment=32'd31248413;
            2,4,8,12: melody_increment=32'd35075158;
            3,9: melody_increment=32'd39370534;
            11: melody_increment=32'd44191930;
            10: melody_increment=32'd46819719;
            default: melody_increment=0;
        endcase
    end
endfunction
function [15:0] melody_length;
    input [4:0] note;
    begin
        case(note)
            1,2,13,14: melody_length=NOTE_UNIT_SAMPLES;
            16: melody_length=4*NOTE_UNIT_SAMPLES;
            default: melody_length=2*NOTE_UNIT_SAMPLES;
        endcase
    end
endfunction
function [6:0] melody_gain;
    input [4:0] note;
    begin
        case(note)
            0,3,7,9,12: melody_gain=56;
            1,5: melody_gain=52;
            2,4,8,16: melody_gain=60;
            6: melody_gain=48;
            10: melody_gain=64;
            11,14: melody_gain=54;
            default: melody_gain=50;
        endcase
    end
endfunction
function [23:0] render_melody;
    input [31:0] phase;
    input [4:0] note;
    input [15:0] position;
    reg signed [15:0] base;
    reg signed [23:0] weighted;
    reg signed [31:0] amplitude,shaped;
    reg [6:0] envelope;
    reg [15:0] remaining,length;
    begin
        base=sine8(phase[31:24]);
        length=melody_length(note); remaining=length-1-position;
        if(position<(64<<MELODY_ATTACK_SHIFT)) envelope=position>>MELODY_ATTACK_SHIFT;
        else if(remaining<(64<<MELODY_RELEASE_SHIFT)) envelope=remaining>>MELODY_RELEASE_SHIFT;
        else envelope=64;
        weighted=base*$signed({1'b0,melody_gain(note)});
        amplitude=($signed(weighted)*32'sd60)>>>6;
        shaped=amplitude*$signed({1'b0,envelope});
        render_melody=shaped>>>6;
    end
endfunction
wire [23:0] music_pcm=melody_complete ? 24'd0 : render_melody(phase_left,melody_note,melody_position);
wire [23:0] next_left=render_pcm(phase_left,active_lesson,lesson_step,step_count,1'b0);
wire [23:0] next_right=render_pcm(phase_right,active_lesson,lesson_step,step_count,1'b1);
always @(posedge clk or posedge rst) begin
    if(rst) begin
        tick_acc<=0; bit_count<=0; shift_reg<=0;
        phase_left<=0; phase_right<=0; step_count<=0;
        active_lesson<=0; lesson_step<=0;
        melody_note<=0; melody_position<=0; melody_complete<=0;
        bclk<=0; lrck<=0; dout<=0; sample_tick<=0; pcm_left<=0; pcm_right<=0;
    end else begin
        if(mclk_enable) tick_acc<=tick_sum-26'd25000000;
        else tick_acc<=tick_sum[24:0];
        sample_tick<=0;
        if(mclk_enable) begin
            bclk<=~bclk;
            if(bclk) begin
                dout<=shift_reg[63]; shift_reg<={shift_reg[62:0],1'b0};
                if(bit_count==63) begin
                    bit_count<=0; lrck<=~lrck;
                    if(!lrck) shift_reg<={pcm_right,40'd0};
                    else begin
                        sample_tick<=1;
                        if(!enabled || active_lesson!=lesson) begin
                            active_lesson<=lesson; lesson_step<=0; step_count<=0;
                            melody_note<=0; melody_position<=0; melody_complete<=0;
                            phase_left<=0; phase_right<=0;
                            pcm_left<=0; pcm_right<=0; shift_reg<=0;
                        end else if(active_lesson==4) begin
                            pcm_left<=music_pcm; pcm_right<=music_pcm;
                            shift_reg<={music_pcm,40'd0};
                            if(!melody_complete) begin
                                phase_left<=phase_left+melody_increment(melody_note);
                                phase_right<=phase_right+melody_increment(melody_note);
                                if(melody_position==melody_length(melody_note)-1) begin
                                    melody_position<=0; phase_left<=0; phase_right<=0;
                                    if(melody_note==16) melody_complete<=1;
                                    else melody_note<=melody_note+5'd1;
                                end else melody_position<=melody_position+16'd1;
                            end
                        end else begin
                            pcm_left<=next_left; pcm_right<=next_right;
                            shift_reg<={next_left,40'd0};
                            phase_left<=phase_left+phase_increment(active_lesson,lesson_step,0);
                            phase_right<=phase_right+phase_increment(active_lesson,lesson_step,1);
                            if(step_count==STEP_SAMPLES-1) begin step_count<=0; lesson_step<=lesson_step+2'd1; end
                            else step_count<=step_count+16'd1;
                        end
                    end
                end else bit_count<=bit_count+6'd1;
            end
        end
    end
end
endmodule
