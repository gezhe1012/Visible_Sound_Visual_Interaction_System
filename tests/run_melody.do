onerror {quit -code 1 -force}
if {![file exists melody_work]} {vlib melody_work}
vlog -work melody_work ../src/user_source/hdl_source/science_audio_i2s.v ../src/user_source/hdl_source/I2S_receiver.v ../src/user_source/hdl_source/audio_waveform_overlay.v ../src/user_source/hdl_source/audio_spectrum_overlay.v ../src/user_source/hdl_source/fft1024_tables.v ../src/user_source/hdl_source/audio_fft1024.v tb_melody_audio.sv
vlog -work melody_work ../src/user_source/hdl_source/SD/sd_card_bmp.v ../src/user_source/hdl_source/video_fade_transition.v tb_five_page_player.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_melody_audio}
vsim -c -voptargs=+acc -L melody_work melody_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
