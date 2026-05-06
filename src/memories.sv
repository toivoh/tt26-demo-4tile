/*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`include "common_pl.vh"


/*
module mux4 #( parameter LOG2_BITS_IN=5 ) (
		input wire [1:0] addr,
		input wire [2**LOG2_BITS_IN-1:0] data_in,
		output wire [2**(LOG2_BITS_IN-2)-1:0] data_out
	);
	genvar i;
	generate
		for (i = 0; i < 2**(LOG2_BITS_IN-2); i++) begin
			wire [3:0] data_in_i = data_in[4*i+3 -: 4];
			wire data_out_i;
			//assign data_out[i] = data_in_i[addr];
			sky130_fd_sc_hd__mux4_1 mux4_inst(
				.A0(data_in_i[0]), .A1(data_in_i[1]), .A2(data_in_i[2]), .A3(data_in_i[3]),
				.S0(addr[0]), .S1(addr[1]),
				.X(data_out_i)
			);
			assign data_out[i] = data_out_i;

		end
	endgenerate
endmodule

module mem_mux #( parameter ADDR_BITS=5 ) (
		input wire [ADDR_BITS-1:0] addr,
		input wire [2**ADDR_BITS-1:0] data_in,
		output wire data_out
	);

	assign data_out = data_in[addr];

//	wire [2**(ADDR_BITS-2)-1:0] data1;
//	wire [2**(ADDR_BITS-4)-1:0] data2;
//	mux4 #( .LOG2_BITS_IN(ADDR_BITS  ) ) mux4_inst1( .addr(addr[1:0]), .data_in(data_in), .data_out(data1) );
//	mux4 #( .LOG2_BITS_IN(ADDR_BITS-2) ) mux4_inst2( .addr(addr[3:2]), .data_in(data1  ), .data_out(data2) );
//	assign data_out = data2[addr[ADDR_BITS-1:4]];
endmodule
*/


module np_latch_ram #(
		parameter NUM_ADDR=4, DATA_BITS=8, READ_OFFSET=0,
		READ_OFFSET_TRUNC=0, // 0 or 1 supported
		ADDR_BITS = $clog2(NUM_ADDR) // Don't change unless using READ_OFFSET_TRUNC=1
	) (
		input wire clk, reset,

		input wire we,
		input wire [ADDR_BITS-1:0] addr,
		input wire [DATA_BITS-1:0] wdata,
		output wire [DATA_BITS-1:0] rdata
	);


	genvar i;
	genvar j;


`ifdef USE_LATCHES

	// Demux
	// -----
	wire [NUM_ADDR-1:0] data_we;
	wire [NUM_ADDR-1:0] gclk;

	generate
		for (j = 0; j < NUM_ADDR; j++) begin
			assign data_we[j] = (addr == j) && we;

			`ifndef BUFFER_CLOCK_GATE
			sky130_fd_sc_hd__dlclkp_1 clock_gate(   .CLK(clk),  .GATE(data_we[j]), .GCLK(gclk[j]) );
			`else
			wire _gclk;
			sky130_fd_sc_hd__dlclkp_1 clock_gate( .CLK(clk), .GATE(data_we[j]), .GCLK(_gclk) );
			sky130_fd_sc_hd__clkbuf_8 clock_buffer( .A(_gclk), .X(gclk[j]) );
			`endif
		end
	endgenerate

	// Memory array
	// ------------
	wire [DATA_BITS-1:0] data[NUM_ADDR];

	generate
		wire [DATA_BITS-1:0] wdata2;
		for (i = 0; i < DATA_BITS; i++) begin
			sky130_fd_sc_hd__dlxtn_1 n_latch( .GATE_N(clk), .D(wdata[i]), .Q(wdata2[i]));
		end

		for (j = 0; j < NUM_ADDR; j++) begin
			for (i = 0; i < DATA_BITS; i++) begin
				//sky130_fd_sc_hd__dlxtp_1 p_latch(.GATE(gclk[j]), .D(wdata2[i]), .Q(data[(j+NUM_ADDR-READ_OFFSET)%NUM_ADDR][i]));
				sky130_fd_sc_hd__dlxtp_1 p_latch(.GATE(gclk[j]), .D(wdata2[i]), .Q(data[j][i]));
			end
		end
	endgenerate

