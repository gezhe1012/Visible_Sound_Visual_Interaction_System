onerror {quit -code 1 -force}
if {![file exists voice_work]} {vlib voice_work}
vlog -work voice_work ../src/user_source/hdl_source/inmp441_i2s_rx.v ../src/user_source/hdl_source/voice_analysis_source.v tb_voice_input.sv
vlog -work voice_work ../src/user_source/hdl_source/SD/sd_card_bmp.v ../src/user_source/hdl_source/video_fade_transition.v ../src/user_source/hdl_source/science_audio_i2s.v tb_five_page_player.sv tb_six_page_player.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_voice_input}
vsim -c -voptargs=+acc -L voice_work voice_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
