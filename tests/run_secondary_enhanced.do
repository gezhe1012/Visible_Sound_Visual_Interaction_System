onerror {quit -code 1 -force}
if {![file exists enhanced_work]} {vlib enhanced_work}
vlog -work enhanced_work ../src/user_source/hdl_source/secondary_harmonics.v ../src/user_source/hdl_source/secondary_lissajous.v tb_secondary_enhanced.sv
vsim -c -voptargs=+acc -L enhanced_work enhanced_work.tb_secondary_enhanced
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
