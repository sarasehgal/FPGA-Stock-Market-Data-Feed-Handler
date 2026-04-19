# run_ila.tcl - Add ILA, implement, program, capture data, and analyze
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Restore main design
set probe_xdc [get_files -quiet {*pin_probe.xdc}]
set main_xdc [get_files -quiet {*constraints.xdc}]
if {$probe_xdc ne ""} { set_property IS_ENABLED false $probe_xdc }
if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }
set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1

# Ensure IP
catch {generate_target all [get_ips clk_wiz_0] -force}
catch {synth_ip [get_ips clk_wiz_0] -force}

# Run synthesis
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1

# Mark signals for debug
set_property mark_debug true [get_nets {u_top/s1_data[*]}]
set_property mark_debug true [get_nets {u_top/s1_valid}]
set_property mark_debug true [get_nets {u_top/s1_start}]
set_property mark_debug true [get_nets {u_top/s1_end}]
set_property mark_debug true [get_nets {u_top/s4_valid}]
set_property mark_debug true [get_nets {u_top/s4_etype_ok}]
set_property mark_debug true [get_nets {u_top/s4_data[*]}]

# Create ILA core
create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]

# Connect ILA clock to clk_50
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets u_top/clk_50]

# Probe 0: s1_data[7:0]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets {u_top/s1_data[0] u_top/s1_data[1] u_top/s1_data[2] u_top/s1_data[3] u_top/s1_data[4] u_top/s1_data[5] u_top/s1_data[6] u_top/s1_data[7]}]

# Probe 1: s1_valid
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 1 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets u_top/s1_valid]

# Probe 2: s1_start
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets u_top/s1_start]

# Probe 3: s1_end
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets u_top/s1_end]

# Probe 4: s4_valid
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets u_top/s4_valid]

# Probe 5: s4_etype_ok
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets u_top/s4_etype_ok]

# Save and implement
save_constraints
close_design

# Reset impl and run with ILA
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set status [get_property STATUS [get_runs impl_1]]
puts "Implementation: $status"

# Program
set bit [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.bit}]
set ltx [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.ltx}]

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx $dev
}
program_hw_devices $dev
puts "PROGRAMMED with ILA"

# Wait for device to come up
after 2000

# Setup ILA trigger: trigger on s1_start rising edge
set ila [get_hw_ilas -of_objects $dev]
if {$ila ne ""} {
    puts "ILA found: $ila"

    # Set trigger on s1_start = rising edge
    set_property TRIGGER_COMPARE_VALUE eq1'bR \
        [get_hw_probes u_top/s1_start -of_objects $ila]

    # Set capture depth
    set_property CONTROL.DATA_DEPTH 4096 [get_hw_ilas $ila]
    set_property CONTROL.TRIGGER_POSITION 100 [get_hw_ilas $ila]

    # Arm the ILA
    run_hw_ila $ila
    puts "ILA armed - waiting for trigger (send a frame now)..."

    # Wait for trigger (timeout 30 sec)
    wait_on_hw_ila $ila -timeout 30

    # Read captured data
    puts ""
    puts "=== ILA CAPTURE RESULTS ==="
    display_hw_ila_data [upload_hw_ila_data $ila]

    # Export to CSV for analysis
    set csv_file [file join $proj_dir ila_capture.csv]
    write_hw_ila_data -csv_file $csv_file [upload_hw_ila_data $ila]
    puts "Saved to: $csv_file"

    # Print the first 50 samples where s1_valid=1
    puts ""
    puts "=== RECEIVED BYTES (first 50 s1_valid samples) ==="
    set ila_data [upload_hw_ila_data $ila]
    set num_samples [get_property DATA_DEPTH $ila_data]
    set count 0
    for {set i 0} {$i < $num_samples && $count < 50} {incr i} {
        set valid [get_property SAMPLE.$i.u_top/s1_valid $ila_data]
        if {$valid == 1} {
            set data [get_property SAMPLE.$i.u_top/s1_data $ila_data]
            set start [get_property SAMPLE.$i.u_top/s1_start $ila_data]
            set end_s [get_property SAMPLE.$i.u_top/s1_end $ila_data]
            puts [format "  byte[%2d] = 0x%02X  start=%s end=%s" $count $data $start $end_s]
            incr count
        }
    }
    puts ""
    puts "Expected first 14 bytes: FF FF FF FF FF FF DE AD BE EF CA FE 88 B5"
    puts "Byte 12=0x88, Byte 13=0xB5 (EtherType)"
} else {
    puts "ERROR: No ILA found on device"
}

close_hw_target
close_hw_manager
