// stock_feed_synth.v - Synthesis wrapper — user-confirmed PHY pin mapping
//
//   K16 → rmii_ref_clk (PHY REFCLKO in)
//   K14 → rmii_crs_dv  (REAL CRS_DV from PHY — off Pmod B)
//   H17 → rmii_rxd[0]
//   G18 → rmii_rxd[1]
//   H18 → rmii_tx_en
//   G16 → rmii_txd[0]
//   J16 → rmii_mdio
//   J15 → rmii_mdc
//   J14 → phy_nrst

`default_nettype none
`timescale 1ns/1ps

module stock_feed_synth (
    input  wire        CLK_100MHZ,
    input  wire        rst_n,

    input  wire        rmii_ref_clk,   // K16
    input  wire        rmii_crs_dv,    // K14
    input  wire [1:0]  rmii_rxd,       // [0]=H17, [1]=G18
    output wire        rmii_tx_en,     // H18
    output wire [1:0]  rmii_txd,       // [0]=G16, [1]=H16
    inout  wire        rmii_mdio,      // J16
    output wire        rmii_mdc,       // J15
    output wire        phy_nrst,       // J14

    output wire        uart_txd,       // B16 — USB-UART TX

    output wire [15:0] LED
);

wire [1:0]  int_rmii_txd;
wire        int_rmii_tx_en;
wire        int_mdc;

stock_feed_top u_top (
    .CLK_100MHZ       (CLK_100MHZ),

    .JB4_P            (rmii_ref_clk),
    .JB3_N            (rmii_rxd[0]),    // H17
    .JB1_N            (rmii_crs_dv),    // K14 → real CRS_DV
    .JB3_P            (rmii_rxd[1]),    // G18
    .JB1_P            (),               // unused
    .JAB_3            (),
    .JB4_N            (rmii_mdio),      // J16
    .JA3_N            (phy_nrst),       // J14
    .mdc_o            (int_mdc),
    .uart_txd         (uart_txd),

    .LED              (LED),

    .rmii_txd         (int_rmii_txd),
    .rmii_tx_en       (int_rmii_tx_en),

    .ext_rst_n        (~rst_n),

    .msg_valid(), .msg_type(), .msg_symbol(), .msg_price(),
    .msg_quantity(), .msg_seq_num(), .msg_side(), .msg_crc_ok(),
    .trigger_valid(), .trigger_symbol_id(), .trigger_price(),
    .trigger_quantity(), .trigger_seq_num(), .trigger_reason(),
    .symbol_halted(), .unknown_count(), .watchdog_expired(),
    .watchdog_rst     (1'b0),
    .lat_parse(), .lat_trigger(), .lat_total()
);

assign rmii_tx_en = int_rmii_tx_en;
assign rmii_txd   = int_rmii_txd;        // both bits
assign rmii_mdc   = int_mdc;

endmodule
`default_nettype wire
