set project_dir [file normalize [file dirname [info script]]]
open_project [file join $project_dir vga_uart_project.xpr]
set_property top top_airDrawing [get_filesets sources_1]
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH_STATUS=[get_property STATUS [get_runs synth_1]]"
open_run synth_1
report_utilization -file [file join $project_dir vga_synth_util.rpt]
report_timing_summary -file [file join $project_dir vga_synth_timing.rpt]
close_project
