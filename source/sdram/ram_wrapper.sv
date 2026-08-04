//-----------------------------------------------------------------------------
// SDRAM controller -- Tang Nano 20K
// V113: V112 + independent Port-A response consume/request acceptance
//-----------------------------------------------------------------------------

module ram #(
    parameter REFRESH_SOFT_CYCLES     = 512,
    parameter REFRESH_HARD_CYCLES     = 1024,
    parameter REFRESH_RECOVERY_CYCLES = 2
) (
    input  logic        clk,
    input  logic        clk_sdram,
    input  logic        init,
    input  logic        port_reset,
    input  logic        clk_ram,

    input  logic [20:0] RAM_A_ADDR,
    input  logic        RAM_A_REQ,
    input  logic        RAM_A_REQ_LEVEL,
    input  logic        RAM_A_CYCLE,
    input  logic        RAM_A_RD_n,
    input  logic [7:0]  RAM_A_DI,
    output logic [7:0]  RAM_A_DO,
    output logic        RAM_A_WAIT,

    input  logic [20:0] RAM_B_ADDR,
    input  logic        RAM_B_REQ,
    output logic [7:0]  RAM_B_DO,

    output logic        sdram_ready,
    output logic [5:0]  DEBUG_FLAGS,

    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic        O_sdram_cs_n,
    output logic        O_sdram_cas_n,
    output logic        O_sdram_ras_n,
    output logic        O_sdram_wen_n,
    inout  wire  [31:0] IO_sdram_dq,
    output logic [10:0] O_sdram_addr,
    output logic [1:0]  O_sdram_ba,
    output logic [3:0]  O_sdram_dqm
);

    localparam FREQ = 140_000_000;
    localparam int WAYS = 4;

