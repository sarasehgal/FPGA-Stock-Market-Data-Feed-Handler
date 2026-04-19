// =============================================================================
//  tb_debug.v  -  Full pipeline testbench with TX response verification
//  15-byte protocol, message routing, halt, watchdog, RMII TX loopback check
// =============================================================================

`timescale 1ns/1ps
`default_nettype none

// Stubs
module clk_wiz_0 (
    input  wire clk_in1,
    output reg  clk_out1,
    output reg  clk_out2,
    output reg  locked
);
    always @(clk_in1)         clk_out1 <= clk_in1;
    always @(posedge clk_in1) clk_out2 <= ~clk_out2;
    initial begin
        clk_out1 = 0;
        clk_out2 = 0;
        locked   = 0;
        #200;
        locked   = 1;
    end
endmodule

module ODDR #(
    parameter DDR_CLK_EDGE = "SAME_EDGE",
    parameter INIT         = 1'b0,
    parameter SRTYPE       = "SYNC"
)(
    output reg  Q,
    input  wire C, CE, D1, D2, R, S
);
    initial Q = INIT;
    always @(posedge C) if (CE) Q <= D1;
endmodule

// Testbench
module tb_debug;

reg CLK_100MHZ = 0;
always #5 CLK_100MHZ = ~CLK_100MHZ;

wire        JB4_P;
reg         JB3_N = 0;
reg         JB1_N = 0;
reg         JB3_P = 0;
wire        JB1_P, JAB_3, JB4_N, JA3_N;
wire [15:0] LED;

wire        msg_valid;
wire [7:0]  msg_type;
wire [31:0] msg_symbol;
wire [31:0] msg_price;
wire [15:0] msg_quantity, msg_seq_num;
wire        msg_side;
wire        msg_crc_ok;

wire        trigger_valid;
wire [3:0]  trigger_symbol_id;
wire [31:0] trigger_price;
wire [31:0] trigger_quantity;
wire [31:0] trigger_seq_num;
wire [7:0]  trigger_reason;

wire [7:0]  symbol_halted;
wire [15:0] unknown_count;
wire        watchdog_expired;
reg         watchdog_rst = 0;

wire [1:0]  rmii_txd;
wire        rmii_tx_en;

wire [31:0] lat_parse, lat_trigger, lat_total;

