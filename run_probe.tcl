# run_probe.tcl - Build pin probe using existing project
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Add probe source and constraints
set probe_v [file join $proj_dir pin_probe.v]
set probe_xdc [file join $proj_dir pin_probe.xdc]

# Add probe file if not already present
if {[get_files -quiet {*pin_probe.v}] eq ""} {
    add_files -norecurse [list $probe_v]
}

# Swap constraints: disable main XDC, use probe XDC
set main_xdc [get_files -quiet {*constraints.xdc}]
if {$main_xdc ne ""} {
    set_property IS_ENABLED false $main_xdc
}
if {[get_files -quiet {*pin_probe.xdc}] eq ""} {
    add_files -fileset constrs_1 -norecurse [list $probe_xdc]
}

# Set top to pin_probe
set_property top pin_probe [current_fileset]
update_compile_order -fileset sources_1

# Ensure clk_wiz_0 IP exists and is synthesized
set cw [get_ips -quiet clk_wiz_0]
if {$cw eq ""} {
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_0
    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
        CONFIG.CLKOUT2_USED {true} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {50.000} \
        CONFIG.USE_LOCKED {true} \
        CONFIG.USE_RESET {false} \
        CONFIG.NUM_OUT_CLKS {2} \
    ] [get_ips clk_wiz_0]
}
generate_target all [get_ips clk_wiz_0] -force
catch {synth_ip [get_ips clk_wiz_0] -force}

# Run synthesis + implementation + bitstream
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set status [get_property STATUS [get_runs impl_1]]
set progress [get_property PROGRESS [get_runs impl_1]]
puts "Status: $status  Progress: $progress"

if {$progress ne "100%"} {
    puts "ERROR: Build failed"
    # Restore main XDC
    if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }
    set_property top stock_feed_synth [current_fileset]
    exit 1
}

# Program
set bit [file join $proj_dir {claude.runs/impl_1/pin_probe.bit}]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts ""
puts "PIN PROBE PROGRAMMED - send frames and watch LEDs:"
puts "  LED 0  = heartbeat"
puts "  LED 1  = PLL locked"
puts "  LED 2  = H18 JB1_P pin1"
puts "  LED 3  = G18 JB1_N pin7  (rxd1)"
puts "  LED 4  = H13 JB2_P pin2  (maybe CRS_DV?)"
puts "  LED 5  = H14 JB2_N pin8"
puts "  LED 6  = H16 JB3_P pin3"
puts "  LED 7  = H17 JB3_N pin9  (rxd0)"
puts "  LED 8  = J16 JB4_N pin10 (mdio)"
puts "  LED 9  = K14 (non-standard)"
puts "  LED 10 = J15"
puts "  LED 11 = K14 raw live"
puts "  LED 12 = H13 raw live"

close_hw_target
close_hw_manager

# Restore project settings for next time
if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }
set_property top stock_feed_synth [current_fileset]
