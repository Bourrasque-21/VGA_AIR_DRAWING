set script_dir [file normalize [file dirname [info script]]]
open_checkpoint [file join $script_dir vga_uart_project.runs synth_1 top_airDrawing.dcp]
puts "PORT_COUNT=[llength [get_ports]]"
puts "CELL_COUNT=[llength [get_cells -hierarchical]]"
puts "HAS_CLK=[llength [get_ports clk]]"
close_design
