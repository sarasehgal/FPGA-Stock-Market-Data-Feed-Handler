# prog_only.tcl — just program, no ILA
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"
set bit "$proj_dir/claude.runs/impl_1/stock_feed_synth.bit"
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
after 1000
puts "DONE"
close_hw_target
close_hw_manager
