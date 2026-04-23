// =============================================================================
//  stock_feed_top.v  -  Urbana board V2I1, LAN8720 RMII stock-feed pipeline
//
//  Pin assignments cross-referenced against URBANA BOARD CONSTRAINTS V2I1:
//
//  RMII pin     FPGA pin  PMOD signal   Connector position
//  -----------  --------  ------------  ------------------
//  ref_clk out  K16       JB4_P         PMOD B pin 10 (top-right)
//  crs_dv  in   K14       (JAB area)    -> mapped as JAB signal below
//  rxd[0]  in   H17       JB3_N         PMOD B pin 5
//  rxd[1]  in   G18       JB1_N         PMOD B pin 3
//  txen    out  H16       JB3_P         PMOD B pin 4  (unused)
//  txd[0]  out  H18       JB1_P         PMOD B pin 1  (unused)
//  txd[1]  out  G16       JAB_3         PMOD AB pin 3 (unused)
//  mdio    io   J16       JB4_N         PMOD B pin 9  (unused)
//  mdc     out  J15       (between B3/B4)              (unused)
//  nrst    out  J14       JA3_N         PMOD A pin 6
//
//  NOTE on rmii_crs_dv (K14):
//    K14 does NOT appear in the official JA/JB/JAB mappings in V2I1.
//    It sits between JA3_P (J13) and JA3_N (J14) in the package.
//    On the PMOD+ Ethernet module this is a dedicated pin.
//    It is constrained directly by pin location in the XDC.
//
//  Clock port name from V2I1: CLK_100MHZ  (N15, LVCMOS33)
//  LEDs: LED[15:0]  (C13..G17, LVCMOS33)
//
//  Clock plan:
//    CLK_100MHZ (100 MHz) -> clk_wiz_0 MMCM -> clk_100 (100 MHz, 0 deg)
//                                             -> clk_50  ( 50 MHz, 0 deg)
//    clk_50 driven onto JB4_P via ODDR -> LAN8720 ref_clk
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module stock_feed_top (
    input  wire        CLK_100MHZ,

    input  wire        JB4_P,   // CHANGED: K16 REFCLKO is an INPUT from PHY in crystal mode
    input  wire        JB3_N,
    input  wire        JB1_N,
    input  wire        JB3_P,
    output wire        JB1_P,
    output wire        JAB_3,
    inout  wire        JB4_N,
    output wire        JA3_N,
    output wire        mdc_o,    // MDC for PHY config
    output wire        uart_txd,     // B16 - USB-UART TXD via FTDI

    output wire [15:0] LED,

    // Stage 6 parsed message outputs
    output reg         msg_valid,
    output reg  [7:0]  msg_type,
    output reg  [31:0] msg_symbol,
    output reg  [31:0] msg_price,
    output reg  [15:0] msg_quantity,
    output reg  [15:0] msg_seq_num,
    output reg         msg_side,
    output reg         msg_crc_ok,

    // Trigger outputs
    output reg         trigger_valid,
    output reg  [3:0]  trigger_symbol_id,
    output reg  [31:0] trigger_price,
    output reg  [31:0] trigger_quantity,
    output reg  [31:0] trigger_seq_num,
    output reg  [7:0]  trigger_reason,

    // New feature outputs
    output reg  [7:0]  symbol_halted,
    output reg  [15:0] unknown_count,
    output reg         watchdog_expired,
    input  wire        watchdog_rst,

    // RMII TX outputs (clk_50 domain)
    output wire [1:0]  rmii_txd,
    output wire        rmii_tx_en,

    // Latency instrumentation outputs (cycles @ clk_100)
    output wire [31:0] lat_parse,
    output wire [31:0] lat_trigger,
    output wire [31:0] lat_total,

    // External reset (active-low, active in synthesis from board button)
    input  wire        ext_rst_n
);

