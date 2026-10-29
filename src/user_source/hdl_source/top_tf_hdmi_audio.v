
module top(
    input                       clk,
    input                       rst_n,          // Board KEY1 / A2: reset (unchanged)
    input                       key1,           // Board KEY2 / B2: next / brightness (unchanged)
    input                       key2,           // Board KEY4 / C1: autoplay / contrast (unchanged)
    input                       key3,           // Board KEY3 / B1: analysis panel toggle
    output                      mic_sck,        // J1-31 / M15, INMP441 SCK
    output                      mic_ws,         // J1-32 / L16, INMP441 WS
    input                       mic_sd,         // J1-33 / N16, INMP441 SD; L/R tied low

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // Independent HDMI_A output; handbook p8. HDMI_B above is unchanged.
    output                      HDMIA_CLK_P,
    output                      HDMIA_D2_P,
    output                      HDMIA_D1_P,
    output                      HDMIA_D0_P,
    output                      HDMIA_DDC_SCL,
    inout                       HDMIA_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire [23:0] vout_data_faded;
wire [23:0] vout_data_osd;
wire [23:0] vout_data_adjusted;
wire hs_adjusted,vs_adjusted,de_adjusted;
wire [23:0] vout_data_waveform;
wire hs_waveform,vs_waveform,de_waveform;
wire waveform_requested_visible;
wire analysis_panel_visible;
wire [23:0] vout_data_analysis;
wire hs_analysis,vs_analysis,de_analysis;
wire spectrum_write,spectrum_done,spectrum_ack;
wire [7:0] spectrum_address;
wire [6:0] spectrum_height;
wire [6:0] displayed_spectrum_height;
wire signed [8:0] display_brightness;
wire [2:0] display_contrast_q2;
wire [1:0] display_active_control;
wire next_key_toggle,auto_key_toggle;
wire        sd_display_valid;

// OSD / transition extension signals
wire        transition_start_toggle;
wire [1:0]  transition_buf_idx;
wire [2:0] transition_lesson_idx,display_lesson_idx;
wire melody_complete;
wire        transition_done_toggle;
wire [1:0]  video_disp_buf_idx;
wire        transition_display_valid;
wire [4:0]  transition_fade_level;
wire [12:0] fade_r_product;
wire [12:0] fade_g_product;
wire [12:0] fade_b_product;

wire [3:0]  state_code;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        sd_card_write_ready;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  sd_disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire rst_all;
wire mic_ready,mic_valid,mic_active,mic_clipped;
wire signed [23:0] mic_pcm;
wire [3:0] mic_gain_shift;
wire analysis_valid,source_clear;
wire [23:0] analysis_left,analysis_right;
wire voice_page=display_lesson_idx==5;
wire analysis_reset=rst_all | source_clear;
wire [23:0] voice_background,picture_background;
inmp441_i2s_rx u_inmp441_i2s_rx(
    .clk(video_clk),.rst(rst_all),.mic_sd(mic_sd),.mic_sck(mic_sck),.mic_ws(mic_ws),
    .mic_pcm(mic_pcm),.mic_valid(mic_valid),.ready(mic_ready));
voice_analysis_source u_voice_source(
    .clk(video_clk),.rst(rst_all),.lesson(display_lesson_idx),.lesson_valid(transition_display_valid),
    .dds_valid(audio_valid),.dds_left(audio_left_data),.dds_right(audio_right_data),
    .mic_valid(mic_valid),.mic_pcm(mic_pcm),.analysis_valid(analysis_valid),
    .analysis_left(analysis_left),.analysis_right(analysis_right),.source_clear(source_clear),
    .active(mic_active),.clipped(mic_clipped),.gain_shift(mic_gain_shift));
live_voice_background u_voice_background(
    .clk(video_clk),.rst(rst_all),.vs(vs),.de(de),.ready(mic_ready),.active(mic_active),
    .clipped(mic_clipped),.panel_visible(waveform_requested_visible),.rgb(voice_background));
assign picture_background=voice_page ? voice_background : vout_data_raw;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
assign rst_all = ~rst_n | ~audio_pll_lock;

// 保持你原来的 TF / SDRAM / video 时钟
science_sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .reset      (1'b0)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000),
    .SCAN_START_SECTOR (32'd0),
    .SCAN_MAX_SECTOR   (32'd131071),
    .SCAN_TARGET_COUNT (3'd5),
    .KEY_EVENT_MODE    (1),
    .AUTO_PLAY_SECONDS (8),
    .WAIT_MELODY_END   (1),
    .LIVE_VOICE_PAGE   (1)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_all),
    .key_next          (next_key_toggle),
    .key_auto          (auto_key_toggle),
    .melody_complete   (melody_complete),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (sd_display_valid),

    .transition_done_toggle (transition_done_toggle),
    .transition_start_toggle(transition_start_toggle),
    .transition_buf_idx     (transition_buf_idx),
    .transition_lesson_idx  (transition_lesson_idx),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (sd_disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_ready       (sd_card_write_ready),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,7'b1111_111}),
    .seg_data_1        ({1'b1,7'b1111_111}),
    .seg_data_2        ({1'b1,7'b1111_111}),
    .seg_data_3        ({1'b1,7'b1111_111}),
    .seg_data_4        ({1'b1,7'b1111_111}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// Extension 4: short/long key gestures, frame-atomic parameters and RGB pipeline.
display_key_controls u_display_key_controls (
    .clk(video_clk), .rst(rst_all), .vs(vs), .key1(key1), .key2(key2),
    .next_toggle(next_key_toggle), .auto_toggle(auto_key_toggle),
    .brightness(display_brightness), .contrast_q2(display_contrast_q2),
    .active_control(display_active_control)
);
video_picture_adjust u_video_picture_adjust (
    .clk(video_clk), .rst(rst_all), .hs(hs), .vs(vs), .de(de),
    .rgb_in(picture_background), .brightness(display_brightness),
    .contrast_q2(display_contrast_q2), .hs_out(hs_adjusted),
    .vs_out(vs_adjusted), .de_out(de_adjusted), .rgb_out(vout_data_adjusted)
);

// ===================== 扩展要求2：双缓冲淡出/淡入转场 =====================
video_fade_transition #(
    .FADE_FRAMES       (16),
    .BLACK_HOLD_FRAMES (2)
) u_video_fade_transition (
    .clk                     (video_clk),
    .rst                     (rst_all),
    .vs                      (vs),
    .request_toggle_async    (transition_start_toggle),
    .request_buf_idx_async   (transition_buf_idx),
    .request_lesson_idx_async(transition_lesson_idx),
    .display_lesson_idx      (display_lesson_idx),
    .display_buf_idx         (video_disp_buf_idx),
    .display_valid           (transition_display_valid),
    .fade_level              (transition_fade_level),
    .done_toggle             (transition_done_toggle)
);

// 4-bit brightness coefficient: 0/16 ... 16/16.
assign fade_r_product = vout_data_adjusted[23:16] * transition_fade_level;
assign fade_g_product = vout_data_adjusted[15:8]  * transition_fade_level;
assign fade_b_product = vout_data_adjusted[7:0]   * transition_fade_level;
assign vout_data_faded = transition_display_valid ?
                         {fade_r_product[11:4], fade_g_product[11:4], fade_b_product[11:4]} :
                         24'h000000;

// Extension 5: listen to the existing video-clock PCM stream, without changing
// the I2S generator/receiver, ACR or HDMI audio ports. Waveform is outside fade.
waveform_key_control u_waveform_key_control (
    .clk(video_clk), .rst(rst_all), .key3(key3),
    .requested_visible(waveform_requested_visible)
);
audio_waveform_overlay u_audio_waveform_overlay (
    .clk(video_clk), .rst(analysis_reset),.voice_mode(voice_page),
    .hs(hs_adjusted), .vs(vs_adjusted), .de(de_adjusted),
    .rgb_in(vout_data_faded), .audio_valid(analysis_valid),
    .requested_visible(waveform_requested_visible),
    .panel_visible(analysis_panel_visible),
    .audio_left(analysis_left), .audio_right(analysis_right),
    .hs_out(hs_waveform), .vs_out(vs_waveform), .de_out(de_waveform),
    .rgb_out(vout_data_waveform)
);

// Passive stereo PCM tap: neither capture nor FFT can stall HDMI audio.
wire fft_capture_start,fft_bin_valid,fft_bin_channel;
wire [8:0] fft_bin_number;
wire [16:0] fft_bin_magnitude;
audio_fft1024 u_audio_fft1024 (
    .clk(video_clk),.rst(analysis_reset),.audio_valid(analysis_valid),
    .audio_left(analysis_left),.audio_right(analysis_right),
    .result_ack(spectrum_ack),.spectrum_write(spectrum_write),
    .spectrum_address(spectrum_address),.spectrum_height(spectrum_height),
    .result_done(spectrum_done),.capture_start(fft_capture_start),
    .bin_valid(fft_bin_valid),.bin_channel(fft_bin_channel),
    .bin_number(fft_bin_number),.bin_magnitude(fft_bin_magnitude)
);
// Reuse the waveform's VS-latched switch, not a second KEY3 controller.
// Its VS reaches this stage two clocks later, after panel_visible is stable.
// Remove only sub-8-pixel residual FFT dust on the microphone page. Both
// screens receive the SAME heights; DDS pages and raw FFT bins are untouched.
assign displayed_spectrum_height=(voice_page && spectrum_height<7'd8) ? 7'd0 : spectrum_height;
audio_spectrum_overlay u_audio_spectrum_overlay (
    .clk(video_clk),.rst(analysis_reset),.voice_mode(voice_page),.hs(hs_waveform),.vs(vs_waveform),.de(de_waveform),
    .rgb_in(vout_data_waveform),.panel_visible(analysis_panel_visible),
    .audio_valid(analysis_valid),.spectrum_write(spectrum_write),
    .spectrum_address(spectrum_address),.spectrum_height(displayed_spectrum_height),
    .result_done(spectrum_done),.result_ack(spectrum_ack),
    .hs_out(hs_analysis),.vs_out(vs_analysis),.de_out(de_analysis),.rgb_out(vout_data_analysis)
);

// ===================== 扩展要求1：Alpha OSD、动态时间与滚动字幕 =====================
video_osd_overlay #(
    .PIXEL_CLK_HZ (25_000_000)
) u_video_osd_overlay (
    .clk     (video_clk),
    .rst     (rst_all),
    .hs      (hs_analysis),
    .vs      (vs_analysis),
    .de      (de_analysis),
    .brightness(display_brightness),
    .contrast_q2(display_contrast_q2),
    .active_control(display_active_control),
    .lesson_idx(display_lesson_idx),
    .audio_valid(analysis_valid),.audio_left(analysis_left),.audio_right(analysis_right),
    .rgb_in  (vout_data_analysis),
    .rgb_out (vout_data_osd)
);

assign vout_data = vout_data_osd;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (video_disp_buf_idx),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_ready       (sd_card_write_ready),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：内部 I2S 测试音 =====================
science_audio_i2s u_science_audio_i2s (
    .clk(video_clk), .rst(rst_all),
    .lesson(display_lesson_idx), .enabled(transition_display_valid && !voice_page),
    .bclk(audio_i2s_bclk), .lrck(audio_i2s_lrck), .dout(audio_i2s_dout),
    .sample_tick(), .pcm_left(), .pcm_right(), .lesson_step(), .melody_complete(melody_complete)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (vs_analysis),
    .I_de          (de_analysis),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

// Secondary display: passive features from the SAME PCM/FFT as HDMI_B.
// No new PLL, SDRAM port, PCM consumer control, or path into the main output.
secondary_hdmi_tx u_secondary_hdmi_tx (
    .pixel_clk(video_clk),.serial_clk(hdmi_5x_clk),.rst(rst_all),
    .lesson(display_lesson_idx),.lesson_valid(transition_display_valid),
    .audio_valid(analysis_valid),.audio_left(analysis_left),.audio_right(analysis_right),
    .capture_start(fft_capture_start),.bin_valid(fft_bin_valid),.bin_channel(fft_bin_channel),
    .bin_number(fft_bin_number),.bin_magnitude(fft_bin_magnitude),
    .spectrum_write(spectrum_write),.spectrum_address(spectrum_address),
    .spectrum_height(displayed_spectrum_height),.result_done(spectrum_done),
    .edid_trigger(edid_trig),
    .tmds_clk_p(HDMIA_CLK_P),.tmds_d2_p(HDMIA_D2_P),
    .tmds_d1_p(HDMIA_D1_P),.tmds_d0_p(HDMIA_D0_P),
    .ddc_scl(HDMIA_DDC_SCL),.ddc_sda(HDMIA_DDC_SDA)
);
endmodule
