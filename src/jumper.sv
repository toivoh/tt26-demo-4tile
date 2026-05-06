/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module jumper #(
		parameter BITS=10, DELTA_BITS=9, RSHIFT=9,
		LOG_N_BITS = $clog2(BITS)
	) (
		input wire clk, reset,

		input wire [BITS-1:0] acc_initial,
		input wire signed [DELTA_BITS-1:0] delta,

		// When do_update is high, take a step according to update_sign and update_shl
		input wire do_update, update_sign,
		input wire [LOG_N_BITS-1:0] update_shl, // must be <= RSHIFT
		input wire extra_term_en,
		input wire [$clog2(RSHIFT+1)-1:0] extra_term_index, // Must be <= RSHIFT

		output wire [BITS-1:0] acc_out
	);

	genvar i;

	reg [BITS-1:0] acc;


	wire signed [BITS+RSHIFT-1:0] delta_ext = delta;
	wire signed [BITS+RSHIFT-1:0] delta_shifted_ext = delta_ext << update_shl;
	wire signed [BITS-1:0] delta_shifted = delta_shifted_ext[BITS+RSHIFT-1:RSHIFT];

	wire [RSHIFT:0] rev_delta;
	for (i = 0; i < RSHIFT; i++) assign rev_delta[i] = delta[RSHIFT-1-i];
	assign rev_delta[RSHIFT] = 0; // OPT: needed? TODO: Need more?

	wire extra_term = extra_term_en & rev_delta[extra_term_index];

	always_ff @(posedge clk) begin
		if (reset) begin
			acc <= acc_initial;
		end else begin
			if (do_update) begin
				acc <= acc + (delta_shifted ^ (update_sign ? '1 : 0)) + (update_sign ^ extra_term);
			end
		end
	end

	assign acc_out = acc;
endmodule : jumper

module count_trailing_zeros #(
		BITS=10,
		// Don't override:
		N_BITS = $clog2(BITS+1)
	) (
		input wire [BITS-1:0] in,
		output wire [N_BITS-1:0] n_trailing
	);

	// not a register
	reg [N_BITS-1:0] n;
	always_comb begin
		// OPT: Don't need all cases?
		casez (in)
			'bzzzzzzzzz1: n = 0;
			'bzzzzzzzz10: n = 1;
			'bzzzzzzz100: n = 2;
			'bzzzzzz1000: n = 3;
			'bzzzzz10000: n = 4;
			'bzzzz100000: n = 5;
			'bzzz1000000: n = 6;
			'bzz10000000: n = 7;
			'bz100000000: n = 8;
			'b1000000000: n = 9;
			default: n = 'X;
		endcase
	end
	assign n_trailing = n;
endmodule

module calc_step_index #(
		parameter BITS = 10, N_MAX = 9,
		// Don't change
		LOG_N_BITS = $clog2(BITS+1)
	) (
		input wire [BITS-1:0] i,
		input wire sign, // 1 for negative
		input wire [LOG_N_BITS-1:0] n,

		output wire [LOG_N_BITS-1:0] index
	);

	wire [BITS-1:0] mask = '1 << n;
	wire [BITS-1:0] pattern = (sign ? i : ~i) & mask;

	count_trailing_zeros #(.BITS(BITS)) count_trailing(
		.in(pattern),
		.n_trailing(index)
	);
endmodule : calc_step_index
