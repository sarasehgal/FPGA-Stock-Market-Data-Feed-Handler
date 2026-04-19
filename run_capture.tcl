# run_capture.tcl - full build + program + ILA capture in one session
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"
open_project "$proj_dir/claude.xpr"

# Disable probe XDCs, enable main
foreach f {pin_probe.xdc pin_test.xdc} {
    set x [get_files -quiet $f]
    if {$x ne ""} { catch { set_property IS_ENABLED false $x } }
}
catch { set_property IS_ENABLED true [get_files -quiet constraints.xdc] }

set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1

# Synth IPs first
catch { generate_target all [get_ips clk_wiz_0] }
catch { synth_ip [get_ips clk_wiz_0] }
catch { generate_target all [get_ips ila_0] }
catch { synth_ip [get_ips ila_0] }

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"

set bit "$proj_dir/claude.runs/impl_1/stock_feed_synth.bit"
set ltx "$proj_dir/claude.runs/impl_1/stock_feed_synth.ltx"
puts "BIT_EXISTS: [file exists $bit]"
puts "LTX_EXISTS: [file exists $ltx]"

if {![file exists $bit]} {
    puts "BIT_NOT_PRODUCED - aborting"
    exit 1
}

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

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
if {$ila eq ""} {
    puts "NO_ILA_FOUND"
    close_hw_target
    close_hw_manager
    exit 1
}
puts "ILA_FOUND: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "  PROBE: $p" }

set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila

# Trigger: crs_dv rising edge OR s1_valid rising edge
set p0 [get_hw_probes -of_objects $ila -filter {NAME =~ *probe0*}]
set p4 [get_hw_probes -of_objects $ila -filter {NAME =~ *probe4*}]
if {$p0 ne ""} {
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $p0
}
if {$p4 ne ""} {
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $p4
}
# rxd!=00 is a reliable fallback trigger
set p1 [get_hw_probes -of_objects $ila -filter {NAME =~ *probe1*}]
if {$p1 ne ""} {
    set_property TRIGGER_COMPARE_VALUE neq2'b00 $p1
}

run_hw_ila $ila
puts "ILA_ARMED"

# Background sender
set sendpy "$proj_dir/_capsend.py"
set fp [open $sendpy w]
puts $fp "import struct, time"
puts $fp "from scapy.all import Ether, Raw, sendp"
puts $fp "for i in range(400):"
puts $fp "    payload = struct.pack('>B4sIHHB', 1, b'AAPL', 123456, 100, i+1, 0)"
puts $fp "    payload += bytes(\[sum(payload) % 256\])"
puts $fp "    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src='d4:a2:cd:1c:a9:0b', type=0x88B5) / Raw(load=payload)"
puts $fp "    sendp(pkt, iface='Ethernet', verbose=False)"
puts $fp "    time.sleep(0.025)"
close $fp

exec cmd /c "start /B python \"$sendpy\" > _capsend.log 2>&1"
after 500

catch { wait_on_hw_ila $ila -timeout 30 }
set ila_data [upload_hw_ila_data $ila]
set csv "$proj_dir/ila_capture.csv"
write_hw_ila_data -csv_file $csv $ila_data -force
puts "CSV_SAVED: $csv"

close_hw_target
close_hw_manager
puts "ALL_DONE"
