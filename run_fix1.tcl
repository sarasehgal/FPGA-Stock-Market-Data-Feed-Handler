## run_fix1.tcl - build with fixes, program, capture ILA on s1_valid, analyze
set proj_dir [file normalize [list C:/Users/LocalAdmin/Desktop/claude\ -\ Copy]]
# (list) form handles the space in the path when passing into Tcl commands below.
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"

open_project "$proj_dir/claude.xpr"

# Make sure main constraints are active
set probe_xdc [get_files -quiet pin_probe.xdc]
if {$probe_xdc ne ""} { catch { set_property IS_ENABLED false $probe_xdc } }
set pin_test_xdc [get_files -quiet pin_test.xdc]
if {$pin_test_xdc ne ""} { catch { set_property IS_ENABLED false $pin_test_xdc } }
set main_xdc [get_files -quiet constraints.xdc]
if {$main_xdc ne ""} { catch { set_property IS_ENABLED true $main_xdc } }

set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1

# Regenerate IPs if necessary
catch { generate_target all [get_ips clk_wiz_0] }
catch { generate_target all [get_ips ila_0] }

# Synth
reset_run synth_1
launch_runs synth_1 -jobs 6
wait_on_run synth_1
puts "SYNTH: [get_property STATUS [get_runs synth_1]]"

open_run synth_1 -name synth_1

# Setup ILA from mark_debug nets
set dbg_nets [get_nets -hierarchical -filter {MARK_DEBUG == TRUE}]
puts "DEBUG_NET_COUNT: [llength $dbg_nets]"
foreach n $dbg_nets { puts "  DN: $n" }

if {[llength $dbg_nets] > 0} {
    setup_debug -sample_depth 4096 -clock [get_clocks -of_objects [get_nets -hier clk_50]]
    implement_debug_core
    save_constraints -force
}

# Keep dbg_hub clock async-routable
catch {
    set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
    set_property C_ENABLE_CLK_DIVIDER true [get_debug_cores dbg_hub]
}

close_design

# Implement + bitstream
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 6
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"

set bit "$proj_dir/claude.runs/impl_1/stock_feed_synth.bit"
set ltx "$proj_dir/claude.runs/impl_1/stock_feed_synth.ltx"
puts "BIT: $bit  exists=[file exists $bit]"
puts "LTX: $ltx  exists=[file exists $ltx]"

# Program
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

# ILA
set ila [lindex [get_hw_ilas -of_objects $dev] 0]
if {$ila ne ""} {
    puts "ILA: $ila"
    foreach p [get_hw_probes -of_objects $ila] { puts "  PROBE: $p" }

    set_property CONTROL.DATA_DEPTH 4096 $ila
    set_property CONTROL.TRIGGER_POSITION 512 $ila

    # Trigger on s1_valid=1 OR rxd!=00, whichever we find
    set sp [get_hw_probes -of_objects $ila -filter {NAME =~ *s1_valid*}]
    if {$sp ne ""} {
        set_property TRIGGER_COMPARE_VALUE eq1'b1 $sp
        puts "TRIG: s1_valid=1"
    } else {
        set sp [get_hw_probes -of_objects $ila -filter {NAME =~ *rmii_rxd_vec*}]
        set_property TRIGGER_COMPARE_VALUE neq2'b00 $sp
        puts "TRIG: rxd!=00"
    }

    run_hw_ila $ila
    puts "ILA_ARMED"

    # Write sender script, launch it non-blocking, then wait on ILA
    set sendpy "$proj_dir/_ila_sender.py"
    set fp [open $sendpy w]
    puts $fp "import struct,time"
    puts $fp "from scapy.all import Ether,Raw,sendp"
    puts $fp "for i in range(80):"
    puts $fp "    payload = struct.pack('>B4sIHHB', 1, b'AAPL', 123456, 100, i+1, 0)"
    puts $fp "    payload += bytes(\[sum(payload) % 256\])"
    puts $fp "    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src='d4:a2:cd:1c:a9:0b', type=0x88B5) / Raw(load=payload)"
    puts $fp "    sendp(pkt, iface='Ethernet', verbose=False)"
    puts $fp "    time.sleep(0.08)"
    close $fp

    # Background send via cmd start
    exec cmd /c "start /B python \"$sendpy\" > _send.log 2>&1"
    after 500

    catch { wait_on_hw_ila $ila -timeout 20 }
    set ila_data [upload_hw_ila_data $ila]
    set csv "$proj_dir/ila_fix1.csv"
    write_hw_ila_data -csv_file $csv $ila_data -force
    puts "CSV_SAVED: $csv"
} else {
    puts "NO_ILA"
}

close_hw_target
close_hw_manager
puts "ALL_DONE"
