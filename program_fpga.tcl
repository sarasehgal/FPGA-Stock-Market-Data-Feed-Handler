# program_fpga.tcl - Detect board, program bitstream, verify
open_hw_manager
connect_hw_server -allow_non_jtag

puts ""
puts "=== Scanning for JTAG targets ==="

set targets [get_hw_targets]
if {[llength $targets] == 0} {
    puts "ERROR: No JTAG targets found. Check USB cable and drivers."
    close_hw_manager
    exit 1
}

foreach t $targets {
    puts "  Target: $t"
}

# Open the first target
set tgt [lindex $targets 0]
open_hw_target $tgt
puts "Opened target: $tgt"

set devices [get_hw_devices]
if {[llength $devices] == 0} {
    puts "ERROR: No devices found on target $tgt"
    close_hw_target
    close_hw_manager
    exit 1
}

foreach d $devices {
    puts "  Device: $d  Part: [get_property PART $d]"
}

# Select the first device
set dev [lindex $devices 0]
current_hw_device $dev
puts "\nProgramming device: $dev"

# Set the bitstream file
set bit_file [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy/claude.runs/impl_1/stock_feed_synth.bit}]
if {![file exists $bit_file]} {
    puts "ERROR: Bitstream not found at $bit_file"
    close_hw_target
    close_hw_manager
    exit 1
}

set_property PROGRAM.FILE $bit_file $dev
puts "Bitstream: $bit_file"

# Program
puts "Programming..."
program_hw_devices $dev
puts ""
puts "============================================"
puts "  PROGRAMMING COMPLETE"
puts "  Device: [get_property PART $dev]"
puts "  Bitstream: $bit_file"
puts "============================================"
puts ""
puts "LED[0] should now be blinking at ~1.5 Hz (heartbeat)"
puts "LED[1] should be solid ON (PLL locked)"
puts ""

# Leave connection open so we can check device status
puts "Device DONE pin: [get_property REGISTER.IR.BIT5_DONE $dev]"

close_hw_target
close_hw_manager