stock_feed_top dut (
    .CLK_100MHZ(CLK_100MHZ),
    .JB4_P(JB4_P), .JB3_N(JB3_N), .JB1_N(JB1_N), .JB3_P(JB3_P),
    .JB1_P(JB1_P), .JAB_3(JAB_3), .JB4_N(JB4_N), .JA3_N(JA3_N),
    .LED(LED),
    .msg_valid(msg_valid), .msg_type(msg_type), .msg_symbol(msg_symbol),
    .msg_price(msg_price), .msg_quantity(msg_quantity),
    .msg_seq_num(msg_seq_num), .msg_side(msg_side), .msg_crc_ok(msg_crc_ok),
    .trigger_valid(trigger_valid), .trigger_symbol_id(trigger_symbol_id),
    .trigger_price(trigger_price), .trigger_quantity(trigger_quantity),
    .trigger_seq_num(trigger_seq_num), .trigger_reason(trigger_reason),
    .symbol_halted(symbol_halted), .unknown_count(unknown_count),
    .watchdog_expired(watchdog_expired), .watchdog_rst(watchdog_rst),
    .rmii_txd(rmii_txd), .rmii_tx_en(rmii_tx_en),
    .lat_parse(lat_parse), .lat_trigger(lat_trigger), .lat_total(lat_total),
    .ext_rst_n(1'b1)
);

wire clk_50  = dut.clk_50;
wire clk_100 = dut.clk_100;

// ── Counters ─────────────────────────────────────────────────────────────────
integer s6_msg_cnt  = 0;
integer trig_cnt    = 0;
integer pass_cnt    = 0, fail_cnt = 0;

// ── Stage 6 monitor ──────────────────────────────────────────────────────────
always @(posedge clk_100) begin
    if (msg_valid) begin
        s6_msg_cnt = s6_msg_cnt + 1;
        $display("[S6-OUT   @%0t] msg #%0d type=%02h sym=%h price=%0d qty=%0d seq=%0d side=%0b crc_ok=%0b",
                 $time, s6_msg_cnt, msg_type, msg_symbol, msg_price, msg_quantity,
                 msg_seq_num, msg_side, msg_crc_ok);
    end
end

// ── Trigger monitor ──────────────────────────────────────────────────────────
always @(posedge clk_100) begin
    if (trigger_valid) begin
        trig_cnt = trig_cnt + 1;
        $display("[TRIG     @%0t] #%0d sym_id=%0d price=%0d qty=%0d seq=%0d reason=%0d",
                 $time, trig_cnt, trigger_symbol_id, trigger_price,
                 trigger_quantity, trigger_seq_num, trigger_reason);
    end
end

// ── RMII RX helpers (for sending frames to DUT) ─────────────────────────────
function [31:0] crc32_step;
    input [31:0] crc;
    input [7:0]  d;
    integer k;
    reg [31:0] c;
    begin
        c = crc ^ {24'h0, d};
        for (k = 0; k < 8; k = k + 1)
            c = c[0] ? (c >> 1) ^ 32'hEDB88320 : (c >> 1);
        crc32_step = c;
    end
endfunction

task send_byte;
    input [7:0] data;
    integer i;
    begin
        for (i = 0; i < 4; i = i + 1) begin
            @(negedge clk_50);
            JB3_N = data[i*2];
            JB1_N = data[i*2+1];
        end
    end
endtask

reg [7:0] fbuf [0:1535];
integer   flen;

task send_frame;
    input integer len;
    input integer corrupt;
    integer i;
    reg [31:0] crc;
    reg [7:0]  fcs[0:3];
    begin
        crc = 32'hFFFF_FFFF;
        for (i = 0; i < len; i = i + 1)
            crc = crc32_step(crc, fbuf[i]);
        crc = ~crc;
        fcs[0] = crc[7:0];  fcs[1] = crc[15:8];
        fcs[2] = crc[23:16]; fcs[3] = crc[31:24];
        if (corrupt) fcs[3] = fcs[3] ^ 8'hFF;

        @(negedge clk_50);
        JB3_P = 1'b1;
        repeat (7) send_byte(8'h55);
        send_byte(8'hD5);
        for (i = 0; i < len; i = i + 1) send_byte(fbuf[i]);
        for (i = 0; i < 4; i = i + 1)   send_byte(fcs[i]);
        repeat (4) @(posedge clk_50);
        JB3_P = 1'b0; JB3_N = 1'b0; JB1_N = 1'b0;
        repeat (12) @(posedge clk_50);
    end
endtask

task build_frame;
    input [7:0]  mt;
    input [31:0] sym;
    input [31:0] price;
    input [15:0] qty;
    input [15:0] seq;
    input        side;
    reg [7:0] ck;
    begin
        fbuf[0]=8'hFF; fbuf[1]=8'hFF; fbuf[2]=8'hFF;
        fbuf[3]=8'hFF; fbuf[4]=8'hFF; fbuf[5]=8'hFF;
        fbuf[6]=8'hDE; fbuf[7]=8'hAD; fbuf[8]=8'hBE;
        fbuf[9]=8'hEF; fbuf[10]=8'hCA; fbuf[11]=8'hFE;
        fbuf[12]=8'h88; fbuf[13]=8'hB5;
        fbuf[14] = mt;
        fbuf[15] = sym[31:24]; fbuf[16] = sym[23:16];
        fbuf[17] = sym[15:8];  fbuf[18] = sym[7:0];
        fbuf[19] = price[31:24]; fbuf[20] = price[23:16];
        fbuf[21] = price[15:8];  fbuf[22] = price[7:0];
        fbuf[23] = qty[15:8];   fbuf[24] = qty[7:0];
        fbuf[25] = seq[15:8];   fbuf[26] = seq[7:0];
        fbuf[27] = {7'd0, side};
        ck = fbuf[14]+fbuf[15]+fbuf[16]+fbuf[17]+fbuf[18]+fbuf[19]+fbuf[20]+
             fbuf[21]+fbuf[22]+fbuf[23]+fbuf[24]+fbuf[25]+fbuf[26]+fbuf[27];
        fbuf[28] = ck;
        flen = 29;
    end
endtask

task check;
    input integer cond;
    input [64*8-1:0] label;
    begin
        if (cond) begin
            $display("[PASS] %0s", label);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0s", label);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ═════════════════════════════════════════════════════════════════════════════
//  TX capture: reconstruct bytes from RMII TX output
//  Sample rmii_txd on posedge clk_50 while rmii_tx_en is high.
//  Detect preamble+SFD, then assemble dibits into bytes.
// ═════════════════════════════════════════════════════════════════════════════
integer tx_pkt_cnt = 0;

reg [7:0]  tx_cap_buf [0:255];  // captured frame bytes (after SFD)
integer    tx_cap_len;

// Storage for up to 4 captured response packets
reg [7:0]  resp_buf [0:3][0:63];
integer    resp_len [0:3];

reg [63:0] tx_sr;         // shift register for preamble/SFD detection
reg        tx_sfd_found;
reg [1:0]  tx_phase;
reg [7:0]  tx_byte_sr;
integer    tx_byte_idx;

always @(posedge clk_50 or negedge dut.rst_50_n) begin
    if (!dut.rst_50_n) begin
        tx_sr        <= 64'd0;
        tx_sfd_found <= 1'b0;
        tx_phase     <= 2'd0;
        tx_byte_sr   <= 8'd0;
        tx_byte_idx  <= 0;
        tx_cap_len   <= 0;
    end else begin
        if (rmii_tx_en) begin
            tx_sr <= {rmii_txd, tx_sr[63:2]};

            if (!tx_sfd_found) begin
                if ({rmii_txd, tx_sr[63:2]} == 64'hD555555555555555) begin
                    tx_sfd_found <= 1'b1;
                    tx_phase     <= 2'd0;
                    tx_byte_idx  <= 0;
                    tx_cap_len   <= 0;
                end
            end else begin
                case (tx_phase)
                    2'd0: begin tx_byte_sr[1:0] <= rmii_txd; tx_phase <= 2'd1; end
                    2'd1: begin tx_byte_sr[3:2] <= rmii_txd; tx_phase <= 2'd2; end
                    2'd2: begin tx_byte_sr[5:4] <= rmii_txd; tx_phase <= 2'd3; end
                    2'd3: begin
                        tx_cap_buf[tx_byte_idx] <= {rmii_txd, tx_byte_sr[5:0]};
                        tx_byte_idx <= tx_byte_idx + 1;
                        tx_cap_len  <= tx_byte_idx + 1;
                        tx_phase    <= 2'd0;
                    end
                endcase
            end
        end else begin
            if (tx_sfd_found && tx_cap_len > 0) begin
                // Frame ended, save it
                $display("[TX-CAP   @%0t] Captured TX frame #%0d, %0d bytes", $time, tx_pkt_cnt, tx_cap_len);
                tx_pkt_cnt = tx_pkt_cnt + 1;
            end
            tx_sfd_found <= 1'b0;
            tx_phase     <= 2'd0;
            tx_sr        <= 64'd0;
        end
    end
end

// Copy captured data into resp_buf when frame ends
// (Done via a separate always block watching tx_en falling edge)
reg tx_en_d;
always @(posedge clk_50 or negedge dut.rst_50_n) begin
    if (!dut.rst_50_n) begin
        tx_en_d <= 1'b0;
    end else begin
        tx_en_d <= rmii_tx_en;
        if (tx_en_d && !rmii_tx_en && tx_sfd_found && tx_cap_len > 0) begin
            // On the cycle AFTER tx_en drops, copy data
        end
    end
end

// Use a task to copy cap_buf into resp_buf at specific points
task save_tx_response;
    input integer idx;
    integer k;
    begin
        resp_len[idx] = tx_cap_len;
        for (k = 0; k < tx_cap_len && k < 64; k = k + 1)
            resp_buf[idx][k] = tx_cap_buf[k];
    end
endtask

// ── Latency tracking ────────────────────────────────────────────────────────
reg [31:0] lat_parse_log  [0:2];
reg [31:0] lat_trig_log   [0:2];
reg [31:0] lat_total_log  [0:2];
integer    lat_log_idx = 0;

task print_latency;
    input [1:0]       slot;
    input [15:0]      seq;
    input [64*8-1:0]  sym_name;
    reg [31:0] lp, lt, ltot;
    begin
        lp   = dut.ts_msg_valid[slot] - dut.ts_rx_ingress[slot];
        lt   = dut.ts_tx_done[slot]   - dut.ts_msg_valid[slot];
        ltot = dut.ts_tx_done[slot]   - dut.ts_rx_ingress[slot];
        lat_parse_log[lat_log_idx] = lp;
        lat_trig_log[lat_log_idx]  = lt;
        lat_total_log[lat_log_idx] = ltot;
        lat_log_idx = lat_log_idx + 1;
        $display("[LATENCY] Frame seq=%0d %0s", seq, sym_name);
        $display("  RX ingress  -> msg_valid : %0d cycles  (%0d ns at 100MHz)", lp, lp * 10);
        $display("  msg_valid   -> TX done   : %0d cycles", lt);
        $display("  Total end-to-end         : %0d cycles  (%0d ns)", ltot, ltot * 10);
    end
endtask

// ═════════════════════════════════════════════════════════════════════════════
//  Main test sequence
// ═════════════════════════════════════════════════════════════════════════════
integer resp_idx;

initial begin
    $dumpfile("tb_debug.vcd");
    $dumpvars(0, tb_debug);

    repeat(5) @(posedge clk_100);
    force dut.rst_ctr   = 20'h80000;
    force dut.rsync_50  = 3'b111;
    force dut.rsync_100 = 3'b111;
    repeat(20) @(posedge clk_100);
    release dut.rst_ctr;
    release dut.rsync_50;
    release dut.rsync_100;
    repeat(10) @(posedge clk_100);

    resp_idx = 0;

    $display("\n[tb] Reset released. Starting 8-frame test sequence.\n");

    // =================================================================
    //  Frame 1: Quote AAPL bid price=123456 qty=100 seq=42
    // =================================================================
    $display("[tb] Frame 1: Quote AAPL bid price=123456");
    build_frame(8'h01, "AAPL", 32'd123456, 16'd100, 16'd42, 1'b0);
    send_frame(flen, 0);
    repeat(600) @(posedge clk_50);
    save_tx_response(0);
    print_latency(2'd2, 16'd42, "AAPL");
    resp_idx = resp_idx + 1;

    // =================================================================
    //  Frame 2: Trade MSFT ask price=223344 qty=250 seq=43
    // =================================================================
    $display("[tb] Frame 2: Trade MSFT ask price=223344");
    build_frame(8'h02, "MSFT", 32'd223344, 16'd250, 16'd43, 1'b1);
    send_frame(flen, 0);
    repeat(600) @(posedge clk_50);
    save_tx_response(1);
    print_latency(2'd3, 16'd43, "MSFT");

    // =================================================================
    //  Frame 3: Cancel AAPL bid seq=44
    // =================================================================
    $display("[tb] Frame 3: Cancel AAPL bid");
    build_frame(8'h03, "AAPL", 32'd0, 16'd0, 16'd44, 1'b0);
    send_frame(flen, 0);
    repeat(400) @(posedge clk_50);

    // =================================================================
    //  Frame 4: Halt NVDA seq=45
    // =================================================================
    $display("[tb] Frame 4: Halt NVDA");
    build_frame(8'h04, "NVDA", 32'd0, 16'd0, 16'd45, 1'b0);
    send_frame(flen, 0);
    repeat(400) @(posedge clk_50);
    check(symbol_halted[2] == 1'b1, "Frame 4: NVDA halted");

    // =================================================================
    //  Frame 5: Quote NVDA bid price=998877 (halted - no trigger)
    // =================================================================
    $display("[tb] Frame 5: Quote NVDA bid price=998877 (halted)");
    begin : blk5
        integer trig_before;
        trig_before = trig_cnt;
        build_frame(8'h01, "NVDA", 32'd998877, 16'd75, 16'd46, 1'b0);
        send_frame(flen, 0);
        repeat(400) @(posedge clk_50);
        check(trig_cnt == trig_before, "Frame 5: NVDA trigger suppressed");
    end

    // =================================================================
    //  Frame 6: Heartbeat seq=47
    // =================================================================
    $display("[tb] Frame 6: Heartbeat");
    build_frame(8'h05, "AAPL", 32'd0, 16'd0, 16'd47, 1'b0);
    send_frame(flen, 0);
    repeat(400) @(posedge clk_50);
    check(watchdog_expired == 1'b0, "Frame 6: watchdog not expired");

    // =================================================================
    //  Frame 7: Unknown type 0xAB seq=48
    // =================================================================
    $display("[tb] Frame 7: Unknown type 0xAB");
    begin : blk7
        integer trig_before;
        trig_before = trig_cnt;
        build_frame(8'hAB, "AAPL", 32'd999999, 16'd1, 16'd48, 1'b0);
        send_frame(flen, 0);
        repeat(400) @(posedge clk_50);
        check(unknown_count == 16'd1, "Frame 7: unknown_count = 1");
        check(trig_cnt == trig_before, "Frame 7: no trigger");
    end

    // =================================================================
    //  Frame 8: Quote TSLA bid price=555555 qty=10 seq=49
    // =================================================================
    $display("[tb] Frame 8: Quote TSLA bid price=555555");
    build_frame(8'h01, "TSLA", 32'd555555, 16'd10, 16'd49, 1'b0);
    send_frame(flen, 0);
    repeat(600) @(posedge clk_50);
    save_tx_response(2);
    print_latency(2'd1, 16'd49, "TSLA");

    // Wait for all TX packets to finish
    repeat(2000) @(posedge clk_50);

    // =================================================================
    //  Verify RX pipeline
    // =================================================================
    $display("\n[tb] ============================================================");
    $display("[tb] RX PIPELINE RESULTS:");
    $display("[tb]   Messages parsed : %0d", s6_msg_cnt);
    $display("[tb]   Triggers fired  : %0d", trig_cnt);
    $display("[tb]   symbol_halted   : %04b", symbol_halted);
    $display("[tb]   unknown_count   : %0d", unknown_count);
    $display("[tb] ============================================================");

    check(s6_msg_cnt == 8, "Total messages = 8");
    check(trig_cnt == 3, "Total triggers = 3");
    check(symbol_halted[2] == 1'b1, "NVDA still halted");
    check(unknown_count == 16'd1, "unknown_count = 1");

    // =================================================================
    //  Verify TX response packets
    // =================================================================
    $display("\n[tb] ============================================================");
    $display("[tb] TX RESPONSE VERIFICATION:");
    $display("[tb]   TX packets captured: %0d", tx_pkt_cnt);
    $display("[tb] ============================================================");

    check(tx_pkt_cnt == 3, "TX packet count = 3");

    // Response 0 should be from Frame 1 trigger: AAPL price=123456 reason=1 seq=42
    if (resp_len[0] >= 29) begin
        $display("[tb] Resp 0: type=%02h sym=%02h%02h%02h%02h price=%02h%02h%02h%02h reason=%02h seq=%02h%02h",
            resp_buf[0][14], resp_buf[0][15], resp_buf[0][16], resp_buf[0][17], resp_buf[0][18],
            resp_buf[0][19], resp_buf[0][20], resp_buf[0][21], resp_buf[0][22],
            resp_buf[0][27], resp_buf[0][25], resp_buf[0][26]);
        check(resp_buf[0][14] == 8'hA1, "Resp 0: type = 0xA1");
        check({resp_buf[0][15], resp_buf[0][16], resp_buf[0][17], resp_buf[0][18]} == "AAPL",
              "Resp 0: symbol = AAPL");
        check({resp_buf[0][19], resp_buf[0][20], resp_buf[0][21], resp_buf[0][22]} == 32'd123456,
              "Resp 0: price = 123456");
        check(resp_buf[0][27] == 8'd1, "Resp 0: reason = 1 (bid)");
        check({resp_buf[0][25], resp_buf[0][26]} == 16'd42, "Resp 0: seq = 42");
    end else begin
        $display("[FAIL] Resp 0: too short (%0d bytes)", resp_len[0]);
        fail_cnt = fail_cnt + 1;
    end

    // Response 1 should be from Frame 2 trigger: MSFT price=223344 reason=2 seq=43
    if (resp_len[1] >= 29) begin
        $display("[tb] Resp 1: type=%02h sym=%02h%02h%02h%02h price=%02h%02h%02h%02h reason=%02h seq=%02h%02h",
            resp_buf[1][14], resp_buf[1][15], resp_buf[1][16], resp_buf[1][17], resp_buf[1][18],
            resp_buf[1][19], resp_buf[1][20], resp_buf[1][21], resp_buf[1][22],
            resp_buf[1][27], resp_buf[1][25], resp_buf[1][26]);
        check(resp_buf[1][14] == 8'hA1, "Resp 1: type = 0xA1");
        check({resp_buf[1][15], resp_buf[1][16], resp_buf[1][17], resp_buf[1][18]} == "MSFT",
              "Resp 1: symbol = MSFT");
        check({resp_buf[1][19], resp_buf[1][20], resp_buf[1][21], resp_buf[1][22]} == 32'd223344,
              "Resp 1: price = 223344");
        check(resp_buf[1][27] == 8'd2, "Resp 1: reason = 2 (ask)");
        check({resp_buf[1][25], resp_buf[1][26]} == 16'd43, "Resp 1: seq = 43");
    end else begin
        $display("[FAIL] Resp 1: too short (%0d bytes)", resp_len[1]);
        fail_cnt = fail_cnt + 1;
    end

    // Response 2 should be from Frame 8 trigger: TSLA price=555555 reason=1 seq=49
    if (resp_len[2] >= 29) begin
        $display("[tb] Resp 2: type=%02h sym=%02h%02h%02h%02h price=%02h%02h%02h%02h reason=%02h seq=%02h%02h",
            resp_buf[2][14], resp_buf[2][15], resp_buf[2][16], resp_buf[2][17], resp_buf[2][18],
            resp_buf[2][19], resp_buf[2][20], resp_buf[2][21], resp_buf[2][22],
            resp_buf[2][27], resp_buf[2][25], resp_buf[2][26]);
        check(resp_buf[2][14] == 8'hA1, "Resp 2: type = 0xA1");
        check({resp_buf[2][15], resp_buf[2][16], resp_buf[2][17], resp_buf[2][18]} == "TSLA",
              "Resp 2: symbol = TSLA");
        check({resp_buf[2][19], resp_buf[2][20], resp_buf[2][21], resp_buf[2][22]} == 32'd555555,
              "Resp 2: price = 555555");
        check(resp_buf[2][27] == 8'd1, "Resp 2: reason = 1 (bid)");
        check({resp_buf[2][25], resp_buf[2][26]} == 16'd49, "Resp 2: seq = 49");
    end else begin
        $display("[FAIL] Resp 2: too short (%0d bytes)", resp_len[2]);
        fail_cnt = fail_cnt + 1;
    end

    // =================================================================
    //  Latency summary and assertions
    // =================================================================
    begin : lat_summary_blk
        reg [31:0] min_tot, max_tot, avg_tot;
        integer li;
        min_tot = lat_total_log[0];
        max_tot = lat_total_log[0];
        for (li = 1; li < 3; li = li + 1) begin
            if (lat_total_log[li] < min_tot) min_tot = lat_total_log[li];
            if (lat_total_log[li] > max_tot) max_tot = lat_total_log[li];
        end
        avg_tot = (lat_total_log[0] + lat_total_log[1] + lat_total_log[2]) / 3;

        $display("\n[LATENCY SUMMARY]");
        $display("  Min total latency : %0d cycles", min_tot);
        $display("  Max total latency : %0d cycles", max_tot);
        $display("  Avg total latency : %0d cycles", avg_tot);

        // Latency range assertions (all 3 trigger frames)
        for (li = 0; li < 3; li = li + 1) begin
            check(lat_parse_log[li] > 0 && lat_parse_log[li] < 5000,
                  "lat_parse in range (0,5000)");
            check(lat_trig_log[li] > 0 && lat_trig_log[li] < 5000,
                  "lat_trigger in range (0,5000)");
            check(lat_total_log[li] > 0 && lat_total_log[li] < 10000,
                  "lat_total in range (0,10000)");
        end
    end

    // =================================================================
    //  Final summary
    // =================================================================
    $display("\n[tb] ============================================================");
    $display("[tb]   PASSED: %0d  /  FAILED: %0d", pass_cnt, fail_cnt);
    $display("[tb] ============================================================");

    if (fail_cnt == 0)
        $display("[tb] *** ALL TESTS PASSED ***");
    else
        $display("[tb] *** %0d TEST(S) FAILED ***", fail_cnt);

    $finish;
end

endmodule

`default_nettype wire
