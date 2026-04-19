// uart_tx.v - Simple 8N1 UART transmitter
// Default: 115200 baud from 100 MHz clock (CLK_DIV = 868)
`default_nettype none
`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_DIV = 868
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,    // pulse high to start sending data
    output reg        ready,    // high when idle and able to accept new byte
    output reg        tx        // UART line (idle high)
);

reg [3:0]  bit_idx;
reg [15:0] cnt;
reg [9:0]  shift;     // start(0) + 8 data (LSB first) + stop(1)
reg        busy;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx      <= 1'b1;
        bit_idx <= 4'd0;
        cnt     <= 16'd0;
        shift   <= 10'b1111111111;
        busy    <= 1'b0;
        ready   <= 1'b1;
    end else begin
        if (!busy) begin
            tx <= 1'b1;
            ready <= 1'b1;
            if (valid) begin
                shift   <= {1'b1, data, 1'b0};   // {stop, data[7:0] LSB-first via shift, start}
                busy    <= 1'b1;
                ready   <= 1'b0;
                bit_idx <= 4'd0;
                cnt     <= 16'd0;
                tx      <= 1'b0;                 // start bit
            end
        end else begin
            if (cnt == CLK_DIV - 1) begin
                cnt <= 16'd0;
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                    tx      <= shift[bit_idx + 1];
                end
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
end

endmodule
`default_nettype wire
