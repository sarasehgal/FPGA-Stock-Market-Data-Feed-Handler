# cap_wide.tcl - connect, arm with pins_r!=0 trigger, short timeout, save CSV
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
if {$ila eq ""} { puts "NO_ILA"; exit 1 }
puts "ILA: $ila"
foreach p [get_hw_probes -of_objects $ila] {
    puts "  PROBE: $p  width=[get_property WIDTH $p]"
}

set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila

# Simple trigger: the 8-bit pins_r probe != 0 (K16 always toggles so fires immediately)
set pr [get_hw_probes pins_r -of_objects $ila]
# There may be multiple pins_r* — pick the 8-bit one
foreach p [get_hw_probes -of_objects $ila] {
    if {[string first pins_r $p] >= 0 && [get_property WIDTH $p] == 8} {
        set pr $p
    }
}
# Ignore K16 (bit 1, toggles constantly). Trigger when any other pin leaves idle.
# Idle pattern ignoring K16: 1011_01X1
set_property TRIGGER_COMPARE_VALUE {neq8'b101101X1} $pr
puts "TRIG: $pr != 101101X1 (any non-K16 pin changed)"
set_property CONTROL.TRIGGER_POSITION 128 $ila

run_hw_ila $ila
puts "ILA_ARMED"

if {[catch {wait_on_hw_ila $ila -timeout 30} err]} {
    puts "WAIT_ERR: $err"
}

set ila_data [upload_hw_ila_data $ila]
set csv "$proj_dir/wide_probe.csv"
write_hw_ila_data -csv_file $csv $ila_data -force
puts "CSV_SAVED: $csv"

close_hw_target
close_hw_manager
puts "ALL_DONE"
