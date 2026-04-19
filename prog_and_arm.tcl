# Program the stock_feed_synth bitstream with ILA, arm, and wait
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]

set bit [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.bit}]
set ltx [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.ltx}]

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
if {[file exists $ltx]} { set_property PROBES.FILE $ltx $dev }
program_hw_devices $dev
puts "PROGRAMMED stock_feed_synth with ILA"
after 3000
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "ILA: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "  $p" }

# Trigger on CRS_DV going HIGH (frame arriving)
set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 100 $ila
set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes u_top/rmii_crs_dv -of_objects $ila]

run_hw_ila $ila
puts ""
puts "ILA ARMED - trigger on CRS_DV=1"
puts "Now run: python send_frames.py --iface Ethernet --test"
puts "Then tell me, and I will read the ILA data."

# Wait up to 60 seconds
wait_on_hw_ila $ila -timeout 60

# Upload and save
set data [upload_hw_ila_data $ila]
set csv [file join $proj_dir ila_final.csv]
write_hw_ila_data -csv_file $csv $data
puts "ILA DATA SAVED: $csv"

# Print samples around trigger
set fp [open $csv r]
set lines [split [read $fp] "\n"]
close $fp
puts ""
puts [lindex $lines 0]
puts [lindex $lines 1]
puts ""
for {set i 92} {$i < [llength $lines] && $i < 250} {incr i} {
    set line [lindex $lines $i]
    if {$line ne ""} { puts $line }
}

close_hw_target
close_hw_manager
