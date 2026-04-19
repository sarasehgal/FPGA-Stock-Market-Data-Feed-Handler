# Reprogram pin probe, include JA pins too
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Use probe constraints
set probe_xdc [get_files -quiet {*pin_probe.xdc}]
set main_xdc [get_files -quiet {*constraints.xdc}]
if {$probe_xdc ne ""} { set_property IS_ENABLED true $probe_xdc }
if {$main_xdc ne ""} { set_property IS_ENABLED false $main_xdc }
set_property top pin_probe [current_fileset]
update_compile_order -fileset sources_1

# Just program the existing probe bitstream
set bit [file join $proj_dir {claude.runs/impl_1/pin_probe.bit}]
if {[file exists $bit]} {
    open_hw_manager
    connect_hw_server -allow_non_jtag
    open_hw_target [lindex [get_hw_targets] 0]
    set dev [lindex [get_hw_devices] 0]
    current_hw_device $dev
    set_property PROGRAM.FILE $bit $dev
    program_hw_devices $dev
    puts "PIN PROBE loaded"
    close_hw_target
    close_hw_manager
} else {
    puts "No probe bitstream found, rebuilding..."
    catch {generate_target all [get_ips clk_wiz_0] -force}
    catch {synth_ip [get_ips clk_wiz_0] -force}
    reset_run synth_1
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1

    open_hw_manager
    connect_hw_server -allow_non_jtag
    open_hw_target [lindex [get_hw_targets] 0]
    set dev [lindex [get_hw_devices] 0]
    current_hw_device $dev
    set_property PROGRAM.FILE $bit $dev
    program_hw_devices $dev
    puts "PIN PROBE built and loaded"
    close_hw_target
    close_hw_manager
}

# Restore for later
if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }
set_property top stock_feed_synth [current_fileset]
