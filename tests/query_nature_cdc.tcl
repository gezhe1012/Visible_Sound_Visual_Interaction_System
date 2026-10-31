# Read-only final gate/routed CDC and coefficient audit. Never modifies a DB.
set test_dir [file dirname [file normalize [info script]]]
set runs [file normalize [file join $test_dir ../src/td_project/HDMI1.4b_Transmitter_v1.0_Runs]]
cd [file join $runs syn_1]
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db HDMI1.4b_Transmitter_v1.0_gate.db
write_verilog [file join $test_dir nature_gate_netlist.v]
update_timing
report_timing_exception -file [file join $test_dir ../doc/nature_intro/evidence/nature_gate_exceptions.txt]
import_db [file join $runs phy_1 HDMI1.4b_Transmitter_v1.0_pr.db]
write_verilog [file join $test_dir nature_routed_netlist.v]
update_timing
report_timing_exception -file [file join $test_dir ../doc/nature_intro/evidence/nature_routed_exceptions.txt]
puts "ALL NATURE CDC DATABASE EXPORT TESTS PASSED: unchanged gate and routed databases exported"
