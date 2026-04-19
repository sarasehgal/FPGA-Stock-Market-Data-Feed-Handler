# run_fix2.tcl - direct ila_0 instantiation, build, program, capture
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"
open_project "$proj_dir/claude.xpr"

# Ensure main constraints only
foreach f {pin_probe.xdc pin_test.xdc} {
    set x [get_files -quiet $f]
    if {$x ne ""} { catch { set_property IS_ENABLED false $x } }
}
set main_xdc [get_files -quiet constraints.xdc]
if {$main_xdc ne ""} { catch { set_property IS_ENABLED true $main_xdc } }

set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1

# IP regen
catch { generate_target all [get_ips clk_wiz_0] }
catch { synth_ip [get_ips clk_wiz_0] }
catch { generate_target all [get_ips ila_0] }
catch { synth_ip [get_ips ila_0] }

reset_run synth_1
launch_runs synth_1 -jobs 6
wait_on_run synth_1
puts "SYNTH: [get_property STATUS [get_runs synth_1]]"

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"

set bit "$proj_dir/claude.runs/impl_1/stock_feed_synth.bit"
set ltx "$proj_dir/claude.runs/impl_1/stock_feed_synth.ltx"
puts "BIT_EXISTS: [file exists $bit]"
puts "LTX_EXISTS: [file exists $ltx]"

# Program + arm ILA
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
if {$ila ne ""} {
    puts "ILA_FOUND: $ila"
    foreach p [get_hw_probes -of_objects $ila] { puts "  PROBE: $p" }

    set_property CONTROL.DATA_DEPTH 2048 $ila
    set_property CONTROL.TRIGGER_POSITION 256 $ila

    # Trigger on any RXD activity (non-zero dibit)
    set rxdp [get_hw_probes -of_objects $ila -filter {NAME =~ *probe1*}]
    if {$rxdp ne ""} {
        set_property TRIGGER_COMPARE_VALUE neq2'b00 $rxdp
        puts "TRIG: rxd!=00 on $rxdp"
    }

    run_hw_ila $ila
    puts "ILA_ARMED"

    # Launch sender in background
    set sendpy "$proj_dir/_ila_sender2.py"
    set fp [open $sendpy w]
    puts $fp "import struct, time"
    puts $fp "from scapy.all import Ether, Raw, sendp"
    puts $fp "for i in range(200):"
    puts $fp "    payload = struct.pack('>B4sIHHB', 1, b'AAPL', 123456, 100, i+1, 0)"
    puts $fp "    payload += bytes(\[sum(payload) % 256\])"
    puts $fp "    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src='d4:a2:cd:1c:a9:0b', type=0x88B5) / Raw(load=payload)"
    puts $fp "    sendp(pkt, iface='Ethernet', verbose=False)"
    puts $fp "    time.sleep(0.04)"
    close $fp

    exec cmd /c "start /B python \"$sendpy\" > _send2.log 2>&1"
    after 500

    catch { wait_on_hw_ila $ila -timeout 25 }
    set ila_data [upload_hw_ila_data $ila]
    set csv "$proj_dir/ila_fix2.csv"
    write_hw_ila_data -csv_file $csv $ila_data -force
    puts "CSV_SAVED: $csv"
} else {
    puts "NO_ILA_FOUND"
}

close_hw_target
close_hw_manager
puts "ALL_DONE"
