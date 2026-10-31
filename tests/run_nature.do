onerror {quit -code 1 -force}
if {![file exists nature_work]} {vlib nature_work}
set h ../src/user_source/hdl_source
vlog -work nature_work $h/nature_intro_controls.v $h/waveform_key_control.v $h/nature_intro_address.v $h/SD/nature_intro_loader.v $h/SD/nature_wav_player.v $h/IP/afifo_16_32_256.v tb_nature_controls.sv tb_nature_address.sv tb_nature_loader.sv tb_nature_wav.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_nature_controls}
vlog -work nature_work $h/SD/bmp_bilinear_reader.v $h/IP/afifo_32_16_256.v $h/SD/frame_fifo_read.v $h/SD/frame_fifo_write.v $h/SD/frame_read_write.v tb_nature_card.sv tb_nature_bandwidth.sv
vlog -work nature_work $h/sound_theme_footer.v $h/video_osd_overlay.v tb_nature_preview.sv
vsim -c -voptargs=+acc -L nature_work nature_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
