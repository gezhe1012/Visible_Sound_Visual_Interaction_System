// Independent video-only instance of the EXISTING vendor HDMI transmitter.
// Pixel/serial clocks are shared with HDMI_B; no additional PLL or audio path.
module secondary_hdmi_tx(
    input pixel_clk,serial_clk,rst,
    input [2:0] lesson,
    input lesson_valid,edid_trigger,
    input audio_valid,
    input [23:0] audio_left,audio_right,
    input capture_start,bin_valid,bin_channel,
    input [8:0] bin_number,
    input [16:0] bin_magnitude,
    input spectrum_write,result_done,
    input [7:0] spectrum_address,
    input [6:0] spectrum_height,
    output tmds_clk_p,tmds_d2_p,tmds_d1_p,tmds_d0_p,
    output ddc_scl,
    inout ddc_sda
);
wire user,valid,last,ready,locked;
wire [23:0] rgb;
wire [9:0] ch0,ch1,ch2,clock_data;
wire frame_tick,scene_clear,shown_right;
wire [6:0] read_column,shown_head,shown_count;
wire [5:0] read_band;
wire [3:0] heat_q;
wire [7:0] trace_q,peak_left,peak_right,average_left,average_right;
wire [79:0] shown_feature;
secondary_feature_store features(
    .clk(pixel_clk),.rst(rst),.frame_tick(frame_tick),.scene_clear(scene_clear),
    .lesson(lesson),.lesson_valid(lesson_valid),.audio_valid(audio_valid),.audio_left(audio_left),.audio_right(audio_right),
    .capture_start(capture_start),.bin_valid(bin_valid),.bin_channel(bin_channel),.bin_number(bin_number),.bin_magnitude(bin_magnitude),
    .spectrum_write(spectrum_write),.result_done(result_done),.spectrum_address(spectrum_address),.spectrum_height(spectrum_height),
    .read_column(read_column),.read_band(read_band),.heat_q(heat_q),.trace_q(trace_q),
    .shown_head(shown_head),.shown_count(shown_count),.shown_feature(shown_feature),.shown_right(shown_right),
    .peak_left(peak_left),.peak_right(peak_right),.average_left(average_left),.average_right(average_right)
);
secondary_audio_renderer renderer(
    .clk(pixel_clk),.rst(rst),.lesson(lesson),.lesson_valid(lesson_valid),.video_locked(locked),
    .heat_q(heat_q),.trace_q(trace_q),.shown_head(shown_head),.shown_count(shown_count),.shown_feature(shown_feature),
    .shown_right(shown_right),.peak_left(peak_left),.peak_right(peak_right),.average_left(average_left),.average_right(average_right),
    .frame_tick(frame_tick),.scene_clear(scene_clear),.read_column(read_column),.read_band(read_band),
    .axis_user(user),.axis_valid(valid),.axis_last(last),.axis_data(rgb)
);
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
    .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),
    .VIDEO_VIC(1),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),
    .AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)
) transmitter(
    .I_pixel_clk(pixel_clk),.I_rst(rst),.I_edid_read_trig(edid_trigger),
    .O_edid_read_valid(),.O_edid_read_data(),
    .I_axis_s_user(user),.I_axis_s_valid(valid),.I_axis_s_last(last),.I_axis_s_data(rgb),.O_axis_s_ready(ready),
    .I_audio_valid(1'b0),.I_audio_left_data(24'd0),.I_audio_right_data(24'd0),
    .I_acr_valid(1'b0),.I_acr_cts(20'd0),.I_acr_n(20'd0),
    .O_video_locked(locked),.O_ddc_scl(ddc_scl),.IO_ddc_sda(ddc_sda),
    .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(clock_data)
);
// Original vendor reference PHY, including its verified bit order and ODDR.
hdmi_phy_wrapper #(.DEVICE("EG")) phy(
    .I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst),
    .I_tmds_channel_0(ch0),.I_tmds_channel_1(ch1),.I_tmds_channel_2(ch2),.I_tmds_channel_clk(clock_data),
    .O_tmds_ch0_p(tmds_d0_p),.O_tmds_ch1_p(tmds_d1_p),.O_tmds_ch2_p(tmds_d2_p),.O_tmds_clk_p(tmds_clk_p)
);
endmodule
