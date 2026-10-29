onerror {quit -code 1 -force}
if {![file exists voice_compat_work]} {vlib voice_compat_work}
set h ../src/user_source/hdl_source
vlog -work voice_compat_work $h/science_audio_i2s.v $h/I2S_receiver.v $h/audio_waveform_overlay.v $h/audio_spectrum_overlay.v $h/audio_fft1024.v $h/fft1024_tables.v $h/sound_theme_footer.v $h/secondary_audio_renderer.v $h/secondary_font5x7.v voice_baseline_wave.v voice_baseline_spectrum.v voice_baseline_footer.v voice_baseline_secondary.v tb_voice_compat.sv
vsim -c -voptargs=+acc -L voice_compat_work voice_compat_work.tb_voice_compat
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