// ---------------------------------------------------------------------------
//  Internal signal aliases  (keep pipeline code readable)
// ---------------------------------------------------------------------------
// RMII signal mapping (confirmed by pin probe):
//   JB4_P (K16) = REFCLKO input from PHY (50MHz) → clk_50
//   JB3_P (mapped to G18 via XDC) = CRS_DV
//   JB3_N (mapped to K14 via XDC) = RXD[0]
//   JB1_N (mapped to H16 via XDC) = RXD[1]
// RMII pin mapping (user-confirmed):
//   G18 via XDC → rmii_rxd[0] = JB3_N port
//   H17 via XDC → rmii_rxd[1] = JB3_P port
//   K14 via XDC → CRS_DV      = JB1_N port
// Double-register inputs on clk_50 to fix setup/hold on BUFG'd PHY clock
reg rmii_rxd_0_r, rmii_rxd_0_rr;
reg rmii_rxd_1_r, rmii_rxd_1_rr;
reg rmii_crs_dv_r, rmii_crs_dv_rr;
always @(posedge clk_50) begin
    rmii_rxd_0_r  <= JB3_N;   rmii_rxd_0_rr  <= rmii_rxd_0_r;
    rmii_rxd_1_r  <= JB3_P;   rmii_rxd_1_rr  <= rmii_rxd_1_r;
    rmii_crs_dv_r <= JB1_N;   rmii_crs_dv_rr <= rmii_crs_dv_r;
end
wire rmii_rxd_0   = rmii_rxd_0_rr;
wire rmii_rxd_1   = rmii_rxd_1_rr;
wire rmii_crs_dv  = rmii_crs_dv_rr;
wire dbg_crs_dv_synth = rmii_crs_dv;

assign JB1_P  = 1'b0;
assign JAB_3  = 1'b0;

// MDIO master — write 0x3100 to BMCR. Try PHY addr 1 (common LAN8720 strap).
wire mdio_o_w, mdio_oe_w, mdio_done_w;
mdio_init #(.PHY_ADDR(5'd1)) u_mdio (
    .clk     (clk_50),
    .rst_n   (rst_50_n),
    .mdc     (mdc_o),
    .mdio_o  (mdio_o_w),
    .mdio_oe (mdio_oe_w),
    .done    (mdio_done_w)
);
// Tristate JB4_N: drive when MDIO master active, else high-Z
assign JB4_N = mdio_oe_w ? mdio_o_w : 1'bz;

// ============================================================================
//  Clock generation
//  clk_50: from PHY's REFCLKO on K16 (JB4_P) via BUFG
//  clk_100: from MMCM (clk_wiz_0) driven by CLK_100MHZ
// ============================================================================
wire clk_100, clk_50, pll_locked;

// PHY provides 50MHz REFCLKO on JB4_P — buffer it for RMII domain
BUFG bufg_phy_clk (.I(JB4_P), .O(clk_50));

// MMCM for clk_100 only (still need 100MHz for pipeline stages 4+)
clk_wiz_0 u_pll (
    .clk_in1  (CLK_100MHZ),
    .clk_out1 (clk_100),
    .clk_out2 (),           // unused — clk_50 comes from PHY now
    .locked   (pll_locked)
);

// ============================================================================
//  Power-on reset
// ============================================================================
reg [19:0] rst_ctr;
wire       sys_rst_active = !pll_locked || !rst_ctr[19] || !ext_rst_n;

always @(posedge clk_100) begin
    if (!pll_locked)       rst_ctr <= 20'd0;
    else if (!rst_ctr[19]) rst_ctr <= rst_ctr + 1'b1;
end

assign JA3_N = ~sys_rst_active;

wire sys_rst_n = ~sys_rst_active;

reg [2:0] rsync_50, rsync_100;
wire rst_50_n  = rsync_50[2];
wire rst_100_n = rsync_100[2];

