# cap_only.tcl - connect to already-programmed FPGA, arm ILA, send frames, capture
set proj_dir "C:/Users/LocalAdmin/Desktop/claude - Copy"

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev

# Auto-load probes file
set ltx "$proj_dir/claude.runs/impl_1/stock_feed_synth.ltx"
if {[file exists $ltx]} { set_property PROBES.FILE $ltx $dev }
refresh_hw_device $dev

set ila [lindex [get_hw_ilas -of_objects $dev] 0]
if {$ila eq ""} { puts "NO_ILA"; exit 1 }
puts "ILA: $ila"
foreach p [get_hw_probes -of_objects $ila] { puts "  PROBE: $p" }

set_property CONTROL.DATA_DEPTH 2048 $ila
set_property CONTROL.TRIGGER_POSITION 256 $ila

# Trigger: crs_dv rising edge (will fire on start of sustained frame, not glitches)
set crs [get_hw_probes u_top/dbg_crs_dv_synth -of_objects $ila]
if {$crs ne ""} {
    set_property TRIGGER_COMPARE_VALUE eq1'b1 $crs
    puts "TRIG: dbg_crs_dv_synth=1"
}

run_hw_ila $ila
puts "ILA_ARMED"

# Launch python sender via powershell — no double quoting
set sendpy "$proj_dir/_cap_send.py"
set fp [open $sendpy w]
puts $fp "import struct, time"
puts $fp "from scapy.all import Ether, Raw, sendp"
puts $fp "for i in range(400):"
puts $fp "    payload = struct.pack('>B4sIHHB', 1, b'AAPL', 123456, 100, i+1, 0)"
puts $fp "    payload += bytes(\[sum(payload) % 256\])"
puts $fp "    pkt = Ether(dst='ff:ff:ff:ff:ff:ff', src='d4:a2:cd:1c:a9:0b', type=0x88B5) / Raw(load=payload)"
puts $fp "    sendp(pkt, iface='Ethernet', verbose=False)"
puts $fp "    time.sleep(0.02)"
close $fp

# Background: powershell Start-Process to avoid quoting issues
exec powershell -Command "Start-Process -WindowStyle Hidden -FilePath python -ArgumentList '$sendpy' -RedirectStandardOutput '$proj_dir/_cap_send.log'" &
after 800

if {[catch {wait_on_hw_ila $ila -timeout 25} err]} {
    puts "WAIT_ERR: $err"
}

set ila_data [upload_hw_ila_data $ila]
set csv "$proj_dir/ila_capture.csv"
write_hw_ila_data -csv_file $csv $ila_data -force
puts "CSV_SAVED: $csv"

close_hw_target
close_hw_manager
puts "ALL_DONE"
