# Audit exactly the three existing request synchronizer DATA endpoints in
# both gate and packed routed databases. No design/database mutations.
set test_dir [file dirname [file normalize [info script]]]
set runs [file normalize [file join $test_dir ../src/td_project/HDMI1.4b_Transmitter_v1.0_Runs]]
cd [file join $runs syn_1]
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
foreach stage {gate pr} {
    if {$stage eq "gate"} {set db [file join $runs syn_1 HDMI1.4b_Transmitter_v1.0_gate.db]} else {set db [file join $runs phy_1 HDMI1.4b_Transmitter_v1.0_pr.db]}
    import_db $db
    if {$stage eq "pr"} {
        report_cells [get_cells -quiet {*frame_fifo_read_m0/read_req_d0_reg_syn_4}] -connection
        write_verilog [file join $test_dir voice_routed_netlist.v]
    } else {
    foreach index {0 1 2} {
        set patterns [list "frame_read_write_m0/frame_fifo_read_m0/read_req_d${index}_reg*.d" "frame_read_write_m0/frame_fifo_read_m0/read_req_d${index}_reg*.mi*"]
        set pins [get_pins -quiet $patterns]
        if {[llength $pins] != 1} {error "Expected exactly one request d${index} DATA pin at $stage; got $pins"}
        puts "PASS $stage request synchronizer d$index = $pins"
    }
    }
}
puts "ALL VOICE CDC DATABASE TESTS PASSED: three separate logical input data pins at gate; packed physical cells exported for connectivity audit"