always @(posedge clk_50  or negedge sys_rst_n)
    if (!sys_rst_n) rsync_50  <= 3'b000;
    else            rsync_50  <= {rsync_50[1:0],  1'b1};

always @(posedge clk_100 or negedge sys_rst_n)
    if (!sys_rst_n) rsync_100 <= 3'b000;
    else            rsync_100 <= {rsync_100[1:0], 1'b1};

// ============================================================================
//  Stage 1 - RMII RX driver  (clk_50 domain)
// ============================================================================
wire [1:0] rmii_rxd_vec = {rmii_rxd_1, rmii_rxd_0};

wire       s1_valid, s1_start, s1_end, s1_err;
wire [7:0] s1_data;

// Direct ILA instantiation (mark_debug + setup_debug flow broken in Vivado 2025.2)
// ILA on clk_50 to verify TX outputs to PHY
ila_0 u_ila (
    .clk    (clk_50),
    .probe0 (s1_valid),                   // 1-bit: byte assembled
    .probe1 ({s1_start, s1_end}),         // 2-bit
    .probe2 (s1_data),                    // 8-bit: RX byte
    .probe3 (s1_start),                   // 1-bit
    .probe4 (s1_valid)                    // 1-bit
);

// Byte echo: capture first 16 received bytes and store them
// These get transmitted back to the laptop for debugging
reg [7:0] echo_buf [0:15];
reg [4:0] echo_cnt;
reg       echo_ready;
integer ei;
always @(posedge clk_50 or negedge rst_50_n) begin
    if (!rst_50_n) begin
        echo_cnt   <= 5'd0;
        echo_ready <= 1'b0;
        for (ei = 0; ei < 16; ei = ei + 1)
            echo_buf[ei] <= 8'd0;
    end else if (s1_valid) begin
        if (s1_start) begin
            echo_cnt   <= 5'd1;
            echo_buf[0] <= s1_data;
            echo_ready <= 1'b0;
        end else if (echo_cnt > 0 && echo_cnt < 16) begin
            echo_buf[echo_cnt] <= s1_data;
            echo_cnt <= echo_cnt + 5'd1;
        end else if (echo_cnt == 5'd16) begin
            echo_ready <= 1'b1; // 16 bytes captured
        end
    end
end

rmii_rx_driver u_rmii_rx (
    .clk         (clk_50),
    .rst_n       (rst_50_n),
    .rxd         (rmii_rxd_vec),
    .crsdv       (rmii_crs_dv),
    .rxerr       (1'b0),
    .byte_valid  (s1_valid),
    .byte_data   (s1_data),
    .frame_start (s1_start),
    .frame_end   (s1_end),
    .frame_err   (s1_err)
);

// ============================================================================
//  Stage 2 - CRC checker bypassed (pass S1 straight to FIFO)
// ============================================================================
wire       s2_valid = s1_valid;
wire [7:0] s2_data  = s1_data;
wire       s2_start = s1_start;
wire       s2_end   = s1_end;

// ============================================================================
//  Stage 3 - Async FIFO  (50 MHz write / 100 MHz read)
// ============================================================================
wire       s3_valid;
wire [9:0] s3_word;
wire       fifo_empty, fifo_full;

async_fifo #(
    .DATA_WIDTH (10),
    .ADDR_WIDTH (11)
) u_rx_fifo (
    .wr_clk   (clk_50),
    .wr_rst_n (rst_50_n),
    .wr_en    (s2_valid),
    .wr_data  ({s2_end, s2_start, s2_data}),
    .full     (fifo_full),

    .rd_clk   (clk_100),
    .rd_rst_n (rst_100_n),
    .rd_en    (!fifo_empty),
    .rd_data  (s3_word),
    .rd_valid (s3_valid),
    .empty    (fifo_empty)
);

wire [7:0] s3_byte  = s3_word[7:0];
wire       s3_start = s3_word[8];
wire       s3_end   = s3_word[9];

// ============================================================================
//  Stage 4 - Ethernet header stripper  (clk_100)
// ============================================================================
wire       s4_valid, s4_start, s4_end, s4_etype_ok;
wire [7:0] s4_data;

eth_header_stripper #(
    .HDR_BYTES (14),
    .ETHERTYPE (16'h88B5)
) u_hdr (
    .clk          (clk_100),
    .rst_n        (rst_100_n),
    .in_valid     (s3_valid),
    .in_data      (s3_byte),
    .in_start     (s3_start),
    .in_end       (s3_end),
    .out_valid    (s4_valid),
    .out_data     (s4_data),
    .out_start    (s4_start),
    .out_end      (s4_end),
    .ethertype_ok (s4_etype_ok)
);

// ============================================================================
//  Stage 5a - Payload assembler  (clk_100)
//  15 bytes -> 120-bit word
// ============================================================================
wire         s5_valid;
wire [119:0] s5_data;

payload_assembler #(
    .PAYLOAD_BYTES (15)
) u_asm (
    .clk       (clk_100),
    .rst_n     (rst_100_n),
    .in_valid  (s4_valid),
    .in_data   (s4_data),
    .in_start  (s4_start),
    .in_end    (s4_end),
    .out_valid (s5_valid),
    .out_data  (s5_data),
    .overflow  ()
);

// ============================================================================
//  Stage 5b - Message FIFO  (clk_100, 16 entries x 120 bits)
// ============================================================================
wire         mf_full, mf_empty, mf_valid;
wire [119:0] mf_data;

sync_fifo #(
    .DATA_WIDTH (120),
    .ADDR_WIDTH (4)
) u_msg_fifo (
    .clk      (clk_100),
    .rst_n    (rst_100_n),
    .wr_en    (s5_valid & !mf_full),
    .wr_data  (s5_data),
    .full     (mf_full),
    .rd_en    (!mf_empty),
    .rd_data  (mf_data),
    .rd_valid (mf_valid),
    .empty    (mf_empty)
);

// ============================================================================
//  Stage 6 - Stock message parser + checksum  (clk_100)
//
//  Payload layout (big-endian, 15 bytes / 120 bits):
//   [119:112] msg_type     8b   (byte 0)
//   [111:80]  symbol       32b  (bytes 1-4, 4 ASCII)
//   [79:48]   price        32b  (bytes 5-8)
//   [47:32]   quantity     16b  (bytes 9-10)
//   [31:16]   seq_num      16b  (bytes 11-12)
//   [15:8]    side         8b   (byte 13: 0=bid, 1=ask)
//   [7:0]     checksum     8b   (byte 14: sum of bytes 0-13 mod 256)
// ============================================================================
function [7:0] payload_cksum;
    input [119:0] p;
    integer b;
    reg [7:0] acc;
    begin
        acc = 8'h00;
        for (b = 0; b <= 13; b = b + 1)
            acc = acc + p[119 - b*8 -: 8];
        payload_cksum = acc;
    end
endfunction

always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        msg_valid    <= 1'b0;
        msg_type     <= 8'h0;
        msg_symbol   <= 32'h0;
        msg_price    <= 32'h0;
        msg_quantity <= 16'h0;
        msg_seq_num  <= 16'h0;
        msg_side     <= 1'b0;
        msg_crc_ok   <= 1'b0;
    end else begin
        msg_valid <= 1'b0;
        if (mf_valid) begin
            msg_valid    <= 1'b1;
            msg_type     <= mf_data[119:112];
            msg_symbol   <= mf_data[111:80];
            msg_price    <= mf_data[79:48];
            msg_quantity <= mf_data[47:32];
            msg_seq_num  <= mf_data[31:16];
            msg_side     <= mf_data[8];
            msg_crc_ok   <= (payload_cksum(mf_data) == mf_data[7:0]);
        end
    end
end

// ============================================================================
//  Message Type Router  (combinational decode, clk_100)
// ============================================================================
localparam [7:0] MT_QUOTE  = 8'h01,
                 MT_TRADE  = 8'h02,
                 MT_CANCEL = 8'h03,
                 MT_HALT   = 8'h04,
                 MT_HB     = 8'h05;

wire msg_is_quote  = msg_valid && msg_crc_ok && (msg_type == MT_QUOTE);
wire msg_is_trade  = msg_valid && msg_crc_ok && (msg_type == MT_TRADE);
wire msg_is_cancel = msg_valid && msg_crc_ok && (msg_type == MT_CANCEL);
wire msg_is_halt   = msg_valid && msg_crc_ok && (msg_type == MT_HALT);
wire msg_is_hb     = msg_valid && msg_crc_ok && (msg_type == MT_HB);
wire msg_is_unknown = msg_valid && msg_crc_ok &&
                      (msg_type != MT_QUOTE) && (msg_type != MT_TRADE) &&
                      (msg_type != MT_CANCEL) && (msg_type != MT_HALT) &&
                      (msg_type != MT_HB);

// Route quote and trade to book_state_manager; cancel also goes there
wire route_to_book = msg_is_quote || msg_is_trade || msg_is_cancel;

// ============================================================================
//  Stage 7 - Symbol LUT / book state / trigger engine  (clk_100)
// ============================================================================
wire [3:0] symbol_id;
wire       symbol_valid;

wire       book_update_valid;
wire [3:0] book_update_symbol_id;
wire [31:0] book_update_price;
wire [31:0] book_update_quantity;
wire [31:0] book_update_seq_num;
wire        book_update_side;

wire       trig_valid_w;
wire [3:0] trig_symbol_id_w;
wire [31:0] trig_price_w;
wire [31:0] trig_quantity_w;
wire [31:0] trig_seq_num_w;
wire [7:0]  trig_reason_w;

wire [31:0] best_bid_w, best_ask_w;

symbol_lut u_symbol_lut (
    .symbol_ascii (msg_symbol),
    .symbol_id    (symbol_id),
    .symbol_valid (symbol_valid)
);

book_state_manager #(
    .NUM_SYMBOLS (8)
) u_book (
    .clk             (clk_100),
    .rst_n           (rst_100_n),

    .msg_valid       (route_to_book),
    .msg_type        (msg_type),
    .symbol_id       (symbol_id),
    .symbol_valid    (symbol_valid),
    .price           (msg_price),
    .quantity        ({16'd0, msg_quantity}),
    .seq_num         ({16'd0, msg_seq_num}),
    .msg_side        (msg_side),
    .msg_crc_ok      (1'b1),
    .msg_is_cancel   (msg_is_cancel),

    .update_valid     (book_update_valid),
    .update_symbol_id (book_update_symbol_id),
    .update_price     (book_update_price),
    .update_quantity  (book_update_quantity),
    .update_seq_num   (book_update_seq_num),
    .update_side      (book_update_side),

    .best_bid         (best_bid_w),
    .best_ask         (best_ask_w),

    .book_valid_bits  ()
);

trigger_engine #(
    .NUM_SYMBOLS (8)
) u_trigger (
    .clk              (clk_100),
    .rst_n            (rst_100_n),

    .update_valid     (book_update_valid),
    .update_symbol_id (book_update_symbol_id),
    .update_price     (book_update_price),
    .update_quantity  (book_update_quantity),
    .update_seq_num   (book_update_seq_num),
    .update_side      (book_update_side),

    .best_bid         (best_bid_w),
    .best_ask         (best_ask_w),

    .symbol_halted    (symbol_halted),

    .trigger_valid      (trig_valid_w),
    .trigger_symbol_id  (trig_symbol_id_w),
    .trigger_price      (trig_price_w),
    .trigger_quantity   (trig_quantity_w),
    .trigger_seq_num    (trig_seq_num_w),
    .trigger_reason     (trig_reason_w)
);

// =================================================================
//  Latency measurement: RX ingress → trigger fire (in clk_100 cycles)
// =================================================================
reg [15:0] trig_latency;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n)          trig_latency <= 16'd0;
    else if (trig_valid_w)   trig_latency <= cycle_counter[15:0] - ts_rx_ingress_tmp[15:0];

// =================================================================
//  UART trigger output
//  Format: TRIG:AAPL:0x0001E240:b:142\r\n
// =================================================================
wire [7:0] uart_byte;
wire       uart_valid;
wire       uart_ready;

trigger_uart u_trig_uart (
    .clk            (clk_100),
    .rst_n          (rst_100_n),
    .trigger_fire   (trig_valid_w),
    .trigger_symbol (msg_symbol),
    .trigger_price  (trig_price_w),
    .trigger_reason (trig_reason_w),
    .trigger_latency(trig_latency),
    .tx_data        (uart_byte),
    .tx_valid       (uart_valid),
    .tx_ready       (uart_ready)
);

uart_tx #(.CLK_DIV(868)) u_uart_tx (
    .clk    (clk_100),
    .rst_n  (rst_100_n),
    .data   (uart_byte),
    .valid  (uart_valid),
    .ready  (uart_ready),
    .tx     (uart_txd)
);

always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        trigger_valid      <= 1'b0;
        trigger_symbol_id  <= 4'd0;
        trigger_price      <= 32'd0;
        trigger_quantity   <= 32'd0;
        trigger_seq_num    <= 32'd0;
        trigger_reason     <= 8'd0;
    end else begin
        trigger_valid <= trig_valid_w;
        if (trig_valid_w) begin
            trigger_symbol_id  <= trig_symbol_id_w;
            trigger_price      <= trig_price_w;
            trigger_quantity   <= trig_quantity_w;
            trigger_seq_num    <= trig_seq_num_w;
            trigger_reason     <= trig_reason_w;
        end
    end
end

// ============================================================================
//  Symbol Halt Register
// ============================================================================
always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        symbol_halted <= 8'b0;
    end else begin
        if (msg_is_halt && symbol_valid && symbol_id < 8)
            symbol_halted[symbol_id] <= 1'b1;
    end
end

// ============================================================================
//  Unknown Message Counter
// ============================================================================
always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n)
        unknown_count <= 16'd0;
    else if (msg_is_unknown)
        unknown_count <= unknown_count + 16'd1;
end

// ============================================================================
//  Watchdog Timer (10,000,000 cycle timeout ~ 100ms @ 100 MHz)
// ============================================================================
reg [23:0] wdog_ctr;

always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        wdog_ctr         <= 24'd0;
        watchdog_expired <= 1'b0;
    end else begin
        if (msg_is_hb || watchdog_rst) begin
            wdog_ctr         <= 24'd0;
            watchdog_expired <= 1'b0;
        end else if (wdog_ctr >= 24'd9_999_999) begin
            watchdog_expired <= 1'b1;
        end else begin
            wdog_ctr <= wdog_ctr + 24'd1;
        end
    end
end

// ============================================================================
//  TX Path: trigger -> packet builder -> RMII TX driver  (clk_50 domain)
//
//  CDC: latch trigger fields in clk_100, pulse-sync the fire signal to clk_50.
// ============================================================================

// Latch trigger info in clk_100 (stable for the CDC crossing)
reg        trig_fire_100;
reg [31:0] trig_sym_lat;
reg [31:0] trig_price_lat;
reg [7:0]  trig_reason_lat;
reg [15:0] trig_seq_lat;

always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        trig_fire_100  <= 1'b0;
        trig_sym_lat   <= 32'd0;
        trig_price_lat <= 32'd0;
        trig_reason_lat<= 8'd0;
        trig_seq_lat   <= 16'd0;
    end else begin
        trig_fire_100 <= 1'b0;
        if (trig_valid_w) begin
            trig_fire_100   <= 1'b1;
            trig_sym_lat    <= msg_symbol;
            trig_price_lat  <= trig_price_w;
            trig_reason_lat <= trig_reason_w;
            trig_seq_lat    <= msg_seq_num;
        end
    end
end

// Toggle-based pulse CDC: clk_100 -> clk_50
reg trig_toggle_100;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n) trig_toggle_100 <= 1'b0;
    else if (trig_fire_100) trig_toggle_100 <= ~trig_toggle_100;

reg [2:0] trig_sync_50;
always @(posedge clk_50 or negedge rst_50_n)
    if (!rst_50_n) trig_sync_50 <= 3'b000;
    else           trig_sync_50 <= {trig_sync_50[1:0], trig_toggle_100};

wire trig_fire_50 = trig_sync_50[2] ^ trig_sync_50[1];

// RMII TX path REMOVED — responses are now sent via UART (uart_txd) instead.
// Tie outputs low so PHY sees idle TX line.
assign rmii_txd   = 2'b00;
assign rmii_tx_en = 1'b0;

// ============================================================================
//  Latency Instrumentation
// ============================================================================
reg [31:0] cycle_counter;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n) cycle_counter <= 32'd0;
    else            cycle_counter <= cycle_counter + 32'd1;

