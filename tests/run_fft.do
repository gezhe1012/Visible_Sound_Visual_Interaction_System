onerror {quit -code 1 -force}
if {![file exists fft_work]} {vlib fft_work}
vlog -work fft_work ../src/user_source/hdl_source/science_audio_i2s.v ../src/user_source/hdl_source/I2S_receiver.v
vlog -work fft_work ../src/user_source/hdl_source/fft1024_tables.v ../src/user_source/hdl_source/audio_fft1024.v ../src/user_source/hdl_source/audio_spectrum_overlay.v ../src/user_source/hdl_source/audio_waveform_overlay.v ../src/user_source/hdl_source/waveform_key_control.v ../src/user_source/hdl_source/video_osd_overlay.v ../src/user_source/hdl_source/video_rgb_to_axis_640x480.v tb_fft1024.sv tb_sound_analysis.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_fft1024}
vsim -c -voptargs=+acc -L fft_work fft_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
