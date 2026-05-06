/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none


module trace_decision_choice(
		input wire side_en, // 1 if side, 0 if portal(x2/x3)
		input wire [1:0] sub_case,
		input wire dom,
		input wire [1:0] face_axis,

		output wire [1:0] decision_axis_out,
		output wire invert_decision_out
	);

	// not registers
	reg [1:0] decision_axis;
	reg invert_decision;

	reg [1:0] portal_axis;

	always_comb begin
		decision_axis   = 'X;
		invert_decision = 0;
		portal_axis = 'X;

		if (side_en) begin
			if (sub_case[0] == 0) decision_axis = 2;
			else begin
				if (dom) decision_axis = 0;
				else decision_axis = 1;
			end
		end else begin
			portal_axis = face_axis + (sub_case[0] == 0 ? 1 : -1);
			// sub_case[0] == 0: (axis2, face_axis)
			// sub_case[0] == 1: (face_axis, axis1)
			if (portal_axis == 3) portal_axis = (sub_case[0] == 0 ? 0 : 2);
			decision_axis = portal_axis;

			invert_decision = invert_decision ^ (sub_case[0] == sub_case[1]); // invert for sub-case 0 and 3
		end

		if (decision_axis[0]) invert_decision = !invert_decision; // compensate for (x, z) order instead of (z, x)
	end

	assign decision_axis_out   = decision_axis;
	assign invert_decision_out = invert_decision;
endmodule

// Assumes descend_decision = {dx_signs_decision, decision}
module trace_state #(
		parameter DEPTH_BITS=3, LEVEL_BITS=3, X_BITS=8, USE_LOG2_AXIS_SIZES=0,
		AXIS_SIZES_BITS=X_BITS, // can be smaller if only smaller sizes are used
		AXIS_SIZES_LSB_SKIP=0, // can use to skip LSBs in axis_sizes if not used
