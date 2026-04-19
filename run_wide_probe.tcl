# run_wide_probe.tcl - build wide_probe design, program, capture ILA
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"
open_project "$proj_dir/claude.xpr"

# Add new files if not present
set wp_v  "$proj_dir/claude.srcs/sources_1/new/wide_probe.v"
set wp_xdc "$proj_dir/claude.srcs/constrs_1/new/wide_probe.xdc"
if {[get_files -quiet wide_probe.v] eq ""} {
    add_files -fileset sources_1 [list $wp_v]
}
if {[get_files -quiet wide_probe.xdc] eq ""} {
    add_files -fileset constrs_1 [list $wp_xdc]
}

# Disable all other XDCs, enable wide_probe.xdc
foreach f [get_files -of_objects [get_filesets constrs_1] *.xdc] {
    set_property IS_ENABLED false $f
}
set_property IS_ENABLED true [get_files wide_probe.xdc]

# Disable specific conflicting source files
foreach name {stock_feed_synth.v stock_feed_top.v stock_feed_modules.v
              axis_eth_fcs_check.v book_state_manager.v lfsr.v rmii_tx_driver.v
              symbol_lut.v trigger_engine.v tx_packet_builder.v
              pin_probe.v pin_test.v tb_debug.v} {
    set ff [get_files -quiet $name]
    if {$ff ne ""} { catch { set_property IS_ENABLED false $ff } }
}
# Make sure wide_probe.v is enabled
set wpf [get_files -quiet wide_probe.v]
if {$wpf ne ""} { set_property IS_ENABLED true $wpf }

set_property top wide_probe [current_fileset]
update_compile_order -fileset sources_1

catch { generate_target all [get_ips ila_0] }
catch { synth_ip [get_ips ila_0] }

reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"

set bit "$proj_dir/claude.runs/impl_1/wide_probe.bit"
set ltx "$proj_dir/claude.runs/impl_1/wide_probe.ltx"
puts "BIT: [file exists $bit]  LTX: [file exists $ltx]"

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

# Trigger on the one-shot "edge_after_idle" signal (probe0 in our RTL)
set t [get_hw_probes u_ila/probe0 -of_objects $ila]
if {$t eq ""} { set t [get_hw_probes edge_after_idle -of_objects $ila] }
if {$t ne ""} {
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $t
    puts "TRIG: edge_after_idle=1"
} else {
    # Fallback: pins_r != 0
    foreach cand [get_hw_probes -of_objects $ila] {
        if {[string match *pins_r* $cand]} {
            set_property TRIGGER_COMPARE_VALUE neq8'h00 $cand
            puts "TRIG: $cand != 00"
        }
    }
}

run_hw_ila $ila
puts "ILA_ARMED"

if {[catch {wait_on_hw_ila $ila -timeout 40} err]} {
    puts "WAIT_ERR: $err"
}

set ila_data [upload_hw_ila_data $ila]
set csv "$proj_dir/wide_probe.csv"
write_hw_ila_data -csv_file $csv $ila_data -force
puts "CSV_SAVED: $csv"

close_hw_target
close_hw_manager
puts "ALL_DONE"
