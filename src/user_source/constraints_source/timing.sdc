
# ============================================================
# merged_top_tf_hdmi_audio.sdc
# 用于：TF 图片轮播 + HDMI(视频+音频) 整合工程
#
# 合并原则：
# 1) 保留 top.sdc 里的系统主时钟与 derive_clocks
# 2) 把 timing(2).sdc 里的 pixel/serial 时钟改成整合工程实际名字
# 3) 增加 hdmi_5x_clk / audio_mclk 的命名
# 4) 不再对内部 net 直接 create_clock，避免和 derive_clocks 重复
# ============================================================

# ------------------------------------------------------------
# 1. 板级输入主时钟
#    你的原 top.sdc 里 clk=50MHz，所以这里仍然用 20ns
# ------------------------------------------------------------
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]

# ------------------------------------------------------------
# 2. 自动推导 PLL 输出时钟
# ------------------------------------------------------------
derive_clocks

# Fractional SCK is an OUTPUT clock-enable waveform, never a fabric clock.
# SD fans out ONLY to sd_meta (packed into the input PAD by TD). Cutting the
# external port launch covers that first sampler without naming a removed D
# pin. The sd_meta Q -> sd_sync D path remains fully timed in video_clk.
set_false_path -from [get_ports {mic_sd}]

# ------------------------------------------------------------
# 3. 给关键 PLL 输出命名
#    下面这些路径是按你当前工程实例名写的：
#      sys_pll      -> sys_pll_m0
#      video_pll    -> video_pll_m0
#      音频 PLL     -> u_audio_pll
#
#    如果综合后实例路径略有不同，就按 Timing Analyzer 里的实际 pin 路径改。
# ------------------------------------------------------------
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {ext_mem_clk_sft} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[2]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
set_max_delay 10 -from [get_clocks {video_clk}] -to [get_ports {mic_sck mic_ws}]
# Startup-only and frame-stable CDC bundles. Bound ONLY paths launched in
# the source clock, passing these stable source signals and terminating at the
# FIRST destination-clock FF. Subsequent synchronizer stages launch in the
# destination clock, so they do not match these constraints.
#
# Using source bundles survives TD's cross-hierarchy slice packing, which may
# rename a first sampler after an unrelated neighboring LUT. No entire clock
# domain is excluded and no pixel, SDRAM data or FIFO Gray-pointer path matches.
# Keep each SDC command on one physical line for TD's deferred SDC reader.
#
# read_req is held until ack and crosses three FFs. The read-buffer index has
# two FFs and is held for a whole frame; use a finite bound rather than the old
# name-dependent first-pin false path. Geometry has two FFs then a frame latch.
set_max_delay -from [get_clocks {video_clk}] -to [get_clocks {ext_mem_clk}] -through [get_nets -quiet {u_nature_intro_controls/slide* u_nature_intro_controls/photo* u_nature_intro_controls/active* u_nature_intro_controls/visible* video_timing_data_m0/read_req u_video_fade_transition/display_buf_idx*}] 20 -datapath_only -nowarn
# SD control toggles/levels are held until consumed; photo payload additionally
# waits three SD clocks AFTER the synchronized request, beyond its two FFs.
set_max_delay -from [get_clocks {video_clk ext_mem_clk}] -to [get_clocks {sd_card_clk}] -through [get_nets -quiet {u_nature_intro_controls/exit_request u_nature_intro_controls/autoplay u_nature_intro_controls/audio_request u_nature_intro_controls/audio_photo* u_nature_intro_controls/teaching_next u_nature_intro_controls/teaching_auto frame_write_toggle_mem sd_card_bmp_m0/write_finish_toggle}] 20 -datapath_only -nowarn
# Video handshakes are stable levels/toggles, each with two sampling FFs.
set_max_delay -from [get_clocks {sd_card_clk}] -to [get_clocks {video_clk}] -through [get_nets -quiet {intro_assets_ready intro_owner intro_audio_ack sd_card_bmp_m0/u_intro_loader/assets_ready sd_card_bmp_m0/u_intro_loader/owner sd_card_bmp_m0/g_intro_audio$u_wav/ack_toggle sd_card_bmp_m0/g_intro_audio$u_wav/play_ready}] 39 -datapath_only -nowarn
# Science audio remains in video_clk; original audio PLL supplies reset lock.

# ------------------------------------------------------------
# 4. 从原 timing(2).sdc 迁移过来的 HDMI 像素/串行时钟约束
#
#    原文件是：
#      create_clock -name pixel_clk  ... [get_nets {S_pixel_clk}]
#      create_clock -name serial_clk ... [get_nets {S_serial_clk}]
#      set_clock_groups -exclusive ...
#
#    在整合工程里，这两个时钟已经由 video_pll 产生，并通过 derive_clocks 建出来了，
#    所以这里只保留“组关系”，不再重复 create_clock。
#
#    这里沿用原作者的写法，把 video_clk 和 hdmi_5x_clk 设成 exclusive。
#    如果后面 Timing Analyzer 明确显示两者之间需要做同步时序分析，再把这一条去掉。
# ------------------------------------------------------------
set_clock_groups -exclusive \
    -group [get_clocks {video_clk}] \
    -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 5. 音频 I2S 发生器/接收器跨域
#
#    audio_mclk 域里生成 I2S，video_clk 域里做三拍同步采样。
#    这类路径不是普通同步时序路径，直接切掉更合理。
# ------------------------------------------------------------
# No active audio_mclk/video_clk crossing remains in the science audio source.

# ------------------------------------------------------------
# 6. 可选：如果你的 frame_read_write 内部异步 FIFO 已经完全处理好了跨域，
#    且报告里总出现 video_clk / sd_card_clk / ext_mem_clk 之间的大量伪违例，
#    可以打开下面这组异步分组。
#
#    建议先不要开，先看报告；
#    只有确认这些跨域都只经过 FIFO / 同步器时再开。
# ------------------------------------------------------------
# set_clock_groups -asynchronous \
#     -group [get_clocks {sd_card_clk}] \
#     -group [get_clocks {ext_mem_clk}] \
#     -group [get_clocks {video_clk}] \
#     -group [get_clocks {hdmi_5x_clk}]

# ------------------------------------------------------------
# 7. 其余 Input/Output delay 先保持空白
#    你当前两个原始 sdc 也都没有写这部分。
# ------------------------------------------------------------
