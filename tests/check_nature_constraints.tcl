# Fail on malformed/empty CDC constraints before a multi-minute implementation.
set test_dir [file dirname [file normalize [info script]]]
set runs [file normalize [file join $test_dir ../src/td_project/HDMI1.4b_Transmitter_v1.0_Runs]]
cd [file join $runs syn_1]
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db HDMI1.4b_Transmitter_v1.0_gate.db
read_sdc ../../../user_source/constraints_source/timing.sdc
update_timing
report_timing_exception -file [file join $test_dir ../doc/nature_intro/evidence/nature_gate_exceptions.txt]
set geometry [get_pins -quiet {frame_read_write_m0/g_intro_map$u_address/p0_reg*.d frame_read_write_m0/g_intro_map$u_address/s0_reg*.d frame_read_write_m0/intro_meta_reg*.d}]
if {[llength $geometry]!=9} {error "Expected nine geometry first D pins, got $geometry"}
puts "PASS NATURE GEOMETRY FIRST STAGE: $geometry"
puts "ALL NATURE CDC CONSTRAINT TESTS PASSED: bounded first-stage data paths only"
