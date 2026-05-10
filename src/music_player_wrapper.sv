/*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

module music_player_wrapper #(
		parameter ACC_BITS = 10, OCT_BITS = 3,
		STATE_BITS = `SYNTH_STATE_BITS,
		VOICE_BITS = 5,
		T_BITS = `MUSIC_T_INT_BITS, T_FRAC_BITS = 13,
		OUT_ACC_BITS = 15,
		MULTIPLIER_ADDITION_BITS = 3,
		PWM_BITS = 10,
		GPHASE_IN_BITS = 19,

`ifdef USE_LINE_BUFFER
		USE_LBUF = 1,
`else
		USE_LBUF = 0,
`endif

		// Don't change
		FRAC_BITS_PER_FRAME = 10,
		FRAME_T_BITS = T_BITS + T_FRAC_BITS - FRAC_BITS_PER_FRAME,
		DELTA_SIGMA_BITS = OUT_ACC_BITS - 1 - PWM_BITS
	)(
		input wire clk, reset,

		input wire [2:0] speedup,

		input wire signed [10:0] x0,
		input wire signed [9:0] y_in,
		input wire [FRAME_T_BITS-1:0] frame_t,

		input wire skip_out_acc_update,
		input wire gphase_override,
		input wire [GPHASE_IN_BITS-1:0] gphase_in,

		output logic [4:0] voice,
		output wire [T_BITS+T_FRAC_BITS-1:0] t,

		output wire [OUT_ACC_BITS-1:0] out_acc,
		output wire new_sample,
		output wire pwm_out,

		output wire odd_sample,
		output wire new_voice_sample, new_voice_sample_pregain,
		output wire signed [ACC_BITS-1:0] acc,
		output wire [1:0] delta_mul_out
	);

	localparam SAMPLE0_X = -960;
	localparam SAMPLE1_X = SAMPLE0_X + 800;

	localparam SAMPLE0_X_VOICE = SAMPLE0_X >>> 5;
	localparam SAMPLE1_X_VOICE = SAMPLE1_X >>> 5;

	// Calculate voice
	// ------------
	wire last_voice = (voice == 24);

	wire signed [5:0] x_voice = x0 >> 5;
	wire [5:0] state = {last_voice, x0[4:0]};

	assign odd_sample = (x_voice >= SAMPLE1_X_VOICE);
	assign voice = x_voice - (odd_sample ? SAMPLE1_X_VOICE : SAMPLE0_X_VOICE);

	assign new_sample = last_voice && (state[4:0] == 0);


	// Calculate t
	// -----------
	wire signed [9:0] y = y_in << USE_LBUF; // -273 <= y_in < 252
	wire saturated = !(y[9:8] == '1 || y[9] == 0);
	wire signed [9:0] y_sat = saturated ? -256 : y;
	wire [8:0] t_y0 = y_sat + 256;

`ifdef USE_LINE_BUFFER
	wire [9:0] t_y = {t_y0[8:1], odd_sample && !saturated, 1'b0};
`else
	wire [9:0] t_y = {t_y0, odd_sample && !saturated};
`endif

	assign t = {frame_t, t_y};

	// Music player
	// ------------

	logic [OUT_ACC_BITS-1:0] out_acc_initial;
	always_comb begin
		out_acc_initial = 'X;
/*
		case (speedup[1:0]) // TODO: use speedup[2] too?
			0: out_acc_initial = -400;
			1: out_acc_initial = -376;
			2: out_acc_initial = -352;
			3: out_acc_initial = -328;
			default: out_acc_initial = 'X;
		endcase
*/
		case (speedup[1:0]) // TODO: use speedup[2] too?
			0: out_acc_initial = -400;
			1: out_acc_initial = -376;
			2: out_acc_initial = -352;
			3: out_acc_initial = -328;
			4: out_acc_initial = -360;
			5: out_acc_initial = -336;
			6: out_acc_initial = -312;
			7: out_acc_initial = -288;
			default: out_acc_initial = 'X;
		endcase
		out_acc_initial = out_acc_initial << (OUT_ACC_BITS - 1 - PWM_BITS);
	end

	music_player #(.OUT_ACC_BITS(OUT_ACC_BITS), .OCT_BITS(OCT_BITS), .ACC_BITS(ACC_BITS), .STATE_BITS(STATE_BITS), .T_INT_BITS(T_BITS), .T_FRAC_BITS(T_FRAC_BITS), .VOICE_BITS(VOICE_BITS), .DELTA_SIGMA_BITS(DELTA_SIGMA_BITS)) mplayer(
		.clk(clk), .reset(reset),

		.t(t), .first_voice(voice==0), .voice(voice), .state(state),
		.out_acc_initial(out_acc_initial),
		.skip_out_acc_update(skip_out_acc_update), .gphase_in(gphase_in), .gphase_override(gphase_override),

		.out_acc(out_acc),

		.new_voice_sample(new_voice_sample), .new_voice_sample_pregain(new_voice_sample_pregain),
		.acc(acc), .delta_mul_out(delta_mul_out)
	);

	// PWM
	// ---
	reg [PWM_BITS+1-1:0] pwm_counter;
	always_ff @(posedge clk) begin
		if (new_sample) pwm_counter <= out_acc[OUT_ACC_BITS-1 -: (PWM_BITS+1)];
		else if (pwm_counter[PWM_BITS] == 1) pwm_counter <= pwm_counter + 1;
	end
	assign pwm_out = !pwm_counter[PWM_BITS];
endmodule : music_player_wrapper
