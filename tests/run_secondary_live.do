onerror {quit -code 1 -force}
if {![file exists secondary_live_work]} {vlib secondary_live_work}
vlog -work secondary_live_work ../src/user_source/hdl_source/science_audio_i2s.v ../src/user_source/hdl_source/I2S_receiver.v ../src/user_source/hdl_source/fft1024_tables.v ../src/user_source/hdl_source/audio_fft1024.v ../src/user_source/hdl_source/secondary_note_thresholds.v ../src/user_source/hdl_source/secondary_pitch_estimator.v ../src/user_source/hdl_source/secondary_feature_store.v ../src/user_source/hdl_source/secondary_font5x7.v ../src/user_source/hdl_source/secondary_audio_renderer.v ../src/user_source/hdl_source/secondary_harmonics.v ../src/user_source/hdl_source/secondary_lissajous.v tb_secondary_live.sv
vsim -c -voptargs=+acc -L secondary_live_work secondary_live_work.tb_secondary_live
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
