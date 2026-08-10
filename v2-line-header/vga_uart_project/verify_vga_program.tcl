set script_dir [file normalize [file dirname [info script]]]
set bitstream_file [file join $script_dir vga_uart_project.runs impl_1 top_airDrawing.bit]

open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a35t_0] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bitstream_file $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAM_DONE=1"
close_hw_manager
