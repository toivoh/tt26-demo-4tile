/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

module subdiv_pl_tracer #(
		`propagated_parameter_definitions, `derived_parameter_definitions,
		USE_JUMPER=1
	) (
		input wire clk, reset, reset_dxf, reset_i_d2,
		input wire hurry,

		input wire [`CTRL_FLAG_BITS-1:0] ctrl_flags,
		input wire [`SCENE_FLAG_BITS-1:0] scene_flags,
		input wire consume_pixel,
		input wire [`FRAME_T_BITS-1:0] frame_t,
		input wire [2:0] interlace_mask,

		input wire [POS_BITS-1:0] i_d2_init, i2_init,

		// For free view
		input wire [DX_BITS-1:0] dxf_x_in, dxf_y_in, dxf_z_in,
		input wire signed [DDX_BITS-1:0] ddx_x_in, ddx_y_in, ddx_z_in,

`ifdef USE_OLD_TRACE_STATE
		input wire [3*X_BITS-1:0] x_corner_initial, // stacked
		input wire [3*X_BITS-1:0] axis_sizes_initial, // stacked
`else
		input wire reset_nav, start_fix, start_adjust,

		input wire [3*X_BITS-1:0] curr_x_initial_stacked,
		input wire [ROOM_BITS-1:0] curr_room_initial,
		input wire tstate_override_en,
		input wire [3*X_BITS-1:0] delta_x_stacked,
`endif


		// The external overrides take effect when reset is high
		input wire update_dx_ext, update_dx1_ext, next_update_dx1_ext,
		input wire [2:0] ddx_sign_ext, update_dx_ext_mask,
		input wire [N_BITS-1:0] ddx_shl_ext,


		//output wire done,

		input wire ack_emit, // the rest of the emit interface is in `subdiv_tracer_output_definitions

		// Outputs from subdiv_tracer that need to be forwarded to the top wrapper, for emit and debug
		`subdiv_tracer_output_definitions,

		output wire use_jumper
	);
	assign use_jumper = USE_JUMPER;

	// Forward inputs needed to debug how the subdivider is started
	assign subdiv_tracer_reset_out = reset;
	assign dxf_out = {dxf_z_in, dxf_y_in, dxf_x_in};
	assign ddx_out = {ddx_z_in, ddx_y_in, ddx_x_in};
`ifdef USE_OLD_TRACE_STATE
	assign axis_sizes_initial_out = axis_sizes_initial;
`else
	assign axis_sizes_initial_out = 'X;
`endif


	localparam FA_STACK_DEPTH = MAX_DEPTH+1; // OPT: Does it need to be this much? It's only about 2-3 FFs, though...
	genvar i;


	//wire curr_decision;
	//wire curr_hit;


	// Subdivider
	// ==========

	//wire subdiv_en;

	wire [TAG_BITS-1:0] curr_tag;

	// Use curr_decision = {dx_signs, ang_leq_decision} to get a multibit decision for dx_signs and also store dx_signs in d1[3:1]
	wire [DECISION_BITS-1:0] decision_mask = (depth == 0 && level[2] == 0) ? 4'b1110 : 4'b0001;

//	wire descend, ascend;
	wire ascending;
//	wire [TAG_BITS-1:0] target_tag;

	wire decision_side;
	wire [POS_BITS-1:0] i_dx, i_dx2;
	//wire descend_decision;
	wire update_dx1_subdiv, next_update_dx1_subdiv;
	wire update_dx2_subdiv, ddx2_sign_subdiv;
	wire [N_BITS-1:0] ddx2_shl_subdiv;
	wire [DECISION_BITS-1:0] d1;
	wire restart_from_top;
	subdivider_pl #(.POS_BITS(POS_BITS), .LEVEL_BITS(DEPTH_BITS+LEVEL_BITS), .DECISION_BITS(DECISION_BITS), .STACK_DEPTH(STACK_DEPTH), .TAG_BITS(TAG_BITS)) subdiv_inst(
		.clk(clk), .reset(reset), .reset_i_d2(reset_i_d2), .en(subdiv_en),
		.ctrl_flags(ctrl_flags), .consume_pixel(consume_pixel),
		.i_d2_init(i_d2_init), .i2_init(i2_init),

		.emit(emit), .ack_emit(ack_emit),
		.i1_emit(i1_emit), .length_m1_emit(length_m1_emit), .i2_emit(i2_emit),
		.curr_tag(curr_tag), .ascend(ascend), .ascending(ascending), .adjusting_out(adjusting), .descend(descend), .descend_decision(descend_decision), .target_tag(target_tag),
		.restart_from_top(restart_from_top),

		.i_d_out(i_dx), .i_d2_out(i_dx2), .decision_side_out(decision_side),
//		.update_dx_ext(update_dx_ext), .ddx_sign_ext(ddx_sign_ext), .ddx_shl_ext(ddx_shl_ext),
		.update_dx1(update_dx1_subdiv), .next_update_dx1(next_update_dx1_subdiv), .update_dx2(update_dx2_subdiv), .ddx2_sign(ddx2_sign_subdiv), .ddx2_shl(ddx2_shl_subdiv),

		.curr_decision(curr_decision), .decision_mask(decision_mask), .curr_hit(curr_hit), .accept_hit(accept_hit), .d1_out(d1),

		.level_out(subdivider_level), .state_out(subdiv_state), .line_done_out(line_done), .stack_pointer_out(stack_pointer_out), .stack_depth_out(stack_depth_out)
	);

	assign updating_i_d2 = update_dx2_subdiv;


	wire lock_dx2_update = ctrl_flags[`CTRL_FLAG_LOCK_DX2_UPDATE];

/*
	wire update_dx2 = reset ? update_dx_ext : update_dx2_subdiv;
	wire ddx2_sign = reset ? ddx_sign_ext : ddx2_sign_subdiv;
	wire [N_BITS-1:0] ddx_shl = reset ? ddx_shl_ext : ddx2_shl_subdiv;
*/
/*
	wire update_dx2 = update_dx2_subdiv;
	wire ddx2_sign = ddx2_sign_subdiv;
	wire [N_BITS-1:0] ddx_shl = ddx2_shl_subdiv;
*/
	wire dx2_ext_en = reset && update_dx_ext;

/*
	wire update_dx2 = dx2_ext_en ? update_dx_ext : (lock_dx2_update ? consume_pixel : update_dx2_subdiv);
	//wire ddx2_sign = dx2_ext_en ? ddx_sign_ext : ddx2_sign_subdiv;
	wire [N_BITS-1:0] ddx_shl = dx2_ext_en ? ddx_shl_ext : (lock_dx2_update ? 0 : ddx2_shl_subdiv);
	wire [2:0] update_dx2_sign = dx2_ext_en ? ddx_sign_ext : {3{lock_dx2_update ? 1'b0 : ddx2_sign_subdiv}};
*/
	logic update_dx2;
	logic [N_BITS-1:0] ddx_shl;
	logic [2:0] update_dx2_sign;
	always_comb begin
		if (dx2_ext_en) begin
			update_dx2 = update_dx_ext;
			ddx_shl = ddx_shl_ext;
			update_dx2_sign = ddx_sign_ext;
		end else begin
			update_dx2 = update_dx2_subdiv;
			ddx_shl = ddx2_shl_subdiv;
			update_dx2_sign = {3{ddx2_sign_subdiv}};
		end

/*
		if (!reset && lock_dx2_update) begin
			update_dx2 = consume_pixel;
			ddx_shl = 0;
			update_dx2_sign = 0;
		end
*/
	end


	wire update_dx1 = reset ? update_dx1_ext : update_dx1_subdiv;
	wire next_update_dx1 = reset ? next_update_dx1_ext : next_update_dx1_subdiv;

	// TODO: is this ok for the initial stepping of dx2?
	wire [N_BITS-1:0] n_trailing;
	calc_step_index #(.BITS(POS_BITS), .N_MAX(MAX_LOG_N)) calc_index(
		.i(i_dx2), .n(ddx_shl),
		//.sign(ddx2_sign),
		.sign(ddx2_sign_subdiv),
		//.sign(!reset && lock_dx2_update ? 0 : ddx2_sign_subdiv),
		.index(n_trailing)
	);


	// dx state
	// --------

	localparam DXF_BITS = DX_BITS + DXF_FRAC_BITS;

//	(* mem2reg *) reg signed [DXF_BITS-1:0] dxf[3];
	wire signed [DX_BITS-1:0] dxf_in[3];
	assign dxf_in[0] = dxf_x_in;
	assign dxf_in[1] = dxf_y_in;
	assign dxf_in[2] = dxf_z_in;
	wire signed [DDX_BITS-1:0] ddx[3];
	assign ddx[0] = ddx_x_in;
	assign ddx[1] = ddx_y_in;
	assign ddx[2] = ddx_z_in;

/*
	generate
		for (i = 0; i < 3; i++) begin
			wire signed [DXF_BITS-1:0] ddx_ext = ddx[i];
			always_ff @(posedge clk) begin
				if (reset_dxf) begin
					dxf[i] <= {dxf_in[i], {DXF_FRAC_BITS{1'b0}}};
				end else begin
					if (update_dx2) begin
						dxf[i] <= dxf[i] + ((ddx_ext << ddx_shl) ^ (ddx2_sign ? '1 : 0)) + ddx2_sign;
					end
				end
			end
		end
	endgenerate
*/

	localparam DDXE_BITS = DDX_BITS + MAX_LOG_N - DXF_FRAC_BITS;

	//(* mem2reg *) reg signed [DX_BITS-1:0] dx1[3];
	wire signed [DX_BITS-1:0] dx1[3];

	wire signed [DX_BITS-1:0] dx2[3];
	generate
		for (i = 0; i < 3; i++) begin
			wire signed [DDXE_BITS-1:0] ddxe = {ddx[i], {(MAX_LOG_N - DXF_FRAC_BITS){1'b0}}};
			jumper #(.BITS(DX_BITS), .DELTA_BITS(DDXE_BITS), .RSHIFT(MAX_LOG_N)) jumper_inst(
				.clk(clk), .reset(reset_dxf),
				.acc_initial(dxf_in[i]),
				.delta(ddxe),
				.do_update(update_dx2 && (!reset || update_dx_ext_mask[i])), .update_shl(ddx_shl),
				.update_sign(update_dx2_sign[i]),
				.extra_term_en(!dx2_ext_en),
				//.extra_term_index(reset ? ddx_shl_ext : n_trailing),
				.extra_term_index(n_trailing),
				.acc_out(dx2[i])
			);

			always_ff @(posedge clk) begin
/*
				if (reset) begin
					dx1[i] <= dxf_in[i]; // TODO: What should the init value be?
				end else begin
					if (update_dx1_subdiv) dx1[i] <= dx2[i];
				end
*/
				//if (update_dx1) dx1[i] <= dx2[i];
			end

			p_latch_register #(.BITS(DX_BITS)) dx1_register(.clk(clk), .reset('0), .we(update_dx1), .next_we(next_update_dx1), .reset_wdata('0), .wdata(dx2[i]), .rdata(dx1[i]), .next_wdata('X));
		end
	endgenerate




	// Room navigator
	// ==============
	wire [3*X_BITS-1:0] x_corner_stacked;
	wire reset_room_state;

`ifndef USE_OLD_TRACE_STATE
	wire [3*X_BITS-1:0] x_corner_initial;
	wire [ROOM_BITS-1:0] room_initial;
	wire [1:0] override_next_face_axis;
	wire [2:0] override_dx_signs;
	wire override_change_room, override_room_pos_en;
	wire [2:0] override_xc_inv, override_dxc_en, override_dxc_inv, override_dxc_half, override_room_pos_inv;
	wire override_axis_sizes_en;

	room_navigator #(.X_BITS(X_BITS), .ROOM_X_BITS(ROOM_X_BITS), .ROOM_BITS(ROOM_BITS)) navigator (
		.clk(clk), .reset(reset_nav),
		.start_fix(start_fix), .start_adjust(start_adjust),

		.working(nav_working),

		.curr_x_initial_stacked(curr_x_initial_stacked), .curr_room_initial(curr_room_initial),
		.x_corner_stacked(x_corner_stacked), .room(room),

		.x_corner_initial(x_corner_initial), .room_initial(room_initial),
		.next_face_axis(override_next_face_axis), .dx_signs(override_dx_signs), .change_room(override_change_room),
		.xc_inv(override_xc_inv), .dxc_en(override_dxc_en), .dxc_inv(override_dxc_inv), .dxc_half(override_dxc_half),
		.room_pos_en(override_room_pos_en), .room_pos_inv(override_room_pos_inv),
		.override_axis_sizes_en(override_axis_sizes_en), .reset_room_state(reset_room_state)
	);
`else
	assign nav_working = 0;
	assign reset_room_state = 0;
	wire [3*X_BITS-1:0] x_corner_initial = 0;
	wire [ROOM_BITS-1:0] room_initial = 0;
`endif

	assign x_corner_initial_out = x_corner_initial;
	assign room_initial_out = room_initial;

	// Trace state
	// ===========

	wire do_ascend;

	wire [X_BITS-1:0] x_corner[3];
	assign {x_corner[2], x_corner[1], x_corner[0]} = x_corner_stacked;
	assign x_corner_0 = x_corner[0];
	assign x_corner_1 = x_corner[1];
	assign x_corner_2 = x_corner[2];

	wire [3*X_BITS-1:0] axis_sizes_stacked;
`ifdef USE_OLD_TRACE_STATE
	wire [3*X_BITS-1:0] axis_sizes_stacked_eff = axis_sizes_stacked;
`else
	wire [3*X_BITS-1:0] axis_sizes_stacked_eff = (tstate_override_en && override_axis_sizes_en) ? delta_x_stacked : axis_sizes_stacked;
`endif

	wire [X_BITS-1:0] axis_sizes[3];
	assign {axis_sizes[2], axis_sizes[1], axis_sizes[0]} = axis_sizes_stacked_eff;
	assign axis_sizes_0 = axis_sizes[0];
	assign axis_sizes_1 = axis_sizes[1];
	assign axis_sizes_2 = axis_sizes[2];

/*
	// not a register
	(* mem2reg *) reg [DX_BITS-1:0] dx[3];
	always_comb begin
		if (use_free_view) begin
			//if (USE_JUMPER) begin
				dx[0] = dxj[0];
				dx[1] = dxj[1];
				dx[2] = dxj[2];
			end else begin
				dx[0] = dxf[0] >> DXF_FRAC_BITS;
				dx[1] = dxf[1] >> DXF_FRAC_BITS;
				dx[2] = dxf[2] >> DXF_FRAC_BITS;
			end
		end else begin
			dx[0] = i_dx - 256; // TODO
			dx[1] = dx_y_in;
			dx[2] = dx_z_in;
		end
	end
*/

	//wire [DX_BITS-1:0] dx[3];
	//assign {dx[2], dx[1], dx[0]} = dx_in;

	assign dx1_e0 = dx1[0];
	assign dx1_e1 = dx1[1];
	assign dx1_e2 = dx1[2];

	assign dx2_e0 = dx2[0];
	assign dx2_e1 = dx2[1];
	assign dx2_e2 = dx2[2];

	wire signed [DX_BITS-1:0] dx[3];
	assign dx[0] = decision_side ? dx2[0] : dx1[0];
	assign dx[1] = decision_side ? dx2[1] : dx1[1];
	assign dx[2] = decision_side ? dx2[2] : dx1[2];

	assign dx_e0 = dx[0];
	assign dx_e1 = dx[1];
	assign dx_e2 = dx[2];

	wire [2:0] dx_signs = {dx[2][DX_BITS-1], dx[1][DX_BITS-1], dx[0][DX_BITS-1]};
	//assign dx_signs_td = {dx_signs[2:1], descend_decision};
	//assign dx_signs_td = dx_signs;

	// sign-magnitude conversion
	wire [DX_BITS-1:0] dx_sm[3];
	generate
		for (i = 0; i < 3; i++) assign dx_sm[i] = dx[i] ^ (dx[i][DX_BITS-1] ? {(DX_BITS-1){1'b1}} : '0);
	endgenerate


	assign dx_signs_td = d1[3:1];


`ifndef USE_OLD_TRACE_STATE
//	wire [`SCENE_FLAG_BITS-1:0] scene_flags = (1 << `SCENE_FLAG_CEIL_DEC) | (1 << `SCENE_FLAG_BLOCKAGES);
//	wire [`SCENE_FLAG_BITS-1:0] scene_flags = frame_t >> 6; // alternate for now to exercise the flag
//	wire [`SCENE_FLAG_BITS-1:0] scene_flags = (1 << `SCENE_FLAG_CEIL_DEC) | (1 << `SCENE_FLAG_BLOCKAGES) | (1 << `SCENE_FLAG_PORTALS);
//	wire [`SCENE_FLAG_BITS-1:0] scene_flags = (1 << `SCENE_FLAG_ALT_HEIGHTS);

//	wire [X_BITS-1:0] main_w = 256, sub_w = 256;
//	wire [X_BITS-1:0] main_w = 256-64, sub_w = 256+64;
//	wire [X_BITS-1:0] main_w = 256+64, sub_w = 256-64;

	logic [X_BITS-1:0] main_w, sub_w;
	always_comb begin
		if (scene_flags[`SCENE_FLAG_NARROW]) begin
			main_w = 256-96; sub_w = 256+96;
		end else begin
			main_w = 256; sub_w = 256;
		end
	end


	//wire [ROOM_BITS-1:0] room;
	wire [2:0] room_dir_signs;
	wire [1:0] room_dir_axis;

	//wire [3*X_BITS-1:0] axis_sizes_stacked;
	wire [3*X_BITS-1:0] room_pos_stacked;
	wire [ROOM_BITS-1:0] neighbor_room;
	wire [2:0] mirroring;
//	scene #(.ROOM_BITS(ROOM_BITS), .X_BITS(X_BITS)) scene_inst(
	scene1 #(.ROOM_BITS(ROOM_BITS), .X_BITS(X_BITS)) scene_inst(
		.scene_flags(scene_flags),
		.main_w(main_w), .sub_w(sub_w),
		.main_d(main_w), .sub_d(sub_w),
		.room(room), .room_dir_signs(room_dir_signs), .room_dir_axis(room_dir_axis),
		.axis_sizes(axis_sizes_stacked), .room_pos(room_pos_stacked), .neighbor_room(neighbor_room),
		.mirroring(mirroring)
	);

	assign {room_pos_2, room_pos_1, room_pos_0} = room_pos_stacked;
`endif



	reg prev_descend;
	always_ff @(posedge clk) begin
		prev_descend <= descend;
	end

	wire [1:0] prev_face_axis;
	wire prev_old_dom;

	wire [DEPTH_BITS-1:0] target_depth;
	wire [LEVEL_BITS-1:0] target_level;

	wire push, pop;
	wire wall_hit;
	wire trace_state_working;
`ifdef USE_OLD_TRACE_STATE
	assign trace_state_working = 0;
	assign wall_face_axis = face_axis;
	trace_state #(
`else
	trace_state_rs #(
		.ROOM_BITS(ROOM_BITS),
`endif
		.X_BITS(X_BITS), .DEPTH_BITS(DEPTH_BITS), .LEVEL_BITS(LEVEL_BITS), .MAX_DEPTH(MAX_DEPTH),
		.AXIS_SIZES_BITS(AXIS_SIZES_BITS), .AXIS_SIZES_LSB_SKIP(AXIS_SIZES_LSB_SKIP)
	) trace_state_inst(
		.clk(clk), .reset(reset || reset_room_state || (restart_from_top && !tstate_override_en)), // TODO: is restart_from_top always valid when !tstate_override_en?

`ifdef USE_OLD_TRACE_STATE
		.axis_sizes_initial(axis_sizes_initial),

		.axis_sizes_out(axis_sizes_stacked),
`else
		.room_initial(room_initial),

		.room_out(room), .room_dir_signs_out(room_dir_signs), .room_dir_axis_out (room_dir_axis),
		.axis_sizes_in(axis_sizes_stacked_eff), .room_pos_in(room_pos_stacked), .neighbor_room(neighbor_room), .mirroring(mirroring),
		.working(trace_state_working),

		.ack_hit(ascending),
		.wall_face_axis_out(wall_face_axis),
`endif

		.x_corner_initial(x_corner_initial),

		.descend(descend || (trace_state_working && prev_descend)), .ascend(do_ascend),
		.interlace_mask(interlace_mask),

`ifdef USE_OLD_TRACE_STATE
		.override_en(0), .override_next_face_axis('X), .override_change_room('X), .override_xc_inv('X), .override_dxc_en('X), .override_dxc_inv('X), .override_dxc_half('X), .override_room_pos_en('X), .override_room_pos_inv('X),
`else
		.override_en(tstate_override_en),
		.override_next_face_axis(override_next_face_axis), .override_change_room(override_change_room),
		.override_xc_inv(override_xc_inv), .override_dxc_en(override_dxc_en), .override_dxc_inv(override_dxc_inv), .override_dxc_half(override_dxc_half),
		.override_room_pos_en(override_room_pos_en), .override_room_pos_inv(override_room_pos_inv),
`endif

		//.dx_signs_in(dx_signs_td),
`ifdef USE_OLD_TRACE_STATE
		.dx_signs(dx_signs_td),
`else
		.dx_signs(tstate_override_en ? override_dx_signs : dx_signs_td),
`endif
		.descend_decision(descend_decision),
		.prev_face_axis(prev_face_axis), .prev_old_dom(prev_old_dom), .target_depth(target_depth), .target_level(target_level),

		.depth_out(depth), .level_out(level), .x_corner_out(x_corner_stacked),
		.face_axis_out(face_axis), .axis_1_dom_0_out(dom), .old_dom_out(old_dom), .wall_hit_out(wall_hit),

		.push(push), .pop(pop)
	);

	// hurry forces a wall hit to return and move on.
	// No point in forcing a hit while ascending, the emit will just get lost.
	//assign curr_hit = wall_hit || (!ascending && hurry && (n_emit <= LOG_N_HURRY_THRESH));
	assign curr_hit = wall_hit || (accept_hit && hurry && (length_m1_emit <= 2**LOG_N_HURRY_THRESH));
	assign forced_hit = curr_hit && !wall_hit;

	// Descend / ascend control
	// ------------------------
	assign curr_tag = {depth, level};
	//assign do_ascend = ascend && curr_tag != target_tag;
	//assign subdiv_en = !do_ascend;

	wire need_ascend = ascend && (curr_tag != target_tag || trace_state_working);
	assign do_ascend = need_ascend && !(emit && !ack_emit);

	assign {target_depth, target_level} = target_tag;

	wire emit_en = !emit || ack_emit;
	assign subdiv_en = !need_ascend && !trace_state_working && emit_en;

	// Stack for (dom, face_axis)
	// --------------------------
`ifdef COMPRESS_FA_STACK
	localparam FA_STACK_ENTRY_BITS = 2;
	wire [1:0] fa_stack_push_value = face_axis | old_dom;
	wire [1:0] fa_stack_pop_value;
	assign prev_old_dom = fa_stack_pop_value[0];

	assign prev_face_axis[0] = fa_stack_pop_value[0] && (fa_stack_pop_value != 3); // fa_stack_pop_value == 3 ==> prev_face_axis = 2
	assign prev_face_axis[1] = fa_stack_pop_value[1];
`else
	localparam FA_STACK_ENTRY_BITS = 3;
	wire [2:0] fa_stack_push_value = {old_dom, face_axis};
	wire [2:0] fa_stack_pop_value;
	assign {prev_old_dom, prev_face_axis} = fa_stack_pop_value;
`endif

/*
	(* mem2reg *) reg [FA_STACK_ENTRY_BITS-1:0] face_axis_stack[FA_STACK_DEPTH]; // TODO: reduce to 2 bits per entry
	wire [FA_STACK_ENTRY_BITS-1:0] face_axis_stack_pop[FA_STACK_DEPTH+1]; // (Usually) need an extra element here since `depth` will be one step greater when popping compared to the corresponding push

	always_ff @(posedge clk) begin
		// depth+1 since depth is not increased until after push
		if (push) face_axis_stack[depth] <= fa_stack_push_value;
		//if (pop) face_axis_stack[depth];
	end
	//assign {prev_old_dom, prev_face_axis} = face_axis_stack[(depth-1)&((1 << DEPTH_BITS) - 1)];
	for (i = 0; i < FA_STACK_DEPTH; i++) assign face_axis_stack_pop[(i+1)&((1 << DEPTH_BITS) - 1)] = face_axis_stack[i];
	assign fa_stack_pop_value = face_axis_stack_pop[depth];

	// Set the leftover entry to 'X; we will not pop from it
	assign face_axis_stack_pop[FA_STACK_DEPTH >= 2**DEPTH_BITS ? FA_STACK_DEPTH : 0] = 'X;
*/

	np_latch_ram #(.NUM_ADDR(FA_STACK_DEPTH), .DATA_BITS(FA_STACK_ENTRY_BITS), .READ_OFFSET_TRUNC(1), .ADDR_BITS(DEPTH_BITS)) face_axis_stack_latches(
		.clk(clk), .reset(reset),
		.addr(depth),
		.we(push), .wdata(fa_stack_push_value),
		.rdata(fa_stack_pop_value)
	);


	// Decision
	// ========

	wire [1:0] decision_axis;
	wire invert_decision;

	trace_decision_choice trace_decision_choice_inst(
		.side_en(level[2]), .sub_case(level[1:0]), // mapping depends on how level is encoded
		.dom(dom), .face_axis(face_axis),
		.decision_axis_out(decision_axis), .invert_decision_out(invert_decision)
	);

	wire raw_decision;
	ang_leq #(.BITS_X(X_BITS-1-DET_RED_X), .BITS_Y(DX_BITS-1-DET_RED_DX), .BITS_N(DYNAMIC_RSHIFT_BITS)) ang_leq_inst(
		.x1(x_corner[0]>>DET_RED_X), .x2(x_corner[1]>>DET_RED_X), .x3(x_corner[2]>>DET_RED_X),
		.y1(dx_sm[0][DX_BITS-2:0]>>DET_RED_DX), .y2(dx_sm[1][DX_BITS-2:0]>>DET_RED_DX), .y3(dx_sm[2][DX_BITS-2:0]>>DET_RED_DX),
		.axis(decision_axis),
		.sign(raw_decision)
	);
	wire ang_leq_decision = raw_decision ^ invert_decision;

	//wire dx_sign_decision = dx_signs[level];

	//assign curr_decision = (depth == 0 && level <= 3) ? dx_sign_decision : ang_leq_decision;
	assign curr_decision = {dx_signs, ang_leq_decision};
	//assign done = 0; // TODO
endmodule : subdiv_pl_tracer
