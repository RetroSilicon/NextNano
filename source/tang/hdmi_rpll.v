// clk_hdmi_gowin.v
module clk_hdmi_gowin
(
    input  wire clkin_27,      // Tang Nano 20K HDMI crystal 27 MHz
    output wire clk_pixel_x5,  // 135 MHz
    output wire clk_pixel,     // 27 MHz (clk_pixel_x5 ÷5)
    output wire pll_locked
);

    wire clk_135_raw;

    rPLL hdmi_pll (
        .CLKOUT  (clk_135_raw),    // 135 MHz
        .LOCK    (pll_locked),
        .CLKOUTP (),
        .CLKOUTD (),
        .CLKOUTD3(),
        .RESET   (1'b0),
        .RESET_P (1'b0),
        .CLKIN   (clkin_27),       // 27 MHz in
        .CLKFB   (1'b0),
        .FBDSEL  (6'b000000),
        .IDSEL   (6'b000000),
        .ODSEL   (6'b000000),
        .PSDA    (4'b0000),
        .DUTYDA  (4'b0000),
        .FDLY    (4'b1111)
    );

    defparam hdmi_pll.FCLKIN     = "28.125";
    defparam hdmi_pll.IDIV_SEL   = 0;   // IDIV = 1
    defparam hdmi_pll.FBDIV_SEL  = 4;   // FBDIV = 5  (27 × 5 / 1 = 135 MHz)
    defparam hdmi_pll.ODIV_SEL   = 4;   // ODIV = 4   (VCO = 540 MHz, OK range 400-1200)
    defparam hdmi_pll.PSDA_SEL   = "0000";
    defparam hdmi_pll.DYN_DA_EN  = "false";
    defparam hdmi_pll.DUTYDA_SEL = "1000";
    defparam hdmi_pll.CLKOUT_FT_DIR  = 1'b1;
    defparam hdmi_pll.CLKOUTP_FT_DIR = 1'b1;
    defparam hdmi_pll.CLKOUT_DLY_STEP = 0;
    defparam hdmi_pll.CLKOUTP_DLY_STEP = 0;
    defparam hdmi_pll.CLKFB_SEL       = "internal";
    defparam hdmi_pll.CLKOUT_BYPASS   = "false";
    defparam hdmi_pll.CLKOUTP_BYPASS  = "false";
    defparam hdmi_pll.CLKOUTD_BYPASS  = "false";
    defparam hdmi_pll.DYN_SDIV_SEL    = 2;
    defparam hdmi_pll.CLKOUTD_SRC     = "CLKOUT";
    defparam hdmi_pll.CLKOUTD3_SRC    = "CLKOUT";
    defparam hdmi_pll.DEVICE          = "GW2AR-18C";

    CLKDIV clkdiv_pixel (
        .CLKOUT(clk_pixel),
        .HCLKIN(clk_135_raw),
        .RESETN(pll_locked),
        .CALIB (1'b0)
    );
    defparam clkdiv_pixel.DIV_MODE = "5";
    defparam clkdiv_pixel.GSREN    = "false";

    assign clk_pixel_x5 = clk_135_raw;

endmodule