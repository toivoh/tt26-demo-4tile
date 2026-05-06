/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module ang_leq #(parameter BITS_X=8, BITS_Y=8, BITS_N=0) (
		//input wire [BITS_X-1:0] x1, x2, x3,
		input wire signed [BITS_X+1-1:0] x1, x2, x3, // Assumes !(x_a < 0 && x_b < 0)
		input wire [BITS_Y-1:0] y1, y2, y3,

		input wire [1:0] axis,

		output wire sign,

		output wire signed [BITS_X+1-1:0] x_a0, x_b0,
		output wire [BITS_Y-1:0] y_a, y_b
	);

	// Choose subset
	// -------------
	// not registers
	reg sel_a_2, sel_b_3;
	always_comb begin
		case (axis)
			0: {sel_a_2, sel_b_3} = 2'b11; // x -> (y, z)
			1: {sel_a_2, sel_b_3} = 2'b01; // y -> (x, z)
			2: {sel_a_2, sel_b_3} = 2'b00; // z -> (x, y)
			default: {sel_a_2, sel_b_3} = 'X;
		endcase
	end

//	wire [BITS_X+1-1:0] x_a = sel_a_2 ? x2 : x1;
//	wire [BITS_X+1-1:0] x_b = sel_b_3 ? x3 : x2;

	assign x_a0 = sel_a_2 ? x2 : x1;
	assign x_b0 = sel_b_3 ? x3 : x2;

	localparam CUT_BITS = 2**BITS_N-1;
	localparam BITS_X_RED = BITS_X - CUT_BITS;

	wire [BITS_X_RED-1:0] x_a;
	wire [BITS_X_RED-1:0] x_b;
	generate
		if (BITS_N == 0) begin
			assign x_a = x_a0[BITS_X-1:0];
			assign x_b = x_b0[BITS_X-1:0];
		end else begin
			wire [BITS_X-1:0] x_a1 = x_a0[BITS_X-1:0];
			wire [BITS_X-1:0] x_b1 = x_b0[BITS_X-1:0];

			wire [CUT_BITS-1:0] prefix = x_a1[BITS_X-1 -: CUT_BITS] | x_b1[BITS_X-1 -: CUT_BITS] ;
			wire [BITS_N-1:0] rshift;
			priority_encoder #(.N_BITS(BITS_N)) prio_enc(.pattern(prefix), .n_out(rshift));

			assign x_a = x_a1 >> rshift;
			assign x_b = x_b1 >> rshift;
		end
	endgenerate

	assign y_a = sel_a_2 ? y2 : y1;
	assign y_b = sel_b_3 ? y3 : y2;

	wire [BITS_X_RED+BITS_Y-1:0] prod1, prod2;

/*
	assign prod1 = x_a * y_b;
	assign prod2 = x_b * y_a;
*/

	approx_mul_rshift_5 #(.BITS_X(BITS_X), .BITS_Y(BITS_Y)) mul1(.x(x_a), .y(y_b), .product(prod1));
	approx_mul_rshift_5 #(.BITS_X(BITS_X), .BITS_Y(BITS_Y)) mul2(.x(x_b), .y(y_a), .product(prod2));

/*
	approx_mul_rshift_6 #(.BITS_X(BITS_X), .BITS_Y(BITS_Y)) mul1(.x(x_a), .y(y_b), .product(prod1));
	approx_mul_rshift_6 #(.BITS_X(BITS_X), .BITS_Y(BITS_Y)) mul2(.x(x_b), .y(y_a), .product(prod2));
*/

	// subdet = prod1 - prod2

	wire sign_subdet = (prod1 >= prod2); // subdet >= 0

//	assign sign = sign_subdet;

	// not a register
	reg sign_out;
	always_comb begin
		sign_out = sign_subdet;
		if (x_a0[BITS_X]) sign_out = 0; // prod1 <= 0 ==> subdet negative
		if (x_b0[BITS_X]) sign_out = 1; // prod2 <= 0 ==> subdet positive
		// TODO: assert that boths signs are not negative at the same time?
	end
	assign sign = sign_out;
endmodule : ang_leq

module approx_mul_rshift_5 #(parameter BITS_X=8, BITS_Y=9) (
		input wire [BITS_X-1:0] x,
		input wire [BITS_Y-1:0] y,
		output wire [BITS_X+BITS_Y-5-1:0] product
	);

	assign product = x[BITS_X-1:2]*y[BITS_Y-1:3] + x[BITS_X-1:5]*y[2:0] + x[1:0]*y[BITS_Y-1:5] + x[4:3]*y[2] + x[4]*y[1] + x[1]*y[4];
endmodule

module approx_mul_rshift_6 #(parameter BITS_X=8, BITS_Y=9) (
		input wire [BITS_X-1:0] x,
		input wire [BITS_Y-1:0] y,
		output wire [BITS_X+BITS_Y-6-1:0] product
	);

	assign product = x[BITS_X-1:3]*y[BITS_Y-1:3] + x[BITS_X-1:6]*y[2:0] + x[2:0]*y[BITS_Y-1:6] + x[5:4]*y[2] + x[2:1]*y[5] + x[5]*y[1] + x[2]*y[4];
endmodule

module priority_encoder #(parameter N_BITS=3) (
		input wire [2**N_BITS-1-1:0] pattern,
		output wire [N_BITS-1:0] n_out
	);

	// not a register
	reg [N_BITS-1:0] n;
	always_comb begin
		casez (pattern)
			7'b0000000: n = 0;
			7'b0000001: n = 1;
			7'b000001z: n = 2;
			7'b00001zz: n = 3;
			7'b0001zzz: n = 4;
			7'b001zzzz: n = 5;
			7'b01zzzzz: n = 6;
			7'b1zzzzzz: n = 7;
			default: n = 'X;
		endcase
	end
	assign n_out = n;
endmodule