//		AXIS_SIZES_BITS=7, AXIS_SIZES_LSB_SKIP=2,
		MAX_DEPTH=4, // set to -1 to skip check, but what will be the consequences if depth goes >= 2^DEPTH_BITS-1?
		// Don't change:
		LOG2_AXIS_SIZES_BITS=$clog2(AXIS_SIZES_BITS-AXIS_SIZES_LSB_SKIP)
	) (
		input wire clk, reset,

		input wire [3*X_BITS-1:0] x_corner_initial, // stacked
		input wire [3*X_BITS-1:0] axis_sizes_initial, // stacked
		input wire [3*LOG2_AXIS_SIZES_BITS-1:0] log2_axis_sizes_initial, // stacked, used if USE_LOG2_AXIS_SIZES=1. 0 corresponds to 2^AXIS_SIZES_LSB_SKIP.

		input wire descend, ascend, // descend and ascend can't be true at the same time
		// For descend
		//input wire [2:0] dx_signs_in,
		input wire [3:0] descend_decision,
		// For ascend
		input wire [1:0] prev_face_axis,
		input wire prev_old_dom,
		input wire [DEPTH_BITS-1:0] target_depth,
		input wire [LEVEL_BITS-1:0] target_level,
		input wire [2:0] dx_signs,

		output wire [DEPTH_BITS-1:0] depth_out,
		output wire [LEVEL_BITS-1:0] level_out,
		output wire [3*X_BITS-1:0] x_corner_out, // stacked
		output wire [3*X_BITS-1:0] axis_sizes_out, // stacked
		output wire [1:0] face_axis_out,
		output wire axis_1_dom_0_out, old_dom_out,
		output wire  wall_hit_out,

		output wire push, pop // depth <= depth + push - pop
	);

	localparam AXIS_SIZES_MASK = ((1 << AXIS_SIZES_BITS) - 1) & (-1 << AXIS_SIZES_LSB_SKIP);

	localparam LEVEL_SIDE1 = 2**LEVEL_BITS - 2;
	localparam LEVEL_SIDE2 = 2**LEVEL_BITS - 1;

	localparam LEVEL_INITIAL = 2; // TODO: 3 or 5 instead? + change level update logic

	localparam LEVEL_DX_SIGN_0 = 0;
	localparam LEVEL_DX_SIGN_1 = 1;
	localparam LEVEL_DX_SIGN_2 = 2;

	localparam LEVEL_CORNER_X3_1 = 0;
	localparam LEVEL_CORNER_X3_2 = 1;
	localparam LEVEL_CORNER_X2_1 = 2;
	localparam LEVEL_CORNER_X2_2 = 3;

	genvar i;


	reg [DEPTH_BITS-1:0] depth;
	reg [LEVEL_BITS-1:0] level;
	//reg [2:0] dx_signs;

	(* mem2reg *) reg [X_BITS-1:0] x_corner[3];
	(* mem2reg *) reg [X_BITS-1:0] axis_sizes[3]; // OPT: Does this need full resolution?
	(* mem2reg *) reg [LOG2_AXIS_SIZES_BITS-1:0] log2_axis_sizes[3];

	// For debug
	wire [X_BITS-1:0] axis_sizes_out_arr[3];

	wire [X_BITS-1:0] x_corner_e0 = x_corner[0];
	wire [X_BITS-1:0] x_corner_e1 = x_corner[1];
	wire [X_BITS-1:0] x_corner_e2 = x_corner[2];
	wire [X_BITS-1:0] axis_sizes_e0 = axis_sizes[0];
	wire [X_BITS-1:0] axis_sizes_e1 = axis_sizes[1];
	wire [X_BITS-1:0] axis_sizes_e2 = axis_sizes[2];

	// old_dom is used as an intermediate since dom and face_axis are pushed together
	// level = LEVEL_SIDE1:  (old_dom, axis_1_dom_0) = (axis_1_dom_0, d)
	// level = LEVEL_SIDE2:  push!((old_dom, face_axis)); face_axis = f(axis_1_dom_0, d)
	reg [1:0] face_axis;
	reg axis_1_dom_0, old_dom, wall_hit;


	wire [1:0] new_face_axis = axis_1_dom_0 ? (descend_decision[0] ? 2 : 1) : (descend_decision[0] ? 0 : 2);
	wire [1:0] descend_face_axis = ((level == LEVEL_SIDE2 && !ascend) ? new_face_axis : face_axis);

	wire [2:0] plane_mask = {descend_face_axis != 2, descend_face_axis != 1, descend_face_axis != 0};

	// not registers
	reg [LEVEL_BITS-1:0] eff_level;
	reg [DEPTH_BITS-1:0] next_depth;
	reg [LEVEL_BITS-1:0] next_level;
	reg [1:0] next_face_axis;
	//reg next_axis_1_dom_0, 
	reg next_wall_hit;
	reg [2:0] axs_shrink_en, axs_expand_en;
	reg [2:0] dxc_inv, dxc_en, xc_inv;
	reg dxc_quarter;
	reg [2:0] dxc_half;
	reg r_push, r_pop;
	reg depth_jump_ascend;
	always_comb begin
		eff_level = level; // OPT: could be 'X here, set only in ascend case
		next_depth = depth;
		next_level = level;
		next_face_axis = face_axis;
		//next_axis_1_dom_0 = axis_1_dom_0; //'X;
		next_wall_hit = wall_hit;
		axs_shrink_en = '0; axs_expand_en = '0;
		dxc_en = '0;
		dxc_inv = 'X;
		dxc_quarter = 0; dxc_half = '0;
		xc_inv = '0;
		depth_jump_ascend = 0;

		r_push = 0;
		r_pop = 0;

		// OPT
		if (descend) begin // OPT: switch on {ascend, descend}?
			if (level == LEVEL_SIDE2) r_push = 1;

			next_level = level + 1;
			if (depth == 0) begin
				if (level == 2) next_level = LEVEL_SIDE1; // also offset corner based on dx_signs, done below
			end else begin
				if (level == 3) next_level = LEVEL_SIDE1;
			end

			if (level == LEVEL_SIDE2) begin
				// x1 -> x3, go to new cube
				// Specific transition for the current cube connection function:
				dxc_en = plane_mask;
				dxc_inv = '1;
				dxc_quarter = 1;
				axs_shrink_en = plane_mask;

				//if (depth >= 4) next_wall_hit = 1; // TODO: remove?
				if (MAX_DEPTH >= 0 && depth == MAX_DEPTH) next_wall_hit = 1;
			end else if (depth != 0) begin
				case (level)
					LEVEL_CORNER_X3_2: begin
						// x3 -> x2
						dxc_en = plane_mask;
						dxc_inv = '1;
					end
					LEVEL_CORNER_X2_2: begin
						// x2 -> x4
						dxc_en = '1;
						dxc_inv = '0;
					end
					default: begin
						dxc_en = '0;
						dxc_inv = 'X;
						dxc_quarter = 'X; dxc_half = 'X;
					end
				endcase

