`timescale 1ns/1ps
// Direct pixel-for-pixel comparison to immutable 6e58891 source fixtures.
module tb_voice_compat;
reg clk=0,rst=1;
always #20 clk=~clk;
reg [2:0] lesson=0;
integer col=0,line=0,frames=0,pixels=0,cycles=0;
always @(posedge clk) if(!rst) begin
    if(col==799) begin col<=0;if(line==524) begin line<=0;frames<=frames+1;end else line<=line+1;end
    else col<=col+1;
end
wire hs=col>=96,vs=line>=2,de=col>=160 && line>=45;
wire [9:0] x=col-160,y=line-45;
wire [23:0] rgb_in={x[7:0],y[7:0],x[7:0]^y[7:0]};
wire bclk,lrck,dout,audio_valid;
wire [23:0] audio_left,audio_right;
science_audio_i2s #(.STEP_SAMPLES(512),.NOTE_UNIT_SAMPLES(128)) dds(.clk(clk),.rst(rst),.enabled(1'b1),.lesson(lesson),
    .bclk(bclk),.lrck(lrck),.dout(dout),.sample_tick(),.pcm_left(),.pcm_right(),.lesson_step(),.melody_complete());
I2S_receiver rx(.I_clk(clk),.I_rst(rst),.I_i2s_BCLK(bclk),.I_i2s_LRCK(lrck),.I_i2s_DOUT(dout),
    .O_audio_valid(audio_valid),.O_audio_left_data(audio_left),.O_audio_right_data(audio_right));
wire [23:0] wrgb,old_wrgb,srgb,old_srgb;
wire wh,wv,wd,visible,oh,ov,od,old_visible,sh,sv,sd,osh,osv,osd,ack,old_ack;
wire spectrum_write,result_done;
wire [7:0] spectrum_address;
wire [6:0] spectrum_height;
audio_waveform_overlay wave(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb_in(rgb_in),.voice_mode(1'b0),
    .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),.requested_visible(1'b1),
    .panel_visible(visible),.hs_out(wh),.vs_out(wv),.de_out(wd),.rgb_out(wrgb));
voice_baseline_wave old_wave(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb_in(rgb_in),
    .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),.requested_visible(1'b1),
    .panel_visible(old_visible),.hs_out(oh),.vs_out(ov),.de_out(od),.rgb_out(old_wrgb));
audio_fft1024 fft(.clk(clk),.rst(rst),.audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
    .result_ack(ack),.spectrum_write(spectrum_write),.spectrum_address(spectrum_address),.spectrum_height(spectrum_height),
    .result_done(result_done),.capture_start(),.bin_valid(),.bin_channel(),.bin_number(),.bin_magnitude());
audio_spectrum_overlay spectrum(.clk(clk),.rst(rst),.hs(wh),.vs(wv),.de(wd),.rgb_in(wrgb),.voice_mode(1'b0),
    .panel_visible(visible),.audio_valid(audio_valid),.spectrum_write(spectrum_write),.spectrum_address(spectrum_address),.spectrum_height(spectrum_height),
    .result_done(result_done),.result_ack(ack),.hs_out(sh),.vs_out(sv),.de_out(sd),.rgb_out(srgb));
voice_baseline_spectrum old_spectrum(.clk(clk),.rst(rst),.hs(oh),.vs(ov),.de(od),.rgb_in(old_wrgb),
    .panel_visible(old_visible),.audio_valid(audio_valid),.spectrum_write(spectrum_write),.spectrum_address(spectrum_address),.spectrum_height(spectrum_height),
    .result_done(result_done),.result_ack(old_ack),.hs_out(osh),.vs_out(osv),.de_out(osd),.rgb_out(old_srgb));
wire draw,old_draw;
wire [23:0] footer_rgb,old_footer_rgb;
sound_theme_footer footer(.clk(clk),.rst(rst),.vs(vs),.de(de),.x(x),.y(y),.lesson_idx(lesson),
    .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),.draw(draw),.rgb(footer_rgb));
voice_baseline_footer old_footer(.clk(clk),.rst(rst),.vs(vs),.de(de),.x(x),.y(y),.lesson_idx(lesson),
    .audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),.draw(old_draw),.rgb(old_footer_rgb));
wire frame_tick,scene_clear,axis_user,axis_valid,axis_last;
wire old_tick,old_clear,old_user,old_valid,old_last;
wire [6:0] read_column,old_column;
wire [5:0] read_band,old_band;
wire [11:0] xy_read_address,old_xy;
wire [23:0] axis_data,old_data;
wire [79:0] shown_feature=80'h81130123400010000000;
secondary_audio_renderer secondary(.clk(clk),.rst(rst),.lesson(lesson),.lesson_valid(1'b1),.video_locked(1'b1),
    .heat_q(4'd10),.trace_q(8'h94),.shown_head(7'd110),.shown_count(7'd96),.shown_feature(shown_feature),.shown_right(1'b0),
    .peak_left(8'd100),.peak_right(8'd70),.average_left(8'd40),.average_right(8'd30),.harmonic_heights(30'h12345678),
    .harmonic_valid(1'b1),.xy_q(1'b1),.xy_visible(1'b1),.*);
voice_baseline_secondary old_secondary(.clk(clk),.rst(rst),.lesson(lesson),.lesson_valid(1'b1),.video_locked(1'b1),
    .heat_q(4'd10),.trace_q(8'h94),.shown_head(7'd110),.shown_count(7'd96),.shown_feature(shown_feature),.shown_right(1'b0),
    .peak_left(8'd100),.peak_right(8'd70),.average_left(8'd40),.average_right(8'd30),.harmonic_heights(30'h12345678),
    .harmonic_valid(1'b1),.xy_q(1'b1),.xy_visible(1'b1),.frame_tick(old_tick),.scene_clear(old_clear),
    .read_column(old_column),.read_band(old_band),.xy_read_address(old_xy),
    .axis_user(old_user),.axis_valid(old_valid),.axis_last(old_last),.axis_data(old_data));
always @(posedge clk) if(!rst) begin
    #2;cycles=cycles+1;
    if({wh,wv,wd,wrgb,visible,sh,sv,sd,srgb,ack}!=={oh,ov,od,old_wrgb,old_visible,osh,osv,osd,old_srgb,old_ack}) $fatal(1,"Original waveform/spectrum changed page%0d",lesson);
    if({draw,footer_rgb}!=={old_draw,old_footer_rgb}) $fatal(1,"Original footer changed page%0d",lesson);
    if({frame_tick,scene_clear,axis_user,axis_valid,axis_last,axis_data,read_column,read_band,xy_read_address}!==
       {old_tick,old_clear,old_user,old_valid,old_last,old_data,old_column,old_band,old_xy}) $fatal(1,"Original secondary raster changed page%0d",lesson);
    if(de) pixels=pixels+1;
end
integer page;
initial begin
    repeat(8) @(negedge clk);rst=0;
    for(page=0;page<5;page=page+1) begin
        lesson=page;wait(frames==(page+1)*3);@(negedge clk);
    end
    if(pixels!=4608000) $fatal(1,"Five-page pixel coverage incomplete %0d",pixels);
    $display("ALL VOICE COMPATIBILITY TESTS PASSED: 4608000 five-page active pixels exact to 6e58891, waveform, amplitude, stereo FFT, acknowledgement, footer, secondary harmonic/XY layouts and framing");$finish;
end
initial begin #300000000;$fatal(1,"Compatibility timeout");end
endmodule