`ifndef SYNTHESIS
    initial begin
        if (REFRESH_SOFT_CYCLES < 1)
            $error("REFRESH_SOFT_CYCLES must be >= 1");
        if (REFRESH_HARD_CYCLES <= REFRESH_SOFT_CYCLES)
            $error("REFRESH_HARD_CYCLES must be greater than REFRESH_SOFT_CYCLES");
        if (REFRESH_HARD_CYCLES > 4095)
            $error("REFRESH_HARD_CYCLES must fit the 12-bit refresh counter");
        if (REFRESH_RECOVERY_CYCLES < 1 || REFRESH_RECOVERY_CYCLES > 15)
            $error("REFRESH_RECOVERY_CYCLES must be in range 1..15");
    end
`endif

    assign O_sdram_clk  = clk_sdram;
    assign O_sdram_cke  = 1'b1;
    assign O_sdram_cs_n = 1'b0;

    reg         dq_oen = 1'b1;
    reg  [31:0] dq_out;
    assign IO_sdram_dq = dq_oen ? {32{1'bz}} : dq_out;

    reg [31:0] data_reg;
    always @(posedge clk)
        data_reg <= IO_sdram_dq;

    localparam CMD_LoadMode    = 3'b000;
    localparam CMD_AutoRefresh = 3'b001;
    localparam CMD_Precharge   = 3'b010;
    localparam CMD_Active      = 3'b011;
    localparam CMD_Write       = 3'b100;
    localparam CMD_Read        = 3'b101;
    localparam CMD_NOP         = 3'b111;

    localparam RASCAS_DELAY = 3'd2;
    localparam CAS_LATENCY  = 3'd2;
    localparam [10:0] MODE = {4'b0000, CAS_LATENCY[2:0], 1'b0, 3'b000};

    localparam [3:0] STATE_IDLE  = 4'd0;
    localparam [3:0] STATE_START = 4'd1;
    localparam [3:0] STATE_CONT  = STATE_START + {1'b0, RASCAS_DELAY};
    localparam [3:0] STATE_READY = STATE_CONT + {1'b0, CAS_LATENCY} + 4'd2;
    localparam [3:0] STATE_LAST  = 4'd7;

    reg [3:0] state = STATE_IDLE;

    localparam [1:0] MODE_NORMAL = 2'b00;
    localparam [1:0] MODE_RESET  = 2'b01;
    localparam [1:0] MODE_LDM    = 2'b10;
    localparam [1:0] MODE_PRE    = 2'b11;

    reg [1:0] mode = MODE_NORMAL;
    reg [4:0] reset = 5'h1f;

    reg [20:0] a = 21'd0;
    reg [7:0]  data = 8'h00;
    reg        we = 1'b0;
    reg        ram_req = 1'b0;
    reg        ch0_busy = 1'b0;
    reg        ch1_busy = 1'b0;
    reg        sdram_ready_r = 1'b0;

    //-------------------------------------------------------------------------
    // Same-source-domain status levels used only by refresh arbitration.
    //-------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg a_req_level_meta_112 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg a_req_level_sync_112 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg a_cycle_meta_112 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg a_cycle_sync_112 = 1'b0;
    reg a_source_cycle_active_112 = 1'b0;

    always @(posedge clk) begin
        if (init) begin
            a_req_level_meta_112      <= 1'b0;
            a_req_level_sync_112      <= 1'b0;
            a_cycle_meta_112          <= 1'b0;
            a_cycle_sync_112          <= 1'b0;
            a_source_cycle_active_112 <= 1'b0;
        end else begin
            a_req_level_meta_112      <= RAM_A_REQ_LEVEL;
            a_req_level_sync_112      <= a_req_level_meta_112;
            a_cycle_meta_112          <= RAM_A_CYCLE;
            a_cycle_sync_112          <= a_cycle_meta_112;
            a_source_cycle_active_112 <= a_req_level_sync_112 | a_cycle_sync_112;
        end
    end

    //-------------------------------------------------------------------------
    // Port-A request mailbox and reset epoch.
    //-------------------------------------------------------------------------
    reg [20:0] a_req_addr_28   = 21'd0;
    reg [7:0]  a_req_wdata_28  = 8'h00;
    reg        a_req_write_28  = 1'b0;
    reg        a_req_epoch_28  = 1'b0;
    reg        a_req_toggle_28 = 1'b0;
    reg        a_epoch_28      = 1'b0;
    reg        port_reset_d_28 = 1'b1;

    (* ASYNC_REG = "TRUE" *) reg a_req_toggle_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg a_req_toggle_sync2 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg a_epoch_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg a_epoch_sync2 = 1'b0;
    reg a_req_toggle_seen_112 = 1'b0;
    reg a_epoch_seen_112 = 1'b0;

    always @(posedge clk) begin
        if (init) begin
            a_req_toggle_sync1 <= 1'b0;
            a_req_toggle_sync2 <= 1'b0;
            a_epoch_sync1      <= 1'b0;
            a_epoch_sync2      <= 1'b0;
        end else begin
            a_req_toggle_sync1 <= a_req_toggle_28;
            a_req_toggle_sync2 <= a_req_toggle_sync1;
            a_epoch_sync1      <= a_epoch_28;
            a_epoch_sync2      <= a_epoch_sync1;
        end
    end

    wire a_req_event = (a_req_toggle_sync2 != a_req_toggle_seen_112);
    wire a_epoch_event = (a_epoch_sync2 != a_epoch_seen_112);
    wire a_req_epoch_matches = (a_req_epoch_28 == a_epoch_sync2);

    //-------------------------------------------------------------------------
    // Port-B control synchronizer and held payload capture.
    //-------------------------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg b_req_toggle_sync1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg b_req_toggle_sync2 = 1'b0;
    reg b_req_toggle_seen_112 = 1'b0;

    // Disposable first payload sample.  It may capture the address on the
    // coincident clk_ram/clk edge, but it is overwritten on following fast
    // edges and is not consumed until the synchronized request event.  Once a
    // request is pending or its SDRAM fill has started, the sample is frozen.
    reg [20:0] b_req_addr_r = 21'd0;
    reg b_req_pending = 1'b0;

    always @(posedge clk) begin
        if (init) begin
            b_req_toggle_sync1 <= 1'b0;
            b_req_toggle_sync2 <= 1'b0;
        end else begin
            b_req_toggle_sync1 <= RAM_B_REQ;
            b_req_toggle_sync2 <= b_req_toggle_sync1;
        end
    end

    always @(posedge clk) begin
        if (init) begin
            b_req_addr_r <= 21'd0;
        end else if (!b_req_pending && !ch1_busy) begin
            b_req_addr_r <= RAM_B_ADDR;
        end
    end

    wire b_req_event = (b_req_toggle_sync2 != b_req_toggle_seen_112);
    wire b_have_request = b_req_pending | b_req_event;

    // Track the synchronized request cadence.  The fixed synchronizer delay
    // does not change the 16-fast-clock distance between successive requests.
    reg [4:0] b_phase_age = 5'h1f;
    wire b_stream_active = (b_phase_age < 5'd24);
    wire b_refresh_slot_safe = !b_stream_active || (b_phase_age <= 5'd6);

    always @(posedge clk) begin
        if (init || !sdram_ready_r || mode != MODE_NORMAL) begin
            b_phase_age <= 5'h1f;
        end else if (b_req_event) begin
            b_phase_age <= 5'd0;
        end else if (b_phase_age != 5'h1f) begin
            b_phase_age <= b_phase_age + 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // Port-A 4-way cache.
    //-------------------------------------------------------------------------
    reg [20:2]     tag_a  [0:WAYS-1];
    reg [31:0]     data_a [0:WAYS-1];
    reg [WAYS-1:0] valid_a = '0;
    reg [2:0]      plru = 3'b000;
    reg [1:0]      ch0_way = 2'd0;
    reg            ch0_epoch = 1'b0;

    wire [WAYS-1:0] a_src_way_ne;
    wire [WAYS-1:0] a_src_way_hit;
    genvar gi;
    generate
        for (gi = 0; gi < WAYS; gi = gi + 1) begin : g_cmp
            assign a_src_way_ne[gi]  = (tag_a[gi] != a_req_addr_28[20:2]);
            assign a_src_way_hit[gi] = valid_a[gi] & ~a_src_way_ne[gi];
        end
    endgenerate

    wire       a_src_hit = |a_src_way_hit;
    wire       a_src_fetch_req = a_req_write_28 | ~a_src_hit;
    wire [1:0] a_src_hit_way = a_src_way_hit[1] ? 2'd1 :
                                a_src_way_hit[2] ? 2'd2 :
                                a_src_way_hit[3] ? 2'd3 : 2'd0;

    wire [1:0] plru_victim = plru[0] ? (plru[2] ? 2'd3 : 2'd2)
                                      : (plru[1] ? 2'd1 : 2'd0);
    wire [1:0] a_src_victim = ~valid_a[0] ? 2'd0 :
                              ~valid_a[1] ? 2'd1 :
                              ~valid_a[2] ? 2'd2 :
                              ~valid_a[3] ? 2'd3 : plru_victim;

    function [2:0] plru_touch(input [2:0] cur, input [1:0] w);
        reg [2:0] n;
        begin
            n = cur;
            case (w)
                2'd0: begin n[0] = 1'b1; n[1] = 1'b1; end
                2'd1: begin n[0] = 1'b1; n[1] = 1'b0; end
                2'd2: begin n[0] = 1'b0; n[2] = 1'b1; end
                2'd3: begin n[0] = 1'b0; n[2] = 1'b0; end
            endcase
            plru_touch = n;
        end
    endfunction

    wire [7:0] a_src_way0_byte =
        (a_req_addr_28[1:0] == 2'd0) ? data_a[0][7:0]   :
        (a_req_addr_28[1:0] == 2'd1) ? data_a[0][15:8]  :
        (a_req_addr_28[1:0] == 2'd2) ? data_a[0][23:16] :
                                       data_a[0][31:24];

    wire [7:0] a_src_way1_byte =
        (a_req_addr_28[1:0] == 2'd0) ? data_a[1][7:0]   :
        (a_req_addr_28[1:0] == 2'd1) ? data_a[1][15:8]  :
        (a_req_addr_28[1:0] == 2'd2) ? data_a[1][23:16] :
                                       data_a[1][31:24];

    wire [7:0] a_src_way2_byte =
        (a_req_addr_28[1:0] == 2'd0) ? data_a[2][7:0]   :
        (a_req_addr_28[1:0] == 2'd1) ? data_a[2][15:8]  :
        (a_req_addr_28[1:0] == 2'd2) ? data_a[2][23:16] :
                                       data_a[2][31:24];

    wire [7:0] a_src_way3_byte =
        (a_req_addr_28[1:0] == 2'd0) ? data_a[3][7:0]   :
        (a_req_addr_28[1:0] == 2'd1) ? data_a[3][15:8]  :
        (a_req_addr_28[1:0] == 2'd2) ? data_a[3][23:16] :
                                       data_a[3][31:24];

    wire [7:0] a_src_hit_byte =
          ({8{a_src_way_hit[0]}} & a_src_way0_byte)
        | ({8{a_src_way_hit[1]}} & a_src_way1_byte)
        | ({8{a_src_way_hit[2]}} & a_src_way2_byte)
        | ({8{a_src_way_hit[3]}} & a_src_way3_byte);

    reg [20:0] req_addr_r = 21'd0;
    reg [7:0]  req_wdata_r = 8'h00;
    reg        req_write_r = 1'b0;
    reg        req_epoch_r = 1'b0;
    reg        a_hit_r = 1'b0;
    reg        fetch_req_r = 1'b0;
    reg [1:0]  hit_way_r = 2'd0;
    reg [1:0]  victim_r = 2'd0;
    reg        a_fetch_pending = 1'b0;

    //-------------------------------------------------------------------------
    // Port-B single-line cache.  All lookup inputs are backend-local.
    //-------------------------------------------------------------------------
    reg [20:2] last_b = '1;
    reg [31:0] last_b_data;
    reg        last_b_valid = 1'b0;
    reg [20:2] b_fill_line = '0;
    reg [1:0]  b_fill_offset = 2'b00;

    wire b_match_r = last_b_valid && (last_b == b_req_addr_r[20:2]);
    wire [7:0] b_hit_byte =
        (b_req_addr_r[1:0] == 2'd0) ? last_b_data[7:0]   :
        (b_req_addr_r[1:0] == 2'd1) ? last_b_data[15:8]  :
        (b_req_addr_r[1:0] == 2'd2) ? last_b_data[23:16] :
                                      last_b_data[31:24];

    //-------------------------------------------------------------------------
    // Refresh scheduler and ready.
    //-------------------------------------------------------------------------
    reg [11:0] rfsh_cnt = 12'd0;
    reg        refresh_pending = 1'b0;
    reg        refresh_busy = 1'b0;
    reg [3:0]  refresh_recovery = 4'd0;

    wire refresh_recovery_active = (refresh_recovery != 4'd0);
    wire refresh_soft_due = refresh_pending || (rfsh_cnt >= (REFRESH_SOFT_CYCLES - 1));
    wire refresh_hard_due = (rfsh_cnt >= (REFRESH_HARD_CYCLES - 1));
    wire refresh_source_idle = !a_source_cycle_active_112 && !a_fetch_pending && !ch0_busy;

    reg init_refresh = 1'b0;

    //-------------------------------------------------------------------------
    // Port-A response mailbox, tagged with the source reset epoch.
    //-------------------------------------------------------------------------
    reg [7:0] resp_pub_data = 8'hff;
    reg       resp_pub_epoch = 1'b0;
    reg       resp_pub_toggle = 1'b0;

    //-------------------------------------------------------------------------
    // Physical SDRAM initialization cadence.
    //-------------------------------------------------------------------------
    reg [14:0] rst_cnt = 15'd0;
    reg rst_done = 1'b0;
    reg rst_done_p1 = 1'b0;
    reg cfg_now = 1'b0;

    always @(posedge clk) begin
        rst_done_p1 <= rst_done;
        cfg_now     <= rst_done & ~rst_done_p1;
        if (rst_cnt != FREQ / 1000 * 200 / 1000) begin
            rst_cnt  <= rst_cnt + 1'b1;
            rst_done <= 1'b0;
        end else begin
            rst_done <= 1'b1;
        end
        if (init) begin
            rst_cnt  <= 15'd0;
            rst_done <= 1'b0;
        end
    end

    always @(posedge clk) begin : init_sequence
        reg init_old = 1'b0;
        init_old <= init;

        if (init_old & ~init) begin
            reset         <= 5'h1f;
            init_refresh  <= 1'b0;
            sdram_ready_r <= 1'b0;
        end else if (state == STATE_LAST && rst_done) begin
            if (reset != 0) begin
                reset <= reset - 5'd1;
                if (reset == 14) begin
                    mode         <= MODE_PRE;
                    init_refresh <= 1'b0;
                end else if (reset == 13 || reset == 12) begin
                    mode         <= MODE_RESET;
                    init_refresh <= 1'b1;
                end else if (reset == 3) begin
                    mode         <= MODE_LDM;
                    init_refresh <= 1'b0;
                end else begin
                    mode         <= MODE_RESET;
                    init_refresh <= 1'b0;
                end
            end else begin
                mode          <= MODE_NORMAL;
                init_refresh  <= 1'b0;
                sdram_ready_r <= 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Diagnostics.
    //-------------------------------------------------------------------------
    reg dbg_b_overrun_112 = 1'b0;
    reg dbg_b_pending_long_112 = 1'b0;
    reg dbg_refresh_hard_blocked_112 = 1'b0;
    reg [4:0] b_pending_age_112 = 5'd0;
    reg [6:0] refresh_hard_age_112 = 7'd0;

    reg dbg_a_req_same_response_28 = 1'b0;
    reg dbg_a_req_while_busy_28 = 1'b0;
    reg dbg_resp_without_outstanding_28 = 1'b0;

    always @(posedge clk) begin
        if (init || !sdram_ready_r || mode != MODE_NORMAL) begin
            dbg_b_overrun_112            <= 1'b0;
            dbg_b_pending_long_112       <= 1'b0;
            dbg_refresh_hard_blocked_112 <= 1'b0;
            b_pending_age_112            <= 5'd0;
            refresh_hard_age_112         <= 7'd0;
        end else begin
            if (b_req_event && (b_req_pending || ch1_busy))
                dbg_b_overrun_112 <= 1'b1;

            if (b_req_pending) begin
                if (b_pending_age_112 != 5'h1f)
                    b_pending_age_112 <= b_pending_age_112 + 1'b1;
                if (b_pending_age_112 >= 5'd15)
                    dbg_b_pending_long_112 <= 1'b1;
            end else begin
                b_pending_age_112 <= 5'd0;
            end

            if (refresh_hard_due && !refresh_busy) begin
                if (refresh_hard_age_112 != 7'h7f)
                    refresh_hard_age_112 <= refresh_hard_age_112 + 1'b1;
                if (refresh_hard_age_112 >= 7'd63)
                    dbg_refresh_hard_blocked_112 <= 1'b1;
            end else begin
                refresh_hard_age_112 <= 7'd0;
            end
        end
    end

    assign DEBUG_FLAGS = {
        dbg_refresh_hard_blocked_112,
        dbg_b_pending_long_112,
        dbg_b_overrun_112,
        dbg_resp_without_outstanding_28,
        dbg_a_req_while_busy_28,
        dbg_a_req_same_response_28
    };

    //-------------------------------------------------------------------------
    // clk_ram frontend.
    //-------------------------------------------------------------------------
    reg ram_a_wait_28 = 1'b1;
    reg resp_seen_28 = 1'b0;
    reg a_outstanding_28 = 1'b0;
    wire a_response_available_28 = (resp_pub_toggle != resp_seen_28);

    (* ASYNC_REG = "TRUE" *) reg sdram_ready_meta_28 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg sdram_ready_sync_28 = 1'b0;

    assign sdram_ready = sdram_ready_sync_28;
    assign RAM_A_WAIT = ram_a_wait_28 | RAM_A_REQ | port_reset | init;

    always @(posedge clk_ram) begin
        if (init) begin
            sdram_ready_meta_28 <= 1'b0;
            sdram_ready_sync_28 <= 1'b0;
            RAM_A_DO            <= 8'hff;
            ram_a_wait_28       <= 1'b1;
            resp_seen_28        <= 1'b0;
            a_outstanding_28    <= 1'b0;
            a_req_addr_28       <= 21'd0;
            a_req_wdata_28      <= 8'h00;
            a_req_write_28      <= 1'b0;
            a_req_epoch_28      <= 1'b0;
            a_req_toggle_28     <= 1'b0;
            a_epoch_28          <= 1'b0;
            port_reset_d_28     <= 1'b1;
        end else begin
            sdram_ready_meta_28 <= sdram_ready_r;
            sdram_ready_sync_28 <= sdram_ready_meta_28;
            port_reset_d_28     <= port_reset;

            if (port_reset) begin
                if (!port_reset_d_28)
                    a_epoch_28 <= ~a_epoch_28;
                RAM_A_DO         <= 8'hff;
                ram_a_wait_28    <= 1'b1;
                resp_seen_28     <= resp_pub_toggle;
                a_outstanding_28 <= 1'b0;
            end else if (!sdram_ready_sync_28) begin
                ram_a_wait_28    <= 1'b1;
                resp_seen_28     <= resp_pub_toggle;
                a_outstanding_28 <= 1'b0;
            end else begin
                // Consume a response toggle independently of request capture.
                // This is intentionally not an else-if condition for the
                // request registers below: an orphan/stale response may be
                // acknowledged on the same clk_ram edge as a new request.
                if (a_response_available_28)
                    resp_seen_28 <= resp_pub_toggle;

                // Accept a request only when there is no active transaction.
                // The enable of these request registers depends only on the
                // source-domain request and outstanding state, never on the
                // backend response toggle.
                if (RAM_A_REQ && !a_outstanding_28) begin
                    a_req_addr_28    <= RAM_A_ADDR;
                    a_req_wdata_28   <= RAM_A_DI;
                    a_req_write_28   <= RAM_A_RD_n;
                    a_req_epoch_28   <= a_epoch_28;
                    a_req_toggle_28  <= ~a_req_toggle_28;
                    ram_a_wait_28    <= 1'b1;
                    a_outstanding_28 <= 1'b1;
                end else if (a_response_available_28) begin
                    // Only a response from the current epoch may complete a
                    // genuinely outstanding transaction.
                    if (a_outstanding_28 && resp_pub_epoch == a_epoch_28) begin
                        RAM_A_DO         <= resp_pub_data;
                        ram_a_wait_28    <= 1'b0;
                        a_outstanding_28 <= 1'b0;
                    end else if (!a_outstanding_28) begin
                        // Stale/orphan response: mark it seen and leave the
                        // frontend idle.  No request payload is discarded.
                        ram_a_wait_28 <= 1'b0;
                    end
                end else if (!a_outstanding_28) begin
                    ram_a_wait_28 <= 1'b0;
                end
            end
        end
    end

    always @(posedge clk_ram) begin
        if (init) begin
            dbg_a_req_same_response_28      <= 1'b0;
            dbg_a_req_while_busy_28         <= 1'b0;
            dbg_resp_without_outstanding_28 <= 1'b0;
        end else if (sdram_ready_sync_28 && !port_reset) begin
            if (RAM_A_REQ && a_outstanding_28 && a_response_available_28)
                dbg_a_req_same_response_28 <= 1'b1;
            if (RAM_A_REQ && a_outstanding_28 && !a_response_available_28)
                dbg_a_req_while_busy_28 <= 1'b1;
            if (a_response_available_28 && !a_outstanding_28)
                dbg_resp_without_outstanding_28 <= 1'b1;
        end
    end

    //-------------------------------------------------------------------------
    // Access manager.
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (init) begin
            valid_a               <= '0;
            plru                  <= 3'b000;
            req_addr_r            <= 21'd0;
            req_wdata_r           <= 8'h00;
            req_write_r           <= 1'b0;
            req_epoch_r           <= 1'b0;
            a_hit_r               <= 1'b0;
            fetch_req_r           <= 1'b0;
            hit_way_r             <= 2'd0;
            victim_r              <= 2'd0;
            a_fetch_pending       <= 1'b0;
            a_req_toggle_seen_112 <= 1'b0;
            a_epoch_seen_112      <= 1'b0;
            b_req_toggle_seen_112 <= 1'b0;
            b_req_pending         <= 1'b0;
            ch0_busy              <= 1'b0;
            ch1_busy              <= 1'b0;
            ch0_epoch             <= 1'b0;
            RAM_B_DO              <= 8'hff;
            last_b_valid          <= 1'b0;
            b_fill_line           <= '0;
            b_fill_offset         <= 2'b00;
            resp_pub_data         <= 8'hff;
            resp_pub_epoch        <= 1'b0;
            resp_pub_toggle       <= 1'b0;
            rfsh_cnt              <= 12'd0;
            refresh_pending       <= 1'b0;
            refresh_busy          <= 1'b0;
            refresh_recovery      <= 4'd0;
            ram_req               <= 1'b0;
            we                    <= 1'b0;
        end else begin
            //-------------------------------------------------------------
            // Refresh timer.
            //-------------------------------------------------------------
            if (!sdram_ready_r || mode != MODE_NORMAL) begin
                rfsh_cnt         <= 12'd0;
                refresh_pending  <= 1'b0;
                refresh_busy     <= 1'b0;
                refresh_recovery <= 4'd0;
            end else begin
                if (refresh_recovery != 4'd0)
                    refresh_recovery <= refresh_recovery - 1'b1;
                if (!refresh_busy) begin
                    if (rfsh_cnt < (REFRESH_HARD_CYCLES - 1))
                        rfsh_cnt <= rfsh_cnt + 1'b1;
                    if (rfsh_cnt >= (REFRESH_SOFT_CYCLES - 1))
                        refresh_pending <= 1'b1;
                end
            end

            //-------------------------------------------------------------
            // Port-A epoch cancellation and request acceptance.
            //-------------------------------------------------------------
            if (a_epoch_event) begin
                a_epoch_seen_112 <= a_epoch_sync2;
                a_fetch_pending  <= 1'b0;

                // Discard only an old-epoch packet.  A very early new-epoch
                // request remains pending and is consumed on a later clk edge.
                if (a_req_event && !a_req_epoch_matches)
                    a_req_toggle_seen_112 <= a_req_toggle_sync2;
            end else if (a_req_event) begin
                if (!a_req_epoch_matches) begin
                    // A stale pre-reset request crossed after the epoch.
                    a_req_toggle_seen_112 <= a_req_toggle_sync2;
                end else begin
                    a_req_toggle_seen_112 <= a_req_toggle_sync2;
                    if (!a_src_fetch_req) begin
                        resp_pub_data   <= a_src_hit_byte;
                        resp_pub_epoch  <= a_req_epoch_28;
                        resp_pub_toggle <= ~resp_pub_toggle;
                        plru            <= plru_touch(plru, a_src_hit_way);
                    end else begin
                        req_addr_r      <= a_req_addr_28;
                        req_wdata_r     <= a_req_wdata_28;
                        req_write_r     <= a_req_write_28;
                        req_epoch_r     <= a_req_epoch_28;
                        a_hit_r         <= a_src_hit;
                        fetch_req_r     <= a_src_fetch_req;
                        hit_way_r       <= a_src_hit_way;
                        victim_r        <= a_src_victim;
                        a_fetch_pending <= 1'b1;
                    end
                end
            end

            //-------------------------------------------------------------
            // Port-B cache hit from an already captured request.
            //-------------------------------------------------------------
            if (!sdram_ready_r || mode != MODE_NORMAL) begin
                b_req_toggle_seen_112 <= b_req_toggle_sync2;
                b_req_pending         <= 1'b0;
            end else begin
                if (b_req_event)
                    b_req_toggle_seen_112 <= b_req_toggle_sync2;

                // A hit is returned on the same fast edge on which the
                // synchronized event is consumed.  A miss becomes pending
                // unless the IDLE arbiter below starts it immediately.
                if (b_have_request && b_match_r) begin
                    RAM_B_DO      <= b_hit_byte;
                    b_req_pending <= 1'b0;
                end else if (b_req_event) begin
                    b_req_pending <= 1'b1;
                end
            end

            //-------------------------------------------------------------
            // IDLE arbitration.
            //-------------------------------------------------------------
            if (state == STATE_IDLE && mode == MODE_NORMAL) begin
                ram_req  <= 1'b0;
                we       <= 1'b0;
                ch0_busy <= 1'b0;
                ch1_busy <= 1'b0;

                if (!refresh_recovery_active) begin
                    if (b_have_request && !b_match_r) begin
                        b_req_pending <= 1'b0;
                        a             <= b_req_addr_r;
                        ram_req       <= 1'b1;
                        b_fill_line   <= b_req_addr_r[20:2];
                        b_fill_offset <= b_req_addr_r[1:0];
                        ch1_busy      <= 1'b1;
                        state         <= STATE_START;
                    end else if (refresh_hard_due && b_refresh_slot_safe && !b_req_event) begin
                        // A hard-due refresh is no longer allowed to lose to
                        // Port A.  Port-A payload is already held locally and
                        // the requester remains stalled by RAM_A_WAIT.
                        ram_req         <= 1'b0;
                        refresh_busy    <= 1'b1;
                        refresh_pending <= 1'b1;
                        state           <= STATE_START;
                    end else if (a_fetch_pending && a_source_cycle_active_112) begin
                        a_fetch_pending <= 1'b0;
                        we              <= req_write_r;
                        a               <= req_addr_r;
                        data            <= req_wdata_r;
                        ram_req         <= fetch_req_r;
                        ch0_busy        <= 1'b1;
                        ch0_epoch       <= req_epoch_r;

                        if (req_write_r) begin
                            if (a_hit_r)
                                valid_a[hit_way_r] <= 1'b0;
                            ch0_way <= hit_way_r;
                        end else begin
                            ch0_way <= a_hit_r ? hit_way_r : victim_r;
                        end
                        state <= STATE_START;
                    end else if (a_fetch_pending) begin
                        a_fetch_pending <= 1'b0;
                        we              <= req_write_r;
                        a               <= req_addr_r;
                        data            <= req_wdata_r;
                        ram_req         <= fetch_req_r;
                        ch0_busy        <= 1'b1;
                        ch0_epoch       <= req_epoch_r;

                        if (req_write_r) begin
                            if (a_hit_r)
                                valid_a[hit_way_r] <= 1'b0;
                            ch0_way <= hit_way_r;
                        end else begin
                            ch0_way <= a_hit_r ? hit_way_r : victim_r;
                        end
                        state <= STATE_START;
                    end else if (refresh_soft_due && refresh_source_idle && b_refresh_slot_safe && !b_req_event && !b_req_pending) begin
                        ram_req         <= 1'b0;
                        refresh_busy    <= 1'b1;
                        refresh_pending <= 1'b1;
                        state           <= STATE_START;
                    end
                end
            end

            //-------------------------------------------------------------
            // Transaction completion.
            //-------------------------------------------------------------
            if (state == STATE_READY) begin
                if (refresh_busy) begin
                    refresh_busy     <= 1'b0;
                    refresh_pending  <= 1'b0;
                    rfsh_cnt         <= 12'd0;
                    refresh_recovery <= REFRESH_RECOVERY_CYCLES;
                end

                if (ch0_busy) begin
                    ch0_busy <= 1'b0;

                    if (ram_req) begin
                        if (we) begin
                            if (ch0_epoch == a_epoch_sync2) begin
                                resp_pub_data   <= data;
                                resp_pub_epoch  <= ch0_epoch;
                                resp_pub_toggle <= ~resp_pub_toggle;
                            end
                        end else begin
                            tag_a[ch0_way]        <= a[20:2];
                            data_a[ch0_way]       <= data_reg;
                            valid_a[ch0_way]      <= 1'b1;
                            plru                  <= plru_touch(plru, ch0_way);
                            if (ch0_epoch == a_epoch_sync2) begin
                                resp_pub_data   <= data_reg[(a[1:0] * 8) +: 8];
                                resp_pub_epoch  <= ch0_epoch;
                                resp_pub_toggle <= ~resp_pub_toggle;
                            end
                        end
                    end else begin
                        plru <= plru_touch(plru, ch0_way);
                        if (ch0_epoch == a_epoch_sync2) begin
                            resp_pub_data   <= data_a[ch0_way][(a[1:0] * 8) +: 8];
                            resp_pub_epoch  <= ch0_epoch;
                            resp_pub_toggle <= ~resp_pub_toggle;
                        end
                    end
                end

                if (ch1_busy) begin
                    ch1_busy     <= 1'b0;
                    RAM_B_DO     <= data_reg[(b_fill_offset * 8) +: 8];
                    last_b       <= b_fill_line;
                    last_b_data  <= data_reg;
                    last_b_valid <= 1'b1;
                end
            end

            // Original state counter.
            if (mode != MODE_NORMAL || state != STATE_IDLE || reset) begin
                state <= state + 4'd1;
                if (state == STATE_LAST)
                    state <= STATE_IDLE;
            end
        end
    end

    //-------------------------------------------------------------------------
    // SDRAM command generation
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (state == STATE_START)
            O_sdram_ba <= 2'b00;

        dq_oen <= 1'b1;

        casex ({ram_req, we, mode, state})
            {2'b1x, MODE_NORMAL, STATE_START}: {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_Active;
            {2'b11, MODE_NORMAL, STATE_CONT}: begin
                {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_Write;
                dq_out <= {data, data, data, data};
                dq_oen <= 1'b0;
            end
            {2'b10, MODE_NORMAL, STATE_CONT}: {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_Read;
            {2'b0x, MODE_NORMAL, STATE_START}: {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_AutoRefresh;
            {2'bxx, MODE_LDM, STATE_START}: {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_LoadMode;
            {2'bxx, MODE_PRE, STATE_START}: {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= CMD_Precharge;
            default: {O_sdram_ras_n, O_sdram_cas_n, O_sdram_wen_n} <= (init_refresh && state == STATE_START) ? CMD_AutoRefresh : CMD_NOP;
        endcase

        casex ({ram_req, mode, state})
            {1'b1, MODE_NORMAL, STATE_START}: O_sdram_addr <= a[20:10];
            {1'b1, MODE_NORMAL, STATE_CONT}: begin
                O_sdram_addr[10]  <= 1'b1;
                O_sdram_addr[9:0] <= {1'b0, a[9:2]};
                O_sdram_dqm <= a[1:0] == 2'd0 ? 4'b1110 :
                               a[1:0] == 2'd1 ? 4'b1101 :
                               a[1:0] == 2'd2 ? 4'b1011 : 4'b0111;
            end
            {1'bx, MODE_LDM, STATE_START}: O_sdram_addr <= MODE;
            {1'bx, MODE_PRE, STATE_START}: begin
                O_sdram_addr     <= 11'd0;
                O_sdram_addr[10] <= 1'b1;
            end
            default: O_sdram_addr <= 11'd0;
        endcase

        if (ram_req && !we && state == STATE_CONT)
            O_sdram_dqm <= 4'b0000;
    end

endmodule
