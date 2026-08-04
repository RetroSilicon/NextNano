//
// ddram.v
// Copyright (c) 2021 Sorgelig
//
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// ------------------------------------------
//

// 16-bit version

module ddram
(
	input         DDRAM_CLK,

	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	input         reset,

	input  [27:1] wraddr,
	input  [15:0] din,
	input         we_req,
	output reg    we_ack,

	input  [27:0] rdaddr,
	output  [7:0] dout,
	input         rom_req,
	output reg    rom_ack
);

assign DDRAM_BURSTCNT = ram_burst;
assign DDRAM_BE       = ram_be | {8{ram_read}};
assign DDRAM_ADDR     = {4'b0011, ram_address}; // RAM at 0x30000000
assign DDRAM_RD       = ram_read;
assign DDRAM_DIN      = ram_data;
assign DDRAM_WE       = ram_write;

assign dout  =  ram_q[{rdaddr[2:0],  3'b000} +:8];

reg  [7:0] ram_burst;
reg [63:0] ram_q, next_q;
reg [63:0] ram_data;
reg [27:3] ram_address, cache_addr;
reg        ram_read = 0;
reg        ram_write = 0;
reg  [7:0] ram_be = 0;

always @(posedge DDRAM_CLK) begin
	reg [1:0]  state  = 0;

	if(rom_req != rom_ack && state != 1 && cache_addr == rdaddr[27:3]) rom_ack <= rom_req;

	if(!DDRAM_BUSY) begin
		ram_write <= 0;
		ram_read  <= 0;

		case(state)
			0: if(we_ack != we_req) begin
					ram_be        <= 8'd3<<{wraddr[2:1],1'b0};
					ram_data		  <= {4{din}};
					ram_address   <= wraddr[27:3];
					ram_write 	  <= 1;
					ram_burst     <= 1;
					cache_addr    <= '1;
					cache_addr[3] <= 0;
					we_ack        <= we_req;
				end
				else if(rom_req != rom_ack) begin
					if((cache_addr+1'd1) == rdaddr[27:3]) begin
						rom_ack     <= rom_req;
						ram_q       <= next_q;
						cache_addr  <= rdaddr[27:3];
						ram_address <= rdaddr[27:3]+1'd1;
						ram_read    <= 1;
						ram_burst   <= 1;
						state       <= 2;
					end
					else if(cache_addr != rdaddr[27:3]) begin
						ram_address <= rdaddr[27:3];
						cache_addr  <= rdaddr[27:3];
						ram_read    <= 1;
						ram_burst   <= 2;
						state       <= 1;
					end 
				end

			1: if(DDRAM_DOUT_READY) begin
					ram_q   <= DDRAM_DOUT;
					rom_ack <= rom_req;
					state   <= 2;
				end

			2: if(DDRAM_DOUT_READY) begin
					next_q  <= DDRAM_DOUT;
					state   <= 0;
				end
		endcase
	end
	
	if(reset) begin
		cache_addr    <= '1;
		cache_addr[3] <= 0;
	end
end

endmodule
