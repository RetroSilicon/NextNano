// hdmi_out_gowin.v
// Serializes 3× 10-bit TMDS parallel words + routes clk_pixel as clock
// Uses 3× OSER10 + 4× ELVDS_OBUF (Gowin primitives)
//
// Pattern matches proven working serializer from Nanomig/MiSTle projects.
// Clock channel is NOT serialized - clk_pixel goes directly through ELVDS_OBUF.

module hdmi_out_gowin (
    input  wire        clk_pixel,       // 27 MHz
    input  wire        clk_pixel_x5,    // 135 MHz (OSER10 high-speed clock)
    input  wire        reset,           // active HIGH reset

    // TMDS parallel inputs from hdmi.vhd (Alexey Spirkov)
    // LSB first on wire - matches OSER10 D0..D9 ordering
    input  wire [9:0]  tmds_red,        // O_RED
    input  wire [9:0]  tmds_green,      // O_GREEN
    input  wire [9:0]  tmds_blue,       // O_BLUE

    // Differential HDMI outputs
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,     // [0]=blue, [1]=green, [2]=red
    output wire [2:0]  tmds_data_n
);

    // Single-ended serial streams before ELVDS_OBUF
    wire s_red;
    wire s_green;
    wire s_blue;

    // --------------------------------------------------
    // OSER10: Blue channel
    // --------------------------------------------------
    OSER10 oser_blue (
        .Q     (s_blue),
        .D0    (tmds_blue[0]),   // LSB first
        .D1    (tmds_blue[1]),
        .D2    (tmds_blue[2]),
        .D3    (tmds_blue[3]),
        .D4    (tmds_blue[4]),
        .D5    (tmds_blue[5]),
        .D6    (tmds_blue[6]),
        .D7    (tmds_blue[7]),
        .D8    (tmds_blue[8]),
        .D9    (tmds_blue[9]),
        .PCLK  (clk_pixel),
        .FCLK  (clk_pixel_x5),
        .RESET (reset)
    );

    // --------------------------------------------------
    // OSER10: Green channel
    // --------------------------------------------------
    OSER10 oser_green (
        .Q     (s_green),
        .D0    (tmds_green[0]),
        .D1    (tmds_green[1]),
        .D2    (tmds_green[2]),
        .D3    (tmds_green[3]),
        .D4    (tmds_green[4]),
        .D5    (tmds_green[5]),
        .D6    (tmds_green[6]),
        .D7    (tmds_green[7]),
        .D8    (tmds_green[8]),
        .D9    (tmds_green[9]),
        .PCLK  (clk_pixel),
        .FCLK  (clk_pixel_x5),
        .RESET (reset)
    );

    // --------------------------------------------------
    // OSER10: Red channel
    // --------------------------------------------------
    OSER10 oser_red (
        .Q     (s_red),
        .D0    (tmds_red[0]),
        .D1    (tmds_red[1]),
        .D2    (tmds_red[2]),
        .D3    (tmds_red[3]),
        .D4    (tmds_red[4]),
        .D5    (tmds_red[5]),
        .D6    (tmds_red[6]),
        .D7    (tmds_red[7]),
        .D8    (tmds_red[8]),
        .D9    (tmds_red[9]),
        .PCLK  (clk_pixel),
        .FCLK  (clk_pixel_x5),
        .RESET (reset)
    );

    // --------------------------------------------------
    // ELVDS_OBUF: single-ended -> differential pair
    // 3 data channels + 1 clock (clock goes directly from clk_pixel)
    // --------------------------------------------------
    ELVDS_OBUF obuf_blue (
        .I  (s_blue),
        .O  (tmds_data_p[0]),
        .OB (tmds_data_n[0])
    );

    ELVDS_OBUF obuf_green (
        .I  (s_green),
        .O  (tmds_data_p[1]),
        .OB (tmds_data_n[1])
    );

    ELVDS_OBUF obuf_red (
        .I  (s_red),
        .O  (tmds_data_p[2]),
        .OB (tmds_data_n[2])
    );

    // Clock channel - clk_pixel goes directly through ELVDS_OBUF (no serialization)
    ELVDS_OBUF obuf_clk (
        .I  (clk_pixel),
        .O  (tmds_clk_p),
        .OB (tmds_clk_n)
    );

endmodule