// wide_probe.v - v2: probe K14 and neighborhood (off Pmod B) plus K16/H16/G16 references
`default_nettype none
`timescale 1ns/1ps

module wide_probe (
    input  wire        CLK_100MHZ,
    input  wire        rst_n,

    // New candidate pins (RXD likely here — off Pmod B)
    input  wire        K14, K15, J13, J15, G16, H15, H16, K16,

    output wire [15:0] LED
);

// [7]=K14 [6]=K15 [5]=J13 [4]=J15 [3]=G16 [2]=H15 [1]=H16 [0]=K16
wire [7:0] pins = {K14, K15, J13, J15, G16, H15, H16, K16};

reg  [7:0] pins_r;
reg [15:0] idle_cnt;

always @(posedge CLK_100MHZ) begin
    pins_r  <= pins;
    if (pins != 8'h00) idle_cnt <= 16'd0;
    else if (idle_cnt != 16'hFFFF) idle_cnt <= idle_cnt + 1'b1;
end

ila_0 u_ila (
    .clk    (CLK_100MHZ),
    .probe0 (1'b0),
    .probe1 (2'b00),
    .probe2 (pins_r),
    .probe3 (1'b0),
    .probe4 (1'b0)
);

assign LED = idle_cnt;

endmodule
`default_nettype wire
