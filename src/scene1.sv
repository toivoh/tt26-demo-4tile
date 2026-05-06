/*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

module scene1 #(
		parameter ROOM_BITS=8, X_BITS=8,

		MAX_I = 8, MAX_J = 8, MAX_K = 1,
/*
		LOG2_STEP_X = 7, LOG2_STEP_Z = 7,
		HEIGHT_MAIN = 256, HEIGHT_WIND = 16,
		WIND_X = 96, WIND_Z = 96
*/
		LOG2_STEP_X = 7+1, LOG2_STEP_Z = 7+1,
		PORTAL_SX = 80*2, PORTAL_SZ = 80*2, PORTAL_X_SY = (256-96)*2, PORTAL_Z_SY = (256-96)*2,
		HEIGHT_MAIN = 256*2, HEIGHT_WIND = 16*2,
		WIND_X = 96*2, WIND_Z = 96*2,
		//LOG2_TUNNEL_AMP = 7
		LOG2_TUNNEL_AMP = 8
	) (
		input wire [`SCENE_FLAG_BITS-1:0] scene_flags,
		input wire [X_BITS-1:0] main_w, sub_w, // must average 2^LOG2_STEP_X
		input wire [X_BITS-1:0] main_d, sub_d, // must average 2^LOG2_STEP_Z

		input wire [ROOM_BITS-1:0] room,
		input wire [2:0] room_dir_signs,
		input wire [1:0] room_dir_axis,

		output logic [3*X_BITS-1:0] axis_sizes, // stacked
		output logic [3*X_BITS-1:0] room_pos, // stacked
		output logic [ROOM_BITS-1:0] neighbor_room,
		output logic [2:0] mirroring
	);

	localparam I_BITS = $clog2(MAX_I+1);
	localparam J_BITS = $clog2(MAX_J+1);
	localparam K_BITS = $clog2(MAX_K+1);

	wire ceil_dec_en = scene_flags[`SCENE_FLAG_CEIL_DEC];
	wire portal_en = scene_flags[`SCENE_FLAG_PORTALS];
	wire blockage_en = scene_flags[`SCENE_FLAG_BLOCKAGES];
	wire alt_height_en = scene_flags[`SCENE_FLAG_ALT_HEIGHTS];
`ifdef USE_TUNNEL
	wire tunnel_en = scene_flags[`SCENE_FLAG_TUNNEL];
`else
	wire tunnel_en = 0;
`endif

	wire [I_BITS-1:0] i;
	wire [J_BITS-1:0] j;
	wire [K_BITS-1:0] k;
	//wire [K_BITS-1:0] k_wind = 1, k_main = 0;
	assign {k, j, i} = room;

	wire in_portal = i[0] && j[0] && blockage_en;

	logic [X_BITS-1:0] sx, sy, sz;
	logic [X_BITS-1:0] px, py, pz;
	//logic [ROOM_BITS-1:0] nxp, nxn, nyp, nyn, nzp, nzn;
	logic [2:0] m = 0;
	logic signed [X_BITS-1:0] tx, ty;
	always_comb begin
		tx = 'X; ty  = 'X;
		case (j[2:0])
/*
			0: begin; tx =  0; ty =  4; end
			1: begin; tx = -3; ty =  3; end
			2: begin; tx = -4; ty =  0; end
			3: begin; tx = -3; ty = -3; end
			4: begin; tx =  0; ty = -4; end
			5: begin; tx =  3; ty = -3; end
			6: begin; tx =  4; ty =  0; end
			7: begin; tx =  3; ty =  3; end
*/
			0: begin; tx =  0; ty =  3; end
			1: begin; tx = -2; ty =  2; end
			2: begin; tx = -3; ty =  0; end
			3: begin; tx = -2; ty = -2; end
			4: begin; tx =  0; ty = -3; end
			5: begin; tx =  2; ty = -2; end
			6: begin; tx =  3; ty =  0; end
			7: begin; tx =  2; ty =  2; end
			default: begin; tx = 'X; ty = 'X; end
		endcase

		px = i << LOG2_STEP_X;
		pz = j << LOG2_STEP_Z;
		if (k == 0 || in_portal) begin
			py = 0;

			//sx = 1 << (LOG2_STEP_X-1);
			//sz = 1 << (LOG2_STEP_Z-1);
			sx = ((i[0] == 0) ? main_w : sub_w) >> 1;
			sz = ((j[0] == 0) ? main_d : sub_d) >> 1;
			sy = HEIGHT_MAIN >> 1;

			//if (alt_height_en && !(i[0] && j[0])) sy = HEIGHT_MAIN;
			//if (alt_height_en && !(i[0] && (j[0] ^ i[1]))) sy = HEIGHT_MAIN;
			if (alt_height_en) sy = (!i[0] + !j[0] + 1) << 8;
			//if (alt_height_en) sy = (!i[0] + (j[0]^i[1]) + 1) << 8; // houses?
			//if (alt_height_en && (i[1:0] == 1 || (j[1:0] == 0))) sy = 3 << 8; // combine with the previous ones

			if (portal_en) begin
				if (in_portal) begin
					// Inside a portal block
					if (k == 0) sz = PORTAL_SZ >> 1;
					if (k == 1) sx = PORTAL_SX >> 1;
					sy = (k == 0 ? PORTAL_X_SY : PORTAL_Z_SY) >> 1;
				end
			end

			if (tunnel_en) begin
				sx = HEIGHT_MAIN >> 1;
				px = tx << (LOG2_TUNNEL_AMP - 2);
				py = ty << (LOG2_TUNNEL_AMP - 2);
			end
		end else begin
			py = -((HEIGHT_MAIN + HEIGHT_WIND) >> 1);

			sx = WIND_X >> 1;
			sz = WIND_Z >> 1;
			sy = HEIGHT_WIND >> 1;
		end
	end

	assign axis_sizes = {sz, sy, sx};
	assign room_pos = {pz, py, px};
	assign mirroring = m;

	wire [2:0] rds = room_dir_signs ^ mirroring;

	wire [I_BITS-1:0] i_nb = i + (rds[0] ? -1 : 1);
	wire [J_BITS-1:0] j_nb = j + (rds[2] ? -1 : 1);
	wire [K_BITS-1:0] k_opposite = !k;

	logic nb_x_en, nb_z_en;

	logic [ROOM_BITS-1:0] nb_x, nb_y, nb_z;
	logic nb_k_x, nb_k_z;
	always_comb begin
		nb_x = -1; nb_y = -1; nb_z = -1;
		nb_x_en = 1; nb_z_en = 1;

		nb_k_x = k;
		nb_k_z = k;

		// Walls
		if (rds[0] == 1 && i == 0) nb_x_en = 0;
		if (rds[0] == 0 && i == MAX_I) nb_x_en = 0;
		if (!tunnel_en) begin
			if (rds[2] == 1 && j == 0) nb_z_en = 0;
			if (rds[2] == 0 && j == MAX_J) nb_z_en = 0;
		end

		if (blockage_en) begin
			if (portal_en) begin
				//if (i[0]) nb_k_z = 1; // lead into portal in z direction (if we're not inside one, then we override below)
				if (i[0]) nb_k_z = !k; // lead into/out of portal in z direction
				if (in_portal) begin
					// Inside a portal block
					if (k == 0) nb_z_en = 0; // k = 0: portal in x direction
					if (k == 1) nb_x_en = 0;
					//nb_k_z = 0;
				end
				//if (j[0]) nb_x_en = 0;
				//if (i[0]) nb_z_en = 0;
			end else begin
				// Pillars
				if (j[0]) nb_x_en = 0;
				if (i[0]) nb_z_en = 0;
			end
		end

		if (k != rds[1] && ceil_dec_en && !in_portal) nb_y = {k_opposite, j, i};

		if (k == 0 || in_portal) begin
			if (nb_x_en) nb_x = {nb_k_x, j, i_nb};
			if (nb_z_en) nb_z = {nb_k_z, j_nb, i};
		end

		if (tunnel_en) nb_x_en = 0;

//`ifdef FPGA
		if (room == '1) begin
			nb_x = 4;
			nb_y = 4;
			nb_z = 4;
		end
//`endif
	end

	always_comb begin
		neighbor_room = 'X;
		case (room_dir_axis)
			0: neighbor_room = nb_x;
			1: neighbor_room = nb_y;
			2: neighbor_room = nb_z;
			default: neighbor_room = 'X;
		endcase
	end
endmodule : scene1
