//============================================================================
//
//  SDRAM controller
//  Copyright (C) 2021 Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module sdram
(
	input             clk,
	input             init,

	output reg [12:0] SDRAM_A,
	inout  reg [15:0] SDRAM_DQ,
	output reg  [1:0] SDRAM_BA,
	output reg        SDRAM_DQML,
	output reg        SDRAM_DQMH,
	output reg        SDRAM_nWE,
	output reg        SDRAM_nCAS,
	output reg        SDRAM_nRAS,
	output            SDRAM_nCS,
	output            SDRAM_CKE,
	output            SDRAM_CLK,

	input      [20:0] RAM_A_ADDR,
	input             RAM_A_REQ,
	input             RAM_A_RD_n,
	input       [7:0] RAM_A_DI,
	output reg  [7:0] RAM_A_DO,
	output reg        RAM_A_WAIT,

	input      [20:0] RAM_B_ADDR,
	input             RAM_B_REQ,
	output reg  [7:0] RAM_B_DO
);

assign SDRAM_nCS = 0;
assign SDRAM_CKE = 1;
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11];

localparam RASCAS_DELAY   = 3'd2; // tRCD=20ns -> 2 cycles@85MHz
localparam BURST_LENGTH   = 3'd1; // 0=1, 1=2, 2=4, 3=8, 7=full page
localparam ACCESS_TYPE    = 1'd0; // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2; // 2/3 allowed
localparam OP_MODE        = 2'd0; // only 0 (standard operation) allowed
localparam NO_WRITE_BURST = 1'd1; // 0=write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

localparam STATE_IDLE  = 3'd0;             // state to check the requests
localparam STATE_START = STATE_IDLE+1'd1;  // state in which a new command is started
localparam STATE_CONT  = STATE_START+RASCAS_DELAY;
localparam STATE_READY = STATE_CONT+CAS_LATENCY+2'd2;
localparam STATE_LAST  = STATE_READY;      // last state in cycle

reg  [2:0] state;
reg [22:0] a;
reg  [1:0] bank;
reg [15:0] data;
reg        we;
reg        ram_req=0;
reg [21:2] last_a[2] = '{'1,'1};
reg  [8:0] rfsh_cnt;

