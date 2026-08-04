//
// Scandoubler for ZX Spectrum Next -> Tang Nano 20K LCD
//
// Single clock domain: clk_sys (CLK_28 = 4 * CLK_7)
// No clock domain crossing - everything runs on CLK_28 with clock enables.
//
// ce_x1 fires at CLK_7 rate  (every 4th CLK_28) -> input pixel rate
// ce_x2 fires at CLK_14 rate (every 2nd CLK_28) -> output pixel rate (2x)
//
// Write side: on ce_x1, store pixel + sync info into line buffer
// Read side:  on ce_x2, read from buffer at 2x rate
//             Output counter synced to input hsync (same clock domain!)
//
// Line buffer: single RAM addressed by {line_toggle, hcnt}
//

module scandoubler (
    input  wire        clk_sys,    // 28 MHz system clock
    input  wire        reset,

    // Input video (directly from ZX Next, active at CLK_7 rate)
    input  wire        hs_in,      // active HIGH hsync (directly active-high recommended, but active-low also handled)
    input  wire        vs_in,      // active HIGH vsync
    input  wire [2:0]  r_in,
    input  wire [2:0]  g_in,
    input  wire [2:0]  b_in,
    input  wire        hblank_n,
    input  wire        vblank_n,

    // Output video
    output reg  [4:0]  o_r,
    output reg  [5:0]  o_g,
    output reg  [4:0]  o_b,
    output reg         o_hs,      // active high
    output reg         o_vs,      // active high
    output reg         o_de,      // data enable
    output wire        pixel_ena  // active on ce_x2 - directly useable
);

    // =====================================================================
    // Clock enable generation
    // =====================================================================
    // CLK_28 / 4 = CLK_7 rate, CLK_28 / 2 = CLK_14 rate
    //
    // Sync divider to input hsync falling edge so we stay aligned.

    reg [1:0] i_div;
    reg       ce_x1;   // pulses at CLK_7 rate
    reg       ce_x2;   // pulses at CLK_14 rate

    always @(posedge clk_sys) begin
        reg last_hs;
        if (reset) begin
            last_hs <= 0;
            i_div   <= 0;
        end else begin
            last_hs <= hs_in;
            // Re-sync divider on hsync falling edge (start of line)
            if (last_hs && !hs_in)
                i_div <= 0;
            else
                i_div <= i_div + 1'd1;
        end
    end

    always @(*) begin
        ce_x1 = (i_div == 2'b01);   // once every 4 clocks
        ce_x2 = i_div[0];           // once every 2 clocks
    end

    assign pixel_ena = ce_x2;

    // =====================================================================
    // Line buffer - single RAM, two halves
    // =====================================================================
    // Address: {line_toggle, hcnt[9:0]} 
    // Data: {de, r[2:0], g[2:0], b[2:0]} = 10 bits

    parameter HCNT_WIDTH = 10;

    (* ramstyle = "no_rw_check" *) reg [9:0] sd_buffer [0:2*2**HCNT_WIDTH-1];

    // =====================================================================
    // Write side - runs at ce_x1 (CLK_7 rate)
    // =====================================================================

    reg        line_toggle;
    reg [HCNT_WIDTH-1:0] hcnt;
    reg [HCNT_WIDTH-1:0] hs_max;    // length of input line
    reg [HCNT_WIDTH-1:0] hs_rise;   // position of hsync rising edge

    always @(posedge clk_sys) begin
        reg hsD, vsD;

        if (reset) begin
            hsD         <= 0;
            vsD         <= 0;
            line_toggle <= 0;
            hcnt        <= 0;
            hs_max      <= 0;
            hs_rise     <= 0;
        end else if (ce_x1) begin
            hsD <= hs_in;

            // Falling edge of hsync = start of new line
            if (hsD && !hs_in) begin
                hs_max <= hcnt;
                hcnt   <= 0;
            end else begin
                hcnt <= hcnt + 1'd1;
            end

            // Rising edge of hsync = save position
            if (!hsD && hs_in)
                hs_rise <= hcnt;

            // Vsync edge toggles line_toggle reset
            vsD <= vs_in;
            if (vsD != vs_in)
                line_toggle <= 0;

            // Hsync falling edge toggles line
            if (hsD && !hs_in)
                line_toggle <= !line_toggle;

            // Store pixel with DE
            sd_buffer[{line_toggle, hcnt}] <= {hblank_n & vblank_n, r_in, g_in, b_in};
        end
    end

    // =====================================================================
    // Read side - runs at ce_x2 (CLK_14 rate = 2x input)
    // =====================================================================
    //
    // Output counter runs at 2x speed.
    // It is re-synced to input hsync (same clock domain, no CDC needed).
    // Reads from the OTHER half of the buffer (~line_toggle).
    //
    // Each input line of hs_max pixels is read twice:
    //   sd_hcnt counts 0..hs_max at ce_x2 rate
    //   Since ce_x2 = 2 * ce_x1, sd_hcnt wraps twice per input line
    //   = two output lines per input line
    //

    reg [HCNT_WIDTH-1:0] sd_hcnt;
    reg        hs_sd, vs_sd;
    reg [9:0]  sd_data_out;

    always @(posedge clk_sys) begin
        reg hsD;

        if (reset) begin
            hsD        <= 0;
            sd_hcnt    <= 0;
            hs_sd      <= 0;
            vs_sd      <= 0;
            sd_data_out <= 0;
        end else if (ce_x2) begin
            hsD <= hs_in;

            // Counter management
            sd_hcnt <= sd_hcnt + 1'd1;
            if (hsD && !hs_in)      sd_hcnt <= hs_max;  // sync to input
            if (sd_hcnt == hs_max)  sd_hcnt <= 0;       // wrap

            // Replicate hsync at 2x rate
            if (sd_hcnt == hs_max)   hs_sd <= 0;
            if (sd_hcnt == hs_rise)  hs_sd <= 1;

            // Vsync pass-through
            vs_sd <= vs_in;

            // Read from the OTHER line buffer half
            sd_data_out <= sd_buffer[{~line_toggle, sd_hcnt}];
        end
    end

    // =====================================================================
    // Output formatting
    // =====================================================================
    // sd_data_out = {de, r[2:0], g[2:0], b[2:0]}

    wire       out_de = sd_data_out[9];
    wire [2:0] out_r  = sd_data_out[8:6];
    wire [2:0] out_g  = sd_data_out[5:3];
    wire [2:0] out_b  = sd_data_out[2:0];

// Licznik linii output
reg [9:0] v_cnt;
reg       prev_hs;

    always @(posedge clk_sys) begin
        if (reset) begin
            o_r  <= 0;
            o_g  <= 0;
            o_b  <= 0;
            o_hs <= 0;
            o_vs <= 0;
            o_de <= 0;
        end else if (ce_x2) begin
            o_hs <= hs_sd;
            o_vs <= vs_sd;
            //o_de <= out_de;

        prev_hs <= o_hs;
        if (o_hs && !prev_hs)        // rising edge hsync = nowa linia
            v_cnt <= v_cnt + 1;
        if (vs_sd)                    // reset na vsync (nawet jeśli LCD go ignoruje)
            v_cnt <= 0;

o_de <= out_de && (v_cnt > 70); //75 76 77

            // RGB333 -> RGB565
            if (out_de) begin
                o_r <= {out_r, out_r[2:1]};   // ABC -> ABCAB
                o_g <= {out_g, out_g};         // ABC -> ABCABC
                o_b <= {out_b, out_b[2:1]};   // ABC -> ABCAB
            end else begin
                o_r <= 5'd0;
                o_g <= 6'd0;
                o_b <= 5'd0;
            end
        end
    end

endmodule