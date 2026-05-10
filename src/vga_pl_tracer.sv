/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

`ifdef FPGA
`define INITIAL_FRAME_T 0
//`define INITIAL_FRAME_T (512*4)
`else
`define INITIAL_FRAME_T 0
`endif

module vga_pl_tracer #( `propagated_parameter_definitions, `derived_parameter_definitions ) (
		input wire clk, reset,

		input wire force_x_at_thresh, force_y_at_thresh,
		input wire [2:0] speedup,
		input wire interlace_enable,

		output wire [VALUE_BITS-1:0] value_out,
		output logic [5:0] rgb_out,
		output wire hsync, vsync, new_frame, new_vga_line,
		output wire active, x_active, y_active,

		// Outputs from buffered_tracer that need to be forwarded to the top wrapper, for emit and debug
		`buffered_tracer_output_definitions,
		output wire [10:0] scan_x0,
		output int scan_x, scan_y,
		output wire [15:0] sound_sample,
		output wire pwm_out,

		output wire [`MUSIC_T_INT_BITS+3-1:0] frame_t_out
	);


	localparam SCAN_X0_BITS = 11;
	localparam SCAN_X_BITS = 10;
	localparam SCAN_Y_BITS = 10;//9;
	localparam VIS_Y_BITS = 9;

	localparam PAL_BITS = 2;

	localparam MUSIC_T_BITS = `MUSIC_T_INT_BITS + 13;
	localparam T_BITS = MUSIC_T_BITS-10;

	reg [T_BITS-1:0] frame_t;
	assign frame_t_out = frame_t;

	wire view_calc_done;


	// Sequence
	// ========

	localparam PART_BITS = 3;
	wire [PART_BITS-1:0] part = frame_t[T_BITS-1:11];
	wire [1:0] pattern = frame_t[10:9];
	wire [1:0] measure = frame_t[8:7];

	wire [2:0] ttf_part0 = frame_t >> 7;

	logic [PART_BITS-1:0] part_eff;
	logic alt_part;
	logic [2:0] ttf_part;
	logic [`CTRL_FLAG_BITS-1:0] ctrl_flags;
	logic [`SCENE_FLAG_BITS-1:0] scene_flags;
	logic [PAL_BITS-1:0] palette;
	logic interlace_en;

	logic reset_nav;
	logic [ROOM_BITS-1:0] room_initial;
	logic [X_BITS-1:0] x_corner_initial[3];
	logic signed [X_BITS-1:0] delta_x[3];
	logic lock_dx2_en, lock_dx2_partial;
	logic inverse_video;
	logic ttf_t_shift_speedup;

	always_comb begin
		ttf_part = 0;
		ctrl_flags = 0;
		scene_flags = (1 << `SCENE_FLAG_CEIL_DEC) | (1 << `SCENE_FLAG_BLOCKAGES);
		room_initial = 4;

		x_corner_initial[0] = 0;
		x_corner_initial[1] = (-128+16)*2;
		x_corner_initial[2] = 0;

		delta_x[0] =  0;
		delta_x[1] =  0;
		delta_x[2] = -1; interlace_en = 1;

		palette = 0;
		inverse_video = 0;

		reset_nav = (frame_t[10:0] == 0);

		lock_dx2_en = 0;
		lock_dx2_partial = 0;

		alt_part = 0;
		ttf_t_shift_speedup = 0;

`ifdef CYCLE_FLAGS
		ttf_part = frame_t >> 7;
		ctrl_flags[`CTRL_FLAG_ALT_SHADING] = frame_t[6];
		ctrl_flags[`CTRL_FLAG_LOCK_DX2_UPDATE] = frame_t[7];
		scene_flags = frame_t >> 6;

		x_corner_initial[0] = 0;

//		x_corner_initial[1] = 32; // portals
//		x_corner_initial[1] = 128+32; // tunnel
//		x_corner_initial[1] = -96*2;
//		x_corner_initial[1] = 32*2;

		x_corner_initial[2] = 0;

		room_initial = 4;
`else

		part_eff = part;
		if (part == 4 || part == 1) begin
			//part_eff = frame_t >> 9;
			part_eff = frame_t >> 8;
			if (part == 1 && part_eff == 5) part_eff[2] = 0;
			alt_part = 1;
			reset_nav |= (frame_t[7:0] == 0);
		end

		case (part_eff)
			0: begin
			//0, 6: begin
				palette = 0;
				scene_flags = (1 << `SCENE_FLAG_CEIL_DEC) | (1 << `SCENE_FLAG_BLOCKAGES);

				x_corner_initial[1] = (-128+16)*2;
				/*
				if (part_eff[2]) begin
					delta_x[2] = -2; interlace_en = 0;
					palette = 2;
				end
				*/
			end
			1: begin
				/*
				palette = 2;
				ctrl_flags[`CTRL_FLAG_LOCK_DX2_UPDATE] = 1;
				ctrl_flags[`CTRL_FLAG_ALT_SHADING] = 'X;
				ttf_part = ttf_part0;
				*/
				// Repeated scene
				palette = 0;
				scene_flags = (1 << `SCENE_FLAG_CEIL_DEC) | (1 << `SCENE_FLAG_BLOCKAGES);
				x_corner_initial[1] = (-128+16)*2;
/*
				palette = 1;
				scene_flags = (1 << `SCENE_FLAG_ALT_HEIGHTS) | (1 << `SCENE_FLAG_BLOCKAGES);
				//x_corner_initial[1] = (-128+16)*2;
				x_corner_initial[1] = 32; // portals
*/
			end
			2: begin
				palette = 1;
				scene_flags = 1 << (`SCENE_FLAG_TUNNEL);
				ctrl_flags[`CTRL_FLAG_ALT_SHADING] = 1;

				x_corner_initial[1] = 128+32;
				delta_x[2] = -2; interlace_en = 0;
			end
			3: begin
				palette = 0;
				scene_flags = (1 << `SCENE_FLAG_ALT_HEIGHTS);

				x_corner_initial[1] = (-128+16)*2;
			end
			4: begin
				// Extra scene
				palette = 1;
				scene_flags = (1 << `SCENE_FLAG_ALT_HEIGHTS) | (1 << `SCENE_FLAG_BLOCKAGES);
			end
			5: begin
				palette = 2;
				scene_flags = (1 << `SCENE_FLAG_CEIL_DEC) | (1 << `SCENE_FLAG_BLOCKAGES) | (1 << `SCENE_FLAG_PORTALS) | (1 << `SCENE_FLAG_NARROW);
				ctrl_flags[`CTRL_FLAG_ALT_SHADING] = 1;

				if (alt_part) begin
					palette = 0;
					ttf_t_shift_speedup = 1;
				end

				x_corner_initial[1] = 32; // portals
			end
			6: begin
				palette = 0;
				scene_flags = 1 << (`SCENE_FLAG_TUNNEL) | (1 << `SCENE_FLAG_NARROW);

				x_corner_initial[1] = 128+32;
				delta_x[2] = -2; interlace_en = 0;
			end
			7: begin
				// Extra scene
/*
				palette = 0;
				scene_flags = 1 << (`SCENE_FLAG_TUNNEL) | (1 << `SCENE_FLAG_NARROW);
*/

				palette = 1;
				scene_flags = (1 << `SCENE_FLAG_ALT_HEIGHTS) | (1 << `SCENE_FLAG_NARROW);
			end
		endcase

		if (part == 1) begin
			ttf_part = ttf_part0^4;
			if (pattern != 0 || measure == 3) lock_dx2_en = 1;
			if (pattern != 1) lock_dx2_partial = 1;
		end
		if (part == 4) begin
			ttf_part = ttf_part0 ^ (ttf_part0[2] ? 2 : 0);
			inverse_video = (pattern == 0) && measure[0];
		end

		if (lock_dx2_en) begin
			if (!(lock_dx2_partial && dx2_e1[7 -: 2] == '0)) begin
				palette = 2;
				ctrl_flags[`CTRL_FLAG_LOCK_DX2_UPDATE] = view_calc_done;
			end else begin
				palette = 0;
				if (pattern[1]) palette = !measure[1];
			end
		end
`endif
	end



	// Raster scan
	// ===========
	wire signed [SCAN_X0_BITS-1:0] x0;
	wire signed [SCAN_X_BITS-1:0] x = x0[SCAN_X0_BITS-1:1];
	wire new_pixel = x0[0];
	wire signed [SCAN_Y_BITS-1:0] full_y, y_orig;
	wire signed [VIS_Y_BITS-1:0] y = full_y;
	//wire active, x_active, y_active;
	wire new_line, x_active_start, y_hit;
	//raster_scan_c rs(
	raster_scan #(
		.USE_DOUBLE_X(1),
`ifdef USE_LINE_BUFFER
		.USE_LBUF(1)
`else
		.USE_LBUF(0)
`endif
	) rs (
		.clk(clk), .reset(reset), .en(1'b1), .speedup(speedup),
		.force_x_at_thresh(force_x_at_thresh), .force_y_at_thresh(force_y_at_thresh),
		.x(x0), .y(full_y), .y_orig(y_orig),
		.active(active), .hsync(hsync), .vsync(vsync), .new_frame(new_frame), .active_line_done(new_line), .new_line(new_vga_line), .x_active_start(x_active_start), .y_hit(y_hit),
		.x_active(x_active), .y_active(y_active)
	);

	assign scan_x = x;
	assign scan_y = full_y;
	assign scan_x0 = x0;


	// Tracer
	// ======
	//localparam T_BITS = 9; // Increasing it to 10 makes rotation jittery for some reason? TODO: why?
//	localparam T_BITS = DXF_FRAC_BITS+2;

`ifdef FPGA
	localparam DELTA_T = 2;
`else
	localparam DELTA_T = 1;
`endif

	always_ff @(posedge clk) begin
		if (reset || (frame_t == ((4*6+1)*512-DELTA_T))) frame_t <= `INITIAL_FRAME_T;
//		if (reset || (frame_t == ((4*6+2)*512))) frame_t <= '0;
//		if (reset || (frame_t == ((4*6+2)*512-DELTA_T))) frame_t <= '0;
//		if (reset || (frame_t == ((4*6+2)*512-DELTA_T))) frame_t <= 4*512;
`ifdef FPGA
		else frame_t <= frame_t + {new_frame, 1'b0};
`else
		else frame_t <= frame_t + new_frame;
`endif
	end


	wire matrix_running;

	//wire signed [DX_BITS-1:0] dxf_in[3];
	wire signed [DDX_BITS-1:0] ddx[3];

	wire signed [DX_BITS-1:0] dxf0[3];

//	wire [POS_BITS-1:0] i2_init = 639;

	wire [VALUE_BITS-1:0]  initial_value = 0;
	//wire [LENGTH_BITS-1:0] initial_length = 160 - 60 - 1; // 60 cycles for the current matrix computation, length is actually length - 1
	wire [LENGTH_BITS-1:0] initial_length = 0;


	wire [X_BITS-1:0] axis_sizes_initial[3];
	assign axis_sizes_initial[0] = 8 << 3;
	assign axis_sizes_initial[1] = 8 << 3;
	assign axis_sizes_initial[2] = 8 << 3;


	wire consume_pixel = x0[0] && x_active;

	wire reset_view_calc = new_line || reset;

	wire reset_dxf, reset_i_d2;
	wire [POS_BITS-1:0] i_d2_init, i2_init;
	wire update_dx_ext, update_dx1_ext, next_update_dx1_ext;
	wire [2:0] ddx_sign_ext, update_dx_ext_mask;
	wire [N_BITS-1:0] ddx_shl_ext;

	wire tstate_override_en = y_hit;
	wire start_adjust = y_hit && x_active_start;
//	wire tstate_override_en = 0;
//	wire start_adjust = 0;

	// not registers
	//reg update_dx, ddx_sign;
	//reg [N_BITS-1:0] ddx_shl;

	wire [2:0] interlace_mask = (interlace_enable && interlace_en && y_orig[0] && !y_hit) ? 3'b100 : 3'b000;

	//wire [VALUE_BITS-1:0] curr_value;
	buffered_pl_tracer #( `parameters_forward ) btracer(
		.clk(clk), .reset((reset_view_calc || !view_calc_done) && !force_y_at_thresh), .reset_dxf(reset_dxf), .reset_i_d2(reset_i_d2),

		.ctrl_flags(ctrl_flags),
		.scene_flags(scene_flags),
		.frame_t(frame_t), .y(y), .interlace_mask(interlace_mask),

		.i_d2_init(i_d2_init), .i2_init(i2_init),
		.update_dx_ext(update_dx_ext), .update_dx1_ext(update_dx1_ext), .next_update_dx1_ext(next_update_dx1_ext), .update_dx_ext_mask(update_dx_ext_mask), .ddx_sign_ext(ddx_sign_ext), .ddx_shl_ext(ddx_shl_ext),

		.initial_value(initial_value), .initial_length(initial_length),
		.dxf_x_in(dxf0[0]), .dxf_y_in(dxf0[1]), .dxf_z_in(dxf0[2]),
		.ddx_x_in(ddx[0]), .ddx_y_in(ddx[1]), .ddx_z_in(ddx[2]),
`ifdef USE_OLD_TRACE_STATE
		.x_corner_initial({x_corner_initial[2], x_corner_initial[1], x_corner_initial[0]}),
		.axis_sizes_initial({axis_sizes_initial[2], axis_sizes_initial[1], axis_sizes_initial[0]}),
`else
		.reset_nav(reset || reset_nav), .start_fix(0), .start_adjust(start_adjust),

		.curr_x_initial_stacked({x_corner_initial[2], x_corner_initial[1], x_corner_initial[0]}), .curr_room_initial(room_initial),
		.tstate_override_en(tstate_override_en),
`ifdef FPGA
		.delta_x_stacked({delta_x[2][X_BITS-2:0], 1'b0, delta_x[1][X_BITS-2:0], 1'b0, delta_x[0][X_BITS-2:0], 1'b0}), // double the speed
`else
		.delta_x_stacked({delta_x[2], delta_x[1], delta_x[0]}),
`endif
`endif

		.consume_pixel(consume_pixel),
		//.curr_value(curr_value) // included in `buffered_tracer_output_forward
		`buffered_tracer_output_forward
	);

	// dxf, ddx calculation
	// ====================
/*
	view_calc #(.DX_BITS(DX_BITS), .DDX_BITS(DDX_BITS), .DXF_FRAC_BITS(DXF_FRAC_BITS), .T_BITS(T_BITS), .Y_BITS(SCAN_Y_BITS)) view(
		.clk(clk), .reset(reset), .new_line(new_line),

		.t(frame_t), .y(y),
		.reset_dxf(reset_dxf), .matrix_running(matrix_running),
		.ddx_0(ddx[0]), .ddx_1(ddx[1]), .ddx_2(ddx[2]),
		.dxf0_0(dxf0[0]), .dxf0_1(dxf0[1]), .dxf0_2(dxf0[2]),
		.update_dx_out(update_dx), .ddx_shl_out(ddx_shl), .ddx_sign_out(ddx_sign)
	);
*/


	localparam TTF_BITS = 10;

	localparam TTF_T_SHIFT_BITS = 2;
	localparam TTF_Y_SHIFT_BITS = 1;

	logic ttf_t_en, ttf_y_en;
	logic ttf_t_inv;
	logic [TTF_T_SHIFT_BITS-1:0] ttf_t_shift;
	logic [TTF_Y_SHIFT_BITS-1:0] ttf_y_shift;

	logic [TTF_BITS-1:0] ttf_offset, ttf_mask;

	wire [1:0] ttf_src;
	logic [TTF_BITS-1:0] ttf;


/*
	always_comb begin
		ttf = 0;
		if (ttf_src[`T1T2FOV_BIT_FOV]) ttf = 100;
		else begin
			if (ttf_src[`T1T2FOV_BIT_T2]) ttf = ~(frame_t>>3);
			else ttf = (frame_t>>2);
		end
	end
*/

	always_comb begin
		ttf_t_en = 0; ttf_t_inv = 'X; ttf_t_shift = 'X;
		ttf_y_en = 0; ttf_y_shift = 'X;
		ttf_offset = 0;
		ttf_mask = '1;

/*
		if      (ttf_src[`T1T2FOV_BIT_FOV]) begin ttf_offset = 96; end
		else if (ttf_src[`T1T2FOV_BIT_T2])  begin ttf_t_en = 1; ttf_t_inv = 1; ttf_t_shift = 0; end
		else                                begin ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 1; end
*/
		case (ttf_part)
			0: begin
				if      (ttf_src[`T1T2FOV_BIT_FOV]) begin ttf_offset = 96; end
				else if (!ttf_src[`T1T2FOV_BIT_T2]) begin ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 1; end
				else                                begin ttf_t_en = 1; ttf_t_inv = 1; ttf_t_shift = 0; end
			end
			1: begin
				if      (ttf_src[`T1T2FOV_BIT_FOV]) begin ttf_offset = 96; end
				else if (!ttf_src[`T1T2FOV_BIT_T2]) begin ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 1; ttf_y_en = 1; ttf_y_shift = 0; end
				else                                begin ttf_t_en = 1; ttf_t_inv = 1; ttf_t_shift = 0; end
			end
			2: begin
				if      (ttf_src[`T1T2FOV_BIT_FOV]) begin ttf_offset = 96; end
				else if (!ttf_src[`T1T2FOV_BIT_T2]) begin ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 1; ttf_y_en = 1; ttf_y_shift = 0; end
				else                                begin ttf_t_en = 1; ttf_t_inv = 1; ttf_t_shift = 0; ttf_y_en = 1; ttf_y_shift = 0; end
			end
			3: begin
				if      (ttf_src[`T1T2FOV_BIT_FOV]) begin ttf_offset = 96; end
				else if (!ttf_src[`T1T2FOV_BIT_T2]) begin ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 1; ttf_y_en = 1; ttf_y_shift = 1; end
				else                                begin ttf_t_en = 1; ttf_t_inv = 1; ttf_t_shift = 0; ttf_y_en = 1; ttf_y_shift = 1; end
			end
			4, 5: begin
				if      (ttf_src[`T1T2FOV_BIT_FOV]) begin ttf_offset = 0; ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 2; ttf_mask = 'hff; end
				else if (!ttf_src[`T1T2FOV_BIT_T2]) begin ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 1; end
				else                                begin ttf_t_en = 1; ttf_t_inv = 1; ttf_t_shift = 0; end
			end
			6, 7: begin
				if      (ttf_src[`T1T2FOV_BIT_FOV]) begin ttf_offset = 0; ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 2; ttf_mask = 'hff;  ttf_y_en = 1; ttf_y_shift = 0; end
				else if (!ttf_src[`T1T2FOV_BIT_T2]) begin ttf_t_en = 1; ttf_t_inv = 0; ttf_t_shift = 1; end
				else                                begin ttf_t_en = 1; ttf_t_inv = 1; ttf_t_shift = 0; end
			end
		endcase
		//if (ctrl_flags[`CTRL_FLAG_LOCK_DX2_UPDATE]) ttf_t_shift |= 2;
		if (lock_dx2_en || ttf_t_shift_speedup) ttf_t_shift |= 2;
	end

	wire [TTF_BITS+2**TTF_T_SHIFT_BITS-1-1:0] ttf_t_src0 = frame_t << ttf_t_shift;
	wire [TTF_BITS-1:0] ttf_t_src1 = ttf_t_src0 >> (2**TTF_T_SHIFT_BITS-1);
	wire [TTF_BITS-1:0] ttf_t_src = ttf_t_inv ? ~ttf_t_src1 : ttf_t_src1;

	wire [TTF_BITS-1:0] ttf_y_src = y << ttf_y_shift;

	// OPT: carry save adder?
//	assign ttf = ((ttf_t_en ? ttf_t_src : '0) + (ttf_y_en ? ttf_y_src : 0) + ttf_offset) & ttf_mask;
	assign ttf = ((ttf_t_en ? ttf_t_src : '0) + (ttf_y_en ? ttf_y_src : 0) | ttf_offset) & ttf_mask; // TODO: ok to or ttf_offset instead of adding?



	view_calc_pl #(.POS_BITS(POS_BITS), .DX_BITS(DX_BITS), .DDX_FRAC_BITS(DXF_FRAC_BITS), .DDX_INT_BITS(DDX_BITS - 1 - DXF_FRAC_BITS)) view_calc_inst(
		.clk(clk), .reset(reset_view_calc),

		.t1t2fov_src(ttf_src),
`ifdef USE_TTF
		.t1({ttf, 1'b0}), .t2({ttf, 1'b0}), .fov_factor(ttf), .y(y),
//		.t1(ttf), .t2(ttf), .fov_factor(ttf), .y(y),
`else
		.t1(frame_t>>1), .t2(~(frame_t>>2)), .fov_factor(100), .y(y),
`endif

//		.t1(frame_t>>1), .t2(~(frame_t>>2)), .fov_factor(100), .y(y),
//		.t1(frame_t), .t2(~(frame_t>>1)), .fov_factor(100), .y(y),

//		.t1($signed(frame_t)+y), .t2(~(frame_t>>1)), .fov_factor(100), .y(y),
//		.t1($signed(frame_t)+y), .t2($signed(~(frame_t>>1))+y), .fov_factor(100), .y(y),
//		.t1($signed(frame_t)+(y<<1)), .t2($signed(~(frame_t>>1))+(y<<1)), .fov_factor(100), .y(y),
//		.t1($signed(frame_t)+(y<<2)), .t2($signed(~(frame_t>>1))+(y<<2)), .fov_factor(100), .y(y),
//		.t1(frame_t), .t2(~(frame_t>>1)), .fov_factor(frame_t&255), .y(y),
//		.t1(frame_t), .t2(~(frame_t>>1)), .fov_factor(128+(y>>1)), .y(y),
//		.t1(frame_t), .t2(~(frame_t>>1)), .fov_factor((frame_t+y)&255), .y(y),

		.updating_i_d2(updating_i_d2),
		.dx2_x_in(dx2_e0), .dx2_y_in(dx2_e1), .dx2_z_in(dx2_e2),
		.dx1_x_in(dx1_e0), .dx1_y_in(dx1_e1), .dx1_z_in(dx1_e2),

		.reset_dxf_out(reset_dxf), .reset_i_d2_out(reset_i_d2),
		.i_d2_init_out(i_d2_init), .i2_init_out(i2_init),
		.dxf_x_out(dxf0[0]), .dxf_y_out(dxf0[1]), .dxf_z_out(dxf0[2]),
		.ddx_x_out(ddx[0]), .ddx_y_out(ddx[1]), .ddx_z_out(ddx[2]),
		.update_dx_ext_out(update_dx_ext), .update_dx1_ext_out(update_dx1_ext), .next_update_dx1_ext_out(next_update_dx1_ext), .update_dx_ext_mask_out(update_dx_ext_mask), .ddx_sign_ext_out(ddx_sign_ext), .ddx_shl_ext_out(ddx_shl_ext),
		.done(view_calc_done)
	);

	logic [VALUE_BITS-1:0] used_value;
	always_comb begin
		if (ctrl_flags[`CTRL_FLAG_LOCK_DX2_UPDATE]) begin
			//used_value = dx2_e0[7 -: 2];
			//used_value = dx2_e0[6 -: 2] | dx2_e2[5 -: 2];
			//used_value = (dx2_e0[6 -: 2] | dx2_e2[5 -: 2]) & (dx2_e1[7 -: 2] | dx2_e0[5 -: 2]);
			used_value = (dx2_e0[6 -: 2] | dx2_e2[5 -: 2]) & (dx2_e1[7 -: 2]);
		end else begin
			used_value = curr_value;
		end
		//if (inverse_video) used_value = ~used_value;
		//if (inverse_video) used_value[1] ^= used_value[0];
		if (inverse_video) used_value[0] ^= used_value[1];
	end


	assign value_out = active ? used_value : '0;

	//assign rgb_out = {value_out, value_out, value_out};
	//assign rgb_out = {value&2'b10, value&2'b11, value};
	always_comb begin
		rgb_out = 'X;
		case (palette)
			0: case (used_value)
				// blue
				0: rgb_out = 6'b000000;
				1: rgb_out = 6'b000001;
				2: rgb_out = 6'b000110;
				3: rgb_out = 6'b101011;
				default: rgb_out = 'X;
			endcase
			1: case (used_value)
				// blue -> green
				0: rgb_out = 6'b000010;
				1: rgb_out = 6'b000110;
				2: rgb_out = 6'b011010;
				3: rgb_out = 6'b011110;
				//4: rgb_out = 6'b101110;
				default: rgb_out = 'X;
			endcase
			2: case (used_value)
				// purple -> yellow
				0: rgb_out = 6'b010001;
				1: rgb_out = 6'b100101;
				2: rgb_out = 6'b111001;
				3: rgb_out = 6'b111110;
				default: rgb_out = 'X;
			endcase
			default: rgb_out = 'X;
		endcase
/*
		case (used_value)
			// blue
			0: rgb_out = 6'b000000;
			1: rgb_out = 6'b000001;
			2: rgb_out = 6'b000110;
			3: rgb_out = 6'b101011;
		endcase
*/
/*
			// blue 2
			0: rgb_out = 6'b000001;
			1: rgb_out = 6'b000110;
			2: rgb_out = 6'b101011;
			3: rgb_out = 6'b101111;

			// purple -> yellow
			0: rgb_out = 6'b010001;
			1: rgb_out = 6'b100101;
			2: rgb_out = 6'b111001;
			3: rgb_out = 6'b111110;

			// red -> yellow
			0: rgb_out = 6'b010000;
			1: rgb_out = 6'b100100;
			2: rgb_out = 6'b111001;
			3: rgb_out = 6'b111110;

			// blue -> green
			0: rgb_out = 6'b000010;
			1: rgb_out = 6'b000110;
			2: rgb_out = 6'b011010;
			3: rgb_out = 6'b011110;
			//4: rgb_out = 6'b101110;
*/

		if (!active) rgb_out = '0;
	end


`ifdef USE_MUSIC
	music_player_wrapper mplayer_wrapper(
		.clk(clk), .reset(reset),

		.speedup(speedup),
		.x0(x0), .y_in(full_y), .frame_t(frame_t),
		.skip_out_acc_update(0), .gphase_override(0), .gphase_in('X),

		.out_acc(sound_sample), .pwm_out(pwm_out)
	);
`else
	assign sound_sample = '0;
`endif
endmodule : vga_pl_tracer
