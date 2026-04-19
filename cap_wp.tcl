# cap_wp.tcl - connect to already-programmed wide_probe, arm, capture
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set ltx "$proj_dir/claude.runs/impl_1/wide_probe.ltx"
if {[file exists $ltx]} { set_property PROBES.FILE $ltx $dev }
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila

# Trigger on pins_r (8-bit) changing from all-zero idle
set pr [get_hw_probes -of_objects $ila -filter {WIDTH == 8}]
set_property TRIGGER_COMPARE_VALUE neq8'h00 $pr
puts "TRIG: pins_r != 0"

run_hw_ila $ila
puts "ARMED"
if {[catch {wait_on_hw_ila $ila -timeout 25} err]} { puts "ERR: $err" }
set d [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file "$proj_dir/wide_probe.csv" $d -force
puts "CSV_SAVED"
close_hw_target
close_hw_manager
