onerror {quit -code 1 -force}
if {![file exists work]} {vlib work}
vlog -work work ../src/user_source/hdl_source/SD/bmp_bilinear_reader.v tb_bmp_bilinear_reader.sv
vsim -c -voptargs=+acc work.tb_bmp_bilinear_reader
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
