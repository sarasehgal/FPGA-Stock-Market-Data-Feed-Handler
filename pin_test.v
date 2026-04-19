// pin_test.v - Read all pins on CLK_100MHZ. Activity stretcher per pin.
// No driving, no BUFG, no complexity. Just read and display.

`default_nettype none
module pin_test (
    input  wire CLK_100MHZ,
    input  wire pin0,   // H18
    input  wire pin1,   // G18
    input  wire pin2,   // H16
    input  wire pin3,   // H17
    input  wire pin4,   // K16
    input  wire pin5,   // J16
    input  wire pin6,   // H13
    input  wire pin7,   // H14
    input  wire pin8,   // J15
    input  wire pin9,   // J14
    input  wire pin10,  // G16
    input  wire pin11,  // E16
    input  wire pin12,  // K14 (non-standard, showed activity in first probe!)
    output reg [15:0] LED
);

reg [25:0] hb;
always @(posedge CLK_100MHZ) hb <= hb + 1;

// Double-register all pins for metastability
reg [12:0] pins_s1, pins_s2, pins_prev;
always @(posedge CLK_100MHZ) begin
    pins_s1  <= {pin12, pin11, pin10, pin9, pin8, pin7, pin6, pin5, pin4, pin3, pin2, pin1, pin0};
    pins_s2  <= pins_s1;
    pins_prev <= pins_s2;
end

// Per-pin activity stretcher (~200ms)
reg [23:0] str0,str1,str2,str3,str4,str5,str6,str7,str8,str9,str10,str11,str12;

always @(posedge CLK_100MHZ) begin
    if (pins_s2[0]  != pins_prev[0])  str0  <= 24'hFFFFFF; else if (|str0)  str0  <= str0  - 1;
    if (pins_s2[1]  != pins_prev[1])  str1  <= 24'hFFFFFF; else if (|str1)  str1  <= str1  - 1;
    if (pins_s2[2]  != pins_prev[2])  str2  <= 24'hFFFFFF; else if (|str2)  str2  <= str2  - 1;
    if (pins_s2[3]  != pins_prev[3])  str3  <= 24'hFFFFFF; else if (|str3)  str3  <= str3  - 1;
    if (pins_s2[4]  != pins_prev[4])  str4  <= 24'hFFFFFF; else if (|str4)  str4  <= str4  - 1;
    if (pins_s2[5]  != pins_prev[5])  str5  <= 24'hFFFFFF; else if (|str5)  str5  <= str5  - 1;
    if (pins_s2[6]  != pins_prev[6])  str6  <= 24'hFFFFFF; else if (|str6)  str6  <= str6  - 1;
    if (pins_s2[7]  != pins_prev[7])  str7  <= 24'hFFFFFF; else if (|str7)  str7  <= str7  - 1;
    if (pins_s2[8]  != pins_prev[8])  str8  <= 24'hFFFFFF; else if (|str8)  str8  <= str8  - 1;
    if (pins_s2[9]  != pins_prev[9])  str9  <= 24'hFFFFFF; else if (|str9)  str9  <= str9  - 1;
    if (pins_s2[10] != pins_prev[10]) str10 <= 24'hFFFFFF; else if (|str10) str10 <= str10 - 1;
    if (pins_s2[11] != pins_prev[11]) str11 <= 24'hFFFFFF; else if (|str11) str11 <= str11 - 1;
    if (pins_s2[12] != pins_prev[12]) str12 <= 24'hFFFFFF; else if (|str12) str12 <= str12 - 1;
end

always @(posedge CLK_100MHZ) begin
    LED[0]  <= hb[25];     // heartbeat — MUST blink
    LED[1]  <= |str0;      // H18 activity
    LED[2]  <= |str1;      // G18 activity
    LED[3]  <= |str2;      // H16 activity
    LED[4]  <= |str3;      // H17 activity
    LED[5]  <= |str4;      // K16 activity (50MHz REFCLKO? will be always ON)
    LED[6]  <= |str5;      // J16 activity
    LED[7]  <= 1'b0;
    LED[8]  <= |str6;      // H13 activity
    LED[9]  <= |str7;      // H14 activity
    LED[10] <= |str8;      // J15 activity
    LED[11] <= |str9;      // J14 activity
    LED[12] <= |str10;     // G16 activity
    LED[13] <= |str11;     // E16 activity
    LED[14] <= |str12;     // K14 activity ← KEY PIN TO WATCH
    LED[15] <= |str0 | |str1 | |str2 | |str3 | |str5 |
               |str6 | |str7 | |str8 | |str9 | |str10 | |str11; // any (excl K16)
end

endmodule
`default_nettype wire
