# Restore main design, rebuild with corrected CRS_DV pin, program
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Restore main constraints, disable probe constraints
set probe_xdc [get_files -quiet {*pin_probe.xdc}]
if {$probe_xdc ne ""} { set_property IS_ENABLED false $probe_xdc }
set main_xdc [get_files -quiet {*constraints.xdc}]
if {$main_xdc ne ""} { set_property IS_ENABLED true $main_xdc }

# Set top back to stock_feed_synth
set_property top stock_feed_synth [current_fileset]
update_compile_order -fileset sources_1

# Ensure IP
catch {generate_target all [get_ips clk_wiz_0] -force}
catch {synth_ip [get_ips clk_wiz_0] -force}

# Build
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set status [get_property STATUS [get_runs impl_1]]
puts "Build: $status"

# Program
set bit [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.bit}]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "DONE pin: [get_property REGISTER.IR.BIT5_DONE $dev]"
puts ""
puts "=== STOCK FEED DESIGN PROGRAMMED WITH CRS_DV ON H13 ==="
close_hw_target
close_hw_manager
