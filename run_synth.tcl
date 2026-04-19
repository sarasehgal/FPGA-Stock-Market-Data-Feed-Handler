# =============================================================================
#  run_synth.tcl  -  Generate clk_wiz_0 IP and run synthesis
#  Usage: vivado -mode batch -source run_synth.tcl
# =============================================================================

set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]

# Open the existing project
open_project [file join $proj_dir claude.xpr]

# ── Add the synthesis wrapper if not already in project ──────────────────────
set synth_src [file join $proj_dir {claude.srcs/sources_1/new/stock_feed_synth.v}]
# Add any missing source files
set src_dir [file join $proj_dir {claude.srcs/sources_1/new}]
foreach f {stock_feed_synth.v rmii_tx_driver.v tx_packet_builder.v} {
    set found [get_files -quiet "*$f"]
    if {$found eq ""} {
        set fpath [file join $src_dir $f]
        puts "INFO: Adding $f to project..."
        add_files -norecurse [list $fpath]
    }
}
update_compile_order -fileset sources_1

# ── Set synthesis top module to the synthesis wrapper ─────────────────────────
set_property top stock_feed_synth [current_fileset]

# ── Generate clk_wiz_0 IP if it does not already exist ───────────────────────
set cw_ip [get_ips -quiet clk_wiz_0]
if {$cw_ip eq ""} {
    puts "INFO: Creating clk_wiz_0 IP..."
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
              -module_name clk_wiz_0

    set_property -dict [list \
        CONFIG.PRIM_IN_FREQ        {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
        CONFIG.CLKOUT2_USED        {true} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {50.000} \
        CONFIG.USE_LOCKED          {true} \
        CONFIG.USE_RESET           {false} \
        CONFIG.NUM_OUT_CLKS        {2} \
    ] [get_ips clk_wiz_0]

    generate_target all [get_ips clk_wiz_0]
    synth_ip [get_ips clk_wiz_0]
    puts "INFO: clk_wiz_0 IP generated successfully."
} else {
    puts "INFO: clk_wiz_0 IP already exists, ensuring targets are generated..."
    catch {generate_target all [get_ips clk_wiz_0] -force}
    catch {synth_ip [get_ips clk_wiz_0] -force}
}

# ── Reset and run synthesis ──────────────────────────────────────────────────
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# ── Report results ───────────────────────────────────────────────────────────
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]

puts "============================================================"
puts "  Synthesis status  : $synth_status"
puts "  Synthesis progress: $synth_progress"
puts "============================================================"

if {$synth_progress ne "100%"} {
    puts "ERROR: Synthesis did not complete."
    exit 1
}

# Open the synthesis run to get reports
open_run synth_1 -name synth_1

# Utilisation summary
set rpt_dir $proj_dir
report_utilization -file [file join $rpt_dir synth_utilization.txt]
report_timing_summary -file [file join $rpt_dir synth_timing.txt]

puts "\n── UTILISATION SUMMARY ──"
report_utilization

puts "\n── TIMING SUMMARY (worst 5 paths) ──"
report_timing_summary -no_header -max_paths 5

puts "\n============================================================"
puts "  Synthesis complete.  Reports saved."
puts "============================================================"
