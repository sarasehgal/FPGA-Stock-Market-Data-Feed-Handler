# prog_cap.tcl - re-program from existing BIT, arm ILA, capture
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"
set bit "$proj_dir/claude.runs/impl_1/stock_feed_synth.bit"
set ltx "$proj_dir/claude.runs/impl_1/stock_feed_synth.ltx"

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

set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila

puts "ILA probes:"
foreach p [get_hw_probes -of_objects $ila] { puts "  $p width=[get_property WIDTH $p]" }
# Trigger on rmii_tx_en rising edge
set t [get_hw_probes -of_objects $ila -filter {NAME =~ *tx_en*}]
if {$t eq ""} {
    # fallback: use first 1-bit probe
    foreach p [get_hw_probes -of_objects $ila] {
        if {[get_property WIDTH $p] == 1} { set t $p; break }
    }
}
set_property TRIGGER_COMPARE_VALUE eq1'b1 $t
puts "TRIG: $t == 1"

run_hw_ila $ila
puts "ILA_ARMED"

if {[catch {wait_on_hw_ila $ila -timeout 30} err]} { puts "WAIT_ERR: $err" }

if {[catch {set ila_data [upload_hw_ila_data $ila]} err]} {
    puts "UPLOAD_ERR: $err"
} else {
    write_hw_ila_data -csv_file "$proj_dir/real_capture.csv" $ila_data -force
    puts "CSV_SAVED"
}

close_hw_target
close_hw_manager
puts "ALL_DONE"
