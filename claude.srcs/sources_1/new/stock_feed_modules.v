// =============================================================================
//  stock_feed_modules.v
//  Pipeline sub-modules for stock_feed_top.v
//  All modules use `default_nettype none and explicit port widths.
// =============================================================================
`default_nettype none
`timescale 1ns/1ps


// =============================================================================
//  1. RMII RX Driver  (rewritten after rmii_ethernet.v reference design)
//
//  Preamble/SFD detection: continuously shifts RXD into a 64-bit register
//  and waits for the exact pattern 64'hD555555555555555 (SFD in MSBs,
//  7 preamble bytes in LSBs, all shifted in dibit by dibit LSB-first).
//  This is identical to the technique used in rmii_ethernet.v and avoids
//  the dibit-counter/NBA-hazard bugs in the previous implementation.
//
//  Once SFD is detected, a 2-bit byte counter accumulates further dibits
//  into bytes and emits byte_valid pulses. CRSDV de-asserting = frame end.
// =============================================================================
module rmii_rx_driver (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [1:0] rxd,
    input  wire       crsdv,
    input  wire       rxerr,
    output reg        byte_valid,
    output reg  [7:0] byte_data,
    output reg        frame_start,
    output reg        frame_end,
    output reg        frame_err
);

    // Phase 1: compensate for double-register latency on RXD inputs
    localparam [1:0] PHASE_INIT = 2'd1;

    // ------------------------------------------------------------------------
    // Delay RMII inputs for a stable aligned dibit stream
    // ------------------------------------------------------------------------
    reg [1:0] rxd_r,    rxd_rr;
    reg       crsdv_r,  crsdv_rr;
    reg       rxerr_r,  rxerr_rr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_r    <= 2'b00;
            rxd_rr   <= 2'b00;
            crsdv_r  <= 1'b0;
            crsdv_rr <= 1'b0;
            rxerr_r  <= 1'b0;
            rxerr_rr <= 1'b0;
        end else begin
            rxd_r    <= rxd;
            rxd_rr   <= rxd_r;
            crsdv_r  <= crsdv;
            crsdv_rr <= crsdv_r;
            rxerr_r  <= rxerr;
            rxerr_rr <= rxerr_r;
        end
    end

    // RMII dibit: LAN8720 outputs RXD0 as the FIRST (LSB) bit and RXD1 as the
    // SECOND (MSB) bit of each dibit, so {rxd[1], rxd[0]} is the "natural"
    // dibit. However, on the upside-down DWEII PMOD the two RXD lines are
    // physically swapped versus our XDC mapping, so we swap them back here.
    wire [1:0] dibit = {rxd_rr[0], rxd_rr[1]};
    wire       dv    = crsdv_rr;
    wire       er    = rxerr_rr;

    // ------------------------------------------------------------------------
    // Preamble/SFD detection on aligned dibit stream
    // ------------------------------------------------------------------------
    reg [63:0] preamble_sr;
    reg        sfd_found;
    reg        d_dv;
    reg        arm_data;

    wire [63:0] preamble_next = {dibit, preamble_sr[63:2]};
    wire        sfd_match_now = (preamble_next == 64'hD555555555555555);

    // ------------------------------------------------------------------------
    // Byte assembly with explicit phase control
    // ------------------------------------------------------------------------
    reg [1:0] phase;
    reg [7:0] byte_sr;
    reg       first_byte;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            preamble_sr <= 64'h0;
            sfd_found   <= 1'b0;
            d_dv        <= 1'b0;
            arm_data    <= 1'b0;

            phase       <= PHASE_INIT;
            byte_sr     <= 8'h00;
            byte_valid  <= 1'b0;
            byte_data   <= 8'h00;
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            frame_err   <= 1'b0;
            first_byte  <= 1'b1;
        end else begin
            d_dv        <= dv;
            byte_valid  <= 1'b0;
            frame_start <= 1'b0;
            frame_end   <= 1'b0;
            frame_err   <= 1'b0;

            // Always track aligned dibits for SFD detection
            preamble_sr <= preamble_next;

            // End-of-frame on aligned DV falling edge
            if (!dv && d_dv && sfd_found) begin
                frame_end   <= 1'b1;
                frame_err   <= er;
                sfd_found   <= 1'b0;
                arm_data    <= 1'b0;
                phase       <= PHASE_INIT;
                byte_sr     <= 8'h00;
                first_byte  <= 1'b1;

            end else if (!dv) begin
                sfd_found   <= 1'b0;
                arm_data    <= 1'b0;
                phase       <= PHASE_INIT;
                byte_sr     <= 8'h00;
                first_byte  <= 1'b1;

            end else if (!sfd_found && sfd_match_now) begin
                // Last dibit of SFD just arrived
                sfd_found   <= 1'b1;
                arm_data    <= 1'b1;
                phase       <= PHASE_INIT;
                byte_sr     <= 8'h00;
                first_byte  <= 1'b1;

            end else if (arm_data) begin
                // One-cycle bubble so the final SFD dibit is not consumed as data
                arm_data <= 1'b0;

            end else if (sfd_found) begin
                if (er) begin
                    frame_err <= 1'b1;
                end else begin
                    case (phase)
                        2'd0: begin
                            byte_sr[1:0] <= dibit;
                            phase        <= 2'd1;
                        end

                        2'd1: begin
                            byte_sr[3:2] <= dibit;
                            phase        <= 2'd2;
                        end

                        2'd2: begin
                            byte_sr[5:4] <= dibit;
                            phase        <= 2'd3;
                        end

                        2'd3: begin
                            byte_sr[7:6] <= dibit;
                            byte_valid   <= 1'b1;
                            byte_data    <= {dibit, byte_sr[5:0]};
                            frame_start  <= first_byte;
                            first_byte   <= 1'b0;
                            phase        <= 2'd0;
                        end
                    endcase
                end
            end
        end
    end

endmodule
// =============================================================================
//  2. Ethernet CRC-32 checker
//  Wrapper around axis_eth_fcs_check (Alex Forencich / verilog-ethernet).
//  Adapts our byte-stream interface to AXI-Stream and back.
//  Bad frames (tuser=1 on tlast) are suppressed at the output.
//  Requires axis_eth_fcs_check.v and lfsr.v to be present in the project.
// =============================================================================
module eth_crc_checker (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_valid,
    input  wire [7:0] in_data,
    input  wire       in_start,
    input  wire       in_end,
    input  wire       in_err,
    output wire       out_valid,
    output wire [7:0] out_data,
    output wire       out_start,
    output wire       out_end
);

wire rst = ~rst_n;

wire [7:0] m_tdata;
wire       m_tvalid;
wire       m_tlast;
wire       m_tuser;

assign out_valid = m_tvalid && !(m_tlast && m_tuser);
assign out_data  = m_tdata;

// out_start: delay in_start by 5 in_valid beats to match the FCS checker's
// 4-byte shift register + 1 output register pipeline.
reg [4:0] start_shift;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        start_shift <= 5'b00000;
    else if (in_valid)
        start_shift <= {start_shift[3:0], in_start};
end
assign out_start = out_valid && start_shift[4];

// out_end: after in_end, 4 residual bytes remain in the FCS checker's
// pipeline.  They get flushed when the next frame's bytes arrive.
// Count 4 out_valid beats after in_end; assert out_end on the 4th.
reg [2:0] end_countdown;
reg       end_pending;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        end_countdown <= 3'd0;
        end_pending   <= 1'b0;
    end else begin
        if (in_end) begin
            end_countdown <= 3'd4;
            end_pending   <= 1'b1;
        end else if (end_pending && out_valid) begin
            end_countdown <= end_countdown - 3'd1;
            if (end_countdown == 3'd1)
                end_pending <= 1'b0;
        end
    end
end
assign out_end = end_pending && (end_countdown == 3'd1) && out_valid;

axis_eth_fcs_check u_fcs_check (
    .clk              (clk),
    .rst              (rst),

    // Input - direct byte stream from RMII driver
    .s_axis_tdata     (in_data),
    .s_axis_tvalid    (in_valid),
    .s_axis_tready    (),          // not used - RMII driver cannot be backpressured
    .s_axis_tlast     (in_end),
    .s_axis_tuser     (in_err),

    // Output - tie tready high, always accepting
    .m_axis_tdata     (m_tdata),
    .m_axis_tvalid    (m_tvalid),
    .m_axis_tready    (1'b1),
    .m_axis_tlast     (m_tlast),
    .m_axis_tuser     (m_tuser),

    // Status — not used
    .busy             (),
    .error_bad_fcs    ()
);

endmodule


// =============================================================================
//  3. Asynchronous FIFO  (Gray-coded pointers, dual-clock)
//  Standard 2-FF synchroniser on each pointer crossing.
// =============================================================================
module async_fifo #(
    parameter DATA_WIDTH = 10,
    parameter ADDR_WIDTH = 11
) (
    // Write port
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  full,

    // Read port
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output reg                   rd_valid,
    output wire                  empty
);

localparam DEPTH = (1 << ADDR_WIDTH);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Binary and Gray pointers
reg [ADDR_WIDTH:0] wr_bin, wr_gray;
reg [ADDR_WIDTH:0] rd_bin, rd_gray;

// Synchronised pointers (write domain sees rd_gray, read domain sees wr_gray)
reg [ADDR_WIDTH:0] rd_gray_wr0, rd_gray_wr1;
reg [ADDR_WIDTH:0] wr_gray_rd0, wr_gray_rd1;

// Gray encode / decode helpers
function [ADDR_WIDTH:0] bin2gray;
    input [ADDR_WIDTH:0] b;
    begin bin2gray = b ^ (b >> 1); end
endfunction

function [ADDR_WIDTH:0] gray2bin;
    input [ADDR_WIDTH:0] g;
    integer i;
    reg [ADDR_WIDTH:0] b;
    begin
        b[ADDR_WIDTH] = g[ADDR_WIDTH];
        for (i = ADDR_WIDTH-1; i >= 0; i = i - 1)
            b[i] = b[i+1] ^ g[i];
        gray2bin = b;
    end
endfunction

// Write side
always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
        wr_bin  <= 0;
        wr_gray <= 0;
    end else if (wr_en && !full) begin
        mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        wr_bin  <= wr_bin + 1'b1;
        wr_gray <= bin2gray(wr_bin + 1'b1);
    end
end

// Sync rd_gray into wr_clk domain
always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) {rd_gray_wr1, rd_gray_wr0} <= 0;
    else           {rd_gray_wr1, rd_gray_wr0} <= {rd_gray_wr0, rd_gray};
end

// Full when write pointer catches up to read pointer (MSBs differ, rest equal)
assign full = (wr_gray == {~rd_gray_wr1[ADDR_WIDTH:ADDR_WIDTH-1],
                             rd_gray_wr1[ADDR_WIDTH-2:0]});

// Read side
always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_bin   <= 0;
        rd_gray  <= 0;
        rd_valid <= 1'b0;
        rd_data  <= 0;
    end else begin
        rd_valid <= 1'b0;
        if (rd_en && !empty) begin
            rd_data  <= mem[rd_bin[ADDR_WIDTH-1:0]];
            rd_valid <= 1'b1;
            rd_bin   <= rd_bin + 1'b1;
            rd_gray  <= bin2gray(rd_bin + 1'b1);
        end
    end
end

// Sync wr_gray into rd_clk domain
always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) {wr_gray_rd1, wr_gray_rd0} <= 0;
    else           {wr_gray_rd1, wr_gray_rd0} <= {wr_gray_rd0, wr_gray};
end

assign empty = (rd_gray == wr_gray_rd1);

endmodule


// =============================================================================
//  4. Synchronous FIFO  (single-clock, for message buffering)
// =============================================================================
module sync_fifo #(
    parameter DATA_WIDTH = 256,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  full,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] rd_data,
    output reg                   rd_valid,
    output wire                  empty
);

localparam DEPTH = (1 << ADDR_WIDTH);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
reg [ADDR_WIDTH:0]   wr_ptr, rd_ptr;

assign full  = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
               (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
assign empty = (wr_ptr == rd_ptr);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr   <= 0;
        rd_ptr   <= 0;
        rd_valid <= 1'b0;
        rd_data  <= 0;
    end else begin
        rd_valid <= 1'b0;
        if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1'b1;
        end
        if (rd_en && !empty) begin
            rd_data  <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_valid <= 1'b1;
            rd_ptr   <= rd_ptr + 1'b1;
        end
    end
end
endmodule


// =============================================================================
//  5. Ethernet Header Stripper
//  Counts off HDR_BYTES bytes, checks EtherType, then passes payload.
// =============================================================================
module eth_header_stripper #(
    parameter HDR_BYTES  = 14,
    parameter ETHERTYPE  = 16'h88B5
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_start,
    input  wire        in_end,
    output reg         out_valid,
    output reg  [7:0]  out_data,
    output reg         out_start,
    output reg         out_end,
    output reg         ethertype_ok
);

reg [3:0]  hdr_cnt;       // counts 0..(HDR_BYTES-1), 0-indexed
reg        in_hdr;
reg        type_ok;
reg [7:0]  etype_msb;     // latch EtherType MSB at byte offset 12
reg        first_payload; // fires out_start exactly once on first payload byte

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hdr_cnt       <= 4'd0;
        in_hdr        <= 1'b0;
        type_ok       <= 1'b0;
        etype_msb     <= 8'h00;
        first_payload <= 1'b0;
        out_valid     <= 1'b0;
        out_data      <= 8'h00;
        out_start     <= 1'b0;
        out_end       <= 1'b0;
        ethertype_ok  <= 1'b0;
    end else begin
        out_valid <= 1'b0;
        out_start <= 1'b0;
        out_end   <= 1'b0;

        if (in_valid) begin
            if (in_start) begin
                hdr_cnt       <= 4'd1;
                in_hdr        <= 1'b1;
                type_ok       <= 1'b0;
                first_payload <= 1'b0;
            end else if (in_hdr) begin
                hdr_cnt <= hdr_cnt + 1'b1;

                if (hdr_cnt == 4'd12) etype_msb <= in_data;
                if (hdr_cnt == 4'd13) begin
                    type_ok      <= ({etype_msb, in_data} == ETHERTYPE);
                    ethertype_ok <= ({etype_msb, in_data} == ETHERTYPE);
                end

                if (hdr_cnt == HDR_BYTES - 1) begin
                    in_hdr        <= 1'b0;
                    first_payload <= type_ok ||
                                     ({etype_msb, in_data} == ETHERTYPE);
                end
            end else begin
                // Payload phase
                if (type_ok) begin
                    out_valid     <= 1'b1;
                    out_data      <= in_data;
                    out_start     <= first_payload;
                    out_end       <= in_end;
                    first_payload <= 1'b0;
                end
                if (in_end) begin
                    in_hdr        <= 1'b0;
                    hdr_cnt       <= 4'd0;
                    first_payload <= 1'b0;
                end
            end
        end

        if (in_end) begin
            in_hdr        <= 1'b0;
            hdr_cnt       <= 4'd0;
            first_payload <= 1'b0;
        end
    end
end
endmodule


// =============================================================================
//  6. Payload Assembler
//  Collects PAYLOAD_BYTES bytes then outputs a single wide bus word.
// =============================================================================
module payload_assembler #(
    parameter PAYLOAD_BYTES = 32
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       in_valid,
    input  wire [7:0]                 in_data,
    input  wire                       in_start,
    input  wire                       in_end,
    output reg                        out_valid,
    output reg  [PAYLOAD_BYTES*8-1:0] out_data,
    output reg                        overflow
);

reg [PAYLOAD_BYTES*8-1:0] shift;
reg [5:0]                  byte_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        shift     <= 0;
        byte_cnt  <= 6'd0;
        out_valid <= 1'b0;
        out_data  <= 0;
        overflow  <= 1'b0;
    end else begin
        out_valid <= 1'b0;
        overflow  <= 1'b0;

        if (in_valid) begin
            if (in_end) begin
                // Frame boundary: reset assembler state unconditionally
                byte_cnt <= 6'd0;
            end else if (in_start) begin
                // First payload byte of a new frame: reset and accept it
                byte_cnt <= 6'd1;
                shift    <= {{(PAYLOAD_BYTES*8-8){1'b0}}, in_data};
            end else if (byte_cnt < PAYLOAD_BYTES - 1) begin
                shift    <= {shift[PAYLOAD_BYTES*8-9:0], in_data};
                byte_cnt <= byte_cnt + 1'b1;
            end else if (byte_cnt == PAYLOAD_BYTES - 1) begin
                out_valid <= 1'b1;
                out_data  <= {shift[PAYLOAD_BYTES*8-9:0], in_data};
                byte_cnt  <= 6'd0;
            end else begin
                overflow <= 1'b1;
                byte_cnt <= 6'd0;
            end
        end
    end
end
endmodule

`default_nettype wire