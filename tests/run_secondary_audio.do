onerror {quit -code 1 -force}
if {![file exists secondary_audio_work]} {vlib secondary_audio_work}
vlog -work secondary_audio_work ../src/user_source/hdl_source/fft1024_tables.v ../src/user_source/hdl_source/audio_fft1024.v ../src/user_source/hdl_source/secondary_note_thresholds.v ../src/user_source/hdl_source/secondary_pitch_estimator.v ../src/user_source/hdl_source/secondary_feature_store.v ../src/user_source/hdl_source/secondary_font5x7.v ../src/user_source/hdl_source/secondary_audio_renderer.v tb_secondary_pitch.sv tb_secondary_audio_preview.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_secondary_pitch}
vsim -c -voptargs=+acc -L secondary_audio_work secondary_audio_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
