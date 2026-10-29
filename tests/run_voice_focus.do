onerror {quit -code 1 -force}
if {![file exists voice_display_work]} {vlib voice_display_work}
set h ../src/user_source/hdl_source
vlog -work voice_display_work $h/audio_spectrum_overlay.v $h/secondary_audio_renderer.v $h/secondary_font5x7.v voice_baseline_focus_secondary.v tb_voice_focus.sv
vsim -c -voptargs=+acc -L voice_display_work voice_display_work.tb_voice_focus
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
