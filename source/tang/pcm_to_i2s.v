// PCM stereo (12-bit unsigned, clamped) -> I2S mono transmitter
// For Tang Nano 20K onboard DAC (MSM5351 or similar)
//
// ZX Next top module outputs:
//   audio_L[11:0] - 12-bit unsigned PCM (clamped/saturated from 13-bit)
//   audio_R[11:0] - 12-bit unsigned PCM (clamped/saturated from 13-bit)
//
// Volume control [2:0]:
//   0 = full         (0 dB)
//   1 = -6 dB        (1/2)
//   2 = -12 dB       (1/4)
//   3 = -18 dB       (1/8)
//   4 = -24 dB       (1/16)
//   5 = -30 dB       (1/32)
//   6 = -36 dB       (1/64)
//   7 = mute
//
// I2S output: standard Philips I2S format
//   - SDATA transitions on BCLK falling edge
//   - Receiver samples on BCLK rising edge
//   - 1 BCLK delay after LRCK transition before MSB
//   - LRCK: 0 = left, 1 = right
//
// From 28 MHz clock:
//   MCLK = 14 MHz    (28/2)
//   BCLK = 3.5 MHz   (28/8)
//   LRCK = ~54.7 kHz (BCLK/64, 32 bits per channel)

module pcm_to_i2s (
    input  wire        clk,        // 28 MHz
    input  wire        reset_n,

    // PCM input from ZX Next top (12-bit unsigned, clamped)
    input  wire [11:0] pcm_l,
    input  wire [11:0] pcm_r,

    // Volume: 0=full, 1=-6dB, 2=-12dB, ... 6=-36dB, 7=mute
    input  wire  [2:0] volume,

    // I2S output
    output wire        i2s_mclk,   // master clock to DAC (14 MHz)
    output reg         i2s_bclk,
    output reg         i2s_lrck,   // 0=left, 1=right
    output reg         i2s_sdata
);

    // ==========================================================
    // 1. Mix stereo to mono, convert to signed 16-bit
    // ==========================================================
    // 12-bit unsigned [0..4095], midpoint = 2048
    wire signed [12:0] sl = {1'b0, pcm_l} - 13'sd2048;
    wire signed [12:0] sr = {1'b0, pcm_r} - 13'sd2048;

    // Average (L+R)/2
    wire signed [13:0] sum  = sl + sr;
    wire signed [12:0] avg  = sum[13:1];  // 13-bit signed, range -2048..+2047

    // Scale to 16-bit (shift left 3)
    wire signed [15:0] full = {avg, 3'b000};

    // ==========================================================
    // 2. Volume: arithmetic right shift (sign-extending)
    // ==========================================================
    reg signed [15:0] mono;

    always @(*) begin
        case (volume)
            3'd0: mono = full;
            3'd1: mono = {full[15], full[15:1]};
            3'd2: mono = {{2{full[15]}}, full[15:2]};
            3'd3: mono = {{3{full[15]}}, full[15:3]};
            3'd4: mono = {{4{full[15]}}, full[15:4]};
            3'd5: mono = {{5{full[15]}}, full[15:5]};
            3'd6: mono = {{6{full[15]}}, full[15:6]};
            3'd7: mono = 16'sd0;  // mute
        endcase
    end

    // ==========================================================
    // 3. MCLK generation: 28 MHz / 2 = 14 MHz
    // ==========================================================
    reg mclk_r;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) mclk_r <= 1'b0;
        else          mclk_r <= ~mclk_r;
    assign i2s_mclk = mclk_r;

    // ==========================================================
    // 4. Master counter: 512 clk cycles = 64 BCLK periods = 1 frame
    // ==========================================================
    // cnt[2:0] = sub-phase within one BCLK period (0..7)
    // cnt[8:3] = bit position within frame (0..63)
    //
    // BCLK = high when cnt[2]==0, low when cnt[2]==1
    // Update SDATA/LRCK on BCLK falling edge (sub == 4)

    reg [8:0] cnt;
    wire [5:0] bit_pos = cnt[8:3];
    wire [2:0] sub     = cnt[2:0];

    reg signed [15:0] samp;    // latched sample
    reg        [15:0] sreg;    // shift register

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cnt       <= 9'd0;
            i2s_bclk  <= 1'b0;
            i2s_lrck  <= 1'b0;
            i2s_sdata <= 1'b0;
            samp      <= 16'd0;
            sreg      <= 16'd0;
        end else begin
            cnt <= cnt + 9'd1;

            // BCLK: high for first half, low for second half of each period
            i2s_bclk <= ~cnt[2];

            // All updates on BCLK falling edge
            if (sub == 3'd4) begin

                // LRCK: 0 for left ch (bit_pos 0..31), 1 for right (32..63)
                i2s_lrck <= bit_pos[5];

                // Latch new mono sample just before frame wraps
                if (bit_pos == 6'd63)
                    samp <= mono;

                // I2S data: 1 BCLK delay after LRCK edge, then 16 bits MSB-first
                // Left:  delay at bit_pos 0, data at 1..16, zero-pad 17..31
                // Right: delay at bit_pos 32, data at 33..48, zero-pad 49..63
                // Mono = same sample on both channels

                if (bit_pos == 6'd0 || bit_pos == 6'd32) begin
                    // Delay slot after LRCK transition - load shift register
                    sreg      <= samp;
                    i2s_sdata <= 1'b0;
                end
                else if (bit_pos <= 6'd16 || (bit_pos >= 6'd33 && bit_pos <= 6'd48)) begin
                    // Shift out MSB first
                    i2s_sdata <= sreg[15];
                    sreg      <= {sreg[14:0], 1'b0};
                end
                else begin
                    // Zero padding for remaining bits
                    i2s_sdata <= 1'b0;
                end
            end
        end
    end

endmodule
