onerror {quit -code 1 -force}
if {![file exists voice_display_work]} {vlib voice_display_work}
set h ../src/user_source/hdl_source
vlog -work voice_display_work $h/inmp441_i2s_rx.v $h/voice_analysis_source.v $h/live_voice_background.v $h/audio_waveform_overlay.v $h/audio_spectrum_overlay.v $h/audio_fft1024.v $h/fft1024_tables.v $h/secondary_pitch_estimator.v $h/secondary_note_thresholds.v $h/secondary_feature_store.v $h/secondary_audio_renderer.v $h/secondary_font5x7.v $h/video_osd_overlay.v $h/sound_theme_footer.v tb_voice_display.sv
vsim -c -voptargs=+acc -L voice_display_work voice_display_work.tb_voice_display
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