// Capture RX ingress timestamp at s1_start (clk_50 reads clk_100 counter)
reg [31:0] ts_rx_ingress_tmp;
always @(posedge clk_50 or negedge rst_50_n)
    if (!rst_50_n)     ts_rx_ingress_tmp <= 32'd0;
    else if (s1_start) ts_rx_ingress_tmp <= cycle_counter;

// Per-slot timestamp arrays indexed by seq_num[1:0]
reg [31:0] ts_rx_ingress [0:3];
reg [31:0] ts_msg_valid  [0:3];

integer lat_i;
always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        for (lat_i = 0; lat_i < 4; lat_i = lat_i + 1) begin
            ts_rx_ingress[lat_i] <= 32'd0;
            ts_msg_valid[lat_i]  <= 32'd0;
        end
    end else if (msg_valid) begin
        ts_rx_ingress[msg_seq_num[1:0]] <= ts_rx_ingress_tmp;
        ts_msg_valid[msg_seq_num[1:0]]  <= cycle_counter;
    end
end

// TX done timestamp captured when last byte of TX packet is consumed (clk_50)
reg [31:0] ts_tx_done [0:3];
integer lat_j;
always @(posedge clk_50 or negedge rst_50_n) begin
    if (!rst_50_n) begin
        for (lat_j = 0; lat_j < 4; lat_j = lat_j + 1)
            ts_tx_done[lat_j] <= 32'd0;
    end else if (trig_fire_50) begin
        ts_tx_done[trig_seq_lat[1:0]] <= cycle_counter;
    end
