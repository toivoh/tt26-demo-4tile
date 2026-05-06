/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module carry_save_adder #( BITS=8 ) (
		input wire [BITS-1:0] x, y, z,
		output wire [BITS-1:0] s, c
	);

	genvar i;
	generate
		for (i = 0; i < BITS; i++) begin
`ifdef PURE_RTL
			assign {c[i], s[i]} = x[i] + y[i] + z[i];
`else
			sky130_fd_sc_hd__fa_1 full_adder(
				.A(x[i]), .B(y[i]), .CIN(z[i]),
				.COUT(c[i]), .SUM(s[i])
			);
`endif
		end
	endgenerate
endmodule : carry_save_adder

module three_term_adder #( BITS=8 ) (
		input wire [BITS-1:0] x, y, z,
		input wire neg_x, neg_y, neg_z, // inv_x and inv_y cannot be high at the same time
		input wire force_carry_in_xy_low, force_carry_in_z_high,
		output wire [BITS-1:0] sum
	);

	wire [BITS-1:0] x1 = neg_x ? ~x : x;
	wire [BITS-1:0] y1 = neg_y ? ~y : y;
	wire [BITS-1:0] z1 = neg_z ? ~z : z;

	wire [BITS-1:0] c, s;
	carry_save_adder #(.BITS(BITS)) csa(
		.x(x1), .y(y1), .z(z1),
		.s(s), .c(c)
	);

	wire carry_in_xy = (neg_x || neg_y) && !force_carry_in_xy_low;
	wire carry_in_z = neg_z || force_carry_in_z_high;

	assign sum = s + {c[BITS-1-1:0], carry_in_z} + carry_in_xy;

`ifdef NO_SYNTH
	wire [BITS-1:0] expected = x1 + y1 + z1 + carry_in_xy + carry_in_z;
	assert(sum == expected);
