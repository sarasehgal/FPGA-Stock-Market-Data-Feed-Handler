set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]

set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports CLK_100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK_100MHZ]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports rst_n]

# Probe: Pmod A area + neighbors of K14 (confirmed CRS_DV)
# Looking for PHY RXD[1] overhanging from Pmod B into Pmod A
# [7]=J13  [6]=J14  [5]=L13  [4]=L14  [3]=M13  [2]=M14  [1]=K13  [0]=G18(ref RXD[0])
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports K14]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports K15]
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS33} [get_ports J13]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports J15]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports G16]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports H15]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports H16]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports K16]

# LEDs
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN A17 IOSTANDARD LVCMOS33} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN C18 IOSTANDARD LVCMOS33} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS33} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports {LED[15]}]