`else

	(* mem2reg *) reg [DATA_BITS-1:0] data[NUM_ADDR];
	always_ff @(posedge clk) begin
		if (we) data[addr] <= wdata;
	end

`endif

	// Remapping for stack popping
	// ---------------------------

	wire [DATA_BITS-1:0] data_out0[NUM_ADDR];
	for (i = 0; i < NUM_ADDR; i++) assign data_out0[(i+READ_OFFSET)%NUM_ADDR] = data[i];

	// Extra remapping when READ_OFFSET_TRUNC = 1 (identity when it is zero)
	wire [DATA_BITS-1:0] data_out[NUM_ADDR+READ_OFFSET_TRUNC];
	for (i = 0; i < NUM_ADDR; i++) assign data_out[(i+READ_OFFSET_TRUNC)&((1 << ADDR_BITS) - 1)] = data_out0[i];
	if (READ_OFFSET_TRUNC > 0) assign data_out[NUM_ADDR >= 2**ADDR_BITS ? NUM_ADDR : 0] = 'X; // Set the leftover entry to 'X; we will not pop from it

	// Mux
	// ---
	assign rdata = data_out[addr];
	/*
	generate
		for (i = 0; i < DATA_BITS; i++) begin
			wire [NUM_ADDR-1:0] data_in;
			for (j = 0; j < NUM_ADDR; j++) begin
				assign data_in[j] = data[j][i];
			end
			mem_mux #( .ADDR_BITS(ADDR_BITS) ) mux_inst ( .addr(addr), .data_in(data_in), .data_out(rdata[i]) );
			//mux4 #( .LOG2_BITS_IN(ADDR_BITS) ) mux4_inst1( .addr(addr[1:0]), .data_in(data_in), .data_out(rdata[i]) ); // only for ADDR_BITS=2!
		end
	endgenerate
	*/
endmodule : np_latch_ram


`ifdef USE_LATCHES

module np_latch_registers #( parameter NUM_REGS=2, DATA_BITS=8, USE_ALU_REG_PRUNING=0 ) (
		input wire clk, reset,

		input wire [NUM_REGS-1:0] we,
		//input wire [$clog2(NUM_REGS)-1:0] addr,
		input wire [DATA_BITS-1:0] wdata,
		//output wire [DATA_BITS-1:0] rdata
		output wire [NUM_REGS*DATA_BITS-1:0] all_data
	);

	localparam ADDR_BITS = $clog2(NUM_REGS);


	genvar i;
	genvar j;


	// Demux
	// -----
	wire [NUM_REGS-1:0] data_we;
	wire [NUM_REGS-1:0] gclk;

	generate
		for (j = 0; j < NUM_REGS; j++) begin
			//assign data_we[j] = (addr == j) && we;
			assign data_we[j] = we[j];

			`ifndef BUFFER_CLOCK_GATE
			sky130_fd_sc_hd__dlclkp_1 clock_gate(   .CLK(clk),  .GATE(data_we[j]), .GCLK(gclk[j]) );
			`else
			wire _gclk;
			sky130_fd_sc_hd__dlclkp_1 clock_gate( .CLK(clk), .GATE(data_we[j]), .GCLK(_gclk) );
			sky130_fd_sc_hd__clkbuf_8 clock_buffer( .A(_gclk), .X(gclk[j]) );
			`endif
		end
	endgenerate

	// Memory array
	// ------------
	wire [DATA_BITS-1:0] data[NUM_REGS];

	wire [DATA_BITS-1:0] wdata2;
	generate
		for (i = 0; i < DATA_BITS; i++) begin
			sky130_fd_sc_hd__dlxtn_1 n_latch( .GATE_N(clk), .D(wdata[i]), .Q(wdata2[i]));
		end

		for (j = 0; j < NUM_REGS; j++) begin
			for (i = 0; i < DATA_BITS; i++) begin