end

// Derived latency outputs (most recent trigger frame)
wire [1:0] lat_slot = trig_seq_lat[1:0];
assign lat_parse   = ts_msg_valid[lat_slot]  - ts_rx_ingress[lat_slot];
assign lat_trigger = ts_tx_done[lat_slot]    - ts_msg_valid[lat_slot];
assign lat_total   = ts_tx_done[lat_slot]    - ts_rx_ingress[lat_slot];

// ============================================================================
//  Status LEDs  -  visible activity for demo
//
//  LED[0]     : heartbeat ~1.5 Hz (proves FPGA is alive)
//  LED[1]     : PLL locked (solid ON = clock OK)
//  LED[2]     : RX activity flash (stretches CRS_DV pulses to ~50ms)
//  LED[3]     : message received flash (~100ms per message)
//  LED[4]     : TX activity flash (stretches tx_en to ~50ms)
//  LED[5]     : trigger fired flash (~200ms)
//  LED[6]     : any symbol halted
//  LED[7]     : watchdog expired
//  LED[15:8]  : trigger chase animation (Knight Rider sweep on trigger)
// ============================================================================
reg [25:0] hb_ctr;
always @(posedge clk_100) hb_ctr <= hb_ctr + 1'b1;

// RX activity stretcher
reg [21:0] rx_stretch;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n)          rx_stretch <= 22'd0;
    else if (s1_valid)       rx_stretch <= 22'h3FFFFF;
    else if (|rx_stretch)    rx_stretch <= rx_stretch - 1'b1;

