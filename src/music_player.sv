/*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

module multiplier_table7 (
		input wire [2:0] note7,
		output logic [9:0] multiplier
	);

	always_comb begin
		multiplier = 'X;
		case (note7)
			0: multiplier = 515;
			1: multiplier = 546;
			2: multiplier = 612;
			3: multiplier = 649;
			4: multiplier = 728;
			5: multiplier = 818;
			6: multiplier = 866;
			default: multiplier = 'X;
		endcase
	end
endmodule


module multiplier_table7x2 (
		input wire [2:0] note7,
		input wire sharp,
		output logic [9:0] multiplier
	);

	logic [9:0] m1, m2;
	always_comb begin
		m1 = 'X;
		m2 = 'X;
		case (note7)
			0: begin; m1 = 577; m2 = 612; end  // Bb/B
			1: begin; m1 = 648; m2 = 648; end  // C
			2: begin; m1 = 728; m2 = 728; end  // D
			3: begin; m1 = 771; m2 = 817; end  // Eb/E
			4: begin; m1 = 866; m2 = 866; end  // F
			5: begin; m1 = 972; m2 = 972; end  // G
			6: begin; m1 = 514; m2 = 545; end  // Ab/A (next octave)
			default: begin; m1 = 'X; m2 = 'X; end
		endcase
	end
	assign multiplier = sharp ? m2 : m1;
endmodule

/*
scale:
0: harmonic minor
4: harmonic minor + third
5: dorian         + third
6: mixolydian     + third
7: major          + third
*/
module multiplier_lookup (
		input wire [2:0] note7,
		input wire [2:0] scale,
		input wire nonharmonic,
		output logic [9:0] multiplier,
		output logic delta_oct
	);

	wire [2:0] index = note7 - ((scale[2] == 0) ? (note7 == 1 ? 3 : 2) : 0);

	logic sharp;
	always_comb begin
		sharp = 'X;
		case (note7)
			0: sharp = (((scale == 4 && !nonharmonic) || scale == 7));
			1: sharp = 1;
			2: sharp = 1;
			3: sharp = scale[1];
			5: sharp = 1;
			6: sharp = (scale[1:0] != 0);
		endcase
	end
	assign delta_oct = scale[2] && (note7[2:1] == '1);

	multiplier_table7x2 mtable(
		.note7(index), .sharp(sharp),
		.multiplier(multiplier)
	);
endmodule


module melody_rom #(parameter OCT0 = 0) (
		input wire [8:0] t,
		input mode_34, lower_end,

		output logic [2:0] note_out,
		output logic [2:0] oct,
		output logic note_on,

		output logic [2:0] root_note_out,
		output logic sus4, add_f, dup_root,

		output logic note_start, note_stop, note_stop_slow,
		output logic root_note_start, root_note_stop
	);

	localparam OCT1 = OCT0 + 1;

	wire [1:0] pattern = t[8:7];
	wire [1:0] measure = t[6:5];

	logic [2:0] add_a, add_b;

	wire [2:0] add_a1 = pattern[1] == 0 ? 3 : 4;

	wire [5:0] pattern_index0 = {t[6:2], 1'b0};
	logic [5:0] pattern_index;

	logic [3:0] note;
	logic lower_en;
	always_comb begin
		note = 'X; add_a = 'X; add_b = 'X;
		//oct = 'X;
		note_on = 0;
		lower_en = 0;

		pattern_index = pattern_index0;
		if (mode_34 && pattern_index == 32) pattern_index = 28;

		case (pattern_index)
			2: begin; note = 1; add_a = add_a1; add_b = 0; note_on = 1; end
			4: begin; note = 3; add_a = add_a1; add_b = 1; note_on = 1; end
			6: begin; note = 4; add_a = add_a1; add_b = 1; note_on = 1; end
			8, 10, 12: begin; note = 5; add_a = add_a1; add_b = 1; note_on = 1; end

			14, 16, 18, 20: begin; note = pattern[1] == 0 ? 1 : 8; add_a = pattern[1] == 0 ? 4 : 3; add_b = 0; note_on = 1; lower_en = 1; end

			22: begin; note = 1; add_a = add_a1; add_b = 0; note_on = 1; end
			24: begin; note = 3; add_a = add_a1; add_b = 1; note_on = 1; end
			26: begin; note = 4; add_a = add_a1; add_b = 1; note_on = 1; end
			28: begin; note = 5; add_a = add_a1; add_b = 1; note_on = 1; end

			32, 34, 36: begin;
				//note = 0+7;
				// TODO: better way to represent?
				case (pattern)
					0: note = 0+7;
					1: note = 2+7;
					2: note = 3+7;
					3: note = 2+7;
				endcase
				add_a = 0; add_b = 0;
				note_on = 1;
			end
			38: begin;
				//note = 6;
				// TODO: better way to represent?
				case (pattern)
					0: note = 6+0;
					1: note = 3+7;
					2: note = 2+7;
					3: note = 1+7;
				endcase
				add_a = 0; add_b = 0;
				note_on = 1;
			end
			40, 42, 44, 46: begin;
				//note = 5;
				// TODO: better way to represent?
				case (pattern)
					0: note = 5+0;
					1: note = 2+7;
					2: note = 1+7;
					3: note = 0+7;
				endcase
				add_a = 0; add_b = 0;
				note_on = 1;
			end
			48, 50, 52, 54: begin;
				//note = 4;
				// TODO: better way to represent?
				lower_en = 1;
				case (pattern)
					0: note = 4+0;
					1: note = 1+7;
					2: note = 5+0;
					3: note = 1+7;
				endcase
				add_a = 0; add_b = 0;
				note_on = 1;
				if (pattern == 3 && pattern_index0[2:0] == 0) note_on = 0;
			end
		endcase
		if (pattern[0] == 0) add_a = 0;
		if (pattern[1] == 0) add_b = 0;
		if (pattern != 3) lower_en = 0;
	end

	always_comb begin
		note_start = 0;
		note_stop = 0;
		note_stop_slow = 0; // note_stop_slow is not currently supported together with note_start; the start will be discarded.

		case (pattern_index0)
			2, 4: begin; note_start = 1; note_stop = 1; end
			6: begin; note_start = 1; note_stop_slow = 1; end
			8:  note_start = 1; 12: note_stop = 1;
			14: note_start = 1; 20: note_stop_slow = 1;

			22, 24, 26, 28: begin; note_start = 1; note_stop = 1; end
			32: note_start = 1; 36: note_stop_slow = 1;
			38: begin; note_start = 1; note_stop = 1; end
			40: note_start = 1; 46: note_stop_slow = 1;
			48: note_start = 1;
			50: if (pattern == 3) note_start = 1;
			54: note_stop_slow = 1;
		endcase

		if (mode_34) case (pattern_index0)
			10: begin; note_stop |= 1; note_stop_slow |= (pattern == 1 || pattern == 2); end
			16, 34: note_start |= 1;
			32: begin; note_start |= 1; note_stop_slow |= 1; end // TODO: support note_stop_slow and note_start at the same time
			//42: begin; note_stop |= !pattern[0]; note_stop_slow |= pattern[0]; end
			42: begin; note_stop |= (pattern == 0); note_stop_slow |= (pattern != 0); end
		endcase

		/*
		// Doesn't seem to be needed?
		if (t[1]==0) note_stop = 0;
		else note_start = 0;
		*/

		note_stop |= note_stop_slow;

		if (!note_on) begin
			note_start = 'X;
			note_stop = 'X;
		end
	end

	wire [3:0] note_sum = note + add_a + add_b; // OPT: CSA?
	wire high_oct = note_sum[3] || (note_sum == 7);
	assign note_out = note_sum[2:0] + high_oct;
	assign oct = (high_oct && !(lower_end && lower_en)) ? OCT1 : OCT0;

	wire [1:0] measure_eff = measure | (pattern_index0 == 14);

	logic [2:0] root_note;
	always_comb begin
		root_note = 'X;
		sus4 = 0;
		add_f = 0;
		dup_root = 0;
		root_note_start = 0;
		root_note_stop = 0;

		case (pattern)
			0: case (measure_eff)
				0: begin; root_note = 1; end
				1: begin; root_note = 1; sus4 = 1; end
				2: begin; root_note = 5; end
				3: begin; root_note = 4; end
				default: begin root_note = 'X; sus4 = 'X; add_f = 'X; dup_root = 'X; end
			endcase
			1: case (measure_eff)
				0: begin; root_note = 4; end
				1: begin; root_note = 5; end
				2: begin; root_note = 1; sus4 = 1; end
				3: begin; root_note = 1; end
				default: begin root_note = 'X; sus4 = 'X; add_f = 'X; dup_root = 'X; end
			endcase
			2: case (measure_eff)
				0: begin; root_note = 1; end
				1: begin; root_note = 1; sus4 = 1; end
				2: begin; root_note = 6; end
				3: begin; root_note = 5; end
				default: begin root_note = 'X; sus4 = 'X; add_f = 'X; dup_root = 'X; end
			endcase
			3: case (measure_eff)
				0: begin; root_note = 5; sus4 = 1; end
				1: begin; root_note = 4; end
				2: begin;
					if (t[4] == 0) root_note = 3;
					else begin
						root_note = 5;
						add_f = 1;
					end
				end
				3: begin; root_note = 1; dup_root = 1; end
				default: begin root_note = 'X; sus4 = 'X; add_f = 'X; dup_root = 'X; end
			endcase
			default: begin root_note = 'X; sus4 = 'X; add_f = 'X; dup_root = 'X; end
		endcase

		case (pattern_index0)
			0, 14, 32, 48: root_note_start = 1;
			12, 30, 46, 62: root_note_stop = 1;
		endcase
		if (mode_34 && pattern_index0[3:0] == 10) root_note_stop = 1;
		if (mode_34 && pattern_index0[3:0] == 0) root_note_start = 1;
	end
	assign root_note_out = root_note;
endmodule : melody_rom


module arpy(
		input wire [2:0] t_in,
		input wire [2:0] root_note,
		input wire sus4,

		output logic [2:0] note,
		output logic stop_slow
	);

	logic [2:0] note0, note1a, note2a, note1b, note2b;
	always_comb begin
		note0 = 'X;
		note1a = 'X;
		note2a = 'X;
		note1b = 'X;
		note2b = 'X;
		case (root_note)
			1: begin
				if (!sus4) begin; note0 = 5; note1a = 3; note2a = 1;  note1b = 4; note2b = 3; end
				else       begin; note0 = 4; note1a = 2; note2a = 1;  note1b = 2; note2b = 1; end // TODO: change?
			end
			3: begin;             note0 = 5; note1a = 3; note2a = 0;  note1b ='X; note2b ='X; end
			4: begin;             note0 = 6; note1a = 4; note2a = 1;  note1b = 5; note2b = 4; end
			5: begin
				if (!sus4) begin; note0 = 5; note1a = 2; note2a = 0;  note1b = 4; note2b = 0; end
				else       begin; note0 = 5; note1a = 2; note2a = 1;  note1b = 4; note2b = 1; end
			end
			6: begin;             note0 = 6; note1a = 3; note2a = 1;  note1b = 5; note2b = 3; end
		endcase
	end

	logic [2:0] t;
	always_comb begin
		note = 'X;
		case (t_in)
			0: note = note0;
			1: note = note1a;
			2: note = note2a;
			3: note = note0;
			4: note = note1b;
			5: note = note2b;
			6: note = note1b;
			7: note = note2b;
			default: note = 'X;
		endcase // t_in
		stop_slow = (t_in == 3) || (t_in == 5);
	end

endmodule


module snh_seq #(parameter BIAS=2) (
		input wire [5:0] t,
		output logic [2:0] level
	);
	always_comb begin
		level = 'X;

		case(t[3:1])
			0: level = BIAS + 2;
			1: level = BIAS + 3;
			2: level = BIAS + 1;
			3: level = BIAS + 0;
			4: level = (t[5:4] == '1) ?  BIAS + 3 : BIAS + 1;
			5: level = (t[5:4] == '1) ?  BIAS + 1 : BIAS + 3;
			6: level = BIAS + 2;
			7: level = t[4] ? BIAS + 1 : BIAS + 3;
			default: level = 'X;
		endcase
	end
endmodule


module music_player #(
		parameter ACC_BITS = 10, OCT_BITS = 3,
		STATE_BITS = `SYNTH_STATE_BITS,
		VOICE_BITS = 5,
		T_INT_BITS = `MUSIC_T_INT_BITS, T_FRAC_BITS = 13,
		OUT_ACC_BITS = 15,
		MULTIPLIER_ADDITION_BITS = 3,
		DELTA_SIGMA_BITS = 4,
		GPHASE_IN_BITS = 19,

		// Don't change
		T_BITS = T_INT_BITS + T_FRAC_BITS
	) (
		input wire clk, reset,

		input wire [T_BITS-1:0] t,
		input wire first_voice,
		input wire [VOICE_BITS-1:0] voice,
		input wire [STATE_BITS-1:0] state,

		input wire [OUT_ACC_BITS-1:0] out_acc_initial,

		input wire skip_out_acc_update,
		input wire gphase_override,
		input wire [GPHASE_IN_BITS-1:0] gphase_in,

		output wire [OUT_ACC_BITS-1:0] out_acc,

		output wire new_voice_sample, new_voice_sample_pregain,
		output wire signed [ACC_BITS-1:0] acc,

		output wire [T_INT_BITS-1:0] t34_int_out,
		output int instrument,
		output wire note_on_out,
		output wire [9:0] multiplier_out,
		output wire [OCT_BITS-1:0] oct_out,
		output wire [1:0] gain_shr_out,
		output wire [ACC_BITS-1:0] vol_out
	);

	localparam NSHIFT_BITS = 3;

	// TODO: remove
`ifdef FPGA
	localparam BASE_OCT = 1;
`else
	localparam BASE_OCT = 0;
`endif

	localparam BASS_OCT = BASE_OCT;

	wire [GPHASE_IN_BITS-1:0] gphase;

	wire melody_voice = (voice[VOICE_BITS-1:3] == 0);
	wire chords_voice = (voice[VOICE_BITS-1:3] == 2);
	wire bass_voice = (voice[VOICE_BITS-1:2] == 2);

	// Just the int bits, unlike what melody_rom takes in
	// TODO: Does it need to be based on t_34 or t_echo instead of t?
	wire [T_INT_BITS-1:0] t_int0 = t[T_INT_BITS+T_FRAC_BITS-1 -: T_INT_BITS];

	wire [T_INT_BITS-8-1:0] part = t_int0[T_INT_BITS-1:8];
	wire [1:0] pattern = t_int0[7:6];
	wire [1:0] measure = t_int0[5:4];


	wire final_measure = (pattern == 3 && measure == 3);

	wire t_int0_ge_54 = (t_int0[5:4] == '1) && (t[3] || (t[2:1] == '1));


	logic en_34;
	logic bass_on, chords_on, melody_on, echo_on, arp_on;
	logic [2:0] scale;
	logic nonharmonic;
	logic arp_high, arp_stop_slow;
	logic keys_en, organ_chords_en, melody_saw_en, pwm_en;
	logic lower_end;
	logic force_pattern3, force_stay_at_end;
	logic chords_snh_en, chords_loud, chords_stutter_en;
	logic pulse_chords;
	logic time_echo_on;
	logic bass_soft;
	always_comb begin
		en_34 = 0; melody_on = 0; echo_on = 0; bass_on = 0; chords_on = 0; arp_on = 0;
		scale = 0;
		nonharmonic = 0;
		arp_stop_slow = 0; arp_high = 0;
		keys_en = 0; melody_saw_en = 0; pwm_en = 0;
		organ_chords_en = 0;
		chords_stutter_en = 0;
		lower_end = 0;
		force_pattern3 = 0; force_stay_at_end = 0;
		chords_snh_en = 0;
		chords_loud = 0;
		bass_soft = 0;

		//en_34 = 0; bass_on = 1; melody_on = 1; echo_on = 1; chords_on = 1; arp_on = 1;
		//en_34 = 1; melody_on = 1; echo_on = 1; bass_on = 0; chords_on = 0; arp_on = 0;
		//en_34 = 1; melody_on = 1; echo_on = 1; bass_on = 0; chords_on = 1; arp_on = 0;
		//en_34 = 1; melody_on = 1; echo_on = 0; bass_on = 0; chords_on = 0; arp_on = 0;
		//en_34 = t[0]; // just to check synthesis

		case (part)
			0, 6: begin
				// 3/4, h+ -> h
				scale = 4;
				en_34 = 1;
				organ_chords_en = 1;
				//organ_chords_en = !melody_voice;
				melody_on = 1; echo_on = 1; bass_on = 0; chords_on = 0; arp_on = 0;
				chords_on = 1; // TODO: Do I want this?
				if (part[2]) begin
					melody_saw_en = 1; pwm_en = 1;
					lower_end = 1;
					chords_on = 1;
					force_pattern3 = 1;

					//if (pattern[0] != t_int0_ge_54) force_stay_at_end = 1;
				end

				//if (!melody_voice) en_34 = 0; // !!!


				if (final_measure) begin
					chords_on = 1;
					if (!melody_voice && !part[2]) scale = 0;

					//if (!part[2]) chords_stutter_en = 1; // !!!
				end
			end
			1, 4: begin
				scale = 0;

				// bass -> chords -> arp
				//bass_on = 1;
/*
				chords_on = (pattern != 0);
				arp_on = pattern[1];
*/

/*
				if (bass_voice) begin
					//if (pattern == 0) en_34 = 1;
					//if (pattern == 1 && !measure[0]) en_34 = 1;
					if (pattern == 0 && !t_int0[3]) en_34 = 1;
				end
*/
				//chords_on = pattern[1];
				//chords_on = pattern[0];
				//arp_on = (pattern == 3);
				//arp_on = pattern[1];
/*
				chords_on = (pattern != 1);
				arp_on = (pattern == 3);
				if (pattern == 0) begin
					if (melody_voice || chords_voice) begin
						en_34 = 1;
						organ_chords_en = 1;
					end
					chords_stutter_en = 1;
				end
				//bass_on = 0; // !!!!
*/

				arp_high = 0;
				arp_stop_slow = 0;

				if (part[2]) begin
					bass_on = pattern[1];
					chords_on = 1;
					//chords_loud = 1;
					arp_on = (pattern == 3);
					chords_snh_en = 1;
					if (final_measure) begin
						arp_high = 1; arp_stop_slow = 1;
					end
				//end else if (pattern == 0) begin
				//end else if (pattern[0] == 0) begin
				end else begin
					//pwm_en = 1;
					bass_on = (pattern != 0);
					//chords_on = (pattern != 2);
					chords_on = (pattern != 1) || (measure == 0);
					melody_on = (pattern == 0);
					organ_chords_en = (pattern == 0);
					arp_on = (pattern == 3);
					//en_34 = !measure[0];
					//en_34 = 0;
					//en_34 = !melody_voice;
					if (measure == 3) begin
						bass_on = 1;
						organ_chords_en = 0;
						//chords_on = 0;
					end
				end
/*
				// arp -> bass -> +chords -> +arp
				bass_on = (pattern != 0);
				chords_on = pattern[1];
				arp_on = (pattern == 0) || (pattern == 3);
*/
			end
			2: begin
				// 4/4 melody
				scale = 0;
				melody_saw_en = 1; pwm_en = 1;
				melody_on = 1; echo_on = 1; bass_on = 1; chords_on = 1; arp_on = 0;

				if (final_measure && !melody_voice) scale = 4;
			end
			3: begin
				// 4/4 keys, rising scale
				scale = {1'b1, pattern};
				nonharmonic = 1;
				melody_on = 1; echo_on = 1; bass_on = 1; chords_on = 1; arp_on = 0;
				keys_en = 1;
				bass_soft = 1;
				//chords_stutter_en = 1;

				if (final_measure && !melody_voice) scale = 0;
			end
			5: begin
				// everything
				scale = 0;
				pwm_en = 1;
				melody_on = 1; echo_on = 1; bass_on = 1; chords_on = 1; arp_on = 1;
				arp_high = 1; arp_stop_slow = 1;
				chords_snh_en = 1;

				if (final_measure && !melody_voice) scale = 4;
			end
			default: begin
				en_34 = 'X; melody_on = 'X; echo_on = 'X; bass_on = 'X; chords_on = 'X; arp_on = 'X;
				scale = 'X;
			end
		endcase

		//melody_on = 0;
		echo_on = melody_on;
		//echo_on = 0;
		time_echo_on = echo_on;

/*
		en_34 = 0; melody_on = 0; echo_on = 0; bass_on = 0; chords_on = 0; arp_on = 0;
		scale = 0;
		arp_stop_slow = 0; arp_high = 0;
		keys_en = 0;
		organ_chords_en = 0;
		lower_end = 0;
		force_pattern3 = 0;
		chords_snh_en = 0;

		scale = 0;
		chords_on = 1;
		chords_snh_en = 1;
*/
		//chords_snh_en = 1;
	end

	wire [2:0] snh_level;
	snh_seq #(.BIAS(2)) snh_seq_inst(
		.t(t_int0[5:0]),
		.level(snh_level)
	);


	localparam T_ECHO_INT_BITS = 6;

	wire [T_BITS-1:0] t_offset = ((voice>>2) == 1) && time_echo_on ? -2 << T_FRAC_BITS : 0;
	logic [T_BITS-1:0] t_echo;
	always_comb begin
		t_echo = t + t_offset;
		t_echo[T_BITS-1:T_ECHO_INT_BITS+T_FRAC_BITS] = t[T_BITS-1:T_ECHO_INT_BITS+T_FRAC_BITS];
	end


	// 3/4
	localparam T_L34_SKIP_BITS = 5; // volume envelops should still have ok precision
	localparam T_INT_BITS_34 = 4;
	localparam T_BITS_L34 = T_INT_BITS_34 + T_FRAC_BITS;

	logic [T_BITS_L34-1:0] t_l_shr2;
	always_comb begin
		t_l_shr2 = t_echo[T_BITS_L34-1:0] >> 2;
		//t_l_shr2[T_L34_SKIP_BITS-1:0] = '0; // mask out some bits that shouldn't be needed
	end

	//wire [T_BITS_L34-1:0] t_l34 = t_echo[T_BITS_L34-1:0] - (en_34 ? t_l_shr2 : '0);
	logic [T_BITS_L34-1:0] t_l34;
	logic t_34_overflow;
	always_comb begin
		t_34_overflow = 0;
		t_l34 = t_echo[T_BITS_L34-1:0] - (en_34 ? t_l_shr2 : '0);
		if (en_34 && t_l34[T_BITS_L34-1 -:2] == '1) begin
			t_34_overflow = 1;
			t_l34[T_BITS_L34-1 -:4] = 11;
		end
	end

	wire [T_BITS-1:0] t_34 = {t_echo[T_BITS-1:T_BITS_L34], t_l34};


	// TODO: Does it need to be based on t_34 or t_echo instead of t?
	wire [T_INT_BITS-1:0] t_int = t[T_INT_BITS+T_FRAC_BITS-1 -: T_INT_BITS];
	wire [T_INT_BITS-1:0] t34_int = t_34[T_INT_BITS+T_FRAC_BITS-1 -: T_INT_BITS];


	wire [2:0] mel_note7, root_note;
	wire [2:0] mel_oct0;
	wire mel_note_on;
	wire mel_note_start, mel_note_stop, mel_note_stop_slow;
	wire root_note_start, root_note_stop;
	wire sus4, add_f, dup_root;

//	wire [T_INT_BITS+1-1:0] t_offset = ((voice>>2) == 1) ? -4 : 0;
//	wire [T_INT_BITS+1-1:0] t_offset = ((voice>>2) == 1) ? -2 : 0;

//	wire [7:0] melody_t = t_34[T_INT_BITS+T_FRAC_BITS-1 -: T_INT_BITS] | (force_pattern3 ? 64*3 : '0);
//	wire [7:0] melody_t = t_34[T_INT_BITS+T_FRAC_BITS-1 -: T_INT_BITS] & 63;

	logic [7:0] melody_t;
	always_comb begin
		melody_t = t_34[T_INT_BITS+T_FRAC_BITS-1 -: T_INT_BITS];
		if (force_pattern3) melody_t[7:6] = 1;
		if (force_stay_at_end) melody_t[5:0] = 52;
	end

//	wire [7:0] melody_t_offset = melody_t + t_offset; // TODO: don't need to offset between patterns

	melody_rom #(.OCT0(2+BASE_OCT)) melody_rom_inst(
//		.t(t_34[T_INT_BITS+T_FRAC_BITS-1 -: (T_INT_BITS+1)] - (voice[2] ? 4 : 0)),
//		.t(t_34[T_INT_BITS+T_FRAC_BITS-1 -: (T_INT_BITS+1)] + t_offset),
//		.t({melody_t_offset, t_34[T_FRAC_BITS-1]}),
		.t({melody_t, t_34[T_FRAC_BITS-1]}),
		.mode_34(en_34), .lower_end(lower_end),
		.note_out(mel_note7), .oct(mel_oct0), .note_on(mel_note_on), .note_start(mel_note_start), .note_stop(mel_note_stop), .note_stop_slow(mel_note_stop_slow),
		.root_note_out(root_note), .sus4(sus4), .add_f(add_f), .dup_root(dup_root),
		.root_note_start(root_note_start), .root_note_stop (root_note_stop)
	);

//	wire [1:0] pattern = melody_t[7:6];
//	wire [1:0] measure = melody_t[5:4];
	wire [5:0] pattern_index0 = {melody_t[5:1], 1'b0};


	//wire [T_INT_BITS-1:0] tbass_int = t34_int;
	wire [T_INT_BITS-1:0] tbass_int = t_int;

	logic bass_note_on, bass_note_stop_slow;
	logic [2:0] bass_delta;
	always_comb begin
		bass_delta = 0;
		bass_note_on = 0;
		bass_note_stop_slow = 0;

		case (tbass_int[4:0] & ~1)
			0, 4, 8, 14, 20, 24: begin; bass_note_on = 1; end
			//10: begin; bass_note_on = 1; end
			2, 12, 16: begin; bass_note_on = 1; bass_note_stop_slow = 1; end
			6, 18: begin; bass_note_on = 1; bass_delta = 4; end
			22: begin; bass_note_on = 1; bass_delta = 2; end
			26: begin; bass_note_on = 1; bass_delta = 4; bass_note_stop_slow = 1; end
		endcase
		if (tbass_int[5]) case (tbass_int[4:0] & ~1)
			22: begin; bass_note_on = 1; bass_delta = 1; end
			26: begin; bass_note_on = 1; bass_delta = 2; end
			28: begin; bass_note_on = 1; end
			30: begin; bass_note_on = 1; bass_delta = 4; bass_note_stop_slow = 1; end
		endcase
	end


	wire [T_FRAC_BITS+1-1:0] t_frac_i1 = t_34[T_FRAC_BITS+1-1:0];
	wire [T_FRAC_BITS+1-1:0] t_frac_i1_inv = ~t_frac_i1;


	wire [2:0] arpy_note;
	wire arpy_stop_slow;
	arpy arpy_inst(
		.t_in(t_int[3:1]), .root_note(root_note), .sus4(sus4),
		.note(arpy_note), .stop_slow(arpy_stop_slow)
	);


	logic voice_on;
	logic note_on;
	logic [2:0] note7;
	logic [OCT_BITS-1:0] oct0;
	logic [1:0] delta_mul;
	logic [OCT_BITS-1:0] delta_oct;
	logic delta_oct4;
	logic note_start, note_stop, note_stop_slow;
	logic saw, neg_pwm_offs;
	logic [NSHIFT_BITS-1:0] nshift;
	logic [ACC_BITS-1:0] slope_frac; // LSB is not used
	logic signed [ACC_BITS-1:0] pwm_offs;
	logic [1:0] gain_shr;

	logic [1:0] note_src;
	logic [2:0] delta_note;
	logic wrap_octave;
	logic root_high;

	logic delta_note_from_chord_en;
	logic [1:0] delta_note_from_chord_index;

	logic nshift_keys_en;

	wire [4:0] voice_case = voice | (organ_chords_en ? (voice[3] << 4): 0);
//	wire [4:0] voice_case = voice | (organ_chords_en ? {{2{!voice[4]}}, 3'b000}: 0);

//	wire [ACC_BITS-1:0] pwm_offs_t = gphase >> 3;
	wire [ACC_BITS-1:0] pwm_offs_t = gphase >> 4;
//	wire [ACC_BITS-1:0] pwm_offs_t = gphase >> 5;

	//int temp1, temp2;
	always_comb begin
		voice_on = 1;
		note_on = 0;
		delta_oct = 0;
		delta_oct4 = 0;

//		note7 = 'X;
//		oct0 = 'X;

		note_start = 0;
		note_stop = 0;
		note_stop_slow = 0;

		delta_mul = 0;

		nshift = 'X;
		saw = 0;
		neg_pwm_offs = 0;
		gain_shr = 0;

		note_src = 0;
		delta_note = 0;
		wrap_octave = 0;
		root_high = 0;

		slope_frac = 0;
		pwm_offs = -512;

		delta_note_from_chord_en = 0;
		delta_note_from_chord_index = 'X;

		nshift_keys_en = 0;

		instrument = -1;

//		case (voice[4:2])
		case (voice_case[4:2])
			// melody + echo
			0, 1: begin
				voice_on = voice[2] ? echo_on : melody_on;
				if (!keys_en) begin
					// Organ
					instrument = 0;
					nshift = 2;
					delta_mul = voice[1:0];
					delta_oct = voice[0];
					//gain_shr = voice[2];
					gain_shr = voice[2] ? 2 : 1;

					note_on = mel_note_on;
					note_src = 0;
					//note7 = mel_note7;
					//oct0 = mel_oct0;
					note_start = mel_note_start;
					note_stop = mel_note_stop;
					note_stop_slow = mel_note_stop_slow;

					if (melody_saw_en) begin
						delta_oct = 0;
						saw = 1;
						nshift = 4;
					end
`ifdef USE_WF_PWM
					if (pwm_en) begin
						pwm_offs = pwm_offs_t[8:0] + 256;
						neg_pwm_offs = pwm_offs_t[9];
					end
`endif
				end else begin
					instrument = 1;
					// Keys
					pwm_offs = -293;
					nshift_keys_en = 1;
					delta_mul = voice[0];
					//delta_mul = 0; // TODO: detune
					delta_oct = 0;
					//delta_oct = voice[1];
					//gain_shr = voice[2];
					gain_shr = voice[2] ? 2 : 1;
					//gain_shr = voice[2] ? 2 : 0;

					note_on = mel_note_on;
					note_src = 0;
					//note7 = mel_note7;
					//oct0 = mel_oct0;
					//note_start = mel_note_start; // TODO: use?
					//note_stop = mel_note_stop || mel_note_stop_slow;

					// OK to just use the same?
					note_stop = mel_note_stop;
					note_stop_slow = mel_note_stop_slow;
				end
			end
			// bass
			2: begin
				instrument = 2;
				voice_on = bass_on;
				//nshift = 5;
				//if (bass_soft) nshift = t_int[1] ? 4 : 3;
				if (bass_soft) nshift = 4;
				else nshift = t_int[1] ? 7 : 5;

				saw = 1;
				delta_mul = voice[1:0];
				gain_shr = 0; //(delta_mul == 0 || delta_mul == 3); // reduce the volume a bit to avoid saturation for now


				delta_oct = bass_delta[2];
				if (bass_delta[1:0] != 0) begin
					delta_note_from_chord_en = 1;
					delta_note_from_chord_index = bass_delta[1:0];
				end

				note_on = bass_note_on;
				note_src = 1;
				//note7 = root_note;
				//oct0 = 0;
				// TODO: note_start/note_stop?
				note_start = bass_soft;
				note_stop_slow = bass_note_stop_slow;
				note_stop = 1;
			end

			// arpeggio
			3: begin
				instrument = 3;
				voice_on = arp_on;
				nshift = 2;
				delta_mul = voice[1:0];
				delta_oct = voice[0];
				gain_shr = 2;

				note_on = 1;
				note_start = 1;
				note_stop = !arp_stop_slow;
				note_stop_slow = arp_stop_slow;
				if (arpy_stop_slow) begin
					note_stop = 0;
					note_stop_slow = 1;
				end
				note_src = 2;
			end

			// chords
			4, 5, 6, 7: begin
				instrument = 4;
				delta_note_from_chord_en = 1;
				delta_note_from_chord_index = voice[2:1];

				voice_on = chords_on;
				saw = 1; nshift = 3;
				if (organ_chords_en) begin
					saw = 0; nshift = 2;
					//if (t_int[0]==0) nshift = 3; // !!!
					//if (t_int[1]==0) nshift = 3; // !!!
				end
				if (chords_snh_en) nshift = snh_level;
				//delta_mul = voice[0] ? 0 : 2;
				delta_mul = {voice[0], voice[3]};

				delta_oct = BASE_OCT-BASS_OCT + 2;
				gain_shr = !chords_loud; // TODO: too low?
				if (organ_chords_en) begin
					gain_shr = 2;
					if (delta_note_from_chord_index == 0) delta_oct = BASE_OCT-BASS_OCT;
					else delta_oct = BASE_OCT-BASS_OCT + 1;
					delta_oct4 = voice[3];
				end

				//if (chords_stutter_en) nshift = t34_int[1] ? 2 : 4;
				//if (chords_stutter_en) nshift = 3;

				note_on = 1;
				note_src = 1;

				note_start = root_note_start;
				//note_stop_slow = root_note_stop;
				note_stop = root_note_stop;

				// note_start = 1; note_stop_slow = 1; note_stop = 0; // !!!

				//note_start |= !t_int[1]; note_stop_slow |= t_int[1]; note_stop = 0; // !!!
				/*
				if (pattern == 1) begin
					note_start |= t_int[3:1] == 0; note_stop_slow |= t_int[3:1] == '1; note_stop = 0; // !!!
				end
				*/
				/*
				if (pattern[1]) begin
					note_start |= t_int[2:1] == 0; note_stop_slow |= t_int[2:1] == '1; note_stop = 0; // !!!
				end
				if (pattern == 3 && measure[1]) begin
					note_start |= !t_int[1]; note_stop_slow |= t_int[1]; note_stop = 0; // !!!
				end
				*/
				
				if (chords_stutter_en && !note_stop) begin
					//note_start |= !t34_int[1]; note_stop_slow |= t34_int[1];
					note_start |= !t_int[1]; note_stop_slow |= t_int[1];
				end
				/*
				if (chords_stutter_en && !note_stop && !note_start) begin
					note_start |= 1; note_stop_slow |= 1;
				end
				*/
				if (pattern == 3 || force_pattern3) begin
					if (pattern_index0 == 48) note_on = 0;
					if (pattern_index0 == 50) note_start = 1;
				end

				// TODO: note_start/note_stop?
/*
				case (voice[2:1])
					0: delta_note = 0;
					1: delta_note = sus4 ? 3 : 2;
					2: delta_note = 4;
					3: begin
						delta_note = 0;
						note_src = 3;
						note_on = add_f;
					end
					default: note_on = 0;
				endcase
*/
			end

			default: voice_on = 0;
		endcase

		if (delta_note_from_chord_en) begin
			case (delta_note_from_chord_index)
				0: delta_note = 0;
				1: delta_note = sus4 ? 3 : 2;
				2: delta_note = 4;
				3: begin
					delta_note = 0;
					if (dup_root) begin
						root_high = 1;
					end else if (add_f) begin
						note_src = 3;
					end else note_on = 0;
				end
				default: note_on = 0;
			endcase // voice[2:1]
		end

		if (nshift_keys_en) begin
			if (mel_note_start) begin
				//{nshift, slope_frac} = ~t_frac_i1 >> (T_FRAC_BITS+1-(ACC_BITS+2));
				//{nshift, slope_frac} = ~t_frac_i1 >> (T_FRAC_BITS+1-(ACC_BITS+3));
				{nshift, slope_frac} = ~t_frac_i1 >> (T_FRAC_BITS+1-(ACC_BITS+1));
				//{nshift, slope_frac} = ~t_frac_i1 >> (T_FRAC_BITS+1-(ACC_BITS));
				nshift += 1;

				//temp1 = t_frac_i1_inv;
				//temp2 = (t_frac_i1_inv >> (T_FRAC_BITS+1-(ACC_BITS-2)));
				//pwm_offs = -512 | (t_frac_i1_inv >> (T_FRAC_BITS+1-(ACC_BITS-2)));
			end else begin
				{nshift, slope_frac} = 0;
				nshift = 1;
				pwm_offs = -512;
			end
		end

		if (force_stay_at_end) note_start = 0;

		//if (voice < 20) voice_on = 0;
		//if (voice >= 12 && voice < 20) voice_on = 0;
	end

	logic [2:0] note7_0;
	always_comb begin
		note7_0 = 'X;
		oct0 = 'X;
		case (note_src)
			0: begin
				note7_0 = mel_note7;
				oct0 = mel_oct0;
			end
			1: begin
				note7_0 = root_note;
				//oct0 = root_high ? BASS_OCT + 1 : BASS_OCT;
				oct0 = BASS_OCT;
			end
			2: begin
				note7_0 = arpy_note;
				oct0 = arp_high ? BASE_OCT + 4 : BASE_OCT + 3;
			end
			3: begin
				note7_0 = 4;
				oct0 = BASS_OCT;
			end
			default: begin
				note7_0 = 'X;
				oct0 = 'X;
			end
		endcase
	end

	wire [3:0] note_sum = note7_0 + delta_note;
	wire high_oct = note_sum[3] || (note_sum == 7);
	assign note7 = note_sum[2:0] + high_oct;
	wire delta_oct2 = high_oct && !wrap_octave;

/*
	wire voice_on = voice[VOICE_BITS-1:3] == 0;

	logic [1:0] delta_mul = {voice[0], voice[1]};
	logic [OCT_BITS-1:0] delta_oct = voice[1];
*/
	wire [9:0] multiplier0, multiplier00;
	wire delta_oct3;
`ifdef USE_SCALES
	multiplier_lookup mul_lookup(
		.note7(note7), .scale(scale), .nonharmonic(nonharmonic),
		.multiplier(multiplier00), .delta_oct(delta_oct3)
	);
`else
	multiplier_table7 mul_table7(
		.note7(note7),
		.multiplier(multiplier00)
	);
	assign delta_oct3 = 0;
`endif


	wire signed [5:0] factor_b_index;

	logic mul0_override, delta_mul_override;
	always_comb begin
		mul0_override = 0;
		delta_mul_override = 0;
		if (gphase_override) begin
			//if (factor_b_index[4:1] > 4) mul0_override = 1;
			if (factor_b_index[4:1] > 5) mul0_override = 1;
			//if (factor_b_index[4:1] > 6) mul0_override = 1;
		end
	end


	assign multiplier0 = mul0_override ? 1 : multiplier00;
	wire [1:0] delta_mul_eff = delta_mul_override ? 1 : delta_mul;

	wire [1:0] delta_oct23 = delta_oct2 + (delta_oct3|root_high) + delta_oct4; // delta_oct3 = 1 only for Ab when scale != 0. TODO: shouldn't coincide with root_high?
	wire [OCT_BITS-1:0] oct = oct0 + delta_oct + delta_oct23;

	wire [9:0] multiplier1 = multiplier0 + delta_mul_eff;
	logic [9:0] multiplier;
	always_comb begin
		multiplier = multiplier0;
		multiplier[MULTIPLIER_ADDITION_BITS-1:0] = multiplier1;
	end

	//wire en = note_on || state[5];
	wire en = 1; // don't block out_acc reset!

	localparam VOL_BITS = ACC_BITS-1;

	// Hack
	localparam TFM_SHL = 0;
	localparam TFM_SHR = 0; //4;
	localparam TFM_BITS = T_FRAC_BITS + TFM_SHL;
	//wire [TFM_BITS-1:0] tfm = t_frac_i1[T_FRAC_BITS] ? ({~t_frac_i1} >> TFM_SHR) : {t_frac_i1, {TFM_SHL{1'b0}}};
	//wire [TFM_BITS-1:0] tfm = t_frac_i1[T_FRAC_BITS] ? {~t_frac_i1, {TFM_SHL{1'b0}}} : {t_frac_i1, {TFM_SHL{1'b0}}};
	//wire [TFM_BITS-1:0] tfm = ({~t_frac_i1} >> TFM_SHR);
	//wire [TFM_BITS-1:0] tfm = t_frac_i1[T_FRAC_BITS] ? ~t_frac_i1 : t_frac_i1;

	logic [TFM_BITS-1:0] tfm;
	always_comb begin
		//if (note_stop_slow) tfm = {~t_frac_i1} >> (T_FRAC_BITS+1-VOL_BITS);
		if (note_stop_slow && !(note_start && t_frac_i1[T_FRAC_BITS+1-1:VOL_BITS-TFM_SHL] == 0)) tfm = {~t_frac_i1} >> (T_FRAC_BITS+1-VOL_BITS);
		else tfm = t_frac_i1[T_FRAC_BITS] ? ({~t_frac_i1} >> TFM_SHR) : {t_frac_i1, {TFM_SHL{1'b0}}};
	end

	logic fade_on;
	logic [ACC_BITS-1:0] vol;
	always_comb begin
		if (t_34[T_FRAC_BITS] == 0) fade_on = note_start;
		else fade_on = note_stop;
		if (note_stop_slow) fade_on = 1;

		vol = 511;
		if (tfm[TFM_BITS-1:9] == 0 && fade_on) vol = tfm;

		//if (!(note_on && voice_on)) vol = 0;
	end

	wire high_saw = (pwm_en && melody_voice);

	wire note_on_eff = note_on && voice_on && !((note_stop || note_stop_slow) && t_34_overflow);
	wire [ACC_BITS-1:0] src1_out, src2_out;
	synth_scheduler #(.OUT_ACC_BITS(OUT_ACC_BITS), .OCT_BITS(OCT_BITS), .STATE_BITS(STATE_BITS), .DELTA_SIGMA_BITS(DELTA_SIGMA_BITS)) sched(
		.clk(clk), .reset(reset), .en(en),

		.note_on(note_on_eff),
		//.first_voice(voice == 0),
		.first_voice(first_voice),
		.state(state),
		.src2_note_mul(multiplier), .src2_pwm_offs(pwm_offs), .src2_vol(vol), .src2_slope_frac(slope_frac), .out_acc_initial(out_acc_initial),
		.oct(oct), .nshift(nshift), .gain_shr(gain_shr), .saw(saw), .high_saw(high_saw), .neg_pwm_offs(neg_pwm_offs),

		.bdrum_phase('X), .bdrum_en(0), .force_no_b_delay(0),

		.override_en(0), .override_src2_sel('X), .override_wes('X),

		.out_acc_out(out_acc),

`ifndef DUPLICATE_SYNTH
		.new_voice_sample(new_voice_sample), .new_voice_sample_pregain(new_voice_sample_pregain),
		.acc_out(acc),
`endif

		.skip_out_acc_update(skip_out_acc_update),
		.gphase_in(gphase_in), .gphase_override(gphase_override),

		.src1_in('X), .src2_in('X),
		.src1_out(src1_out), .src2_out(src2_out),
		.factor_b_index_out(factor_b_index),
		.gphase_out(gphase)
	);

`ifdef DUPLICATE_SYNTH
	synth_scheduler #(.OUT_ACC_BITS(OUT_ACC_BITS), .OCT_BITS(OCT_BITS), .STATE_BITS(STATE_BITS), .DELTA_SIGMA_BITS(DELTA_SIGMA_BITS), .REDUCED(1)) sched_reduced(
		.clk(clk), .reset(reset), .en(en),

		.note_on(note_on_eff),
		//.first_voice(voice == 0),
		.first_voice(first_voice),
		.state(state),
		.src2_note_mul(multiplier), .src2_pwm_offs(pwm_offs), .src2_vol(vol), .src2_slope_frac(slope_frac), .out_acc_initial(out_acc_initial),
		.oct(oct), .nshift(nshift), .gain_shr(gain_shr), .saw(saw), .high_saw(high_saw), .neg_pwm_offs(neg_pwm_offs),

		.bdrum_phase('X), .bdrum_en(0), .force_no_b_delay(0),

		.override_en(0), .override_src2_sel('X), .override_wes('X),

		.src1_in(src1_out), .src2_in(src2_out), .gphase_in(gphase_in),

		.new_voice_sample(new_voice_sample), .new_voice_sample_pregain(new_voice_sample_pregain),
		.acc_out(acc)
	);
`endif


	assign t34_int_out = t34_int;
	assign note_on_out = note_on && voice_on;
	assign multiplier_out = multiplier;
	assign oct_out = oct;
	assign gain_shr_out = gain_shr;
	assign vol_out = vol;
endmodule : music_player
