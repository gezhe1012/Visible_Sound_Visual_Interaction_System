onerror {quit -code 1 -force}
if {![file exists secondary_work]} {vlib secondary_work}
vlog -work secondary_work ../src/user_source/hdl_source/secondary_link_pattern.v tb_secondary_link.sv
vsim -c -voptargs=+acc -L secondary_work secondary_work.tb_secondary_link
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