//			for (i = 0; i < (USE_ALU_REG_PRUNING && (j == `S_OUTPUT_ACC || j == `S_OUTPUT) ? `PROG_ADDR_BITS : DATA_BITS); i++) begin
				sky130_fd_sc_hd__dlxtp_1 p_latch(.GATE(gclk[j]), .D(wdata2[i]), .Q(data[j][i]));

				assign all_data[DATA_BITS*j + i] = data[j][i];
			end
			/*
			for (i = USE_ALU_REG_PRUNING && (j == `S_OUTPUT_ACC || j == `S_OUTPUT) ? `PROG_ADDR_BITS : DATA_BITS; i < DATA_BITS; i++) begin
				assign all_data[DATA_BITS*j + i] = 0; // TODO: 1'bX?
			end
			*/
		end
	endgenerate

/*
	// Mux
	// ---
	//assign rdata = data[addr];
	generate
		for (i = 0; i < DATA_BITS; i++) begin
			wire [NUM_REGS-1:0] data_in;
			for (j = 0; j < NUM_REGS; j++) begin
				assign data_in[j] = data[j][i];
			end
			mem_mux #( .ADDR_BITS(ADDR_BITS) ) mux_inst ( .addr(addr), .data_in(data_in), .data_out(rdata[i]) );
			//mux4 #( .LOG2_BITS_IN(ADDR_BITS) ) mux4_inst1( .addr(addr[1:0]), .data_in(data_in), .data_out(rdata[i]) ); // only for ADDR_BITS=2!
		end
	endgenerate
	*/
endmodule : np_latch_registers

`endif // USE_LATCHES



module p_latch_register #(parameter BITS=8, NEXT_WDATA_EN=0) (
		input wire clk, reset,
		input wire we, next_we, // next_we is used with P-latches, we when falling back to FFs
		input wire [BITS-1:0] reset_wdata, wdata, // reset_wdata must be stable one cyle after reset is released
		input wire [BITS-1:0] next_wdata, // used when not USE_LATCHES, if NEXT_WDATA_EN=1
		output wire [BITS-1:0] rdata
	);
	genvar i;

`ifdef USE_LATCHES
	reg last_reset;
	always_ff @(posedge clk) begin
		last_reset <= reset;
	end

	wire [BITS-1:0] wdata_eff = last_reset ? reset_wdata : wdata;

	wire gclk;
	sky130_fd_sc_hd__dlclkp_1 clock_gate(.CLK(clk), .GATE(next_we || reset), .GCLK(gclk));

	generate
		for (i = 0; i < BITS; i++) begin
			sky130_fd_sc_hd__dlxtp_1 p_latch(.GATE(gclk), .D(wdata_eff[i]), .Q(rdata[i]));
		end
	endgenerate
`else
	reg [BITS-1:0] data;
	always_ff @(posedge clk) begin
		if (reset) begin
			data <= reset_wdata;
		end else begin
			if (we) data <= (NEXT_WDATA_EN ? next_wdata : wdata);
		end
	end
	assign rdata = data;
`endif

endmodule


module bidir_stack #(
		parameter BITS=8, DEPTH=8
	) (
		input wire clk, reset,

		input wire do_push, do_pop,
		input wire [BITS-1:0] push_data,

		output wire [BITS-1:0] top_data
	);

	genvar i;


	wire en = do_push || do_pop;

	(* mem2reg *) reg [BITS-1:0] stack[DEPTH];
	wire [BITS-1:0] stack_push_src[DEPTH];
	wire [BITS-1:0] stack_pop_src[DEPTH];

	generate
		assign stack_push_src[0] = push_data;
		for (i = 1; i < DEPTH; i++) assign stack_push_src[i] = stack[i-1];

		for (i = 0; i < DEPTH-1; i++) assign stack_pop_src[i] = stack[i+1];
		assign stack_pop_src[DEPTH-1] = stack_pop_src[DEPTH-2]; // Doesn't matter since it only affects behavior at stack underflow. This should avoid one mux.

		for (i = 0; i < DEPTH; i++) begin
			wire [BITS-1:0] stack_next0 = do_pop ? stack_pop_src[i] : stack_push_src[i];

			wire [BITS-1:0] stack_next;
			hold_buffer #(.BITS(BITS)) hold_buf(.in(stack_next0), .out(stack_next));

			always_ff @(posedge clk) begin
				if (en) stack[i] <= stack_next;
			end
		end
	endgenerate

	assign top_data = stack[0];
endmodule : bidir_stack
