# run_ila_full.tcl - Build with ILA, program, capture, analyze - fully automated
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Setup project
set probe_xdc [get_files -quiet {*pin_probe.xdc}]
set main_xdc [get_files -quiet {*constraints.xdc}]
if {$probe_xdc ne ""} { set_property IS_ENABLED false $probe_xdc }
if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }
set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1
catch {generate_target all [get_ips clk_wiz_0] -force}
catch {synth_ip [get_ips clk_wiz_0] -force}

# Synth
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1

# Setup ILA from mark_debug
set dbg_nets [get_nets -hierarchical -filter {MARK_DEBUG == TRUE}]
puts "DEBUG NETS: [llength $dbg_nets]"
foreach n $dbg_nets { puts "  $n" }

# Use Vivado's automatic debug setup
if {[llength $dbg_nets] > 0} {
    setup_debug -sample_depth 2048 -clock clk_50
    implement_debug_core
    save_constraints
}

close_design

# Implement
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"

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
after 2000
refresh_hw_device $dev

# Find ILA
set ila [lindex [get_hw_ilas -of_objects $dev] 0]
if {$ila eq ""} { puts "ERROR: No ILA"; close_hw_target; close_hw_manager; exit 1 }
puts "ILA: $ila"

# List probes
foreach p [get_hw_probes -of_objects $ila] { puts "  PROBE: $p" }

# Trigger on s1_start rising
catch {
    set_property CONTROL.DATA_DEPTH 2048 $ila
    set_property CONTROL.TRIGGER_POSITION 100 $ila
    set sp [get_hw_probes -of_objects $ila -filter {NAME =~ *s1_start*}]
    if {$sp ne ""} {
        set_property TRIGGER_COMPARE_VALUE "eq1'b1" $sp
        puts "Trigger: s1_start=1"
    } else {
        set sp [get_hw_probes -of_objects $ila -filter {NAME =~ *s1_valid*}]
        set_property TRIGGER_COMPARE_VALUE "eq1'b1" $sp
        puts "Trigger: s1_valid=1"
    }
}

# Arm ILA
run_hw_ila $ila
puts "ILA ARMED - sending frames..."

# Send frames via Python
after 1000
catch {
    exec python -c {
import struct,time
from scapy.all import Ether,Raw,sendp
for i in range(10):
    payload = struct.pack(">B4sIHHB", 1, b"AAPL", 123456, 100, i+1, 0)
    payload += bytes([sum(payload) % 256])
    pkt = Ether(dst="ff:ff:ff:ff:ff:ff", src="d4:a2:cd:1c:a9:0b", type=0x88B5) / Raw(load=payload)
    sendp(pkt, iface="Ethernet", verbose=False)
    time.sleep(0.3)
    }
}
puts "Frames sent, waiting for trigger..."

# Wait for trigger
catch { wait_on_hw_ila $ila -timeout 15 }

# Upload data
puts "Uploading..."
set ila_data [upload_hw_ila_data $ila]
set csv [file join $proj_dir ila_data.csv]
write_hw_ila_data -csv_file $csv $ila_data
puts "DATA SAVED: $csv"

# Read and analyze
puts ""
puts "================================================================"
puts "  ILA CAPTURE ANALYSIS"
puts "================================================================"

set fp [open $csv r]
set lines [split [read $fp] "\n"]
close $fp

# Print header
puts [lindex $lines 0]
puts [lindex $lines 1]

# Find columns
set header [lindex $lines 0]

# Print samples where s1_valid=1 (received bytes)
puts ""
puts "RECEIVED BYTES (s1_valid=1 samples):"
puts "  Sample  crsdv  rxd  s1_data  start  end  s4_valid  etype_ok  s4_data"
set byte_count 0
for {set i 2} {$i < [llength $lines] && $byte_count < 80} {incr i} {
    set line [lindex $lines $i]
    if {$line eq ""} continue
    set fields [split $line ","]
    # Fields: sample_buf, sample_win, trigger, then probes in order
    # We need to find which field is s1_valid
    # Print all lines where trigger marker or around it
    set sample [lindex $fields 1]
    if {$sample >= 90 && $sample <= 250} {
        puts "  $line"
        incr byte_count
    }
}

puts ""
puts "Total lines in CSV: [llength $lines]"
puts "================================================================"

close_hw_target
close_hw_manager