// Message received stretcher
reg [22:0] msg_stretch;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n)          msg_stretch <= 23'd0;
    else if (msg_valid)      msg_stretch <= 23'h7FFFFF;
    else if (|msg_stretch)   msg_stretch <= msg_stretch - 1'b1;

// TX activity stretcher (sync tx_en from clk_50 domain)
reg tx_en_s0, tx_en_s1;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n) {tx_en_s1, tx_en_s0} <= 2'b00;
    else            {tx_en_s1, tx_en_s0} <= {tx_en_s0, uart_valid};   // UART byte = "TX activity"

reg [21:0] tx_stretch;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n)          tx_stretch <= 22'd0;
    else if (tx_en_s1)       tx_stretch <= 22'h3FFFFF;
    else if (|tx_stretch)    tx_stretch <= tx_stretch - 1'b1;

// Trigger fired stretcher
reg [23:0] trig_stretch;
always @(posedge clk_100 or negedge rst_100_n)
    if (!rst_100_n)           trig_stretch <= 24'd0;
    else if (trig_valid_w)    trig_stretch <= 24'hFFFFFF;
    else if (|trig_stretch)   trig_stretch <= trig_stretch - 1'b1;

// Trigger chase animation (Knight Rider sweep on LED[15:8])
// When trigger fires, start a sweep left then right across 8 LEDs
reg [2:0]  chase_pos;
reg        chase_dir;    // 0=left, 1=right
reg [19:0] chase_timer;
reg        chase_active;
reg [4:0]  chase_cycles; // number of sweeps remaining

