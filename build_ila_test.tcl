# Build with ILA, program, send frames, capture, analyze — fully automatic
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

set probe_xdc [get_files -quiet {*pin_probe.xdc}]
set main_xdc [get_files -quiet {*constraints.xdc}]
if {$probe_xdc ne ""} { set_property IS_ENABLED false $probe_xdc }
if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }
set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1
catch {generate_target all [get_ips clk_wiz_0] -force}
catch {synth_ip [get_ips clk_wiz_0] -force}
catch {generate_target all [get_ips ila_0] -force}
catch {synth_ip [get_ips ila_0] -force}

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "BUILD: [get_property STATUS [get_runs impl_1]]"

# Program
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
after 3000
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
puts "ILA: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "  PROBE: $p" }

# Trigger on s1_valid (any byte assembled)
set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 100 $ila
catch {
    set_property TRIGGER_COMPARE_VALUE "eq1'b1" \
        [get_hw_probes u_top/s1_valid -of_objects $ila]
}

run_hw_ila $ila
puts "ILA ARMED — sending frames..."
after 2000

# Send frames
catch {
    exec python -c {
import struct,time
from scapy.all import Ether,Raw,sendp
for i in range(10):
    payload = struct.pack(">B4sIHHB", 1, b"AAPL", 123456, 100, i+1, 0)
    payload += bytes([sum(payload) % 256])
    sendp(Ether(dst="ff:ff:ff:ff:ff:ff",src="d4:a2:cd:1c:a9:0b",type=0x88B5)/Raw(load=payload), iface="Ethernet", verbose=False)
    time.sleep(0.3)
} &
}
puts "Frames sent"
catch { wait_on_hw_ila $ila -timeout 15 }

set data [upload_hw_ila_data $ila]
set csv [file join $proj_dir ila_result.csv]
write_hw_ila_data -csv_file $csv $data
puts "SAVED: $csv"

# Analyze
set fp [open $csv r]
set lines [split [read $fp] "\n"]
close $fp

puts "\n[lindex $lines 0]"
puts "[lindex $lines 1]"
puts "\nSamples around trigger:"
set found_valid 0
for {set i 2} {$i < [llength $lines]} {incr i} {
    set line [lindex $lines $i]
    if {$line eq ""} continue
    set fields [split $line ","]
    # Print all lines within +-50 of trigger, and any line with s1_valid=1
    set sample [lindex $fields 1]
    set trigger [lindex $fields 2]
    # Check if any field shows s1_valid=1 (field index 6 based on probe order)
    if {$sample >= 80 && $sample <= 200} {
        puts $line
    }
    # Also count lines where rxd != 0
    if {[lindex $fields 4] ne "0" && [lindex $fields 4] ne "00"} {
        if {$found_valid < 30} {
            puts "  RXD_ACTIVE: $line"
            incr found_valid
        }
    }
}

puts "\nTotal lines: [llength $lines]"
puts "Lines with RXD != 0: $found_valid"

close_hw_target
close_hw_manager
