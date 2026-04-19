# run_real.tcl - build real stock_feed_synth with confirmed pin map
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"
open_project "$proj_dir/claude.xpr"

# Enable main constraints; disable wide_probe.xdc and probe xdcs
foreach f [get_files -of_objects [get_filesets constrs_1] *.xdc] {
    set_property IS_ENABLED false $f
}
set mx [get_files -quiet constraints.xdc]
if {$mx ne ""} { set_property IS_ENABLED true $mx }

# Re-enable main RTL, disable wide_probe.v
foreach name {stock_feed_synth.v stock_feed_top.v stock_feed_modules.v
              axis_eth_fcs_check.v book_state_manager.v lfsr.v rmii_tx_driver.v
              symbol_lut.v trigger_engine.v tx_packet_builder.v} {
    set ff [get_files -quiet $name]
    if {$ff ne ""} { set_property IS_ENABLED true $ff }
}
set wp [get_files -quiet wide_probe.v]
if {$wp ne ""} { set_property IS_ENABLED false $wp }

set_property top stock_feed_synth [current_fileset]

# Remove deleted RMII TX files from fileset
foreach gone {rmii_tx_driver.v tx_packet_builder.v} {
    set ff [get_files -quiet $gone]
    if {$ff ne ""} { catch { remove_files $ff } }
}
# Add mdio_init.v / uart_tx.v / trigger_uart.v if not in fileset
foreach name {mdio_init.v uart_tx.v trigger_uart.v} {
    if {[get_files -quiet $name] eq ""} {
        add_files -fileset sources_1 [list "$proj_dir/claude.srcs/sources_1/new/$name"]
    }
}

update_compile_order -fileset sources_1

catch { generate_target all [get_ips clk_wiz_0] }
catch { synth_ip [get_ips clk_wiz_0] }
catch { generate_target all [get_ips ila_0] }
catch { synth_ip [get_ips ila_0] }

reset_run impl_1
reset_run synth_1
# Disable incremental synthesis (was crashing on Graph Differ)
catch { set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1] }
catch { set_property INCREMENTAL_CHECKPOINT {} [get_runs synth_1] }
launch_runs synth_1 -jobs 4
wait_on_run synth_1
puts "SYNTH: [get_property STATUS [get_runs synth_1]]"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"

set bit "$proj_dir/claude.runs/impl_1/stock_feed_synth.bit"
set ltx "$proj_dir/claude.runs/impl_1/stock_feed_synth.ltx"
puts "BIT: [file exists $bit]  LTX: [file exists $ltx]"

if {![file exists $bit]} { exit 1 }

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
if {$ila eq ""} { puts "NO_ILA"; exit 1 }
puts "ILA: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "  PROBE: $p" }

set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila

# Trigger on CRS_DV rising (catches real frame)
set crs [get_hw_probes u_top/dbg_crs_dv_synth -of_objects $ila]
if {$crs ne ""} {
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $crs
    puts "TRIG: CRS_DV=1"
}

run_hw_ila $ila
puts "ILA_ARMED"

if {[catch {wait_on_hw_ila $ila -timeout 45} err]} {
    puts "WAIT_ERR: $err"
}

set ila_data [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file "$proj_dir/real_capture.csv" $ila_data -force
puts "CSV_SAVED"

close_hw_target
close_hw_manager
puts "ALL_DONE"
