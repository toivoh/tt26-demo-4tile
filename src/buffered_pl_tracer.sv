/*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

module buffered_pl_tracer #(
		`propagated_parameter_definitions,
		`derived_parameter_definitions
	) (
		input wire clk, reset, reset_dxf, reset_i_d2,
		input wire [`CTRL_FLAG_BITS-1:0] ctrl_flags,
		input wire [`SCENE_FLAG_BITS-1:0] scene_flags,
		input wire [`FRAME_T_BITS-1:0] frame_t,
		input wire [8:0] y,
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


		input wire [VALUE_BITS-1:0]  initial_value,
		input wire [LENGTH_BITS-1:0] initial_length,

		input wire consume_pixel,
		//output wire consume_pixel,

		// Outputs from buffered_tracer that need to be forwarded to the top wrapper, for emit and debug
		`buffered_tracer_output_definitions
	);

	// Tracer
	// ------
	//wire ack_emit;
	subdiv_pl_tracer #( `parameters_forward ) tracer(
		.clk(clk), .reset(reset), .reset_dxf(reset_dxf), .reset_i_d2(reset_i_d2),
		.hurry(hurry),
		.ctrl_flags(ctrl_flags), .scene_flags(scene_flags), .consume_pixel(consume_pixel), .frame_t(frame_t), .interlace_mask(interlace_mask),

		.i_d2_init(i_d2_init), .i2_init(i2_init),
		.update_dx_ext(update_dx_ext), .update_dx1_ext(update_dx1_ext), .next_update_dx1_ext(next_update_dx1_ext), .ddx_shl_ext(ddx_shl_ext), .ddx_sign_ext(ddx_sign_ext), .update_dx_ext_mask(update_dx_ext_mask),
		.dxf_x_in(dxf_x_in), .dxf_y_in(dxf_y_in), .dxf_z_in(dxf_z_in), .ddx_x_in(ddx_x_in), .ddx_y_in(ddx_y_in), .ddx_z_in(ddx_z_in),
`ifdef USE_OLD_TRACE_STATE
		.x_corner_initial(x_corner_initial),
		.axis_sizes_initial(axis_sizes_initial),
`else
		.reset_nav(reset_nav), .start_fix(start_fix), .start_adjust(start_adjust),

		.curr_x_initial_stacked(curr_x_initial_stacked), .curr_room_initial(curr_room_initial),
		.tstate_override_en(tstate_override_en), .delta_x_stacked(delta_x_stacked),
`endif
		.ack_emit(ack_emit),

		`subdiv_tracer_output_forward
	);


	// Shading
	// -------
	wire [1:0] value_emit_a = ~wall_face_axis;

`ifdef FPGA
	wire doffs = y[1];
`else
	wire doffs = y[0];
`endif

	wire fs = dx_signs_td[wall_face_axis];
	wire [1:0] fa_inv = ~wall_face_axis;

	//wire [2:0] shade = fs ? 1 + doffs + wall_face_axis : 6 + doffs - wall_face_axis;
	wire [2:0] shade = (fs ? 3 : 1) + doffs + (fs ? fa_inv : wall_face_axis);
	//wire [2:0] shade = (fs ? 3 : 0) + doffs + (fs ? fa_inv : wall_face_axis);
	//wire [2:0] shade = (fs ? 3 : 2) + doffs + (fs ? fa_inv : wall_face_axis);
	wire [1:0] value_emit_b = shade[2:1];

	assign value_emit = hurry ? 0 : (ctrl_flags[`CTRL_FLAG_ALT_SHADING] ? value_emit_b : value_emit_a);

	// Interval buffer
	// ---------------
	// TODO: better parameter values?
	interval_buffer2 #(.LENGTH_BITS(LENGTH_BITS), .SHORT_LENGTH_BITS(SHORT_LENGTH_BITS), .TAIL_LENGTH_BITS(TAIL_LENGTH_BITS), .QUEUE_SIZE(QUEUE_SIZE), .VALUE_BITS(VALUE_BITS)) ibuffer(
		.clk(clk), .reset(reset), .restart(0),

		.initial_value(initial_value), .initial_length(initial_length),
		.emit(emit), .length_m1_emit(length_m1_emit), .value_emit(value_emit), .ack_emit(ack_emit),
		.consume_pixel(consume_pixel), .curr_value(curr_value),
		.behind(hurry),
		.tail_index_out(tail_index_out)
	);

	assign consume_pixel_out = consume_pixel;
	assign initial_value_out = initial_value;
	assign initial_length_out = initial_length;
endmodule : buffered_pl_tracer
