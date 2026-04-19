# capture_ila.tcl - Arm ILA, wait for trigger, read data
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev

# Load probes file
set ltx [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.ltx}]
if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx $dev
    puts "Loaded probes: $ltx"
}

# Refresh to find ILA
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "ILA: $ila"

# List all probes
foreach p [get_hw_probes -of_objects $ila] {
    puts "  Probe: $p"
}

# Set trigger: trigger on s1_valid = 1 (any byte received)
# Find the probe that contains s1_valid
set probes [get_hw_probes -of_objects $ila]
foreach p $probes {
    puts "  $p"
}

# Trigger when s1_valid=1 (first byte assembled)
set_property CONTROL.TRIGGER_POSITION 200 $ila
set_property CONTROL.DATA_DEPTH 2048 $ila

set_property TRIGGER_COMPARE_VALUE "eq1'b1" [get_hw_probes u_top/s1_valid -of_objects $ila]
puts "Trigger set on s1_valid=1"

# Arm
run_hw_ila $ila
puts "ILA ARMED - send a frame now! (30 second timeout)"

# Wait
wait_on_hw_ila $ila -timeout 30

puts "Uploading ILA data..."
set ila_data [upload_hw_ila_data $ila]
if {$ila_data ne ""} {

    set csv [file join $proj_dir ila_capture.csv]
    write_hw_ila_data -csv_file $csv $ila_data
    puts "Data saved to: $csv"

    # Read and print the CSV
    set fp [open $csv r]
    set content [read $fp]
    close $fp

    set lines [split $content "\n"]
    puts "\n=== ILA CAPTURE (first 150 lines) ==="
    set count 0
    foreach line $lines {
        if {$count < 150} {
            puts $line
        }
        incr count
    }
    puts "... total $count lines"
} else {
    puts "No ILA data"
}

close_hw_target
close_hw_manager
