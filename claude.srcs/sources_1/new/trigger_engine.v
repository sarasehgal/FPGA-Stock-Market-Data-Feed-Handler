// trigger_engine.v — Multi-strategy trigger with EMA crossover, spread monitor, and cooldown
// Reason codes: 1=bid_thresh, 2=ask_thresh, 3=ema_cross_bid, 4=ema_cross_ask, 5=spread_alert
`timescale 1ns/1ps
`default_nettype none

module trigger_engine #(
    parameter NUM_SYMBOLS  = 8,
    parameter EMA_SHIFT    = 4,           // alpha = 1/16
    parameter SPREAD_THRESH = 32'd10000,  // spread alert if ask-bid > this
    parameter COOLDOWN_CYCLES = 32'd5000  // ~50 us @ 100 MHz per-symbol cooldown
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       update_valid,
    input  wire [3:0] update_symbol_id,
    input  wire [31:0] update_price,
    input  wire [31:0] update_quantity,
    input  wire [31:0] update_seq_num,
    input  wire       update_side,

    // From book_state_manager
    input  wire [31:0] best_bid,
    input  wire [31:0] best_ask,

    input  wire [NUM_SYMBOLS-1:0] symbol_halted,

    output reg        trigger_valid,
    output reg  [3:0] trigger_symbol_id,
    output reg  [31:0] trigger_price,
    output reg  [31:0] trigger_quantity,
    output reg  [31:0] trigger_seq_num,
    output reg  [7:0] trigger_reason
);

// ── Per-symbol state ────────────────────────────────────────────
reg [31:0] ema          [0:NUM_SYMBOLS-1];   // exponential moving average
reg        ema_valid    [0:NUM_SYMBOLS-1];   // has EMA been initialized?
reg [31:0] prev_price   [0:NUM_SYMBOLS-1];   // for crossover detection
reg [31:0] cooldown_ctr [0:NUM_SYMBOLS-1];   // per-symbol cooldown

// ── Threshold LUT ───────────────────────────────────────────────
function [31:0] threshold_for_symbol;
    input [3:0] sid;
    begin
        case (sid)
            4'd0: threshold_for_symbol = 32'd120000; // AAPL
            4'd1: threshold_for_symbol = 32'd200000; // MSFT
            4'd2: threshold_for_symbol = 32'd900000; // NVDA
            4'd3: threshold_for_symbol = 32'd500000; // TSLA
            4'd4: threshold_for_symbol = 32'd180000; // AMZN
            4'd5: threshold_for_symbol = 32'd170000; // GOOG
            4'd6: threshold_for_symbol = 32'd500000; // META
            4'd7: threshold_for_symbol = 32'd650000; // NFLX
            default: threshold_for_symbol = 32'hFFFF_FFFF;
        endcase
    end
endfunction

integer j;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        trigger_valid      <= 1'b0;
        trigger_symbol_id  <= 4'd0;
        trigger_price      <= 32'd0;
        trigger_quantity   <= 32'd0;
        trigger_seq_num    <= 32'd0;
        trigger_reason     <= 8'd0;
        for (j = 0; j < NUM_SYMBOLS; j = j + 1) begin
            ema[j]          <= 32'd0;
            ema_valid[j]    <= 1'b0;
            prev_price[j]   <= 32'd0;
            cooldown_ctr[j] <= 32'd0;
        end
    end else begin
        trigger_valid <= 1'b0;

        // Tick down all cooldown counters
        for (j = 0; j < NUM_SYMBOLS; j = j + 1)
            if (cooldown_ctr[j] > 0) cooldown_ctr[j] <= cooldown_ctr[j] - 1'b1;

        if (update_valid && update_symbol_id < NUM_SYMBOLS) begin

            // ── Update EMA ──────────────────────────────────────
            // EMA_new = EMA_old + (price - EMA_old) >> EMA_SHIFT
            // First sample: initialize EMA to price
            if (!ema_valid[update_symbol_id]) begin
                ema[update_symbol_id]       <= update_price;
                ema_valid[update_symbol_id]  <= 1'b1;
            end else begin
                // Signed difference using two's complement
                if (update_price >= ema[update_symbol_id])
                    ema[update_symbol_id] <= ema[update_symbol_id]
                        + ((update_price - ema[update_symbol_id]) >> EMA_SHIFT);
                else
                    ema[update_symbol_id] <= ema[update_symbol_id]
                        - ((ema[update_symbol_id] - update_price) >> EMA_SHIFT);
            end

            // ── Check triggers (only if not halted and not in cooldown) ──
            if (!symbol_halted[update_symbol_id] && cooldown_ctr[update_symbol_id] == 0) begin

                // Strategy 1: Price threshold + volume filter
                if (update_price >= threshold_for_symbol(update_symbol_id)
                    && update_quantity >= 32'd50) begin
                    trigger_valid      <= 1'b1;
                    trigger_symbol_id  <= update_symbol_id;
                    trigger_price      <= update_price;
                    trigger_quantity   <= update_quantity;
                    trigger_seq_num    <= update_seq_num;
                    trigger_reason     <= update_side ? 8'd2 : 8'd1;
                    cooldown_ctr[update_symbol_id] <= COOLDOWN_CYCLES;
                end

                // Strategy 2: EMA crossover (price crosses above EMA)
                else if (ema_valid[update_symbol_id]
                         && prev_price[update_symbol_id] > 0
                         && prev_price[update_symbol_id] < ema[update_symbol_id]
                         && update_price >= ema[update_symbol_id]
                         && update_quantity >= 32'd50) begin
                    trigger_valid      <= 1'b1;
                    trigger_symbol_id  <= update_symbol_id;
                    trigger_price      <= update_price;
                    trigger_quantity   <= update_quantity;
                    trigger_seq_num    <= update_seq_num;
                    trigger_reason     <= update_side ? 8'd4 : 8'd3;
                    cooldown_ctr[update_symbol_id] <= COOLDOWN_CYCLES;
                end

                // Strategy 3: Bid-ask spread alert
                else if (best_bid > 0 && best_ask > 0
                         && best_ask > best_bid
                         && (best_ask - best_bid) > SPREAD_THRESH) begin
                    trigger_valid      <= 1'b1;
                    trigger_symbol_id  <= update_symbol_id;
                    trigger_price      <= update_price;
                    trigger_quantity   <= update_quantity;
                    trigger_seq_num    <= update_seq_num;
                    trigger_reason     <= 8'd5;
                    cooldown_ctr[update_symbol_id] <= COOLDOWN_CYCLES;
                end
            end

            // Store previous price for next crossover check
            prev_price[update_symbol_id] <= update_price;

        end // update_valid
    end // !rst_n
end

endmodule
`default_nettype wire
