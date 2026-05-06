 /*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module matrix_calc_pl #(
		parameter POS_BITS=10, DX_BITS=10, DDX_FRAC_BITS=9, DDX_INT_BITS=1,
		// Don't override:
		N_BITS = $clog2(POS_BITS+1),
		DDX_BITS = DDX_FRAC_BITS + DDX_INT_BITS + 1
	) (
		input wire clk, reset,

		input wire single_stage,
		input wire [DDX_FRAC_BITS+2-1:0] t,
		input wire [5:0] quadrants, // stacked, 2 bits/axis
		input wire [2:0] zero_axes, one_axes, // one_axes affects only stage 0

		input wire updating_i_d2,
		input wire [DX_BITS-1:0] dx2_x_in, dx2_y_in, dx2_z_in, 

		output wire reset_dxf,
		output logic [POS_BITS-1:0] i_d2_init, i2_init,

		output logic update_dx_ext,
		output logic [2:0] ddx_sign_ext, update_dx_ext_mask,
		output wire [N_BITS-1:0] ddx_shl_ext,

		output wire signed [DX_BITS-1:0] dxf_x_out, dxf_y_out, dxf_z_out,
		output wire signed [DDX_BITS-1:0] ddx_x_out, ddx_y_out, ddx_z_out,

		output wire [2:0] curr_stage,
		output logic stage_done,
		output logic done // done stays high as after finished, as long as reset stays low. (Stays in stage=3, state=3 doing nothing and outputting ddx on ddx_X_out)
	);

	localparam STATE_BITS = 2;
	localparam STAGE_BITS = 2;

	localparam DDX_SOURCE_BITS = 2;
	localparam DDX_SOURCE_T = 0;
	localparam DDX_SOURCE_INV_T = 1;
	localparam DDX_SOURCE_DDX = 2;
	localparam DDX_SOURCE_ONE = 3;

	genvar i;


	reg [STAGE_BITS-1:0] stage;
	reg [STATE_BITS-1:0] state;

	reg [2:0] final_signs;
	(* mem2reg *) reg signed [DDX_BITS-1:0] ddx[3];
	// For debugging
	wire signed [DDX_BITS-1:0] ddx_x = ddx[0];
	wire signed [DDX_BITS-1:0] ddx_y = ddx[1];
	wire signed [DDX_BITS-1:0] ddx_z = ddx[2];


	wire [DDX_FRAC_BITS-1:0] t_frac     = t[DDX_FRAC_BITS-1:0];
	wire [DDX_FRAC_BITS-1:0] t_frac_inv = ~t_frac;

	wire [1:0] t_int = t[DDX_FRAC_BITS+2-1 -: 2];
	wire [1:0] t_ints[3];
	assign t_ints[0] = t_int + quadrants[1:0];
	assign t_ints[1] = t_int + quadrants[3:2];
	assign t_ints[2] = t_int + quadrants[5:4];

	wire [2:0] cos_quadrants = {t_ints[2][0], t_ints[1][0], t_ints[0][0]};
	wire [2:0] factor_signs = {t_ints[2][1], t_ints[1][1], t_ints[0][1]} & (stage == 0 ? ~one_axes : '1);


	always_ff @(posedge clk) begin
		if (reset) begin
			stage <= 0;
			state <= 0;
			final_signs <= 0;
		end	else begin
			if (stage_done) begin
				stage <= single_stage ? 3 : stage + 1;
				state <= 0;
				if (stage == 0 || stage == 2) final_signs <= final_signs ^ factor_signs;
			end else begin
				// Make sure to stay in state = 3 when finished
				//state <= (stage == 3 && state[1]) ? 3 : ((state == 0 && stage == 0) ? 1 : 2);
				case (stage)
					0: state <= (state == 3) ? 3 : state + 1;
					1, 2: state <= 3;
					3: state <= (state[1] == 0) ? 3 : 2;
				endcase
			end
		end
	end

	//wire signed [DX_BITS-1:0] dx2_in[3];
	wire [DX_BITS-1:0] dx2_in[3]; // assume unsigned to use full range of dx2 -- this doesn't work if dx2 is negative
	assign dx2_in[0] = dx2_x_in;
	assign dx2_in[1] = dx2_y_in;
	assign dx2_in[2] = dx2_z_in;

	wire update_ddx = stage_done || (stage == 3 && state == 3);
	generate
		for (i = 0; i < 3; i++) begin
			wire signed [DDX_BITS-1:0] dx2_in_i = (stage == 3) ? $signed(dx2_in[i]) : $signed({1'b0, dx2_in[i]});

			always_ff @(posedge clk) begin
				if (update_ddx) ddx[i] <= dx2_in_i;
			end
		end
	endgenerate


	assign reset_dxf = reset || stage_done;

	// not registers
	logic [DDX_SOURCE_BITS-1:0] ddx_source;
	logic keep_one;
	always_comb begin
		ddx_source = DDX_SOURCE_INV_T;
		update_dx_ext_mask = '1;
		update_dx_ext = 1;
		stage_done = 0;
		done = 0;
		ddx_sign_ext = '0;
		keep_one = 0;

		if (stage == 3) begin
			update_dx_ext = 1;
			ddx_sign_ext = final_signs;
			done = (state == 2);
		end else case (state)
			0: begin
				ddx_source = DDX_SOURCE_T;
				update_dx_ext_mask = ~cos_quadrants;
				if (stage == 2) update_dx_ext_mask = cos_quadrants;
			end
			1: begin
				ddx_source = DDX_SOURCE_INV_T;
				update_dx_ext_mask = cos_quadrants; // (t + 1) instead of t?
			end
			2: begin
				ddx_source = DDX_SOURCE_ONE;
				update_dx_ext_mask = one_axes;
				keep_one = 1;
			end
			3: begin
				ddx_source = DDX_SOURCE_INV_T;
				update_dx_ext = 0;
				stage_done = !updating_i_d2;
			end
		endcase
		if (stage != 0) begin
			ddx_source = DDX_SOURCE_DDX;
			keep_one = 1;
		end

		// Don't start i_d2 iterations until we are done with the initial setup
		if (reset || stage_done || (stage == 0 && state[1] == 0)) i2_init = 0;
		else i2_init = stage == 1 ? t_frac_inv : t_frac;

		update_dx_ext_mask &= ~zero_axes;
		if (!keep_one) update_dx_ext_mask &= ~one_axes;
	end


	assign i_d2_init = 0;

	assign ddx_shl_ext = DDX_FRAC_BITS;


	assign dxf_x_out = 0;
	assign dxf_y_out = 0;
	assign dxf_z_out = 0;

	wire signed [DDX_BITS-1:0] ddx_out[3];
	generate
		for (i = 0; i < 3; i++) begin
			logic signed [DDX_BITS-1:0] ddx_out_i;
			always_comb begin
				ddx_out_i = 'X;
				case (ddx_source)
					DDX_SOURCE_T:     ddx_out_i = t_frac;
					DDX_SOURCE_INV_T: ddx_out_i = t_frac_inv;
					DDX_SOURCE_DDX:   ddx_out_i = ddx[i];
					DDX_SOURCE_ONE:   ddx_out_i = (1 << DDX_FRAC_BITS)-1;
					default:          ddx_out_i = 'X;
				endcase
			end
			assign ddx_out[i] = ddx_out_i;
		end
	endgenerate

	assign ddx_x_out = ddx_out[0];
	assign ddx_y_out = ddx_out[1];
	assign ddx_z_out = ddx_out[2];

	assign curr_stage = stage;
endmodule : matrix_calc_pl
