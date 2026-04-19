// mdio_init.v — one-shot MDIO master that writes a single PHY register at startup
// Default: write 0x3100 to BMCR (reg 0) of PHY addr 0
//   0x3100 = SPEED=100, DUPLEX=full, AUTONEG=disable, RESET=0, ISOLATE=0
`default_nettype none
`timescale 1ns/1ps

module mdio_init #(
    parameter CLK_DIV  = 6'd24,  // clk_50 / (2*(24+1)) = 1 MHz MDC (under 2.5 MHz spec)
    parameter PHY_ADDR = 5'd0,
    parameter REG_ADDR = 5'd0,
    parameter REG_DATA = 16'h3100
)(
    input  wire clk,
    input  wire rst_n,
    output reg  mdc,
    output reg  mdio_o,
    output reg  mdio_oe,    // 1 = drive, 0 = high-Z
    output reg  done
);

// 64-bit write frame: 32 preamble + 01 ST + 01 OP + PHY_ADDR + REG_ADDR + 10 TA + 16 DATA
wire [63:0] frame = {32'hFFFFFFFF, 2'b01, 2'b01, PHY_ADDR, REG_ADDR, 2'b10, REG_DATA};

reg [5:0]  divcnt;
reg [6:0]  bitcnt;     // 0..64 (64 = done)
reg [3:0]  delay_cnt;  // 16-bit power-on delay before starting

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        divcnt    <= 6'd0;
        bitcnt    <= 7'd0;
        mdc       <= 1'b0;
        mdio_o    <= 1'b1;
        mdio_oe   <= 1'b1;
        done      <= 1'b0;
        delay_cnt <= 4'd0;
    end else if (delay_cnt != 4'hF) begin
        // wait some clk_50 cycles (16 cycles) for PHY to stabilize after reset
        delay_cnt <= delay_cnt + 1'b1;
    end else if (!done) begin
        if (divcnt == CLK_DIV) begin
            divcnt <= 6'd0;
            mdc    <= ~mdc;
            // change MDIO on FALLING edge of MDC (i.e., when mdc was 1, becoming 0)
            if (mdc) begin
                if (bitcnt == 7'd64) begin
                    done    <= 1'b1;
                    mdio_oe <= 1'b0;  // release the bus
                end else begin
                    mdio_o <= frame[63 - bitcnt[5:0]];
                    bitcnt <= bitcnt + 1'b1;
                end
            end
        end else begin
            divcnt <= divcnt + 1'b1;
        end
    end
end

endmodule
`default_nettype wire
