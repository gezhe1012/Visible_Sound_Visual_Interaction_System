# Read-only synthesis database audit. Does not run implementation/bitgen.
set test_dir [file dirname [file normalize [info script]]]
set syn_dir [file normalize [file join $test_dir ../src/td_project/HDMI1.4b_Transmitter_v1.0_Runs/syn_1]]
cd $syn_dir
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db HDMI1.4b_Transmitter_v1.0_gate.db
write_verilog [file join $test_dir fft_gate_netlist.v]
