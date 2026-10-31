set test_dir [file dirname [file normalize [info script]]]
set runs [file normalize [file join $test_dir ../src/td_project/HDMI1.4b_Transmitter_v1.0_Runs]]
cd [file join $runs phy_1]
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj -noanalyze
import_db HDMI1.4b_Transmitter_v1.0_pr.db
update_timing
puts "BUNDLE NETS [get_nets -quiet {u_nature_intro_controls/slide* u_nature_intro_controls/photo* u_nature_intro_controls/active* u_nature_intro_controls/visible* video_timing_data_m0/read_req u_video_fade_transition/display_buf_idx*}]"
set_max_delay -from [get_clocks {video_clk}] -to [get_clocks {ext_mem_clk}] -through [get_nets -quiet {u_nature_intro_controls/slide* u_nature_intro_controls/photo* u_nature_intro_controls/active* u_nature_intro_controls/visible* video_timing_data_m0/read_req u_video_fade_transition/display_buf_idx*}] 20 -datapath_only -nowarn
update_timing
report_timing_summary -file [file join $test_dir ../doc/nature_intro/attempts/nature_bundle_probe_timing.txt]
report_timing_exception -file [file join $test_dir ../doc/nature_intro/attempts/nature_bundle_probe_exceptions.txt]
