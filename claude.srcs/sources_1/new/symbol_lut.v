`timescale 1ns/1ps
`default_nettype none

module symbol_lut (
    input  wire [31:0] symbol_ascii,
    output reg  [3:0]  symbol_id,
    output reg         symbol_valid
);

always @(*) begin
    symbol_id    = 4'd0;
    symbol_valid = 1'b1;

    case (symbol_ascii)
        "AAPL": symbol_id = 4'd0;
        "MSFT": symbol_id = 4'd1;
        "NVDA": symbol_id = 4'd2;
        "TSLA": symbol_id = 4'd3;
        "AMZN": symbol_id = 4'd4;
        "GOOG": symbol_id = 4'd5;
        "META": symbol_id = 4'd6;
        "NFLX": symbol_id = 4'd7;
        default: begin
            symbol_id    = 4'd15;
            symbol_valid = 1'b0;
        end
    endcase
end

endmodule

`default_nettype wire
