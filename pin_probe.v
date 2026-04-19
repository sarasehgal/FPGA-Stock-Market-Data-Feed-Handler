// pin_probe.v - Test ONE pin at a time. All other LEDs off.
// Change ACTIVE_PIN parameter to probe different pins.

`default_nettype none
`timescale 1ns/1ps

module pin_probe (
    input  wire CLK_100MHZ,

    // PHY infrastructure
    output wire JB4_P,          // K16 ref_clk
    output wire phy_nrst,       // J14

    // ALL candidate pins as inputs
    input  wire pin_H18,        // JB1_P
    input  wire pin_G18,        // JB1_N
    input  wire pin_H13,        // JB2_P / JA2_P  (CRS_DV confirmed)
    input  wire pin_H14,        // JB2_N / JA2_N
    input  wire pin_H16,        // JB3_P
    input  wire pin_H17,        // JB3_N
    input  wire pin_J16,        // JB4_N
    input  wire pin_K14,        // non-standard
    input  wire pin_F14,        // JA1_P
    input  wire pin_F15,        // JA1_N
    input  wire pin_J13,        // JA3_P
    input  wire pin_E14,        // JA4_P
    input  wire pin_E15,        // JA4_N

    output wire [15:0] LED
);

wire clk_100, clk_50, pll_locked;
clk_wiz_0 u_pll (.clk_in1(CLK_100MHZ),.clk_out1(clk_100),.clk_out2(clk_50),.locked(pll_locked));

ODDR #(.DDR_CLK_EDGE("SAME_EDGE"),.INIT(1'b0),.SRTYPE("SYNC"))
u_oddr (.Q(JB4_P),.C(clk_50),.CE(1'b1),.D1(1'b1),.D2(1'b0),.R(1'b0),.S(1'b0));

reg [19:0] rst_ctr;
always @(posedge clk_100)
    if (!pll_locked) rst_ctr <= 0;
    else if (!rst_ctr[19]) rst_ctr <= rst_ctr + 1;
assign phy_nrst = rst_ctr[19];

// Each pin gets a stretched LED
wire [12:0] all_pins = {pin_E15, pin_E14, pin_J13, pin_F15, pin_F14,
                         pin_K14, pin_J16, pin_H17, pin_H16, pin_H14,
                         pin_H13, pin_G18, pin_H18};

reg [12:0] prev;
reg [22:0] stretch [0:12];
integer si;
always @(posedge clk_100) begin
    prev <= all_pins;
    for (si = 0; si < 13; si = si + 1) begin
        if (all_pins[si] != prev[si])
            stretch[si] <= 23'h7FFFFF;
        else if (|stretch[si])
            stretch[si] <= stretch[si] - 1;
    end
end
initial for (si = 0; si < 13; si = si + 1) stretch[si] = 0;

// LED[0] = pll_locked (solid = alive)
// LED[1] = H18   LED[2] = G18    LED[3] = H13(CRS_DV)
// LED[4] = H14   LED[5] = H16   LED[6] = H17
// LED[7] = J16   LED[8] = K14   LED[9] = F14
// LED[10]= F15   LED[11]= J13   LED[12]= E14  LED[13]= E15
// LED[14-15] = off

assign LED[0]  = pll_locked;
assign LED[1]  = |stretch[0];   // H18
assign LED[2]  = |stretch[1];   // G18
assign LED[3]  = |stretch[2];   // H13 CRS_DV
assign LED[4]  = |stretch[3];   // H14
assign LED[5]  = |stretch[4];   // H16
assign LED[6]  = |stretch[5];   // H17
assign LED[7]  = |stretch[6];   // J16
assign LED[8]  = |stretch[7];   // K14
assign LED[9]  = |stretch[8];   // F14
assign LED[10] = |stretch[9];   // F15
assign LED[11] = |stretch[10];  // J13
assign LED[12] = |stretch[11];  // E14
assign LED[13] = |stretch[12];  // E15
assign LED[14] = 1'b0;
assign LED[15] = 1'b0;

endmodule
`default_nettype wire
