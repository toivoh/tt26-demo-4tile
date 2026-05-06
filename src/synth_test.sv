/*
 * Copyright (c) 2026 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

module synth_alu #(
		parameter FACTOR_A_BITS = 10,
		GPHASE_BITS = 19, OUT_ACC_BITS = 15,
		DELTA_SIGMA_BITS = 4,
		// Don't change:
		ACC_BITS = FACTOR_A_BITS // Must be even and >= FACTOR_A_BITS
	) (
		input wire clk, reset, en,

		input wire [ACC_BITS-1:0] src2_note_mul, src2_pwm_offs, src2_vol, src2_slope_frac,
		input wire [OUT_ACC_BITS-1:0] out_acc_initial,

		input wire [`SRC1_BITS-1:0] src1_sel,
		input wire [`SRC2_BITS-1:0] src2_sel,
		input wire [`SRC2MOD_BITS-1:0] src2_mod,
		input wire [`FLAG_BITS-1:0] flags,
		input wire [`RES_BITS-1:0] res_sel,
		input wire [`WE_BITS-1:0] wes, // NOTE: WE_BIT_ACC must be set if writing to any of the latches

		input wire [1:0] factor_b,
		input wire first_factor_b,
		input wire final_factor_b, // can be held low if ACC_BITS > FACTOR_A_BITS and also when computing a full product

		input wire [ACC_BITS-1:0] add_mask,

		output wire [GPHASE_BITS-1:0] gphase_out,
		output wire signed [ACC_BITS-1:0] acc_out,
		output wire signed [OUT_ACC_BITS-1:0] out_acc_out,

		output wire [ACC_BITS-1:0] src2_out,
		output wire booth_carry_out,
		output wire [ACC_BITS-1:0] result_out
	);

	localparam SRC2_BITS = FACTOR_A_BITS + 1;

	localparam GPHASE_LOW_BITS  = ACC_BITS;
	localparam GPHASE_HIGH_BITS = GPHASE_BITS - ACC_BITS;

	localparam OUT_ACC_LOW_BITS  = ACC_BITS;
	localparam OUT_ACC_HIGH_BITS = OUT_ACC_BITS - ACC_BITS;



	reg signed [ACC_BITS-1:0] acc;
	reg carry;


	wire signed [ACC_BITS+2-1:0] sum;
	logic [ACC_BITS-1:0] result;


	wire [ACC_BITS-1:0] gphase_low, gphase_high;
	wire [ACC_BITS-1:0] out_acc_low, out_acc_high;
	// OPT: Do we actually need to reset these?
	p_latch_register #(.BITS(GPHASE_LOW_BITS),   .NEXT_WDATA_EN(1)) gphase_low_register( .clk(clk),  .reset(reset), .we(wes[`WE_BIT_GPHASE_LOW]),   .next_we(wes[`WE_BIT_GPHASE_LOW]),   .reset_wdata('0), .wdata(acc), .next_wdata(result[GPHASE_LOW_BITS-1:0]),   .rdata(gphase_low));
	p_latch_register #(.BITS(GPHASE_HIGH_BITS),  .NEXT_WDATA_EN(1)) gphase_high_register(.clk(clk),  .reset(reset), .we(wes[`WE_BIT_GPHASE_HIGH]),  .next_we(wes[`WE_BIT_GPHASE_HIGH]),  .reset_wdata('0), .wdata(acc), .next_wdata(result[GPHASE_HIGH_BITS-1:0]),  .rdata(gphase_high));

	p_latch_register #(.BITS(OUT_ACC_LOW_BITS),  .NEXT_WDATA_EN(1)) out_acc_low_register( .clk(clk), .reset(reset), .we(wes[`WE_BIT_OUT_ACC_LOW]),  .next_we(wes[`WE_BIT_OUT_ACC_LOW]),  .reset_wdata('0), .wdata(acc), .next_wdata(result[OUT_ACC_LOW_BITS-1:0]),  .rdata(out_acc_low));
	p_latch_register #(.BITS(OUT_ACC_HIGH_BITS), .NEXT_WDATA_EN(1)) out_acc_high_register(.clk(clk), .reset(reset), .we(wes[`WE_BIT_OUT_ACC_HIGH]), .next_we(wes[`WE_BIT_OUT_ACC_HIGH]), .reset_wdata('0), .wdata(acc), .next_wdata(result[OUT_ACC_HIGH_BITS-1:0]), .rdata(out_acc_high));

	assign gphase_out = {gphase_high, gphase_low};
	assign out_acc_out = {out_acc_high, out_acc_low};


	wire booth_en = src2_mod[`SRC2MOD_BIT_BOOTH];


	// Booth multiplier
	// ================

	wire [2:0] factor_b_1 = factor_b + (carry && !first_factor_b); // 0 - 4
	// If the factor is 2
	// - if this is the final cycle, add
	// - otherwise,
	//   - if acc >= 0, subtract
	//   - if acc < 0, add
	wire next_booth_carry = factor_b_1[2] || (factor_b_1[1:0] == 3) || (factor_b_1 == 2 && !acc[ACC_BITS-1] && !final_factor_b);

	logic booth_add_en, booth_shl, booth_inv;
	always_comb begin
		case (factor_b_1[1:0])
			0: begin; booth_add_en = 0; booth_shl =  0; booth_inv =  0; end
			1: begin; booth_add_en = 1; booth_shl =  0; booth_inv =  0; end
			2: begin; booth_add_en = 1; booth_shl =  1; booth_inv =  next_booth_carry; end
			3: begin; booth_add_en = 1; booth_shl =  0; booth_inv =  1; end
			default: begin; booth_add_en = 'X; booth_shl = 'X; booth_inv = 'X; end
		endcase
	end


	// ALU
	// ===

	wire src2_shl = booth_en ? booth_shl : src2_mod[`SRC2MOD_BIT_SHL1];
	wire src2_inv = booth_en ? booth_inv : src2_mod[`SRC2MOD_BIT_NEG];
	wire src2_zero = booth_en ? !booth_add_en : src2_mod[`SRC2MOD_BIT_ZERO];

	wire carry_in = ((src2_inv) && !src2_mod[`SRC2MOD_BIT_CARRY_IN_CONTROL]) || src2_mod[`SRC2MOD_BIT_CARRY_IN];

	logic signed [ACC_BITS-1:0] acc_in;
	logic [SRC2_BITS-1:0] src2;
	always_comb begin
		acc_in = 'X;
		case (src1_sel)
			`SRC1_ZERO:     acc_in = '0;
			`SRC1_ACC:      acc_in = acc;
			`SRC1_MINUS1:   acc_in = '1;
			//`SRC1_ACC_SHL1: acc_in = acc << 1;
			//`SRC1_INV_ACC:  acc_in = ~acc;
			default: acc_in = 'X;
		endcase

		src2 = 'X;
		case (src2_sel)
			`SRC2_NOTE_MUL:     src2 = src2_note_mul;
			`SRC2_PWM_OFFS:     src2 = {src2_pwm_offs[ACC_BITS-1], src2_pwm_offs}; // sign extend. TODO: needed in more places?
			`SRC2_VOL:          src2 = src2_vol;
			`SRC2_SLOPE_FRAC:   src2 = src2_slope_frac >> 1;
			`SRC2_GPHASE_LOW:   src2 = gphase_low;
			`SRC2_GPHASE_HIGH:  src2 = gphase_high;

			`SRC2_OUT_ACC_LOW:  src2 = out_acc_low;
			`SRC2_OUT_ACC_LOW0: begin
				src2 = out_acc_initial[ACC_BITS-1:0];
				if (DELTA_SIGMA_BITS > 0) src2[DELTA_SIGMA_BITS-1:0] = out_acc_low[DELTA_SIGMA_BITS-1:0];
			end
			`SRC2_OUT_ACC_HIGH: src2 = out_acc_high;
			`SRC2_OUT_ACC_HIGH0:src2 = out_acc_initial[OUT_ACC_BITS-1:ACC_BITS];

			`SRC2_ACC_SHL1:     src2 = acc << 1;
			`SRC2_BDRUM_PHASE:  src2 = 'X;
			default:            src2 = 'X;
		endcase
		if (src2_zero) src2 = '0;
	end
	assign src2_out = src2;


	wire [SRC2_BITS+1-1:0] src2_s = {src2[SRC2_BITS-1] & src2_mod[`SRC2MOD_BIT_SEXT], src2} << src2_shl;
	wire signed [ACC_BITS+2-1:0] src2_i = src2_inv ? ~src2_s : src2_s;

	// sign / zero extend
	wire signed [ACC_BITS+2-1:0] acc_in_ext = {{2{acc_in[ACC_BITS-1] & !flags[`FLAG_ZEXT_ACC]}}, acc_in};

	assign sum = acc_in_ext + src2_i + $signed({1'b0, carry_in});

	wire s1 = sum[ACC_BITS+2-1];
	wire [1:0] s2 = sum[ACC_BITS+1-1 -: 2];
	wire saturate = flags[`FLAG_BIT_SATURATE] && ((s1 == 0 && s2 != '0) || (s1 == 1 && s2 != '1));

	//wire [ACC_BITS-1:0] result = sum[ACC_BITS+2-1:2];
	always_comb begin
		result = 'X;
		case (res_sel)
			`RES_SUM:   result = sum;
			`RES_BOOTH: result = (sum[ACC_BITS+2-1:2] & add_mask) | ({sum[1:0], acc[ACC_BITS-1:2]} & ~add_mask);
			default: result = 'X;
		endcase
		if (saturate) result = s1 ? -(1 << (ACC_BITS-1)) : (1 << (ACC_BITS-1)) - 1;
	end

	wire next_carry = booth_en ? next_booth_carry : sum[ACC_BITS];

	always_ff @(posedge clk) begin
		if (reset) begin
			acc <= 0;
			carry <= 0;
		end else if (en) begin
			if (wes[`WE_BIT_ACC]) acc <= result;
			carry <= next_carry;
		end
	end

	assign acc_out = acc;
	assign booth_carry_out = carry;
	assign result_out = result;
endmodule : synth_alu


module synth_speedup(
		input wire [2:0] speedup,
		input wire [3:0] x,

		output logic fast
	);

	// TODO: Match to unused synth states!
	always_comb begin
		fast = 0;
		//if (speedup[0] && x==8) fast = 1; // skip state = 16
		if (speedup[0] && (x==7 || x == 15)) fast = 1; // skip state = 14, 30
		if (speedup[1] && (x==5 || x == 9 || x == 11 || x == 13)) fast = 1; // skip state = 10, 18, 22, 26
		if (speedup[2] && (x==6 || x == 8 || x == 10)) fast = 1; // skip state = ...
	end
endmodule : synth_speedup


module synth_scheduler  #(
		parameter FACTOR_A_BITS = 10,
		GPHASE_BITS = 19, OUT_ACC_BITS = 15,
		OCT_BITS = 3, NSHIFT_BITS = 3,
		DELTA_SIGMA_BITS = 4,
		// Don't change:
		ACC_BITS = FACTOR_A_BITS, // Must be even and >= FACTOR_A_BITS
		STATE_BITS = 6
	) (
		input wire clk, reset,
		input wire en,

		input wire note_on,
		input wire first_voice,
		input wire [OUT_ACC_BITS-1:0] out_acc_initial,
		input wire [STATE_BITS-1:0] state,
		input wire [ACC_BITS-1:0] src2_note_mul, src2_pwm_offs, src2_vol, src2_slope_frac,
		input wire [OCT_BITS-1:0] oct,
		input wire saw,
		input wire [NSHIFT_BITS-1:0] nshift,
		input wire [`GAIN_SHR_BITS-1:0] gain_shr,

		input wire override_en,
		input wire [`SRC2_BITS-1:0] override_src2_sel,
		input wire [`WE_BITS-1:0] override_wes,

		output wire signed [ACC_BITS-1:0] acc_out,
		output wire signed [OUT_ACC_BITS-1:0] out_acc_out,

		output wire [ACC_BITS-1:0] src2_out,
		output wire booth_carry_out
	);

	// Add one sign bit
	localparam FACTOR_B_INDEX_BITS = $clog2(GPHASE_BITS) + 1;


/*
	localparam STATE_TRI1 = 10;
	localparam STATE_TRI2 = 11;

	// These must be 4 consecutive states
	localparam STATE_SHL0 = 12;
	localparam STATE_SHL1 = 13;
	localparam STATE_SHL2 = 14;
	localparam STATE_SHL3 = 15;

	localparam STATE_SLOPE_FRAC1 = 16;
	localparam STATE_SLOPE_FRAC2 = 17;

	localparam STATE_CLAMP1 = 18;
	localparam STATE_CLAMP2 = 19;

	localparam STATE_GAIN_SHR1 = 20;

	localparam STATE_OUT_ACC1 = 22;
	localparam STATE_OUT_ACC2 = 23;
*/

	// no speedup skips for state < 10

	localparam STATE_TRI1 = 11;
	localparam STATE_TRI2 = 13;

	// These must be 4 2-consecutive states
	localparam STATE_SHL0 = 15;
	localparam STATE_SHL1 = 17;
	localparam STATE_SHL2 = 19;
	localparam STATE_SHL3 = 21;

	localparam STATE_SLOPE_FRAC1 = 23;
	localparam STATE_SLOPE_FRAC2 = 24; // no speedup skip

	localparam STATE_CLAMP1 = 25;
	localparam STATE_CLAMP2 = 27;

	localparam STATE_GAIN_SHR1 = 28; // no speedup skip

	localparam STATE_OUT_ACC1 = 29;
	localparam STATE_OUT_ACC2 = 31;

	localparam STATE_GPHASE1 = 32;
	localparam STATE_GPHASE2 = 33;


	wire [GPHASE_BITS-1:0] gphase;


	logic [`SRC1_BITS-1:0] src1_sel;
	logic [`SRC2_BITS-1:0] src2_sel;
	logic [`SRC2MOD_BITS-1:0] src2_mod;
	logic [`FLAG_BITS-1:0] flags;
	logic [`RES_BITS-1:0] res_sel;
	logic [`WE_BITS-1:0] wes;
	logic [ACC_BITS-1:0] add_mask;
	logic signed [FACTOR_B_INDEX_BITS-1:0] factor_b_index;
	logic first_factor_b;
	//logic [1:0] factor_b;

	logic step_en;
	wire en_eff = en && step_en;

	wire acc_sign = acc_out[ACC_BITS-1];
	reg last_sign;
	always_ff @(posedge clk) if (en_eff) last_sign <= acc_sign && note_on;

	reg tri_part;
	always_ff @(posedge clk) begin
		if (en_eff && (state == STATE_TRI1)) tri_part <= acc_sign;
	end

	// Depends on how STATE_SHL0..3 are spread out
	//wire [1:0] st = state[1:0];
	wire [1:0] st = state[2:1];

	wire [NSHIFT_BITS-1:0] nshift_eff = (saw && tri_part == 0) ? 0 : nshift;

	wire slope_do_shl2 = st < nshift_eff[NSHIFT_BITS-1:1];
	wire slope_do_shl1 = (st == nshift_eff[NSHIFT_BITS-1:1]) && nshift_eff[0];

	always_comb begin
		src1_sel = 'X; src2_sel = 'X;
		src2_mod = '0;
		flags = '0;
		res_sel = `RES_SUM;
		wes = '0;
		add_mask = 'X;
		factor_b_index = 'X;
		first_factor_b = 'X;
		step_en = 1;
		if (override_en) begin
			// write override_src2_sel source to any registers indicated by override_wes
			src1_sel = `SRC1_ZERO;
			src2_sel = override_src2_sel;
			src2_mod = '0;
			res_sel = `RES_SUM;
			wes = override_wes;
			factor_b_index = 0;
			add_mask = '1;
		end else begin
			case (state)
				0, 1, 2, 3, 4, 5, 6, 7, 8, 9: begin
					// note multiplication
					src1_sel = (state == 0) ? `SRC1_ZERO : `SRC1_ACC;
					src2_sel = `SRC2_NOTE_MUL;
					src2_mod[`SRC2MOD_BIT_BOOTH] = 1;
					res_sel = `RES_BOOTH;
					wes[`WE_BIT_ACC] = 1;
					factor_b_index = {state, 1'b0} - oct;
					first_factor_b = (state == 0);
					add_mask = {(2*(ACC_BITS-1)){1'b1}} >> {state, 1'b0}; // OPT? For state < ACC_BITS/2, add_mask will be '1.
				end

				STATE_TRI1: begin
					// triangle
					src1_sel = `SRC1_ZERO;
					src2_sel = `SRC2_ACC_SHL1;
					src2_mod[`SRC2MOD_BIT_CARRY_IN_CONTROL] = 1;
					src2_mod[`SRC2MOD_BIT_NEG] = acc_sign;
					wes[`WE_BIT_ACC] = 1;
				end
				STATE_TRI2: begin
					src1_sel = `SRC1_ACC;
					flags[`FLAG_ZEXT_ACC] = 1;
					src2_sel = `SRC2_PWM_OFFS;
					src2_mod[`SRC2MOD_BIT_SEXT] = 1;
					flags[`FLAG_BIT_SATURATE] = 1;
					wes[`WE_BIT_ACC] = 1;
				end

				STATE_SHL0, STATE_SHL1, STATE_SHL2, STATE_SHL3: begin
					src1_sel = `SRC1_ZERO;
					src2_sel = `SRC2_ACC_SHL1;
					src2_mod[`SRC2MOD_BIT_SEXT] = 1;
					src2_mod[`SRC2MOD_BIT_SHL1] = slope_do_shl2;
					flags[`FLAG_BIT_SATURATE] = 1;
					wes[`WE_BIT_ACC] = slope_do_shl1 || slope_do_shl2;
				end

				STATE_SLOPE_FRAC1: begin
					src1_sel = `SRC1_ACC;
					src2_sel = `SRC2_SLOPE_FRAC;
					src2_mod[`SRC2MOD_BIT_NEG] = !acc_sign;
					// comparison result saved to carry
				end
				STATE_SLOPE_FRAC2: begin
					if (booth_carry_out != acc_sign) begin
						src1_sel = `SRC1_ZERO;
						src2_sel = `SRC2_ACC_SHL1;
						src2_mod[`SRC2MOD_BIT_SEXT] = 1;
					end else begin
						src1_sel = `SRC1_ACC;
						src2_sel = `SRC2_SLOPE_FRAC;
						src2_mod[`SRC2MOD_BIT_NEG] = acc_sign;
					end
					flags[`FLAG_BIT_SATURATE] = 1;
					wes[`WE_BIT_ACC] = 1;
				end

				STATE_CLAMP1: begin
					src1_sel = `SRC1_ACC;
					src2_sel = `SRC2_VOL;
					src2_mod[`SRC2MOD_BIT_NEG] = !acc_sign;
					// comparison result saved to carry
				end
				STATE_CLAMP2: begin
					src1_sel = `SRC1_ZERO;
					src2_sel = `SRC2_VOL;
					src2_mod[`SRC2MOD_BIT_NEG] = acc_sign;
					wes[`WE_BIT_ACC] = (booth_carry_out == acc_sign); //!(booth_carry_out ^ acc_sign);
				end

				STATE_GAIN_SHR1: begin
					// Support gain_shr = 0, 1, or 2
					if (gain_shr != 0) begin
						src1_sel = gain_shr[1] ? `SRC1_ACC : `SRC1_ZERO;
						src2_sel = `SRC2_ACC_SHL1;
						src2_mod[`SRC2MOD_BIT_ZERO] = gain_shr[1];
						src2_mod[`SRC2MOD_BIT_SEXT] = 1;
						res_sel = `RES_BOOTH;
						add_mask = '1;
						wes[`WE_BIT_ACC] = 1;
					end
				end

				STATE_OUT_ACC1: begin
					src1_sel = note_on ? `SRC1_ACC : `SRC1_ZERO;
					flags[`FLAG_ZEXT_ACC] = 1;
					//src2_sel = `SRC2_OUT_ACC_LOW;
					src2_sel = first_voice ? `SRC2_OUT_ACC_LOW0 : `SRC2_OUT_ACC_LOW;
					//src2_mod[`SRC2MOD_BIT_ZERO] = first_voice;
					wes[`WE_BIT_ACC] = 1;
					wes[`WE_BIT_OUT_ACC_LOW] = 1;
				end
				STATE_OUT_ACC2: begin
					src1_sel = last_sign ? `SRC1_MINUS1 : `SRC1_ZERO;
					//src2_sel = `SRC2_OUT_ACC_HIGH;
					src2_sel = first_voice ? `SRC2_OUT_ACC_HIGH0 : `SRC2_OUT_ACC_HIGH;
					src2_mod[`SRC2MOD_BIT_CARRY_IN_CONTROL] = 1;
					src2_mod[`SRC2MOD_BIT_CARRY_IN] = booth_carry_out;
					//src2_mod[`SRC2MOD_BIT_ZERO] = first_voice;
					wes[`WE_BIT_ACC] = 1;
					wes[`WE_BIT_OUT_ACC_HIGH] = 1;
				end

				STATE_GPHASE1: begin
					src1_sel = `SRC1_ZERO;
					flags[`FLAG_ZEXT_ACC] = 1;
					src2_sel = `SRC2_GPHASE_LOW;
					src2_mod[`SRC2MOD_BIT_CARRY_IN_CONTROL] = 1;
					src2_mod[`SRC2MOD_BIT_CARRY_IN] = 1;
					wes[`WE_BIT_ACC] = 1;
					wes[`WE_BIT_GPHASE_LOW] = 1;
				end
				STATE_GPHASE2: begin
					src1_sel = `SRC1_ZERO;
					src2_sel = `SRC2_GPHASE_HIGH;
					src2_mod[`SRC2MOD_BIT_CARRY_IN_CONTROL] = 1;
					src2_mod[`SRC2MOD_BIT_CARRY_IN] = booth_carry_out;
					wes[`WE_BIT_ACC] = 1;
					wes[`WE_BIT_GPHASE_HIGH] = 1;
				end

				default: begin
					wes = '0;
					step_en = 0;
					first_factor_b = 'X;
					src2_mod = 'X;
					flags = 'X;
					res_sel = 'X;
					src1_sel = 'X;
					src2_sel = 'X;
					src2_mod = 'X;
					factor_b_index = 'X;
					add_mask = 'X;
				end
			endcase
		end
	end

	reg prev_factor_b_bit;

	// wire [1:0] factor_b_src = {gphase[{factor_b_index[FACTOR_B_INDEX_BITS-1-1:1], 1'b1} -: 2];

	wire [$clog2(GPHASE_BITS)-1:0] factor_b_index_b1 = {factor_b_index[FACTOR_B_INDEX_BITS-1-1:1], 1'b1};
	wire [$clog2(GPHASE_BITS)-1:0] factor_b_index_b0 = {factor_b_index[FACTOR_B_INDEX_BITS-1-1:1], 1'b0};

	wire [1:0] factor_b_src = factor_b_index[FACTOR_B_INDEX_BITS-1] ? 0 : {gphase[factor_b_index_b1], gphase[factor_b_index_b0]};

//	wire [1:0] factor_b_src = {gphase[{factor_b_index[FACTOR_B_INDEX_BITS-1-1:1], 1'b1}], 
//	                           gphase[{factor_b_index[FACTOR_B_INDEX_BITS-1-1:1], 1'b0}]};

	always_ff @(posedge clk) if (en_eff) prev_factor_b_bit <= factor_b_src[1];
	wire prev_factor_b_bit_eff = (state == 0) ? 0 : prev_factor_b_bit;

	logic [1:0] factor_b_bits;
	always_comb begin
		factor_b_bits = 'X;
		if (factor_b_index[FACTOR_B_INDEX_BITS-1]) factor_b_bits = 0; // factor_b_index < 0
		else begin
			if (factor_b_index[0] == 1) factor_b_bits = factor_b_src;
			else factor_b_bits = {factor_b_src[0], prev_factor_b_bit_eff}; // delay by one bit ==> left shift by one
		end
	end


	wire [ACC_BITS-1:0] result;
	synth_alu #(.FACTOR_A_BITS(FACTOR_A_BITS), .GPHASE_BITS(GPHASE_BITS), .OUT_ACC_BITS(OUT_ACC_BITS), .DELTA_SIGMA_BITS(DELTA_SIGMA_BITS)) alu(
		.clk(clk), .reset(reset), .en(en_eff),

		.src2_note_mul(src2_note_mul), .src2_pwm_offs(src2_pwm_offs), .src2_vol(src2_vol), .src2_slope_frac(src2_slope_frac), .out_acc_initial(out_acc_initial),
		.src1_sel(src1_sel), .src2_sel(src2_sel), .src2_mod(src2_mod), .flags(flags), .res_sel(res_sel), .wes(wes),
		.add_mask(add_mask),
		.final_factor_b(0), .first_factor_b(first_factor_b), .factor_b(factor_b_bits),

		.gphase_out(gphase), .acc_out(acc_out), .src2_out(src2_out), .booth_carry_out(booth_carry_out), .result_out(result), .out_acc_out(out_acc_out)
	);


	reg [ACC_BITS-1:0] debug_phase, debug_tri1, debug_tri2;
	always_ff @(posedge clk) if (en_eff && state == 9) debug_phase <= result;
	always_ff @(posedge clk) if (en_eff && state == STATE_TRI1) debug_tri1 <= result;
	always_ff @(posedge clk) if (en_eff && state == STATE_TRI2) debug_tri2 <= result;
endmodule

module booth_multiplier #(
		parameter FACTOR_A_BITS = 8,
		// Don't change:
		ACC_BITS = FACTOR_A_BITS
	) (
		input wire clk, reset,

		input wire [FACTOR_A_BITS-1:0] factor_a,
		input wire [1:0] factor_b,
		input wire final_factor_b, // can be held low if ACC_BITS > FACTOR_A_BITS

		input wire [ACC_BITS-1:0] add_mask,

		output wire signed [ACC_BITS-1:0] acc_out
	);

	reg signed [ACC_BITS-1:0] acc;
	reg carry;

	wire [2:0] factor_b_1 = factor_b + carry; // 0 - 4
	// If the factor is 2
	// - if this is the final cycle, add
	// - otherwise,
	//   - if acc >= 0, subtract
	//   - if acc < 0, add
	wire next_carry = factor_b_1[2] || (factor_b_1[1:0] == 3) || (factor_b_1 == 2 && !acc[ACC_BITS-1] && !final_factor_b);

	logic add_en, shl, inv;
	always_comb begin
		case (factor_b_1[1:0])
			0: begin; add_en = 0; shl =  0; inv =  0; end
			1: begin; add_en = 1; shl =  0; inv =  0; end
			2: begin; add_en = 1; shl =  1; inv =  next_carry; end
			3: begin; add_en = 1; shl =  0; inv =  1; end
			default: begin; add_en = 'X; shl = 'X; inv = 'X; end
		endcase
	end

	wire [FACTOR_A_BITS-1:0] factor_a_e = add_en ? factor_a : '0;
	wire [FACTOR_A_BITS+1-1:0] factor_a_s = {1'b0, factor_a_e} << shl;
	wire signed [FACTOR_A_BITS+2-1:0] factor_a_i = inv ? ~factor_a_s : factor_a_s;
	wire signed [ACC_BITS+2-1:0] sum = acc + factor_a_i + $signed({1'b0, inv});
	//wire [ACC_BITS-1:0] next_acc = sum[ACC_BITS+2-1:2];

	logic [ACC_BITS-1:0] next_acc;
	always_comb begin
		//next_acc = (sum[ACC_BITS+2-1:2] & add_mask) | (acc[ACC_BITS-1:0] & ~add_mask);
		//if (rot_en) next_acc[ACC_BITS-1 -: 2] = acc[1:0];
		next_acc = (sum[ACC_BITS+2-1:2] & add_mask) | ({sum[1:0], acc[ACC_BITS-1:2]} & ~add_mask);
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			acc <= 0;
			carry <= 0;
		end else begin
			acc <= next_acc;
			carry <= next_carry;
		end
	end

	assign acc_out = acc;
endmodule : booth_multiplier
