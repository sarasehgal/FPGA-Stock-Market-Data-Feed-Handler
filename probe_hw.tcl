open_hw_manager
if {[catch {connect_hw_server -allow_non_jtag} err]} {
    puts "CONNECT_ERR: $err"
    exit 2
}
set tgts [get_hw_targets]
puts "TARGETS: [llength $tgts]"
foreach t $tgts { puts "  T: $t" }
if {[llength $tgts] > 0} {
    open_hw_target [lindex $tgts 0]
    foreach d [get_hw_devices] { puts "  D: $d" }
    close_hw_target
}
close_hw_manager
puts "DONE"
