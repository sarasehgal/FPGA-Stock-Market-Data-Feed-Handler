`timescale 1ns/1ps
`default_nettype none

module trigger_engine #(
    parameter NUM_SYMBOLS = 8
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire       update_valid,
    input  wire [3:0] update_symbol_id,
    input  wire [31:0] update_price,
    input  wire [31:0] update_quantity,
    input  wire [31:0] update_seq_num,
    input  wire       update_side,

    input  wire [NUM_SYMBOLS-1:0] symbol_halted,

    output reg        trigger_valid,
    output reg  [3:0] trigger_symbol_id,
    output reg  [31:0] trigger_price,
    output reg  [31:0] trigger_quantity,
    output reg  [31:0] trigger_seq_num,
    output reg  [7:0] trigger_reason
);

// Reason codes: 1 = bid threshold cross, 2 = ask threshold cross

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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        trigger_valid      <= 1'b0;
        trigger_symbol_id  <= 4'd0;
        trigger_price      <= 32'd0;
        trigger_quantity   <= 32'd0;
        trigger_seq_num    <= 32'd0;
        trigger_reason     <= 8'd0;
    end else begin
        trigger_valid <= 1'b0;

        if (update_valid) begin
            if (update_symbol_id < NUM_SYMBOLS && symbol_halted[update_symbol_id]) begin
                // Halted - no trigger
            end else if (update_price >= threshold_for_symbol(update_symbol_id)
                        && update_quantity >= 32'd50) begin  // volume filter: qty >= 50
                trigger_valid      <= 1'b1;
                trigger_symbol_id  <= update_symbol_id;
                trigger_price      <= update_price;
                trigger_quantity   <= update_quantity;
                trigger_seq_num    <= update_seq_num;
                trigger_reason     <= update_side ? 8'd2 : 8'd1;
            end
        end
    end
end

endmodule

`default_nettype wire