/* verilator lint_off UNSIGNED */
				if (LEVEL_CORNER_X3_1 <= level && level <= LEVEL_CORNER_X2_2) begin // OPT
					next_wall_hit = descend_decision[0];
				end
/* verilator lint_on UNSIGNED */
			end else begin // depth == 0
				if (level == 2) begin
					// Add initial offset to corner
					//xc_inv = dx_signs_in;
					xc_inv = descend_decision[3:1];
					dxc_en = '1;
					dxc_inv = '0;
					dxc_half = '1;
				end
			end
		end else if (ascend) begin
			next_wall_hit = 0;

			// Can we skip two levels at once?
			if (!((target_depth == depth) && (target_level == (level & ~1)))) eff_level[0] = 0;

			if (eff_level == LEVEL_SIDE1 && (target_depth != depth)) begin // optimization: ascend a whole depth level
			//if (0) begin
				r_pop = 1;
				next_level = LEVEL_SIDE2;
				depth_jump_ascend = 1;
			end else begin
				next_level = eff_level - 1; // OPT: share with level + 1
				if (eff_level == LEVEL_SIDE1) begin
					if (depth == 0) next_level = LEVEL_DX_SIGN_2; // also un-offset corner based on dx_signs, done below
					else next_level = LEVEL_CORNER_X2_2;
				end
				if (eff_level == 0) r_pop = 1;
			end

			//if (eff_level == LEVEL_SIDE2+1) begin
			if (eff_level == 0 || depth_jump_ascend) begin
				// go back to previous cuboid
				if (!depth_jump_ascend) begin
					// Specific transition for the current cube connection function:
					// x1 <- x3
					dxc_en = plane_mask;
					dxc_inv = '0;
					dxc_half = '1;
				end else begin
					// Specific transition for the current cube connection function:
					// x1 <- x4
					dxc_en = '1;
					dxc_inv = ~plane_mask;
					dxc_half = plane_mask;
				end
				axs_expand_en = plane_mask;
			end else if (depth != 0 || wall_hit) begin // || wall_hit is for the case when depth has wrapped around to zero
				case (eff_level)
					LEVEL_CORNER_X3_2+1: begin
						// x3 <- x2
						dxc_en = plane_mask;
						dxc_inv = '0;
					end
					//LEVEL_CORNER_X2_2+1: begin
					LEVEL_SIDE1: begin
						// x2 <- x4
						dxc_en = '1;
						dxc_inv = '1;
					end
					default: begin
						dxc_en = '0;
						dxc_inv = 'X;
						dxc_quarter = 'X; dxc_half = 'X;
					end
				endcase
			end else begin // depth == 0
				if (eff_level == LEVEL_SIDE1) begin
					// Remove initial offset from corner
					//x_corner = (x_corner - axis_sizes) .* dx_signs
					xc_inv = dx_signs; // dx_signs_in does not work, it can have changed before we start to ascend.
					dxc_en = '1;
					dxc_inv = ~xc_inv;
					dxc_half = '1;
				end
			end
		end

		next_depth = depth + r_push - r_pop; // OPT
	end

	wire [X_BITS-1:0] x_corner_init[3];
	assign {x_corner_init[2], x_corner_init[1], x_corner_init[0]} = x_corner_initial;
	wire [X_BITS-1:0] axis_sizes_init[3];
	assign {axis_sizes_init[2], axis_sizes_init[1], axis_sizes_init[0]} = axis_sizes_initial;
	wire [LOG2_AXIS_SIZES_BITS-1:0] log2_axis_sizes_init[3];
	assign {log2_axis_sizes_init[2], log2_axis_sizes_init[1], log2_axis_sizes_init[0]} = log2_axis_sizes_initial;

	generate
		for (i = 0; i < 3; i++) begin

			// For USE_LOG2_AXIS_SIZES = 0
			wire [X_BITS-1:0] delta_xc_a0 = dxc_half[i] ? axis_sizes[i] : (dxc_quarter ? (axis_sizes[i] >> 1) : (axis_sizes[i] << 1));

			// For USE_LOG2_AXIS_SIZES = 1
			wire [$clog2(X_BITS)-1:0] log2_as = log2_axis_sizes[i] + (dxc_half[i] ? 1 : (dxc_quarter ? 0 : 2));
			wire [X_BITS-1:0] delta_xc_l0 = (1 << (AXIS_SIZES_LSB_SKIP-1)) << log2_as;

			// Select which one to use
			wire [X_BITS-1:0] delta_xc_0 = USE_LOG2_AXIS_SIZES ? delta_xc_l0 : delta_xc_a0;
			assign axis_sizes_out_arr[i] = USE_LOG2_AXIS_SIZES ? ((1 << AXIS_SIZES_LSB_SKIP) << log2_axis_sizes[i]) : axis_sizes[i];


			wire [X_BITS-1:0] delta_xc_1 = dxc_inv[i] ? ~delta_xc_0 : delta_xc_0;
			wire [X_BITS-1:0] delta_xc_2 = dxc_en[i] ? delta_xc_1 : '0;

			wire [X_BITS-1:0] xc = xc_inv[i] ? ~x_corner[i] : x_corner[i];
			wire [X_BITS-1:0] next_xc_corner = xc + delta_xc_2 + (dxc_en[i] && (dxc_inv[i] || xc_inv[i]));

			always_ff @(posedge clk) begin
				if (reset) begin
					x_corner[i] <= x_corner_init[i];
					axis_sizes[i] <= axis_sizes_init[i] & AXIS_SIZES_MASK;
					log2_axis_sizes[i] <= log2_axis_sizes_init[i];
				end else begin
					x_corner[i] <= next_xc_corner;
					axis_sizes[i] <= (axs_expand_en[i] ? (axis_sizes[i] << 1) : (axs_shrink_en[i] ? (axis_sizes[i] >> 1) : axis_sizes[i])) & AXIS_SIZES_MASK;
					log2_axis_sizes[i] <= log2_axis_sizes[i] + (axs_expand_en[i] ? 1 : (axs_shrink_en[i] ? -1 : 0));
				end
			end
		end
	endgenerate

	always_ff @(posedge clk) begin
		if (reset) begin
			depth <= 0;
			level <= LEVEL_INITIAL;
			// TODO: ok to initialize with X? Tested mostly in verilator...
			//dx_signs <= 'X;
			//{x_corner[2], x_corner[1], x_corner[0]} <= x_corner_initial;
			//{axis_sizes[2], axis_sizes[1], axis_sizes[0]} <= axis_sizes_initial;
			face_axis <= 'X;
			axis_1_dom_0 <= 'X;
			old_dom <= 'X;
			wall_hit <= 0;
		end else begin
			depth <= next_depth;
			level <= next_level;
			if (ascend && (eff_level == 0 || depth_jump_ascend)) begin
				face_axis <= prev_face_axis;
				old_dom <= prev_old_dom;
			end else begin
				face_axis <= next_face_axis;
				//axis_1_dom_0 <= next_axis_1_dom_0;
			end
			wall_hit <= next_wall_hit;

			if (descend) begin
				//if (depth == 0 && level == LEVEL_DX_SIGN_2) dx_signs <= dx_signs_in;
				if (level == LEVEL_SIDE1) begin
					old_dom <= axis_1_dom_0;
					axis_1_dom_0 <= descend_decision[0];
				end
				//if (level == LEVEL_SIDE2) begin
					face_axis <= descend_face_axis;
				//end
			end else if (ascend) begin
				// Don't use eff_level here, LEVEL_SIDE2 is odd
				if (level == LEVEL_SIDE2) axis_1_dom_0 <= old_dom;
			end
		end
	end


	assign depth_out = depth;
	assign level_out = level;
	assign x_corner_out = {x_corner[2], x_corner[1], x_corner[0]};
	assign axis_sizes_out = {axis_sizes_out_arr[2], axis_sizes_out_arr[1], axis_sizes_out_arr[0]};
	assign face_axis_out = face_axis;
	assign axis_1_dom_0_out = axis_1_dom_0;
	assign old_dom_out = old_dom;
	assign wall_hit_out = wall_hit;

	assign push = r_push; assign pop = r_pop;
endmodule : trace_state