`endif
endmodule : three_term_adder


// Assumes descend_decision = {dx_signs_decision, decision}
module trace_state_rs #(
		parameter DEPTH_BITS=3, LEVEL_BITS=3, X_BITS=8,
		AXIS_SIZES_BITS=X_BITS, // can be smaller if only smaller sizes are used
		AXIS_SIZES_LSB_SKIP=0, // can use to skip LSBs in axis_sizes if not used
//		AXIS_SIZES_BITS=7, AXIS_SIZES_LSB_SKIP=2,
		MAX_DEPTH=4, // set to -1 to skip check, but what will be the consequences if depth goes >= 2^DEPTH_BITS-1?
		ROOM_BITS=8
	) (
		input wire clk, reset,

		input wire [3*X_BITS-1:0] x_corner_initial, // stacked
		input wire [ROOM_BITS-1:0] room_initial,

		output wire [ROOM_BITS-1:0] room_out,
		output wire [2:0] room_dir_signs_out,
		output wire [1:0] room_dir_axis_out,
		input wire [3*X_BITS-1:0] axis_sizes_in, // stacked
		input wire [3*X_BITS-1:0] room_pos_in, // stacked
		input wire [ROOM_BITS-1:0] neighbor_room,
		input wire [2:0] mirroring,

		input wire descend, ascend, ack_hit, // descend and ascend can't be true at the same time
		output wire working, next_working, // if working, keep descend or ascend high (ascend could be ok as it is?)

		input wire override_en,
		input wire [1:0] override_next_face_axis, // actually override for room_dir_axis_out
		input wire override_change_room, override_room_pos_en,
		input wire [2:0] override_xc_inv, override_dxc_en, override_dxc_inv, override_dxc_half, override_room_pos_inv,

		// For descend
		//input wire [2:0] dx_signs_in,
		input wire [3:0] descend_decision,
		// For ascend
		input wire [1:0] prev_face_axis,
		input wire prev_old_dom,
		input wire [DEPTH_BITS-1:0] target_depth,
		input wire [LEVEL_BITS-1:0] target_level,
		input wire [2:0] dx_signs,
		// For decend and ascend
		input wire [2:0] interlace_mask,

		output wire [DEPTH_BITS-1:0] depth_out,
		output wire [LEVEL_BITS-1:0] level_out,
		output wire [3*X_BITS-1:0] x_corner_out, // stacked
		output wire [3*X_BITS-1:0] axis_sizes_out, // stacked
		output wire [1:0] face_axis_out, wall_face_axis_out,
		output wire axis_1_dom_0_out, old_dom_out,
		output wire wall_hit_out,

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

	reg [ROOM_BITS-1:0] room;
	(* mem2reg *) reg [X_BITS-1:0] x_corner[3];
	//(* mem2reg *) reg [X_BITS-1:0] axis_sizes[3]; // OPT: Does this need full resolution?

	reg part_two;

	wire [X_BITS-1:0] axis_sizes[3];
	assign {axis_sizes[2], axis_sizes[1], axis_sizes[0]} = axis_sizes_in;

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
	reg [1:0] face_axis, wall_face_axis;
	reg axis_1_dom_0, old_dom, wall_hit;


	wire [1:0] new_face_axis = axis_1_dom_0 ? (descend_decision[0] ? 2 : 1) : (descend_decision[0] ? 0 : 2);
	//wire [1:0] descend_face_axis = ((level == LEVEL_SIDE2 && !part_two && !ascend) ? new_face_axis : face_axis);

	//wire [2:0] plane_mask = {descend_face_axis != 2, descend_face_axis != 1, descend_face_axis != 0};
	wire [2:0] plane_mask = {face_axis != 2, face_axis != 1, face_axis != 0};


	// Calculate corner_signs, for ascending between different depths/rooms
	wire [1:0] corner = part_two ? target_level[2:1] : level[2:1];
	// not a register
	reg [2:0] corner_signs;
	always_comb begin
		corner_signs = 'X;
		case (corner)
			0: corner_signs = ~plane_mask; //x3
			1: corner_signs = '1; // x2
			3: corner_signs = '0; // x1
			default: corner_signs = 'X;
		endcase
	end


	// not registers
	reg [LEVEL_BITS-1:0] eff_level;
	reg [DEPTH_BITS-1:0] next_depth;
	reg [LEVEL_BITS-1:0] next_level;
	reg [1:0] next_face_axis;
	//reg next_axis_1_dom_0, 
	reg next_wall_hit;
	//reg [2:0] axs_shrink_en, axs_expand_en;
	reg change_room;
	reg room_pos_en;
	reg [2:0] room_pos_inv;
	reg [2:0] dxc_inv, dxc_en, xc_inv;
	reg [2:0] dxc_half;
	reg r_push_internal, r_push_external, r_pop;
	reg depth_jump_ascend;
	reg next_part_two;
	reg update_face_axis, update_dom_from_old_dom;
	reg new_wall_face_axis;
	logic interlace_op;
	always_comb begin
		eff_level = level; // OPT: could be 'X here, set only in ascend case
		next_depth = depth;
		next_level = level;
		next_face_axis = face_axis;
		//next_axis_1_dom_0 = axis_1_dom_0; //'X;
		next_wall_hit = wall_hit;
		//axs_shrink_en = '0; axs_expand_en = '0;
		change_room = '0;
		room_pos_en = '0; room_pos_inv = '0;
		dxc_en = '0;
		dxc_inv = 'X;
		dxc_half = '0;
		xc_inv = '0;
		depth_jump_ascend = 0;
		next_part_two = 0;
		update_face_axis = 0;
		update_dom_from_old_dom = 0;
		new_wall_face_axis = 0;

		r_push_internal = 0;
		r_push_external = 0;
		r_pop = 0;

		interlace_op = 0;

		// OPT
		if (descend) begin // OPT: switch on {ascend, descend}?
			if (level == LEVEL_SIDE2) begin
				r_push_external = !part_two;
				r_push_internal = part_two;
			end

			next_level = level + 1;
			if (depth == 0) begin
				if (level == 2) next_level = LEVEL_SIDE1; // also offset corner based on dx_signs, done below
			end else begin
				if (level == 3) next_level = LEVEL_SIDE1;
			end

			if (level == LEVEL_SIDE2) begin
				// x1 -> x3, go to new cube
				// Specific transition for the current cube connection function:
				//dxc_en = plane_mask;
				//dxc_inv = '1;
				//dxc_quarter = 1;
				//axs_shrink_en = plane_mask;

				if (!part_two) begin
					next_wall_hit = (neighbor_room == '1);
					if (!next_wall_hit) begin
						next_part_two = 1;
						// OPT: better way to delay the level and depth update?
						next_level = level; //LEVEL_SIDE2;
						update_face_axis = 1;

						change_room = 1;
						// x_corner -= dx_signs.*room_pos + axis_sizes
						room_pos_en = 1; room_pos_inv = ~dx_signs;
						dxc_en = '1; dxc_inv = '1; dxc_half = '1;
					end else begin
						// OPT: better way to stop the transition?
						next_level = level;
						r_push_internal = 0;
						r_push_external = 0;
						new_wall_face_axis = 1;
					end
				end else begin
					// x_corner += dx_signs.*room_pos + plane_mask_signs.*axis_sizes
					room_pos_en = 1; room_pos_inv = dx_signs;
					dxc_en = '1; dxc_inv = ~plane_mask; dxc_half = '1;
				end

				if (MAX_DEPTH >= 0 && depth == MAX_DEPTH) next_wall_hit = 1; // TODO: update for trace_state_rs?
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
						dxc_half = 'X;
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

					interlace_op = 1;
				end
			end
		end else begin
			if (ack_hit) next_wall_hit = 0;
			if (ascend) begin
				// Can we skip two levels at once?
				if (!((target_depth == depth) && (target_level == (level & ~1)))) eff_level[0] = 0;

				update_dom_from_old_dom = (level == LEVEL_SIDE2);
				if (target_depth != depth) begin
					r_pop = 1;
					change_room = 1;
					next_level = LEVEL_SIDE2;

					next_part_two = 1;
					if (!part_two) begin
						// Start ascending: subtract corner position
						// x_corner -= dx_signs.*room_pos + axis_sizes.*corner_signs
						room_pos_en = 1; room_pos_inv = ~dx_signs;
						dxc_en = '1; dxc_inv = ~corner_signs; dxc_half = '1;
					end else begin
						// part_two == 1
						// just keep ascending one depth level
					end
				end else begin
					// target_depth == depth
					next_part_two = 0;

					if (part_two) begin
						// Finish ascending
						next_level = target_level;
						update_dom_from_old_dom = (target_level != LEVEL_SIDE2);

						// add new corner position
						// x_corner += dx_signs.*room_pos + axis_sizes.*corner_signs
						room_pos_en = 1; room_pos_inv = dx_signs;
						dxc_en = '1; dxc_inv = corner_signs; dxc_half = '1;
						if (depth == 0 && target_level[2]==0) begin
							// Go back to initial state
							dxc_en = '0;
							xc_inv = dx_signs;
							room_pos_inv = '0;
						end
					end else begin
						// transition within one depth level
						next_level = eff_level - 1; // OPT: share with level + 1
						if (eff_level == LEVEL_SIDE1) begin
							if (depth == 0) next_level = LEVEL_DX_SIGN_2; // also un-offset corner based on dx_signs, done below
							else next_level = LEVEL_CORNER_X2_2;
						end

						if (depth != 0) begin
							case (eff_level)
								LEVEL_CORNER_X3_2+1: begin
									// x3 <- x2
									dxc_en = plane_mask;
									dxc_inv = '0;
								end
								//LEVEL_CORNER_X2_2+1: begin
								LEVEL_SIDE1: begin
									if (target_depth == depth && (target_level&~1)==LEVEL_CORNER_X2_1) begin
										// x2 <- x4
										dxc_en = '1;
										dxc_inv = '1;
									end else begin
										// x3 <- x4
										next_level = LEVEL_CORNER_X3_2;
										dxc_en = ~plane_mask;
										dxc_inv = '1;
									end
								end
								default: begin
									dxc_en = '0;
									dxc_inv = 'X;
									dxc_half = 'X;
								end
							endcase

							if (target_level[0] == 0) next_level[0] = 0; // shortcut: no difference between levels that only differ in LSB
						end else begin // depth == 0
							if (eff_level == LEVEL_SIDE1) begin
								// Remove initial offset from corner
								//x_corner = (x_corner - axis_sizes) .* dx_signs
								xc_inv = dx_signs; // dx_signs_in does not work, it can have changed before we start to ascend.
								dxc_en = '1;
								dxc_inv = ~xc_inv;
								dxc_half = '1;

								interlace_op = 1;
							end
						end
					end
				end

			end
		end

		next_depth = depth + r_push_internal - r_pop; // OPT

		if (override_en) begin
			change_room = override_change_room;
			xc_inv = override_xc_inv;
			dxc_en = override_dxc_en;
			dxc_inv = override_dxc_inv;
			dxc_half = override_dxc_half;
			room_pos_en = override_room_pos_en;
			room_pos_inv = override_room_pos_inv;
		end
	end

	wire [X_BITS-1:0] x_corner_init[3];
	wire [X_BITS-1:0] room_pos[3];
	assign {x_corner_init[2], x_corner_init[1], x_corner_init[0]} = x_corner_initial;
	assign {room_pos[2], room_pos[1], room_pos[0]} = room_pos_in;

	wire [X_BITS-1:0] room_pos_e0 = room_pos[0];
	wire [X_BITS-1:0] room_pos_e1 = room_pos[1];
	wire [X_BITS-1:0] room_pos_e2 = room_pos[2];

	generate
		for (i = 0; i < 3; i++) begin

			wire [X_BITS-1:0] delta_xc_0 = dxc_half[i] ? axis_sizes[i] : (axis_sizes[i] << 1);
			wire [X_BITS-1:0] delta_xc_1 = dxc_en[i] ? delta_xc_0 : '0;

			wire [X_BITS-1:0] room_pos_0 = room_pos_en ? room_pos[i] : 0;
/*
			wire [X_BITS-1:0] delta_xc_1 = dxc_inv[i] ? ~delta_xc_0 : delta_xc_0;
			wire [X_BITS-1:0] delta_xc_2 = dxc_en[i] ? delta_xc_1 : '0;

			wire [X_BITS-1:0] xc = xc_inv[i] ? ~x_corner[i] : x_corner[i];
			wire [X_BITS-1:0] next_x_corner = xc + delta_xc_2 + (dxc_en[i] && (dxc_inv[i] || xc_inv[i]));
*/
			
			logic force_carry_in_xy_low, force_carry_in_z_high;
			always_comb begin
				force_carry_in_xy_low = 0;
				force_carry_in_z_high = 0;
				if (interlace_op && interlace_mask[i]) begin
					if (xc_inv[i] == ascend) force_carry_in_z_high = 1;
					else force_carry_in_xy_low = 1;
				end
			end

			wire [X_BITS-1:0] next_x_corner;
			three_term_adder #(.BITS(X_BITS)) xc_adder(
				.x(x_corner[i]), .neg_x(xc_inv[i]),
				.y(delta_xc_1),  .neg_y(dxc_inv[i] & dxc_en[i]),     // mask with en to avoid X in simulation when en=0 but inv=X
				.z(room_pos_0),  .neg_z((room_pos_inv[i] ^ mirroring[i]) & room_pos_en), // mask with en to avoid X in simulation when en=0 but inv=X
				.force_carry_in_xy_low(force_carry_in_xy_low), .force_carry_in_z_high(force_carry_in_z_high),
				.sum(next_x_corner)
			);

			always_ff @(posedge clk) begin
				if (reset) begin
					x_corner[i] <= x_corner_init[i];
				end else begin
					x_corner[i] <= next_x_corner;
				end
			end

			assign axis_sizes_out_arr[i] = axis_sizes[i];
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
			wall_face_axis <= 'X;
			axis_1_dom_0 <= 'X;
			old_dom <= 'X;
			wall_hit <= 0;
			room <= room_initial;
			part_two <= 0;
		end else begin
			depth <= next_depth;
			level <= next_level;
			if (r_pop) begin
				face_axis <= prev_face_axis;
				old_dom <= prev_old_dom;
			end else begin
				//face_axis <= next_face_axis;
				//axis_1_dom_0 <= next_axis_1_dom_0;
			end
			wall_hit <= next_wall_hit;

			if (change_room) room <= neighbor_room;
			part_two <= next_part_two;

			if (descend) begin
				//if (depth == 0 && level == LEVEL_DX_SIGN_2) dx_signs <= dx_signs_in;
				if (level == LEVEL_SIDE1) begin
					old_dom <= axis_1_dom_0;
					axis_1_dom_0 <= descend_decision[0];
				end
				if (update_face_axis) begin
					face_axis <= new_face_axis;
				end
			end else if (ascend) begin
				// Don't use eff_level here, LEVEL_SIDE2 is odd
				//if (level == LEVEL_SIDE2) axis_1_dom_0 <= old_dom;
				if (update_dom_from_old_dom) axis_1_dom_0 <= old_dom;
			end

			if (next_wall_hit && !wall_hit) begin
				if (new_wall_face_axis || update_face_axis) wall_face_axis <= new_face_axis;
				else wall_face_axis <= face_axis;
			end

			//if (override_en) face_axis <= override_next_face_axis;
		end
	end


	assign depth_out = depth;
	assign level_out = level;
	assign room_out = room;
	assign room_dir_signs_out = ascend && !override_en ? ~dx_signs : dx_signs;
	//assign room_dir_axis_out  = ascend || override_en ? face_axis : new_face_axis;
	assign room_dir_axis_out = override_en ? override_next_face_axis : (ascend ? face_axis : new_face_axis);
	assign x_corner_out = {x_corner[2], x_corner[1], x_corner[0]};
	assign axis_sizes_out = {axis_sizes_out_arr[2], axis_sizes_out_arr[1], axis_sizes_out_arr[0]};
	assign face_axis_out = face_axis;
	assign wall_face_axis_out = wall_face_axis;
	assign axis_1_dom_0_out = axis_1_dom_0;
	assign old_dom_out = old_dom;
	assign wall_hit_out = wall_hit;

	assign working = part_two;
	assign next_working = next_part_two;

	assign push = r_push_external; assign pop = r_pop;
endmodule : trace_state_rs
