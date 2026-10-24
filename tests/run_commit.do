onerror {quit -code 1 -force}
if {![file exists commit_work]} {vlib commit_work}
vlog -work commit_work ../src/user_source/hdl_source/SD/sd_card_bmp.v tb_sd_card_commit.sv
vsim -c -voptargs=+acc -L commit_work commit_work.tb_sd_card_commit
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
