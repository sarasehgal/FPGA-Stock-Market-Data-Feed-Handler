# cap_live.tcl - connect to programmed stock_feed_synth, arm, short wait, save CSV
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev

set ltx "$proj_dir/claude.runs/impl_1/stock_feed_synth.ltx"
if {[file exists $ltx]} { set_property PROBES.FILE $ltx $dev }
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
if {$ila eq ""} { puts "NO_ILA"; exit 1 }
puts "ILA: $ila"
foreach p [get_hw_probes -of_objects $ila] {
    puts "  PROBE: $p width=[get_property WIDTH $p]"
}

set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila

# Trigger: rmii_rxd_vec != 2'b00 (frame preamble arrival)
set crs [get_hw_probes u_top/dbg_crs_dv_synth -of_objects $ila]
set_property TRIGGER_COMPARE_VALUE eq1'b1 $crs
puts "TRIG: $crs == 1 (CRS_DV high)"

run_hw_ila $ila
puts "ILA_ARMED"

if {[catch {wait_on_hw_ila $ila -timeout 20} err]} { puts "WAIT_ERR: $err" }

if {[catch {set ila_data [upload_hw_ila_data $ila]} err]} {
    puts "UPLOAD_ERR: $err"
} else {
    write_hw_ila_data -csv_file "$proj_dir/real_capture.csv" $ila_data -force
    puts "CSV_SAVED"
}

close_hw_target
close_hw_manager
puts "ALL_DONE"
