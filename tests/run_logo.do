onerror {quit -code 1 -force}
if {![file exists voice_display_work]} {vlib voice_display_work}
set h ../src/user_source/hdl_source
vlog -work voice_display_work $h/sound_theme_footer.v $h/video_osd_overlay.v voice_baseline_logo_osd.v tb_logo_osd.sv
vsim -c -voptargs=+acc -L voice_display_work voice_display_work.tb_logo_osd
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
