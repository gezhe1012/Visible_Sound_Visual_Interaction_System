onerror {quit -code 1 -force}
if {![file exists ticker_work]} {vlib ticker_work}
vlog -work ticker_work ../src/user_source/hdl_source/sound_theme_footer.v ../src/user_source/hdl_source/video_osd_overlay.v video_osd_overlay_baseline.v tb_theme_ticker.sv tb_ticker_animation.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_theme_ticker}
vsim -c -voptargs=+acc -L ticker_work ticker_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
