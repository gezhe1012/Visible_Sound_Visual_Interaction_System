# Placement-only TimingMedium preset documented in TD's official strategy
# JSON, followed by the normal route/hold-fix/bitgen. Reuses unchanged RTL,
# clocks and timing constraints. Deliberately no post-route phys_opt command.
source ./settings.cfg
set phyWildParams {place opt_timing high place logic_level_opt on place aggressive_opt 20 place enhanced_beeline_opt 3 place post_place_opt high}
set td_root [file dirname [file dirname [info nameofexecutable]]]
source [file join $td_root doc scripts DefaultFlow.tcl]
