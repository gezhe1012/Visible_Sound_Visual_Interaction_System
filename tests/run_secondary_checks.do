onerror {quit -code 1 -force}
if {![file exists secondary_checks_work]} {vlib secondary_checks_work}
vlog -work secondary_checks_work ../src/user_source/hdl_source/secondary_note_thresholds.v ../src/user_source/hdl_source/secondary_pitch_estimator.v ../src/user_source/hdl_source/secondary_feature_store.v ../src/user_source/hdl_source/secondary_font5x7.v ../src/user_source/hdl_source/secondary_audio_renderer.v tb_secondary_store.sv tb_secondary_renderer.sv
if {![info exists TEST_TOP]} {set TEST_TOP tb_secondary_store}
vsim -c -voptargs=+acc -L secondary_checks_work secondary_checks_work.$TEST_TOP
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
