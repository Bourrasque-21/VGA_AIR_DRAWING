set project_dir [file normalize [file dirname [info script]]]
open_project [file join $project_dir vga_uart_project.xpr]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL_STATUS=[get_property STATUS [get_runs impl_1]]"
open_run impl_1
report_utilization -file [file join $project_dir vga_impl_util.rpt]
report_timing_summary -file [file join $project_dir vga_impl_timing.rpt]
close_project
