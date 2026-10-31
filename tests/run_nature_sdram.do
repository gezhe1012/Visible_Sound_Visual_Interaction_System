onerror {quit -code 1 -force}
if {![file exists nature_sdram_work]} {vlib nature_sdram_work}
set h ../src/user_source/hdl_source
vlog -work nature_sdram_work +define+SIMULATION +incdir+$h/include +incdir+../src/td_project $h/include/sdr_init_ref.enc.v $h/include/sdr_wrrd.enc.v $h/include/sdr_as_ram.enc.v $h/SD/sdram.v tb_nature_sdram_contract.sv
vlog -work nature_sdram_work F:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_sdram_2m_32.v
vsim -c -voptargs=+acc -L nature_sdram_work nature_sdram_work.tb_nature_sdram_contract
onbreak {quit -code 1 -force}
run -all
quit -code 0 -force
