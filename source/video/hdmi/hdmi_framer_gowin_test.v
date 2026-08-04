//
// HDMI Framer for ZX Spectrum Next -> HDMI 720x576p 50Hz
// Multi-mode horizontal support: 256, 320, 512, 640 ULA pixels
//
// Writer-side alignment:
//   wr_hcnt is reset on rising edge of hblank_n (start of active region),
//   so wr_hcnt=0 always corresponds to the first visible ULA pixel,
//   independent of the horizontal resolution mode. No reader-side
//   per-mode H_OFFSET calibration is needed.
//
// R_OFFSET below shifts the displayed image right within the HDMI raster
// purely for cosmetic centering. It is NOT used to compensate for video mode.
//
// CDC:
//   wr_line_toggle (max 1 transition per ULA line, ~64us) -> 2-FF + per-line latch
//   vs_edge_seen   (toggles on ULA vsync edge)            -> 2-FF + edge detect
//
// Pipeline:
//   rd_hcnt -> [comb] addr -> [BSRAM 1 cyc] rd_buf_data -> [output reg 1 cyc] o_rgb
//   sync/blank/valid pipelined by 1 stage so they align to the same total
//   2-cycle delay as o_rgb.
//
// Vertical alignment:
//   HDMI vcounter is snapped to V_SYNC_POINT on every ULA vsync edge.
//   This causes at worst one slightly distorted line per frame when the
//   independent PLLs (28 MHz vs 27 MHz) drift. Without this, frame position
//   would slowly walk. Comment-out the snap if you prefer pure free-run.
//

module hdmi_framer_gowin (
    // ===== Write side: clk_sys (28 MHz) =====
    input  wire        clk_sys,
    input  wire        reset,

    // Raw video signals from zxnext
    input  wire        hs_in,       // active HIGH hsync (used only to phase ce_x1)
    input  wire        vs_in,       // active HIGH vsync
    input  wire        hblank_n,    // '1' = active, '0' = horizontal blank
    input  wire        vblank_n,    // '1' = active, '0' = vertical blank
    input  wire [8:0]  rgb_in,      // 9-bit RGB333

    // ===== Read side: clk_hdmi_pixel (27 MHz) =====
    input  wire        clk_hdmi_pixel,
    input reg mode_60,

    // HDMI video output (active HIGH syncs)
    output reg         o_blank,
    output reg         o_hsync,
    output reg         o_vsync,
    output reg  [8:0]  o_rgb
);

    // ==========================================================
    // PARAMETERS / CONSTANTS
    // ==========================================================
    parameter HCNT_WIDTH = 10;   // 1024 entries per buffer half
                                 // (>=896 samples per ULA line @ 14 MHz)

    // CEA-861 720x576p @ 50 Hz
    localparam [10:0] H_ACTIVE  = 11'd720;
    localparam [10:0] H_FPORCH  = 11'd732;
    localparam [10:0] H_SYNC    = 11'd796;
    localparam [10:0] H_TOTAL   = 11'd912;

