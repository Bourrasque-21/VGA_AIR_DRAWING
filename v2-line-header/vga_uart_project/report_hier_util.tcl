set script_dir [file normalize [file dirname [info script]]]
open_checkpoint [file join $script_dir vga_uart_project.runs impl_1 top_airDrawing_routed.dcp]
report_utilization -hierarchical -hierarchical_depth 6 -file [file join $script_dir hier_util.rpt]
close_design
