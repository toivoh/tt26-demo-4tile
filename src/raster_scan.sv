/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module axis_scan #(parameter BITS=10) (
		input wire clk, reset, en,
		input wire force_at_thresh,

		input wire [BITS-1:0] pos0, thresh0, thresh1, thresh2, thresh3,

		output reg [1:0] state,
		output reg [BITS-1:0] pos,
		output wire inc, at_thresh
	);

	// not a register
	reg [BITS-1:0] thresh;
	always_comb begin
		case (state)
			0: thresh = thresh0;
			1: thresh = thresh1;
			2: thresh = thresh2;
			3: thresh = thresh3;
			default: thresh = 'X;
		endcase // state
	end

	assign at_thresh = (pos == thresh) || force_at_thresh;
	assign inc = en && at_thresh;

	always @(posedge clk) begin
		if (reset || (inc && (state == 3))) begin
			state <= 0;
			pos <= pos0;
		end else begin
			pos <= pos + en;
			state <= state + inc;
		end
	end
endmodule : axis_scan


module raster_scan #(
		// X
		//                             state
		parameter FP_W = 16,      // 0
		parameter SYNC_W = 96,    // 1
		parameter BP_W = 48,      // 2
		parameter ACTIVE_W = 640, // 3

		parameter USE_DOUBLE_X = 0,
		parameter USE_LBUF = 0,

		// Y
		//                                       state
		parameter BP_H     = 33  >> USE_LBUF, // 0
		parameter ACTIVE_H = 480 >> USE_LBUF, // 1
		parameter FP_H     = 10  >> USE_LBUF, // 2
		parameter SYNC_H   = 2   >> USE_LBUF, // 3

		// Don't change
		parameter X0 = -(FP_W + SYNC_W + BP_W) - ACTIVE_W/2,
		parameter Y0 = -ACTIVE_H/2 - BP_H
	) (
		input wire clk, reset, en,
		input wire [2:0] speedup,
		input wire force_x_at_thresh, force_y_at_thresh,

		output wire signed [10:0] x,
		output wire signed [9:0] y, y_orig,
		output wire [1:0] x_state,
		output wire [1:0] y_state,
		output wire active, hsync, vsync, new_line, new_frame, x_active, y_active, active_line_done, y_hit, x_active_start
	);

	localparam X_BITS = 10;

	reg en_x_reg;

	wire signed [X_BITS-1:0] x_raw;

	wire x_fast;
	synth_speedup synth_speedup_inst(
		.speedup(speedup), .x(x_raw[3:0]),
		.fast(x_fast)
	);

	always_ff @(posedge clk) begin
		if (reset) en_x_reg <= 0;
		else if (en) en_x_reg <= !en_x_reg && !x_fast;
	end

	wire en_x = USE_DOUBLE_X ? en_x_reg || x_fast : 1;

	//wire [1:0] x_state;
	wire x_inc;
	axis_scan #(.BITS(X_BITS)) scan_x(
		.clk(clk), .reset(reset), .en((en_x || force_x_at_thresh) && en), .force_at_thresh(force_x_at_thresh),
		.pos0(X0),
		.thresh0(X0 + FP_W - 1),
		.thresh1(X0 + FP_W + SYNC_W - 1),
		.thresh2(X0 + FP_W + SYNC_W + BP_W - 1),
		.thresh3(X0 + FP_W + SYNC_W + BP_W + ACTIVE_W - 1),
		.state(x_state), .pos(x_raw), .inc(x_inc)
	);

	assign x = USE_DOUBLE_X ? {x_raw, en_x} : x_raw;

	assign x_active =  (x_state == 3);
	assign hsync    = !(x_state == 1);
	assign new_line =   x_inc && !hsync;
	assign active_line_done = x_active && x_inc;
	assign x_active_start   = (x_state == 2) && x_inc;

	// Y
	localparam Y_BITS = 10;

/*
	// 						   state
	localparam ACTIVE_H = 480;  // 0
	localparam FP_H = 10;		// 1
	localparam SYNC_H = 2; 		// 2
	localparam BP_H = 33; 		// 3
	localparam Y0 = -ACTIVE_H/2;
*/

	//wire [1:0] y_state;
	//wire signed [9:0] y_orig;
	wire y_inc, y_at_thresh;
	axis_scan #(.BITS(Y_BITS)) scan_y(
		.clk(clk), .reset(reset),
		//.en(en && new_line),
		.en(en && active_line_done),
		.force_at_thresh(force_y_at_thresh),
		.pos0(Y0),
		.thresh0(Y0 + BP_H - 1),
		.thresh1(Y0 + BP_H + ACTIVE_H - 1),
		.thresh2(Y0 + BP_H + ACTIVE_H + FP_H - 1),
		.thresh3(Y0 + BP_H + ACTIVE_H + FP_H + SYNC_H - 1),
		.state(y_state), .pos(y_orig), .inc(y_inc), .at_thresh(y_at_thresh)
	);
	assign y = y_orig << USE_LBUF;

/*
	assign y_active  =  (y_state == 0);
	assign vsync     = !(y_state == 2);
	assign new_frame =   y_inc && (y_state == 3);
*/
	assign y_active  =  (y_state == 1);
	//assign vsync     = !(y_state == 3);
	wire vsync0      = !(y_state == 3);
	assign new_frame =   y_inc && (y_state == 3);

	assign y_hit     =  (y_state == 3) && y_at_thresh;

	reg vsync_reg;
	always_ff @(posedge clk) begin
		/*
		if (reset) begin
			vsync_reg <= 1;
		end else begin
			if (en && new_line) vsync_reg <= vsync0;
		end
		*/
		if (en && new_line) vsync_reg <= vsync0;
	end
	assign vsync = vsync_reg;

	assign active = x_active && y_active;
endmodule : raster_scan
