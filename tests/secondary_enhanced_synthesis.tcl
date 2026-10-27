# Official area-oriented mapping options; no RTL, clock or SDC exceptions.
source ./settings.cfg
set synWildParams {gate opt_area high gate pack_effort high}
set td_root [file dirname [file dirname [info nameofexecutable]]]
source [file join $td_root doc scripts DefaultFlow.tcl]
