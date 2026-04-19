# Build pin test using existing project
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Add pin_test files if needed
if {[get_files -quiet {*pin_test.v}] eq ""} {
    add_files -norecurse [list [file join $proj_dir pin_test.v]]
}
# Disable all other XDCs, enable pin_test.xdc
foreach x [get_files -filter {FILE_TYPE == XDC}] { set_property IS_ENABLED false $x }
set ptxdc [get_files -quiet {*pin_test.xdc}]
if {$ptxdc eq ""} {
    add_files -fileset constrs_1 -norecurse [list [file join $proj_dir pin_test.xdc]]
    set ptxdc [get_files {*pin_test.xdc}]
}
set_property IS_ENABLED true $ptxdc

set_property top pin_test [current_fileset]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "BUILD: [get_property STATUS [get_runs impl_1]]"

set bit [file join $proj_dir {claude.runs/impl_1/pin_test.bit}]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev

puts ""
puts "=== PIN TEST PROGRAMMED ==="
puts "LED[0]   = heartbeat"
puts "LED[7:1] = pin index (binary, 0-11)"
puts "LED[11]  = drive pattern"
puts "LED[15]  = readback of currently driven pin"
puts ""
puts "Pin map:  0=H18 1=G18 2=H16 3=H17 4=K16 5=J16 6=H13 7=H14 8=J15 9=J14 10=G16 11=E16"

close_hw_target
close_hw_manager

# Restore project
foreach x [get_files -filter {FILE_TYPE == XDC && NAME =~ *constraints.xdc}] {
    set_property IS_ENABLED true $x
}
set_property top stock_feed_synth [current_fileset]
