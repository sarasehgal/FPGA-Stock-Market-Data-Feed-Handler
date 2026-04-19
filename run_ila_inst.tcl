# Create ILA IP core for direct instantiation
set proj_dir [file normalize {C:/Users/LocalAdmin/Desktop/claude - Copy}]
open_project [file join $proj_dir claude.xpr]

# Create ILA IP if it doesn't exist
set ila_ip [get_ips -quiet ila_0]
if {$ila_ip eq ""} {
    puts "Creating ila_0 IP..."
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 \
              -module_name ila_0
    set_property -dict [list \
        CONFIG.C_NUM_OF_PROBES {5} \
        CONFIG.C_DATA_DEPTH {2048} \
        CONFIG.C_PROBE0_WIDTH {1} \
        CONFIG.C_PROBE1_WIDTH {2} \
        CONFIG.C_PROBE2_WIDTH {8} \
        CONFIG.C_PROBE3_WIDTH {1} \
        CONFIG.C_PROBE4_WIDTH {1} \
        CONFIG.C_EN_STRG_QUAL {false} \
        CONFIG.C_INPUT_PIPE_STAGES {0} \
        CONFIG.ALL_PROBE_SAME_MU_CNT {1} \
    ] [get_ips ila_0]
    generate_target all [get_ips ila_0]
    synth_ip [get_ips ila_0]
    puts "ila_0 IP created and synthesized"
} else {
    puts "ila_0 already exists"
}

close_project