// reg        mode_60 = 1'b0;

    // localparam [9:0]  V_ACTIVE  = 10'd576;
    // localparam [9:0]  V_FPORCH  = 10'd581;
    // localparam [9:0]  V_SYNC    = 10'd586;
    // localparam [9:0]  V_TOTAL   = 10'd622;

    // // Snap point for HDMI vcnt on each ULA vsync edge.
    // parameter [9:0]   V_SYNC_POINT = 10'd590;


    wire [9:0] V_ACTIVE     = mode_60 ? 10'd480 : 10'd576;
    wire [9:0] V_FPORCH     = mode_60 ? 10'd489 : 10'd581;  // FP: 9 / 5 lines
    wire [9:0] V_SYNC       = mode_60 ? 10'd495 : 10'd586;  // sync: 6 / 5 lines
    wire [9:0] V_TOTAL      = mode_60 ? 10'd525 : 10'd622;
    wire [9:0] V_SYNC_POINT = mode_60 ? 10'd499 : 10'd590;  // a few lines into back porch

    // Cosmetic horizontal offset within HDMI active.
    // 0  -> image starts at HDMI x=0 (left aligned)
    // 40 -> 640-px modes pillar-box symmetrically (40 px each side)
    // Pick whatever centers your most common mode.
    parameter [10:0]  R_OFFSET = 11'd0;

    // ==========================================================
    // WRITER (clk_sys @ 28 MHz)
    // ==========================================================

    // 14 MHz pixel sampling enable, phased to ULA hsync falling edge
    reg [1:0] i_div;
    reg       hs_d;

    always @(posedge clk_sys) begin
        if (reset) begin
            i_div <= 2'b00;
            hs_d  <= 1'b0;
        end else begin
            hs_d <= hs_in;
            if (hs_d && !hs_in)
                i_div <= 2'b00;          // resync at hsync falling edge
            else
                i_div <= i_div + 1'b1;
        end
    end

    wire ce_x1 = i_div[0];   // 14 MHz sampling

    // Line buffer: 2 halves (ping-pong) x 1024 entries x 10 bits
    // Bit 9 = active flag, bits 8:0 = RGB333
    // (* syn_ramstyle = "block_ram" *)
    // reg [9:0] line_buf [0:2*(2**HCNT_WIDTH)-1];


(* syn_ramstyle = "block_ram" *)
reg [9:0] line_buf_0 [0:(2**HCNT_WIDTH)-1];