wire       fetch_req = (RAM_A_RD_n || last_a[0] != {1'b0,RAM_A_ADDR[20:2]});

// access manager
always @(posedge clk) begin
	reg old_ref;
	reg        old_b_req;
	reg        old_a_req;
	reg [31:0] last_data[2];
	reg [15:0] data_reg;
	reg        ch0_busy;
	reg        ch1_busy;
	reg  [2:0] store;

	data_reg <= SDRAM_DQ;

	if(~&rfsh_cnt) rfsh_cnt <= rfsh_cnt + 1'd1;

	old_a_req <= RAM_A_REQ;
	if(~old_a_req & RAM_A_REQ) begin
		if(rfsh_cnt[8] || fetch_req) RAM_A_WAIT <= 1;
		else RAM_A_DO <= last_data[0][(RAM_A_ADDR[1:0]*8) +:8];
	end

	if((old_b_req ^ RAM_B_REQ) && (last_a[1] == {1'b0,RAM_B_ADDR[20:2]})) begin
		old_b_req <= RAM_B_REQ;
		RAM_B_DO <= last_data[1][(RAM_B_ADDR[1:0]*8) +:8];
	end
	
	if(state == STATE_IDLE && mode == MODE_NORMAL) begin
		ram_req <= 0;
		we <= 0;
		ch0_busy <= 0;
		ch1_busy <= 0;

		if((old_b_req ^ RAM_B_REQ) && (last_a[1] != {1'b0,RAM_B_ADDR[20:2]})) begin
			old_b_req <= RAM_B_REQ;
			{bank,a} <= RAM_B_ADDR;
			ram_req <= 1;
			last_a[1] <= RAM_B_ADDR[20:2];
			ch1_busy <= 1;
			state <= STATE_START;
		end
		else if((~old_a_req && RAM_A_REQ && (fetch_req || rfsh_cnt[8])) || RAM_A_WAIT) begin
			we <= RAM_A_RD_n;
			{bank,a} <= RAM_A_ADDR;
			data <= {RAM_A_DI,RAM_A_DI};
			ram_req <= fetch_req;
			last_a[0] <= RAM_A_RD_n ? '1 : RAM_A_ADDR[20:2];
			ch0_busy <= 1;
			state <= STATE_START;
		end
		else if(&rfsh_cnt) begin
			rfsh_cnt <= 0;
			state <= STATE_START;
		end
	end

	if(store) begin
		last_data[store[1]][(store[0] ? 16 : 0) +:16] <= data_reg;
		store <= 0;
	end

	if(state == STATE_READY) begin
		if(~ram_req) rfsh_cnt <= 0;
		if(ch0_busy) begin
			ch0_busy <= 0;
			RAM_A_WAIT <= 0;
			if(ram_req) begin
				if(we) RAM_A_DO <= data[7:0];
				else begin
					RAM_A_DO <= a[0] ? data_reg[15:8] : data_reg[7:0];
					last_data[0][(a[1] ? 16 : 0) +:16] <= data_reg;
					store <= {2'b10,~a[1]};
				end
			end
			else RAM_A_DO <= last_data[0][(a[1:0]*8) +:8];
		end
		if(ch1_busy) begin
			ch1_busy <= 0;
			RAM_B_DO <= a[0] ? data_reg[15:8] : data_reg[7:0];
			last_data[1][(a[1] ? 16 : 0) +:16] <= data_reg;
			store <= {2'b11,~a[1]};
		end
	end

	if(mode != MODE_NORMAL || state != STATE_IDLE || reset) begin
		state <= state + 1'd1;
		if(state == STATE_LAST) state <= STATE_IDLE;
	end
end

localparam MODE_NORMAL = 2'b00;
localparam MODE_RESET  = 2'b01;
localparam MODE_LDM    = 2'b10;
localparam MODE_PRE    = 2'b11;

initial reset = 5'h1f;

// initialization 
reg [1:0] mode;
reg [4:0] reset=5'h1f;
always @(posedge clk) begin
	reg init_old=0;
	init_old <= init;

	if(init_old & ~init) reset <= 5'h1f;
	else if(state == STATE_LAST) begin
		if(reset != 0) begin
			reset <= reset - 5'd1;
			if(reset == 14)     mode <= MODE_PRE;
			else if(reset == 3) mode <= MODE_LDM;
			else                mode <= MODE_RESET;
		end
		else mode <= MODE_NORMAL;
	end
end

localparam CMD_NOP             = 3'b111;
localparam CMD_ACTIVE          = 3'b011;
localparam CMD_READ            = 3'b101;
localparam CMD_WRITE           = 3'b100;
localparam CMD_BURST_TERMINATE = 3'b110;
localparam CMD_PRECHARGE       = 3'b010;
localparam CMD_AUTO_REFRESH    = 3'b001;
localparam CMD_LOAD_MODE       = 3'b000;

// SDRAM state machines
always @(posedge clk) begin
	if(state == STATE_START) SDRAM_BA <= (mode == MODE_NORMAL) ? bank : 2'b00;

	SDRAM_DQ <= 'Z;
	casex({ram_req,we,mode,state})
		{2'b1X, MODE_NORMAL, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACTIVE;
		{2'b11, MODE_NORMAL, STATE_CONT }: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE, SDRAM_DQ} <= {CMD_WRITE, data};
		{2'b10, MODE_NORMAL, STATE_CONT }: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
		{2'b0X, MODE_NORMAL, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;

		// init
		{2'bXX,    MODE_LDM, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_LOAD_MODE;
		{2'bXX,    MODE_PRE, STATE_START}: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRECHARGE;

		                          default: {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
	endcase

	casex({ram_req,mode,state})
		{1'b1,  MODE_NORMAL, STATE_START}: SDRAM_A <= a[22:10];
		{1'b1,  MODE_NORMAL, STATE_CONT }: SDRAM_A <= {we & ~a[0], we & a[0], 2'b10, a[9:1]};

		// init
		{1'bX,     MODE_LDM, STATE_START}: SDRAM_A <= MODE;
		{1'bX,     MODE_PRE, STATE_START}: SDRAM_A <= 13'b0010000000000;

		                          default: SDRAM_A <= 13'b0000000000000;
	endcase
end


altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

endmodule
