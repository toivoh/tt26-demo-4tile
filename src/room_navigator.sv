/*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Note: The x position is the position of the room relative the viewer, not the viewer relative to the room ==> all signs are inverted.

module room_navigator #(
		X_BITS=8, ROOM_X_BITS=8, ROOM_BITS=8
	) (
		input wire clk, reset,
		input wire start_fix, start_adjust,

		input wire [3*X_BITS-1:0] curr_x_initial_stacked,
		input wire [ROOM_BITS-1:0] curr_room_initial,

		output wire working,

		output wire [3*X_BITS-1:0] x_corner_initial, // stacked
		output wire [ROOM_BITS-1:0] room_initial,

		output logic [1:0] next_face_axis, // actually override for room_dir_axis_out
		output logic [2:0] dx_signs,
		output logic change_room, room_pos_en,
		output logic [2:0] xc_inv, dxc_en, dxc_inv, dxc_half, room_pos_inv,

		output logic override_axis_sizes_en, // the outside needs to apply override_axis_sizes_en to supply delta values in axis_sizes

		output wire reset_room_state,

		input wire [3*X_BITS-1:0] x_corner_stacked,
		input wire [ROOM_BITS-1:0] room
	);

	localparam STATE_BITS = 3;
	localparam STATE_IDLE = 0;
	localparam STATE_TO_PLUS = 1;
	localparam STATE_CHECK_PLUS = 2;
	localparam STATE_CHECK_MINUS = 3;
	localparam STATE_FINISH_MOVE = 4;
	localparam STATE_STORE = 5;
	localparam STATE_ADJUST = 6;

	localparam STATE_CHECK_MASK = STATE_CHECK_PLUS ^ STATE_CHECK_MINUS;

	genvar i;


	wire [X_BITS-1:0] curr_x_initial[3];
	assign {curr_x_initial[2], curr_x_initial[1], curr_x_initial[0]} = curr_x_initial_stacked;

	wire [X_BITS-1:0] x_corner[3];
	assign {x_corner[2], x_corner[1], x_corner[0]} = x_corner_stacked;
	wire [X_BITS-1:0] xc_e0, xc_e1, xc_e2;
	assign {xc_e2, xc_e1, xc_e0} = x_corner_stacked;

	wire [2:0] xc_signs = {x_corner[2][X_BITS-1], x_corner[1][X_BITS-1], x_corner[0][X_BITS-1]};


	reg [STATE_BITS-1:0] state;

	//reg [ROOM_BITS-1:0] curr_room;
	//(* mem2reg *) reg signed [ROOM_X_BITS-1:0] curr_x[3];

	wire [ROOM_BITS-1:0] curr_room;
	wire signed [ROOM_X_BITS-1:0] curr_x[3];

	wire signed [X_BITS-1:0] curr_x_ext[3];
	for (i = 0; i < 3; i++) assign curr_x_ext[i] = curr_x[i];


	wire signed [X_BITS-1:0] curr_x_e0 = curr_x[0], curr_x_e1= curr_x[1], curr_x_e2 = curr_x[2];


	wire face_plus = (state & STATE_CHECK_MASK) == (STATE_CHECK_PLUS & STATE_CHECK_MASK);
	wire [2:0] check_signs = face_plus ? xc_signs : ~xc_signs;

	always_comb begin
		next_face_axis = 'X;
		casez (check_signs)
			3'bzz1: next_face_axis = 0;
			3'bz10: next_face_axis = 1;
			3'b100: next_face_axis = 2;
			default: next_face_axis = 'X;
		endcase
	end

	logic [STATE_BITS-1:0] next_state;
	logic next_update_curr_x, next_update_curr_room;
	always_comb begin
		next_state = 0;

		//next_face_axis = 'X;
		dx_signs = 'X;
		change_room = '0;
		xc_inv = '0;

		dxc_en = '0;
		dxc_inv = 'X;
		dxc_half = 'X;

		room_pos_en = '0;
		room_pos_inv = 'X;

		override_axis_sizes_en = 0;

		next_update_curr_x = 0;
		next_update_curr_room = 0;

		case (state)
			STATE_IDLE: begin
			end
			STATE_ADJUST: begin
				dxc_en = '1; dxc_inv = '0; dxc_half = '1;
				override_axis_sizes_en = '1;

				next_state = STATE_TO_PLUS; next_update_curr_x = 1;
			end
			STATE_TO_PLUS: begin
				// x += axis_sizes[curr_room]
				dxc_en = '1; dxc_inv = '0; dxc_half = '1;

				next_state = STATE_CHECK_PLUS;
			end
			STATE_CHECK_PLUS: begin
				if (|check_signs) begin
					//  if any x >= 0:
					//  	x += -room_pos[new_room] - axis_sizes[curr_room]
					room_pos_en = '1; room_pos_inv = '1;
					dxc_en = '1; dxc_inv = '1; dxc_half = '1;

					//  	face_axis = <axis with x >= 0>
					//  	change room
					dx_signs = '0;
					change_room = 1;
					//  	=> STATE_FINISH_MOVE

					next_state = STATE_FINISH_MOVE;
				end else begin
					//  else:
					//  	x -= 2*axis_sizes[curr_room]
					dxc_en = '1; dxc_inv = '1; dxc_half = '0;

					next_state = STATE_CHECK_MINUS;
				end
			end
			STATE_CHECK_MINUS: begin
				if (|check_signs) begin
					//  if any x < 0:
					//  	x += -room_pos[new_room] + axis_sizes[curr_room]
					room_pos_en = '1; room_pos_inv = '1;
					dxc_en = '1; dxc_inv = '0; dxc_half = '1;

					//  	face_axis = <axis with x < 0>
					//  	change room
					dx_signs = '1;
					change_room = 1;

					//  	=> STATE_FINISH_MOVE
					next_state = STATE_FINISH_MOVE;
				end else begin
					//  else:
					//  	#x += -axis_sizes[curr_room] # restore
					dx_signs = 'X;
					xc_inv = 'X; dxc_en = 'X; dxc_inv = 'X; dxc_half = 'X; room_pos_en = 'X; room_pos_inv = 'X;
					next_state = STATE_IDLE; // don't need to restore, since we didn't change room
				end
			end
			STATE_FINISH_MOVE: begin
				// x += room_pos[new_room]
				room_pos_en = '1; room_pos_inv = '0;

				next_state = STATE_STORE; next_update_curr_x = 1; next_update_curr_room = 1;
			end
			STATE_STORE: begin
				// curr_x = x
				// curr_room = room
				next_state = STATE_IDLE;
			end
			default: begin
				next_state = 'X;
				dx_signs = 'X; change_room = 'X;
				xc_inv = 'X; dxc_en = 'X; dxc_inv = 'X; dxc_half = 'X; room_pos_en = 'X; room_pos_inv = 'X;
			end
		endcase
	end

	wire update_curr_x = (state == STATE_STORE || state == STATE_TO_PLUS);
	wire update_curr_room = (state == STATE_STORE);

	generate
		for (i = 0; i < 3; i++) begin
			always_ff @(posedge clk) begin
				if (reset) begin
					//curr_x[i] <= curr_x_initial[i];
				end else begin
					// store at STATE_TO_PLUS since we might have updated the position coming from STATE_ADJUST
					//if (state == STATE_STORE || state == STATE_TO_PLUS) curr_x[i] <= x_corner[i];
				end
			end
		end
	endgenerate

	always_ff @(posedge clk) begin
		if (reset) begin
			state <= STATE_IDLE;
			//curr_room <= curr_room_initial;
		end else begin
			if (start_adjust) state <= STATE_ADJUST;
			else if (start_fix) state <= STATE_TO_PLUS;
			else state <= next_state;

			//if (state == STATE_STORE) curr_room <= room;
		end
	end

	wire signed [ROOM_X_BITS-1:0] curr_x0[3];
	wire [ROOM_BITS-1:0] curr_room0;
	p_latch_register #(.BITS(ROOM_BITS)) curr_room_register(.clk(clk), .reset(reset), .we(update_curr_room), .next_we(next_update_curr_room), .reset_wdata(curr_room_initial), .wdata(room), .rdata(curr_room0), .next_wdata('X));
	generate
		for (i = 0; i < 3; i++) begin
			p_latch_register #(.BITS(ROOM_X_BITS)) curr_x_register(.clk(clk), .reset(reset), .we(update_curr_x), .next_we(next_update_curr_x), .reset_wdata(curr_x_initial[i]), .wdata(x_corner[i]), .rdata(curr_x0[i]), .next_wdata('X));
		end
	endgenerate

/*
	assign curr_x[0] = curr_x0[0];
	assign curr_x[1] = curr_x0[1];
	assign curr_x[2] = curr_x0[2];
*/
	assign curr_room = (`CURR_ROOM_FIX_MASK&`CURR_ROOM_FIX_VALUE) | ((~`CURR_ROOM_FIX_MASK)&curr_room0);

	assign curr_x[0] = (`CURR_X_E0_FIX_MASK&`CURR_X_E0_FIX_VALUE) | ((~`CURR_X_E0_FIX_MASK)&curr_x0[0]);
	assign curr_x[1] = (`CURR_X_E1_FIX_MASK&`CURR_X_E1_FIX_VALUE) | ((~`CURR_X_E1_FIX_MASK)&curr_x0[1]);
	assign curr_x[2] = curr_x0[2];


	assign x_corner_initial = {curr_x_ext[2], curr_x_ext[1], curr_x_ext[0]};
	assign room_initial = curr_room;

	assign working = (state != STATE_IDLE);
	assign reset_room_state = start_fix || start_adjust;
endmodule : room_navigator