always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        chase_pos    <= 3'd0;
        chase_dir    <= 1'b0;
        chase_timer  <= 20'd0;
        chase_active <= 1'b0;
        chase_cycles <= 5'd0;
    end else begin
        if (trig_valid_w) begin
            chase_active <= 1'b1;
            chase_pos    <= 3'd0;
            chase_dir    <= 1'b0;
            chase_timer  <= 20'd0;
            chase_cycles <= 5'd6; // 3 full left-right sweeps
        end else if (chase_active) begin
            if (chase_timer >= 20'd400_000) begin // ~4ms per position step
                chase_timer <= 20'd0;
                if (!chase_dir) begin
                    if (chase_pos == 3'd7) begin
                        chase_dir <= 1'b1;
                        chase_cycles <= chase_cycles - 1'b1;
                    end else begin
                        chase_pos <= chase_pos + 1'b1;
                    end
                end else begin
                    if (chase_pos == 3'd0) begin
                        chase_dir <= 1'b0;
                        if (chase_cycles == 5'd0)
                            chase_active <= 1'b0;
                        else
                            chase_cycles <= chase_cycles - 1'b1;
                    end else begin
                        chase_pos <= chase_pos - 1'b1;
                    end
                end
            end else begin
                chase_timer <= chase_timer + 1'b1;
            end
        end
    end
end

// Chase LED pattern: light the active position and neighbors for a wider glow
wire [7:0] chase_leds;
assign chase_leds = chase_active ?
    (8'd1 << chase_pos) | (chase_pos > 0 ? (8'd1 << (chase_pos - 1)) : 8'd0) :
    8'd0;

// Stage-by-stage debug stretchers (each ~100ms)
reg [22:0] s2_stretch, s3_stretch, s4_stretch, s4e_stretch, s5_stretch, mf_stretch;

always @(posedge clk_100 or negedge rst_100_n) begin
    if (!rst_100_n) begin
        s2_stretch  <= 0; s3_stretch  <= 0;
        s4_stretch  <= 0; s4e_stretch <= 0;
        s5_stretch  <= 0; mf_stretch  <= 0;
    end else begin
        if (s2_valid)      s2_stretch  <= 23'h7FFFFF; else if (|s2_stretch)  s2_stretch  <= s2_stretch  - 1;
        if (s3_valid)      s3_stretch  <= 23'h7FFFFF; else if (|s3_stretch)  s3_stretch  <= s3_stretch  - 1;
        if (s4_valid)      s4_stretch  <= 23'h7FFFFF; else if (|s4_stretch)  s4_stretch  <= s4_stretch  - 1;
        if (s4_etype_ok)   s4e_stretch <= 23'h7FFFFF; else if (|s4e_stretch) s4e_stretch <= s4e_stretch - 1;
        if (s5_valid)      s5_stretch  <= 23'h7FFFFF; else if (|s5_stretch)  s5_stretch  <= s5_stretch  - 1;
        if (mf_valid)      mf_stretch  <= 23'h7FFFFF; else if (|mf_stretch)  mf_stretch  <= mf_stretch  - 1;
    end
end

// NOTE: s2_valid is in clk_50 domain, reading from clk_100 stretch is a CDC
// violation but acceptable for debug LEDs

assign LED[0]  = hb_ctr[25];          // heartbeat blink
assign LED[1]  = pll_locked;          // solid when clocks OK
assign LED[2]  = |rx_stretch;         // S1: RMII RX byte activity
assign LED[3]  = |msg_stretch;        // S6: message parsed
assign LED[4]  = |tx_stretch;         // TX response sent
assign LED[5]  = |trig_stretch;       // trigger fired
assign LED[6]  = |symbol_halted;      // any halt active
assign LED[7]  = watchdog_expired;    // watchdog alarm
// Raw pin values directly on LEDs (no processing)
// LED[8]  = CRS_DV pin (H14) — should be LOW idle, HIGH during frame
// LED[9]  = RXD[0] pin (H16) — should flicker during frame
// LED[10] = RXD[1] pin (H17) — should flicker during frame
// LED[11] = JB1_P (H18) raw
// LED[12] = JB1_N (G18) raw — what the original code used as RXD[1]
// LED[13] = JB4_P ref_clk ODDR output (should be always toggling = dim)
// LED[14] = echo_buf[0] bit 0
// LED[15] = echo_ready
assign LED[8]  = rmii_crs_dv;     // H14
assign LED[9]  = rmii_rxd_0;      // H16 via wrapper
assign LED[10] = rmii_rxd_1;      // H17 via wrapper
assign LED[11] = JB1_P;           // H18 raw
assign LED[12] = JB1_N;           // G18 raw
assign LED[13] = mdio_done_w;     // MDIO write completed
assign LED[14] = echo_buf[0][0];
assign LED[15] = echo_ready;

endmodule
`default_nettype wire
