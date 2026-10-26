onerror {quit -code 1 -force}
if {![file exists controls_work]} {vlib controls_work}
vlog -work controls_work ../src/user_source/hdl_source/sound_theme_footer.v
vlog -work controls_work ../src/user_source/hdl_source/video_picture_adjust.v ../src/user_source/hdl_source/display_key_controls.v ../src/user_source/hdl_source/SD/sd_card_bmp.v ../src/user_source/hdl_source/video_osd_overlay.v tb_sd_card_commit.sv tb_video_picture_adjust.sv tb_display_key_controls.sv tb_osd_display_controls.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_video_picture_adjust}
vsim -c -voptargs=+acc -L controls_work controls_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