(* syn_ramstyle = "block_ram" *)
reg [9:0] line_buf_1 [0:(2**HCNT_WIDTH)-1];

    reg                  wr_line_toggle;
    reg [HCNT_WIDTH-1:0] wr_hcnt;
    reg                  hblank_n_d;
    reg                  vs_d;
    reg                  vs_edge_seen;   // toggles on ULA vsync rising edge (CDC bit)

    always @(posedge clk_sys) begin
        if (reset) begin
            wr_line_toggle <= 1'b0;
            wr_hcnt        <= {HCNT_WIDTH{1'b0}};
            hblank_n_d     <= 1'b0;
            vs_d           <= 1'b0;
            vs_edge_seen   <= 1'b0;
        end else if (ce_x1) begin
            hblank_n_d <= hblank_n;
            vs_d       <= vs_in;

            // ULA vsync rising edge -> toggle CDC bit
            if (!vs_d && vs_in)
                vs_edge_seen <= !vs_edge_seen;

            // hblank_n falling edge (end of active) -> flip ping-pong
            if (hblank_n_d && !hblank_n)
                wr_line_toggle <= !wr_line_toggle;

            // hblank_n rising edge (start of active) -> reset hcnt
            // After this, wr_hcnt=0 maps to first visible ULA pixel,
            // independent of horizontal mode (256/320/512/640).
            if (!hblank_n_d && hblank_n)
                wr_hcnt <= {HCNT_WIDTH{1'b0}};
            else if (wr_hcnt != {HCNT_WIDTH{1'b1}})
                wr_hcnt <= wr_hcnt + 1'b1;   // saturate at max - never wrap

            // Always write current sample (active flag carries blank info)
            // line_buf[{wr_line_toggle, wr_hcnt}] <= {hblank_n & vblank_n, rgb_in};
if (wr_line_toggle == 1'b0)
    line_buf_0[wr_hcnt] <= {hblank_n & vblank_n, rgb_in};
else
    line_buf_1[wr_hcnt] <= {hblank_n & vblank_n, rgb_in};
        end
    end

    // ==========================================================
    // READER (clk_hdmi_pixel @ 27 MHz)
    // ==========================================================

    reg [10:0] rd_hcnt;
    reg  [9:0] rd_vcnt;

    // CDC synchronizers
    reg wr_toggle_sync1, wr_toggle_sync2, wr_toggle_latched;
    reg vs_sync1, vs_sync2, vs_sync3;

    always @(posedge clk_hdmi_pixel) begin
        wr_toggle_sync1 <= wr_line_toggle;
        wr_toggle_sync2 <= wr_toggle_sync1;
        vs_sync1        <= vs_edge_seen;
        vs_sync2        <= vs_sync1;
        vs_sync3        <= vs_sync2;

        // Latch wr_toggle once per HDMI line for stable buffer-half selection
        if (rd_hcnt == 11'd0)
            wr_toggle_latched <= wr_toggle_sync2;
    end

    wire vs_edge_pulse = vs_sync2 ^ vs_sync3;

    // HDMI counters - free run between ULA vsync edges, snap on edge
    always @(posedge clk_hdmi_pixel) begin
        if (vs_edge_pulse) begin
            rd_vcnt <= V_SYNC_POINT;
            rd_hcnt <= 11'd0;
        end else if (rd_hcnt == H_TOTAL - 1'b1) begin
            rd_hcnt <= 11'd0;
            if (rd_vcnt == V_TOTAL - 1'b1)
                rd_vcnt <= 10'd0;
            else
                rd_vcnt <= rd_vcnt + 1'b1;
        end else begin
            rd_hcnt <= rd_hcnt + 1'b1;
        end
    end

    // ==========================================================
    // BUFFER ADDRESS WITH SAFE WRAP-AROUND
    // ==========================================================
    // Apply cosmetic R_OFFSET in signed math. When rd_hcnt < R_OFFSET
    // we are to the left of the image - mark address invalid and force
    // black, never let the address wrap into uninitialised buffer space.

    wire signed [11:0] rd_eff =
        $signed({1'b0, rd_hcnt}) - $signed({1'b0, R_OFFSET});

    wire addr_valid = (rd_eff >= 12'sd0) && (rd_eff < 12'sd1024);

    wire [HCNT_WIDTH-1:0] rd_buf_addr =
        addr_valid ? rd_eff[HCNT_WIDTH-1:0] : {HCNT_WIDTH{1'b0}};

    wire rd_line_side = ~wr_toggle_latched;

    // Synchronous BSRAM read (1 cycle latency)
    // reg [9:0] rd_buf_data;
    // always @(posedge clk_hdmi_pixel) begin
    //     rd_buf_data <= line_buf[{rd_line_side, rd_buf_addr}];
    // end

reg [9:0] rd_buf_data_0, rd_buf_data_1;
reg       rd_line_side_d;

always @(posedge clk_hdmi_pixel) begin
    rd_buf_data_0  <= line_buf_0[rd_buf_addr];
    rd_buf_data_1  <= line_buf_1[rd_buf_addr];
    rd_line_side_d <= rd_line_side;   // delay to match BSRAM read latency
end

wire [9:0] rd_buf_data = rd_line_side_d ? rd_buf_data_1 : rd_buf_data_0;

    // ==========================================================
    // PIPELINE-ALIGNED OUTPUT
    // ==========================================================
    // 2-cycle path: rd_hcnt -> [comb addr] -> [BSRAM 1] -> [output reg 1] -> o_rgb
    // Sync/blank/valid get exactly one pipe stage (p1) before the output reg
    // so they share the same 2-cycle latency.

    wire        hdmi_h_active = (rd_hcnt < H_ACTIVE);
    wire        hdmi_v_active = (rd_vcnt < V_ACTIVE);
    wire        hdmi_active   = hdmi_h_active && hdmi_v_active;
    wire        hsync_raw     = (rd_hcnt >= H_FPORCH) && (rd_hcnt < H_SYNC);
    wire        vsync_raw     = (rd_vcnt >= V_FPORCH) && (rd_vcnt < V_SYNC);

    reg hdmi_active_p1, hsync_p1, vsync_p1, addr_valid_p1;

    always @(posedge clk_hdmi_pixel) begin
        hdmi_active_p1 <= hdmi_active;
        hsync_p1       <= hsync_raw;
        vsync_p1       <= vsync_raw;
        addr_valid_p1  <= addr_valid;
    end

    // Final output stage (everything aligned to same rd_hcnt sample)
    always @(posedge clk_hdmi_pixel) begin
        o_blank <= !hdmi_active_p1;
        o_hsync <= hsync_p1;
        o_vsync <= vsync_p1;

        if (hdmi_active_p1 && rd_buf_data[9] && addr_valid_p1)
            o_rgb <= rd_buf_data[8:0];
        else
            o_rgb <= 9'b0;
    end

endmodule