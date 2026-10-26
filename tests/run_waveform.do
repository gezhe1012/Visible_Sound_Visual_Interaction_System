onerror {quit -code 1 -force}
if {![file exists waveform_work]} {vlib waveform_work}
vlog -work waveform_work ../src/user_source/hdl_source/sound_theme_footer.v
vlog -work waveform_work ../src/user_source/hdl_source/audio_waveform_overlay.v ../src/user_source/hdl_source/waveform_key_control.v ../src/user_source/hdl_source/display_key_controls.v ../src/user_source/hdl_source/video_osd_overlay.v ../src/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v ../src/user_source/hdl_source/I2S_receiver.v tb_audio_waveform.sv tb_waveform_i2s.sv tb_waveform_key3.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_audio_waveform}
vsim -c -voptargs=+acc -L waveform_work waveform_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
