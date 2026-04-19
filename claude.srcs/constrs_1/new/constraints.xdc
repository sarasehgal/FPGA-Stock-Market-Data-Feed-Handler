# constraints.xdc - user-confirmed LAN8720 pin map

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]

# 100 MHz board oscillator
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports CLK_100MHZ]
create_clock -period 10.000 -name sys_clk [get_ports CLK_100MHZ]

# Reset button
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS25} [get_ports rst_n]

# RMII
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports rmii_ref_clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets rmii_ref_clk_IBUF]
create_clock -period 20.000 -name phy_clk [get_ports rmii_ref_clk]

set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS33} [get_ports rmii_crs_dv]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports {rmii_rxd[0]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {rmii_rxd[1]}]

set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33 SLEW FAST} [get_ports rmii_tx_en]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33 SLEW FAST} [get_ports {rmii_txd[0]}]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33 SLEW FAST} [get_ports {rmii_txd[1]}]

set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports rmii_mdio]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports rmii_mdc]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports phy_nrst]

# USB-UART: FPGA TX → FTDI RX → COM4 (A16 = "UART_RXD" in XDC = FTDI receives from FPGA)
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports uart_txd]

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

# CDC false paths
set_false_path -from [get_clocks phy_clk] -to [get_clocks -of_objects [get_pins u_top/u_pll/clk_out1]]
set_false_path -from [get_clocks -of_objects [get_pins u_top/u_pll/clk_out1]] -to [get_clocks phy_clk]
