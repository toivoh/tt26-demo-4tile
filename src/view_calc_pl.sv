 /*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

module view_calc_pl #(
		parameter POS_BITS=10, DX_BITS=10, DDX_FRAC_BITS=9, DDX_INT_BITS=1,
		// Don't override:
		N_BITS = $clog2(POS_BITS+1),
		DDX_BITS = DDX_FRAC_BITS + DDX_INT_BITS + 1
	) (
		input wire clk, reset,

		input wire [DDX_FRAC_BITS+2-1:0] t1, t2,
		input wire [DX_BITS-1:0] fov_factor,
		input wire signed [DX_BITS-1:0] y,

		output logic [1:0] t1t2fov_src,

		input wire updating_i_d2,
		input wire [DX_BITS-1:0] dx2_x_in, dx2_y_in, dx2_z_in,
		input wire [DX_BITS-1:0] dx1_x_in, dx1_y_in, dx1_z_in,

		output logic reset_dxf_out, reset_i_d2_out,
		output logic [POS_BITS-1:0] i_d2_init_out, i2_init_out,

		output logic update_dx1_ext_out, next_update_dx1_ext_out,
		output logic update_dx_ext_out,
		output logic [2:0] ddx_sign_ext_out, update_dx_ext_mask_out,
		output logic [N_BITS-1:0] ddx_shl_ext_out,

		output wire signed [DX_BITS-1:0] dxf_x_out, dxf_y_out, dxf_z_out,
		output wire signed [DDX_BITS-1:0] ddx_x_out, ddx_y_out, ddx_z_out,

		output logic done
	);

	localparam STATE_BITS = 2;


	reg [1:0] stage;
	reg [STATE_BITS-1:0] state;

	logic stage_done, next_stage_done;
	logic reset_mat;


	wire mat_reset_dxf;
	wire [POS_BITS-1:0] mat_i_d2_init, mat_i2_init;
	wire mat_update_dx_ext;
	wire [2:0] mat_ddx_sign_ext, mat_update_dx_ext_mask;
	wire [N_BITS-1:0] mat_ddx_shl_ext;
//	wire signed [DX_BITS-1:0] dxf_x_out, dxf_y_out, dxf_z_out;
//	wire signed [DDX_BITS-1:0] ddx_x_out, ddx_y_out, ddx_z_out;
	wire mat_done;



	logic single_stage;
	logic [5:0] quadrants1, quadrants2; 
	logic [2:0] zero_axes, one_axes;

	always_comb begin
		single_stage = 'X;
		quadrants1 = 'X; quadrants2 = 'X;
		zero_axes = 'X; one_axes = 'X;

		case (stage)
			0: begin
				// dx_z
				single_stage = 0;
				quadrants1 = 'b01xx00;
				quadrants2 = 'b010001;
				zero_axes = '0;
				one_axes  = 'b010;
			end
			1: begin
				// ddx_y
				single_stage = 0;
				quadrants1 = 'b11xx10;
				quadrants2 = 'b000100;
				zero_axes = '0;
				one_axes  = 'b010;
			end
			2: begin
				// ddx_x
				single_stage = 1;
				quadrants1 = 'b10xx01;
				zero_axes = 'b010;
				one_axes  = '0;
			end
			default: begin
				single_stage = 'X;
				quadrants1 = 'X; quadrants2 = 'X;
				zero_axes = 'X; one_axes = 'X;
			end
		endcase
	end

	wire [1:0] curr_stage;

	wire [DDX_FRAC_BITS+2-1:0] t = (curr_stage == 0) ? t1 : t2;
	wire [5:0] quadrants =         (curr_stage == 0) ? quadrants1 : quadrants2;

	matrix_calc_pl #(.POS_BITS(POS_BITS), .DX_BITS(DX_BITS), .DDX_FRAC_BITS(DDX_FRAC_BITS), .DDX_INT_BITS(DDX_INT_BITS)) matrix_calc_inst(
		.clk(clk), .reset(reset || reset_mat),

		.single_stage(single_stage), .t(t), .quadrants(quadrants), .zero_axes(zero_axes), .one_axes(one_axes),
		.updating_i_d2(updating_i_d2),
		.dx2_x_in(dx2_x_in), .dx2_y_in(dx2_y_in), .dx2_z_in(dx2_z_in),

		.reset_dxf(mat_reset_dxf),
		.i_d2_init(mat_i_d2_init), .i2_init(mat_i2_init),
		.update_dx_ext(mat_update_dx_ext), .update_dx_ext_mask(mat_update_dx_ext_mask), .ddx_sign_ext(mat_ddx_sign_ext), .ddx_shl_ext(mat_ddx_shl_ext),
//		.dxf_x_out(dxf_x_out), .dxf_y_out(dxf_y_out), .dxf_z_out(dxf_z_out),
		.ddx_x_out(ddx_x_out), .ddx_y_out(ddx_y_out), .ddx_z_out(ddx_z_out),

		.curr_stage(curr_stage), .done(mat_done)
	);

`ifdef VIEW_CALC_PL_DELAY_STAGE_DONE
	reg updating_i_d2_delayed;
	always_ff @(posedge clk) begin
		if (reset) updating_i_d2_delayed <= 0;
		else updating_i_d2_delayed <= updating_i_d2;
	end
	wire updating_i_d2_eff = updating_i_d2 || updating_i_d2_delayed;
`else
	wire updating_i_d2_eff = updating_i_d2;
`endif

	logic mat_control;
	logic zero_dx;

	logic reset_dxf, reset_i_d2;
	logic [POS_BITS-1:0] i_d2_init, i2_init;
	logic update_dx1_ext, next_update_dx1_ext;
	logic update_dx_ext;
	logic [2:0] ddx_sign_ext, update_dx_ext_mask;
	logic [N_BITS-1:0] ddx_shl_ext;

	//assign done = stage_done && (stage == 2);
	assign done = (state == 3);
	//assign reset_mat = reset || (stage_done && stage[1] == 0);
	assign update_dx1_ext = stage_done;
	assign next_update_dx1_ext = next_stage_done;

	always_comb begin
		reset_dxf = '0;
		reset_i_d2 = '0;
		i_d2_init = 'X;
		i2_init = 'X;
		update_dx_ext = 0;
		ddx_sign_ext = '0;
		update_dx_ext_mask = '1;
		ddx_shl_ext = DDX_FRAC_BITS;

		mat_control = 0;
		stage_done = 0; next_stage_done = 0;
		zero_dx = 1;

		case (stage)
			0: begin
				i_d2_init = 0;
				i2_init = fov_factor;
			end
			1: begin
				//i_d2_init = 512;
				//i2_init = (y ^ 256) | 512;
				// The version above can apparently hang the multiplier
				i_d2_init = 256;
				i2_init = (y ^ 256) & 511;
			end
			2: begin
				i_d2_init = 512;
				i2_init = 512 - 320;
			end
		endcase

		case (state)
			0: begin
				mat_control = 1;
			end
			1: begin
				reset_dxf = 1;
				zero_dx = (stage == 0);
			end
			2: begin
				stage_done = !updating_i_d2_eff;
				next_stage_done = !updating_i_d2;
				i_d2_init = 0;
				reset_i_d2 = (stage[1] == 1) && stage_done;
				if (reset_i_d2) i2_init = 639;
			end
			3: begin
`ifdef USE_STACK_UNDERFLOW_RESTART
				i2_init = 639; // Make sure this value stays during the whole done phase
`endif
			end
		endcase

		reset_mat = reset || (stage_done && stage[1] == 0);
		if (reset_mat) mat_control = 1;
	end


	always_comb begin
		if (mat_control) begin
			reset_dxf_out = mat_reset_dxf;
			i_d2_init_out = mat_i_d2_init;
			i2_init_out = mat_i2_init;
			update_dx_ext_out = mat_update_dx_ext;
			ddx_sign_ext_out = mat_ddx_sign_ext;
			update_dx_ext_mask_out = mat_update_dx_ext_mask;
			ddx_shl_ext_out = mat_ddx_shl_ext;
			reset_i_d2_out = 0;
		end else begin
			reset_dxf_out = reset_dxf;
			i_d2_init_out = i_d2_init;
			i2_init_out = i2_init;
			update_dx_ext_out = update_dx_ext;
			ddx_sign_ext_out = ddx_sign_ext;
			update_dx_ext_mask_out = update_dx_ext_mask;
			ddx_shl_ext_out = ddx_shl_ext;
			reset_i_d2_out = reset_i_d2;
		end
		update_dx1_ext_out = update_dx1_ext;
		next_update_dx1_ext_out = next_update_dx1_ext;
		if (reset_dxf_out) reset_i_d2_out = 1;
	end


	always_ff @(posedge clk) begin
		if (reset) begin
			stage <= 0;
			state <= 0;
		end else begin
			if (stage_done) begin
				if (stage[1] == 0) begin
					stage <= stage + 1;
					state <= 0;
				end else begin
					state <= 3;
				end
			end else begin
				case (state)
					0: state <= mat_done;
					1: state <= 2;
				endcase
			end
		end
	end

	assign dxf_x_out = zero_dx ? '0 : dx1_x_in;
	assign dxf_y_out = zero_dx ? '0 : dx1_y_in;
	assign dxf_z_out = zero_dx ? '0 : dx1_z_in;

	always_comb begin
		t1t2fov_src = 0;
		t1t2fov_src[`T1T2FOV_BIT_T2] = (curr_stage != 0);
		t1t2fov_src[`T1T2FOV_BIT_FOV] = !mat_control;
	end
endmodule : view_calc_pl
