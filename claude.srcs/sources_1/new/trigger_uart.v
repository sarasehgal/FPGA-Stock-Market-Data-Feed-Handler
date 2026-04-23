// trigger_uart.v — format trigger as ASCII UART message
// Output: TRIG:AAPL:0x0001E240:b:0x008E\r\n  (29 bytes)
//         ^    ^    ^            ^ ^
//         |    sym  price(hex)  side latency(hex, clk_100 cycles)
`default_nettype none
`timescale 1ns/1ps

module trigger_uart (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        trigger_fire,
    input  wire [31:0] trigger_symbol,
    input  wire [31:0] trigger_price,
    input  wire [7:0]  trigger_reason,
    input  wire [15:0] trigger_latency,
    output reg  [7:0]  tx_data,
    output reg         tx_valid,
    input  wire        tx_ready
);

localparam MSG_LEN = 29;

reg [31:0] sym_lat;
reg [31:0] price_lat;
reg [7:0]  reason_lat;
reg [15:0] lat_lat;

reg [4:0]  idx;
reg        sending;

function [7:0] hex_nibble;
    input [3:0] n;
    begin
        hex_nibble = (n < 4'd10) ? (8'h30 + {4'h0, n}) : (8'h41 + {4'h0, n} - 8'd10);
    end
endfunction

reg [7:0] cur_byte;
always @* begin
    case (idx)
        5'd0:  cur_byte = "T";
        5'd1:  cur_byte = "R";
        5'd2:  cur_byte = "I";
        5'd3:  cur_byte = "G";
        5'd4:  cur_byte = ":";
        5'd5:  cur_byte = sym_lat[31:24];
        5'd6:  cur_byte = sym_lat[23:16];
        5'd7:  cur_byte = sym_lat[15:8];
        5'd8:  cur_byte = sym_lat[7:0];
        5'd9:  cur_byte = ":";
        5'd10: cur_byte = "0";
        5'd11: cur_byte = "x";
        5'd12: cur_byte = hex_nibble(price_lat[31:28]);
        5'd13: cur_byte = hex_nibble(price_lat[27:24]);
        5'd14: cur_byte = hex_nibble(price_lat[23:20]);
        5'd15: cur_byte = hex_nibble(price_lat[19:16]);
        5'd16: cur_byte = hex_nibble(price_lat[15:12]);
        5'd17: cur_byte = hex_nibble(price_lat[11:8]);
        5'd18: cur_byte = hex_nibble(price_lat[7:4]);
        5'd19: cur_byte = hex_nibble(price_lat[3:0]);
        5'd20: cur_byte = ":";
        // Reason: 1=bid_thresh(T), 2=ask_thresh(t), 3=ema_bid(E), 4=ema_ask(e), 5=spread(S)
        5'd21: cur_byte = (reason_lat == 8'd1) ? "T" :
                           (reason_lat == 8'd2) ? "t" :
                           (reason_lat == 8'd3) ? "E" :
                           (reason_lat == 8'd4) ? "e" :
                           (reason_lat == 8'd5) ? "S" : "?";
        5'd22: cur_byte = ":";
        5'd23: cur_byte = hex_nibble(lat_lat[15:12]);
        5'd24: cur_byte = hex_nibble(lat_lat[11:8]);
        5'd25: cur_byte = hex_nibble(lat_lat[7:4]);
        5'd26: cur_byte = hex_nibble(lat_lat[3:0]);
        5'd27: cur_byte = 8'h0D;
        5'd28: cur_byte = 8'h0A;
        default: cur_byte = 8'h00;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sym_lat    <= 32'd0;
        price_lat  <= 32'd0;
        reason_lat <= 8'd0;
        lat_lat    <= 16'd0;
        idx        <= 5'd0;
        sending    <= 1'b0;
        tx_data    <= 8'd0;
        tx_valid   <= 1'b0;
    end else begin
        tx_valid <= 1'b0;
        if (!sending) begin
            if (trigger_fire) begin
                sym_lat    <= trigger_symbol;
                price_lat  <= trigger_price;
                reason_lat <= trigger_reason;
                lat_lat    <= trigger_latency;
                idx        <= 5'd0;
                sending    <= 1'b1;
            end
        end else begin
            if (tx_ready && !tx_valid) begin
                tx_data  <= cur_byte;
                tx_valid <= 1'b1;
                if (idx == MSG_LEN - 1)
                    sending <= 1'b0;
                else
                    idx <= idx + 1'b1;
            end
        end
    end
end

endmodule
`default_nettype wire
