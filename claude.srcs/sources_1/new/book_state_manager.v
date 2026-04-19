`timescale 1ns/1ps
`default_nettype none

module book_state_manager #(
    parameter NUM_SYMBOLS = 4
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       msg_valid,
    input  wire [7:0] msg_type,
    input  wire [3:0] symbol_id,
    input  wire       symbol_valid,
    input  wire [31:0] price,
    input  wire [31:0] quantity,
    input  wire [31:0] seq_num,
    input  wire       msg_side,
    input  wire       msg_crc_ok,
    input  wire       msg_is_cancel,

    output reg        update_valid,
    output reg  [3:0] update_symbol_id,
    output reg  [31:0] update_price,
    output reg  [31:0] update_quantity,
    output reg  [31:0] update_seq_num,
    output reg        update_side,

    output reg  [31:0] best_bid,
    output reg  [31:0] best_ask,

    output reg  [NUM_SYMBOLS-1:0] book_valid_bits
);

integer i;

reg [31:0] best_bid_price [0:NUM_SYMBOLS-1];
reg [31:0] best_ask_price [0:NUM_SYMBOLS-1];
reg [31:0] last_seq       [0:NUM_SYMBOLS-1];

wire accept_msg;
assign accept_msg = msg_valid && msg_crc_ok && symbol_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        update_valid     <= 1'b0;
        update_symbol_id <= 4'd0;
        update_price     <= 32'd0;
        update_quantity  <= 32'd0;
        update_seq_num   <= 32'd0;
        update_side      <= 1'b0;
        best_bid         <= 32'd0;
        best_ask         <= 32'd0;
        book_valid_bits  <= {NUM_SYMBOLS{1'b0}};

        for (i = 0; i < NUM_SYMBOLS; i = i + 1) begin
            best_bid_price[i] <= 32'd0;
            best_ask_price[i] <= 32'd0;
            last_seq[i]       <= 32'd0;
        end
    end else begin
        update_valid <= 1'b0;

        if (accept_msg && (symbol_id < NUM_SYMBOLS)) begin
            if (msg_is_cancel) begin
                // Cancel: zero out both sides, invalidate entry
                best_bid_price[symbol_id] <= 32'd0;
                best_ask_price[symbol_id] <= 32'd0;
                book_valid_bits[symbol_id] <= 1'b0;
                last_seq[symbol_id] <= seq_num;

                update_valid     <= 1'b1;
                update_symbol_id <= symbol_id;
                update_price     <= 32'd0;
                update_quantity  <= 32'd0;
                update_seq_num   <= seq_num;
                update_side      <= msg_side;
                best_bid         <= 32'd0;
                best_ask         <= 32'd0;
            end else if (!book_valid_bits[symbol_id] || (seq_num >= last_seq[symbol_id])) begin
                // Normal quote or trade update
                last_seq[symbol_id]        <= seq_num;
                book_valid_bits[symbol_id] <= 1'b1;

                if (!msg_side) begin
                    // Bid side
                    best_bid_price[symbol_id] <= price;
                    best_bid <= price;
                    best_ask <= best_ask_price[symbol_id];
                end else begin
                    // Ask side
                    best_ask_price[symbol_id] <= price;
                    best_ask <= price;
                    best_bid <= best_bid_price[symbol_id];
                end

                update_valid     <= 1'b1;
                update_symbol_id <= symbol_id;
                update_price     <= price;
                update_quantity  <= quantity;
                update_seq_num   <= seq_num;
                update_side      <= msg_side;
            end
        end
    end
end

endmodule

`default_nettype wire
