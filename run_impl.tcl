# =============================================================================
#  run_impl.tcl  -  Run implementation (P&R) and generate bitstream
#  Usage: vivado -mode batch -source run_impl.tcl
# =============================================================================

set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Ensure top is set
set_property top stock_feed_synth [current_fileset]

# ── Launch implementation ────────────────────────────────────────────────────
set impl_status [get_property STATUS [get_runs impl_1]]
puts "INFO: Current impl_1 status: $impl_status"

# Reset and launch
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]

puts "\n============================================================"
puts "  Implementation status  : $impl_status"
puts "  Implementation progress: $impl_progress"
puts "============================================================"

if {$impl_progress ne "100%"} {
    puts "ERROR: Implementation did not complete."
    # Try to open run anyway for diagnostics
    catch {open_run impl_1 -name impl_1}
    puts "\n── TIMING SUMMARY (post-route) ──"
    catch {report_timing_summary -no_header -max_paths 5}
    exit 1
}

# ── Open run and generate reports ────────────────────────────────────────────
open_run impl_1 -name impl_1

report_utilization -file [file join $proj_dir impl_utilization.txt]
report_timing_summary -file [file join $proj_dir impl_timing.txt]
report_power -file [file join $proj_dir impl_power.txt]

puts "\n── POST-IMPLEMENTATION UTILISATION ──"
report_utilization

puts "\n── POST-ROUTE TIMING SUMMARY ──"
report_timing_summary -no_header -max_paths 5

# ── Find bitstream ───────────────────────────────────────────────────────────
set bit_file [glob -nocomplain [file join $proj_dir {claude.runs/impl_1/*.bit}]]
if {$bit_file ne ""} {
    puts "\n============================================================"
    puts "  BITSTREAM: $bit_file"
    puts "============================================================"
} else {
    puts "\nWARNING: Bitstream file not found in impl_1 directory."
    set bit_file [glob -nocomplain [file join $proj_dir {claude.runs/impl_1/stock_feed_synth.bit}]]
    puts "  Checked: $bit_file"
}

puts "\n============================================================"
puts "  Implementation + bitstream generation complete."
puts "============================================================"
