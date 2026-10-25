onerror {quit -code 1 -force}
if {![file exists science_work]} {vlib science_work}
vlog -work science_work ../src/user_source/hdl_source/video_rgb_to_axis_640x480.v ../src/user_source/hdl_source/science_audio_i2s.v ../src/user_source/hdl_source/I2S_receiver.v ../src/user_source/hdl_source/audio_waveform_overlay.v ../src/user_source/hdl_source/video_fade_transition.v tb_video_axis_framing.sv tb_science_audio.sv tb_science_fade.sv
vlog -work science_work ../src/user_source/hdl_source/SD/bmp_bilinear_reader.v tb_science_card.sv
vlog -work science_work ../src/user_source/hdl_source/IP/afifo_16_32_256.v ../src/user_source/hdl_source/IP/afifo_32_16_256.v ../src/user_source/hdl_source/SD/frame_fifo_write.v ../src/user_source/hdl_source/SD/frame_fifo_read.v ../src/user_source/hdl_source/SD/frame_read_write.v tb_science_frame_bandwidth.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_video_axis_framing}
vsim -c -voptargs=+acc -L science_work science_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
