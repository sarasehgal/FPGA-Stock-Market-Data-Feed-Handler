# Just arm ILA, send frames, capture, read CSV
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set ltx [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.ltx}]
if {[file exists $ltx]} { set_property PROBES.FILE $ltx $dev }
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "ILA: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "  $p" }

# Trigger on rmii_crs_dv = 1
set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 100 $ila
set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes u_top/rmii_crs_dv -of_objects $ila]

run_hw_ila $ila
puts "ARMED at [clock format [clock seconds]]"
after 2000

# Send frames inline via Tcl exec
puts "Sending frames..."
catch {
    exec python {C:/Users/LocalAdmin/Desktop/claude - Copy/test_hw.py} &
} msg
puts "Python: $msg"

# Wait for trigger
catch { wait_on_hw_ila $ila -timeout 20 } msg2
puts "Wait result: $msg2"

# Upload
set data [upload_hw_ila_data $ila]
set csv [file join $proj_dir ila_final.csv]
write_hw_ila_data -csv_file $csv $data
puts "SAVED: $csv"

# Read and print data
set fp [open $csv r]
set lines [split [read $fp] "\n"]
close $fp
puts ""
puts "Header: [lindex $lines 0]"
puts "Radix:  [lindex $lines 1]"

# Show samples 90-200 (around trigger at 100)
puts ""
puts "=== SAMPLES AROUND TRIGGER ==="
for {set i 92} {$i < [llength $lines] && $i < 250} {incr i} {
    set line [lindex $lines $i]
    if {$line ne ""} { puts $line }
}
puts "=== END ==="

close_hw_target
close_hw_manager
