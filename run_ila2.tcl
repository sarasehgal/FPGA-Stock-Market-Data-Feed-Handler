# run_ila2.tcl - Add ILA via mark_debug, implement, program, capture, analyze
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Restore main design
set probe_xdc [get_files -quiet {*pin_probe.xdc}]
set main_xdc [get_files -quiet {*constraints.xdc}]
if {$probe_xdc ne ""} { set_property IS_ENABLED false $probe_xdc }
if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }
set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1

catch {generate_target all [get_ips clk_wiz_0] -force}
catch {synth_ip [get_ips clk_wiz_0] -force}

# Synthesize
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1

# Let Vivado auto-create ILA from mark_debug attributes
puts "Setting up debug from mark_debug attributes..."
set debug_nets [get_nets -hierarchical -filter {MARK_DEBUG == TRUE}]
puts "Found [llength $debug_nets] debug nets:"
foreach n $debug_nets { puts "  $n" }

if {[llength $debug_nets] > 0} {
    # Use setup_debug to create ILA
    create_debug_core u_ila_0 ila
    set_property C_DATA_DEPTH 2048 [get_debug_cores u_ila_0]
    set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
    set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
    set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]

    # Clock: use clk_50 (RMII domain)
    set clk50_net [get_nets -hierarchical {u_top/clk_50}]
    if {$clk50_net eq ""} {
        set clk50_net [get_nets -hierarchical -filter {NAME =~ *clk_50*}]
    }
    puts "Clock net: $clk50_net"
    set_property port_width 1 [get_debug_ports u_ila_0/clk]
    connect_debug_port u_ila_0/clk $clk50_net

    # Probe 0: crsdv + rxd (3 bits)
    set crsdv_net [get_nets -hierarchical -filter {NAME =~ *dbg_crsdv*}]
    set rxd_nets [get_nets -hierarchical -filter {NAME =~ *dbg_rxd*}]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
    set_property port_width [expr [llength $crsdv_net] + [llength $rxd_nets]] [get_debug_ports u_ila_0/probe0]
    connect_debug_port u_ila_0/probe0 [concat $crsdv_net $rxd_nets]

    # Probe 1: s1_data (8 bits)
    create_debug_port u_ila_0 probe
    set s1d_nets [lsort [get_nets -hierarchical -filter {NAME =~ *s1_data*}]]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
    set_property port_width [llength $s1d_nets] [get_debug_ports u_ila_0/probe1]
    connect_debug_port u_ila_0/probe1 $s1d_nets

    # Probe 2: s1_valid + s1_start + s1_end (3 bits)
    create_debug_port u_ila_0 probe
    set ctrl_nets [list]
    foreach pat {*s1_valid* *s1_start* *s1_end*} {
        set n [get_nets -hierarchical -filter "NAME =~ $pat && MARK_DEBUG == TRUE"]
        if {$n ne ""} { lappend ctrl_nets {*}$n }
    }
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
    set_property port_width [llength $ctrl_nets] [get_debug_ports u_ila_0/probe2]
    connect_debug_port u_ila_0/probe2 $ctrl_nets

    # Probe 3: s4_valid + s4_etype_ok + s4_data (10 bits)
    create_debug_port u_ila_0 probe
    set s4_nets [list]
    foreach pat {*s4_valid* *s4_etype_ok* *s4_data*} {
        set n [get_nets -hierarchical -filter "NAME =~ $pat && MARK_DEBUG == TRUE"]
        if {$n ne ""} { lappend s4_nets {*}$n }
    }
    if {[llength $s4_nets] > 0} {
        set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
        set_property port_width [llength $s4_nets] [get_debug_ports u_ila_0/probe3]
        connect_debug_port u_ila_0/probe3 $s4_nets
    }

    save_constraints
    puts "ILA setup complete with [llength $debug_nets] probes"
} else {
    puts "WARNING: No mark_debug nets found!"
}

close_design

# Implement
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "Implementation: [get_property STATUS [get_runs impl_1]]"

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

# Find and configure ILA
set ilas [get_hw_ilas -of_objects $dev]
puts "ILAs found: $ilas"

if {[llength $ilas] > 0} {
    set ila [lindex $ilas 0]
    puts "Using ILA: $ila"

    # List probes
    set probes [get_hw_probes -of_objects $ila]
    puts "Probes:"
    foreach p $probes { puts "  $p  width=[get_property PORT_WIDTH $p]" }

    # Trigger on dbg_crsdv rising edge (CRS_DV goes high = frame arriving)
    set crsdv_probe [get_hw_probes -of_objects $ila -filter {NAME =~ *dbg_crsdv*}]
    if {$crsdv_probe ne ""} {
        set_property CONTROL.TRIGGER_POSITION 200 $ila
        set_property TRIGGER_COMPARE_VALUE "eq1'b1" $crsdv_probe
        puts "Trigger set on CRS_DV = 1"
    } else {
        # Try triggering on s1_start
        set start_probe [get_hw_probes -of_objects $ila -filter {NAME =~ *s1_start*}]
        if {$start_probe ne ""} {
            set_property CONTROL.TRIGGER_POSITION 200 $ila
            set_property TRIGGER_COMPARE_VALUE "eq1'b1" $start_probe
            puts "Trigger set on s1_start = 1"
        }
    }

    # Arm and wait
    puts "ILA armed - send a frame within 30 seconds..."
    run_hw_ila $ila

    # Send frames via external process
    puts "Launching frame sender..."
    exec python -c "import struct,time; from scapy.all import Ether,Raw,sendp; \[sendp(Ether(dst='ff:ff:ff:ff:ff:ff',src='d4:a2:cd:1c:a9:0b',type=0x88B5)/Raw(load=struct.pack('>B4sIHHB',1,b'AAPL',123456,100,1,0)+b'\\xa7'),iface='Ethernet',verbose=False) or time.sleep(0.5) for _ in range(5)\]" &

    wait_on_hw_ila $ila -timeout 30

    # Upload and display data
    set ila_data [upload_hw_ila_data $ila]

    # Write to CSV
    set csv [file join $proj_dir ila_capture.csv]
    write_hw_ila_data -csv_file $csv $ila_data
    puts "\nILA data saved to: $csv"

    # Print first 100 samples
    puts "\n=== RAW ILA DATA (first 100 samples around trigger) ==="
    puts "Sample  crsdv_rxd  s1_data  s1_valid s1_start s1_end"

    # Read the CSV file and print it
    set fp [open $csv r]
    set csv_data [read $fp]
    close $fp
    set lines [split $csv_data "\n"]
    set count 0
    foreach line $lines {
        if {$count < 102} {
            puts $line
        }
        incr count
    }
    puts "... ($count total lines)"

} else {
    puts "ERROR: No ILA found after programming"
}

close_hw_target
close_hw_manager
