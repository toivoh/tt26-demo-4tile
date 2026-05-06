/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

// Return n_out that minimizes abs(in - 2**(n_out+1)), rounding up when there is a tie.
// in should be >= 2
module find_closest_pow2_m1 #(
		BITS=11,
		// Don't override:
		N_BITS = $clog2(BITS+1)
	) (
		input wire [BITS-1:0] in,
		output wire [N_BITS-1:0] n_out
	);

	// not a register
	reg [N_BITS-1:0] n;
	always_comb begin
		// OPT: Don't need all cases?
		casez (in)
//			'b0000000000: n = 'X;
//			'b00000000001: n =  -1?; //    1
			'b00000000001: n =  0; //    1  -- needed in corner case when input is inverted, can still be seen as rounding up
			'b00000000010: n =  0; //    2
			'b00000000011: n =  1; //    3
			'b0000000010z: n =  1; //    4 -    5
			'b0000000011z: n =  2; //    6 -    7
			'b000000010zz: n =  2; //    8 -   11
			'b000000011zz: n =  3; //   12 -   15
			'b00000010zzz: n =  3; //   16 -   23
			'b00000011zzz: n =  4; //   24 -   31
			'b0000010zzzz: n =  4; //   32 -   47
			'b0000011zzzz: n =  5; //   48 -   63
			'b000010zzzzz: n =  5; //   64 -   95
			'b000011zzzzz: n =  6; //   96 -  127
			'b00010zzzzzz: n =  6; //  128 -  191
			'b00011zzzzzz: n =  7; //  192 -  255
			'b0010zzzzzzz: n =  7; //  256 -  383
			'b0011zzzzzzz: n =  8; //  384 -  511
			'b010zzzzzzzz: n =  8; //  512 -  767
			'b011zzzzzzzz: n =  9; //  768 - 1023
			'b10zzzzzzzzz: n =  9; // 1024 - 1535
			'b11zzzzzzzzz: n = 10; // 1536 - 2047
//			'b10zzzzzzzzzz: n = 10; // 2048 - 3071
			default: n = 'X;
		endcase
		//$display("closest_pow2_m1", " in:", in, " n:", n);
	end
	assign n_out = n;
endmodule


module subdivider_pl #(
		parameter POS_BITS=9, LEVEL_BITS=2, TAG_BITS=6, DECISION_BITS=1, STACK_DEPTH=16,
		// Don't override:
		N_BITS = $clog2(POS_BITS+1),
		STATE_BITS = 2
	) (
		input wire clk, reset, reset_i_d2, en,

		input wire [`CTRL_FLAG_BITS-1:0] ctrl_flags,
		input wire consume_pixel,

		input wire [POS_BITS-1:0] i_d2_init, i2_init,
//		output wire done,

		// Emit interface
		input wire ack_emit, // set high when the emit has been observed
		// When emit goes high, don't set en=1 before the emit has been consumed and acked (ok to do it the same cycle).
		// Also, don't ascend before that, since the emit will depend on the trace state.
		output wire emit,
		output wire [POS_BITS-1:0] i1_emit,
		output wire [POS_BITS-1:0] length_m1_emit, // interval length-1
		output wire [POS_BITS-1:0] i2_emit, // not expected to be used?

/*
		// The external overrides take effect when reset is high
		input wire update_dx_ext, ddx_sign_ext,
		input wire [N_BITS-1:0] ddx_shl_ext,
*/

		// dx operations
		output logic update_dx1, next_update_dx1,
		output logic update_dx2, ddx2_sign,
		output logic [N_BITS-1:0] ddx2_shl,

		// Descend / ascend interface
		input [TAG_BITS-1:0] curr_tag,
		output wire descend, // go to next tag
		output wire ascend, adjusting_out,
		output wire ascending, // like ascend, except it needs one cycle to go high
		output wire [DECISION_BITS-1:0] descend_decision,
		output wire [TAG_BITS-1:0] target_tag, // when ascend is true, ascend to this tag
		output logic restart_from_top,

		// Decision interface
		// The subdivider is making a decision if !ascend && !adjusting && en
		output wire [LEVEL_BITS-1:0] level_out,
		output wire [2**LEVEL_BITS-1:0] level_decisions_out,
		output wire decision_side_out,
		output wire [POS_BITS-1:0] i_d_out, i_d2_out,
		input wire [DECISION_BITS-1:0] curr_decision, decision_mask,
		input curr_hit,
		output wire accept_hit,
		output wire [DECISION_BITS-1:0] d1_out, // needed?

		// For debugging
		output wire [STATE_BITS-1:0] state_out,
		output wire line_done_out,
		output wire [$clog2(STACK_DEPTH)-1:0] stack_pointer_out,
		output wire [$clog2(STACK_DEPTH+1)-1:0] stack_depth_out
	);

	localparam STATE_D1 = 0;
	localparam STATE_D2 = 1;
	localparam STATE_BISECT = 2;
	localparam STATE_ASCENDING = 3;

	localparam STACK_ENTRY_BITS = TAG_BITS + POS_BITS;
	localparam STACK_POINTER_BITS = $clog2(STACK_DEPTH);
	localparam STACK_DEPTH_BITS = $clog2(STACK_DEPTH+1);

	localparam N_BISECT_BITS = POS_BITS + 2; // +2 bits: terms may be left shifted by one, need sign bit

	genvar i;

	reg [STATE_BITS-1:0] state;
	reg [POS_BITS-1:0] i1, i2, i1_bisect, i2_bisect;
	reg [DECISION_BITS-1:0] d1;
	reg [POS_BITS-1:0] i_d2;
	reg [POS_BITS-1:0] i_d1; // not intended to be used
	reg emit_acked;
	reg last_ascending;
	reg line_done;

	reg [STACK_POINTER_BITS-1:0] stack_pointer;
	reg [STACK_DEPTH_BITS-1:0] stack_depth;
/*
`ifndef USE_LATCHES
	(* mem2reg *) reg [STACK_ENTRY_BITS-1:0] stack[STACK_DEPTH];
	wire [STACK_ENTRY_BITS-1:0] stack_pop[STACK_DEPTH];
	//for (i = 0; i < STACK_DEPTH; i++) assign stack_pop[(i+1)&((1 << STACK_POINTER_BITS) - 1)] = stack[i];
	for (i = 0; i < STACK_DEPTH; i++) assign stack_pop[(i+1)%STACK_DEPTH] = stack[i];
`endif
*/

	// not intended to be used
	reg [LEVEL_BITS-1:0] level;
	reg [2**LEVEL_BITS-1:0] level_decisions;
	(* mem2reg *) reg [LEVEL_BITS-1:0] level_stack[STACK_DEPTH];
//	wire [LEVEL_BITS-1:0] level_stack_pop[STACK_DEPTH+1];
//	for (i = 0; i < STACK_DEPTH; i++) assign level_stack_pop[(i+1)&((1 << STACK_POINTER_BITS) - 1)] = level_stack[i];
	wire [LEVEL_BITS-1:0] level_stack_pop[STACK_DEPTH];
	for (i = 0; i < STACK_DEPTH; i++) assign level_stack_pop[(i+1)%STACK_DEPTH] = level_stack[i];


	wire agree_with_d1 = ((d1&decision_mask) == (curr_decision&decision_mask));
	wire [DECISION_BITS-1:0] curr_d1 = (state == STATE_D1) ? curr_decision : d1;

	wire [N_BISECT_BITS-1:0] n_bisect;

	int debug_t;
	always_ff @(posedge clk) begin
		if (reset) debug_t <= 0;
		else debug_t <= debug_t + 1;
	end

	wire decision_side = (state != STATE_D1);

	assign ascending = (state == STATE_ASCENDING);

	assign accept_hit = !ascending && (i_d2 == i2) && !emit_acked; // When we emit, we assume that i_d2 == i2. Trying to emit when emit_acked is set would skip the emit.
	wire curr_hit_eff = curr_hit && accept_hit;

	wire [POS_BITS-1:0] stack_top_i2;

	// not registers
	reg [STATE_BITS-1:0] next_state;
	reg [POS_BITS-1:0] next_i1, next_i2;
	reg [POS_BITS+1-1:0] next_i1_bisect, next_i2_bisect; // +1 bit to handle <<1
	reg update_i_d1, next_update_i_d1;
	reg update_i_d2, update_i_d2_sign;
	reg force_update_i_d2; // update i_d2 regardless of en_eff
	reg update_i_d2_sign_from_n_bisect;
	//reg decision_side;
	reg do_descend, do_return, do_push;
	reg adjusting;
	reg force_log2_delta_i_zero;
	always_comb begin
		next_state = 'X;
		//decision_side = 1;
		do_descend = 0;
		do_return = 0;
		do_push = 0;
		next_i1 = i1;
		next_i2 = i2;
		next_i1_bisect = i1_bisect;
		next_i2_bisect = i2_bisect;
		update_i_d1 = 0; next_update_i_d1 = 0;
		update_i_d2 = 0;
		update_i_d2_sign = 'X;
		force_update_i_d2 = 0;
		update_i_d2_sign_from_n_bisect = 0;
		adjusting = 0;
		force_log2_delta_i_zero = 0;

		//$display("ac ", "t=",debug_t, " s:", state, " i1:", i1, " i2:", i2, " i1b:", i1_bisect, " i2b:", i2_bisect, " l:", level, " cd:", curr_decision, " ch:", curr_hit, " ds:", decision_side, " id2:", i_d2);

`ifdef NO_SYNTH
		assert(curr_hit_eff || ascending || i_d1 == i1);
`endif

		if (!reset && (curr_hit_eff || ascending)) begin
			do_return = 1;
			next_state = STATE_D1;
			//decision_side = 'X;

			if (state != STATE_ASCENDING) begin
				// First cycle of ascent: i_d2 += 1, to prepare for updating i_d1 next cycle
				next_update_i_d1 = 1;
				update_i_d2 = 1; force_update_i_d2 = 1;
				update_i_d2_sign = 0;
				force_log2_delta_i_zero = 1;
			end else begin
				if (!last_ascending) update_i_d1 = 1; // Second cycle of ascent, i_d1 <= i_d2

				// Start iterating on i_dx2 -- almost same behavior as in STATE_D1, which will finish iterating
				next_i1_bisect = i_d2 << 1; // i_d2;
				next_i2_bisect = stack_top_i2 << 1; // stack_top_i2;
				//if (n_bisect != 0) begin
				if (next_i1_bisect != next_i2_bisect) begin
					adjusting = 1;
					update_i_d2 = 1; force_update_i_d2 = 1;
					//update_i_d2_sign = n_bisect[N_BISECT_BITS-1];
					update_i_d2_sign_from_n_bisect = 1;
				end
			end
			//update_i_d1 = (state != STATE_ASCENDING); // Only update during the first cycle of each ascent

			next_i1 = i2+1;
			next_i2 = stack_top_i2;
		end else case (reset ? STATE_D1 : state)
			STATE_D1: begin
				//decision_side = 0;
				// OPT: could we avoid the left shift?
				next_i1_bisect = i_d2 << 1; // i_d2;
				next_i2_bisect = i2 << 1; // i2;

				//if (n_bisect != 0) begin
				if (next_i1_bisect != next_i2_bisect) begin
					adjusting = 1;
					update_i_d2 = 1; force_update_i_d2 = 1;
					//update_i_d2_sign = n_bisect[N_BISECT_BITS-1];
					update_i_d2_sign_from_n_bisect = 1;
					next_state = STATE_D1;
				end	else begin
					if (i1 == i2) begin
						do_descend = 1; next_state = STATE_D1;
					end else begin
						next_state = STATE_D2;
					end
				end
			end
			STATE_D2: begin
				//decision_side = 1;
				if (agree_with_d1) begin
					do_descend = 1; next_state = STATE_D1;
				end else begin
					next_state = STATE_BISECT;
					next_i1_bisect = i1;
					next_i2_bisect = i2;

					update_i_d2 = 1; update_i_d2_sign = 1;
				end
			end
			STATE_BISECT: begin
				//decision_side = 1;
				if (agree_with_d1) next_i1_bisect = i_d2;
				else               next_i2_bisect = i_d2;
				update_i_d2 = 1; update_i_d2_sign = !agree_with_d1;
				next_state = STATE_BISECT;
			end
			default: begin
				next_state = 'X; do_descend = 'X; do_return = 'X;
			end
		endcase

		//if (n_bisect == 1) begin
		//if (i2_bisect - i1_bisect == 1) begin
		if (next_state == STATE_BISECT && next_i2_bisect - next_i1_bisect == 1) begin
		//if (next_state == STATE_BISECT && n_bisect == 1) begin // OPT: can we use n_bisect instead of next_i2_bisect - next_i1_bisect?
			do_push = 1;
			do_descend = 1; next_state = STATE_D1;
			next_i2 = next_i1_bisect; // TODO: correct?

			// take one step back if needed
			update_i_d2 = !agree_with_d1;
			update_i_d2_sign = 1;
			force_log2_delta_i_zero = 1;
		end


		//if (do_descend) next_state = STATE_D1;
		
	end


`ifdef USE_STACK_UNDERFLOW_RESTART
	// Don't restart during the first two ascent cycles; they update dx1 and dx2
	assign restart_from_top = (stack_depth == 0 && do_return && !(emit && !ack_emit) && ascending);
`else
	assign restart_from_top = 0;
`endif


	wire en_enabled = !(curr_hit_eff && (state != STATE_ASCENDING));
	wire en_eff = (en && en_enabled) || restart_from_top;



	assign n_bisect = next_i2_bisect - next_i1_bisect;
	wire [N_BISECT_BITS-1-1:0] closest_pow2_in = n_bisect[N_BISECT_BITS-1] ? ~n_bisect : n_bisect;
	wire [N_BITS-1:0] log2_delta_i;
	find_closest_pow2_m1 #(.BITS(POS_BITS+1)) closest_pow2_m1(.in(closest_pow2_in), .n_out(log2_delta_i));
	wire [N_BITS-1:0] log2_delta_i_eff = force_log2_delta_i_zero ? 0 : log2_delta_i;



	generate
		for (i = 0; i < DECISION_BITS; i++) begin
			always_ff @(posedge clk) begin
				if (reset) begin
					d1[i] <= 'X;
				end begin
					if ((en_eff && state == STATE_D1) && decision_mask[i]) d1[i] <= curr_decision[i];
				end
			end
		end
	endgenerate

	wire [STACK_ENTRY_BITS-1:0] stack_push_data = {curr_tag, i2};
	wire [STACK_ENTRY_BITS-1:0] stack_top_data;
	assign {target_tag, stack_top_i2} = stack_top_data;

`ifdef INTERVAL_STACK_USE_BIDIR
	bidir_stack #(.BITS(STACK_ENTRY_BITS), .DEPTH(STACK_DEPTH)) stack_bidir(
		.clk(clk), .reset(reset),
		.do_push(en_eff && do_push), .do_pop(en_eff && do_return),
		.push_data(stack_push_data),
		.top_data (stack_top_data)
	);
`else
//`ifdef USE_LATCHES

	//wire [STACK_ENTRY_BITS-1:0] stack_top_data2;
	np_latch_ram #(.NUM_ADDR(STACK_DEPTH), .DATA_BITS(STACK_ENTRY_BITS), .READ_OFFSET(1)) stack_latches_ram(
		.clk(clk), .reset(reset),
		.we(en_eff && do_push),
		.addr(stack_pointer),
		.wdata(stack_push_data),
		.rdata(stack_top_data)
		//.rdata(stack_top_data2)
	);

/*
`else
	assign {target_tag, stack_top_i2} = stack_pop[stack_pointer];
	always_ff @(posedge clk) begin
		if (en_eff && do_push) begin
			stack[stack_pointer] <= {curr_tag, i2};
		end
	end
`endif
*/
`endif

	wire [LEVEL_BITS-1:0] level_pop = level_stack_pop[stack_pointer];
	always_ff @(posedge clk) begin
		if (en_eff && do_push) begin
			level_stack[stack_pointer] <= level;
		end
	end

	wire update_i_d2_sign_eff = update_i_d2_sign_from_n_bisect ? n_bisect[N_BISECT_BITS-1] : update_i_d2_sign;

	wire signed [1:0] sp_delta = do_push - do_return;
	wire [STACK_POINTER_BITS-1:0] sp_incdec = $signed(stack_pointer) + sp_delta;

	logic [STACK_POINTER_BITS-1:0] sp_next;
	logic [STACK_DEPTH_BITS-1:0] sd_next;
	always_comb begin
		sp_next = sp_incdec;
		if (do_push && stack_pointer == STACK_DEPTH-1) sp_next = 0;
		if (do_return && stack_pointer == 0) sp_next = STACK_DEPTH-1;

		sd_next = $signed(stack_depth) + sp_delta;
	end
	// Keep stack_depth from becoming > STACK_DEPTH
	wire update_stack_depth = !(do_push && stack_depth == STACK_DEPTH);

	wire lock_dx2_update = ctrl_flags[`CTRL_FLAG_LOCK_DX2_UPDATE] && !reset;
	always_comb begin
		update_dx2 = update_i_d2 && (en_eff || force_update_i_d2) && !restart_from_top;
		ddx2_sign = update_i_d2_sign_eff;
		ddx2_shl = log2_delta_i_eff;

		if (lock_dx2_update) begin
			update_dx2 = consume_pixel;
			ddx2_sign = 0;
			ddx2_shl = 0;
		end
	end

	always_ff @(posedge clk) begin
		if (reset || restart_from_top) begin
			state <= STATE_D1;
			i2 <= i2_init;
			stack_pointer <= 0;
			stack_depth <= 0;
			level <= 0;
			level_decisions <= 0;
		end else begin
			if (en_eff) begin
				state <= next_state;
				i2 <= next_i2;

				stack_pointer <= sp_next;
				if (update_stack_depth) stack_depth <= sd_next;

				if (do_return) begin
					level <= level_pop;
				end else begin
					level <= level + do_descend;
					if (do_descend) level_decisions[level] <= curr_d1;
				end
			end else begin
				if (do_return) state <= STATE_ASCENDING;
			end
		end

		if (reset) begin
			i1 <= 0;
			i_d1 <= 0;
			emit_acked <= 0;
			last_ascending <= 0;
			line_done <= 0;
		end else begin
			if (en_eff) begin
				i1 <= next_i1;
				i1_bisect <= next_i1_bisect;
				i2_bisect <= next_i2_bisect;
			end

			if (update_i_d1 && !restart_from_top) i_d1 <= i_d2; // TODO: should it be !restart_from_top? i_d1 isn't used?
			//if (update_i_d1) i_d1 <= i2 + 1;

			emit_acked <= (emit_acked & !en_eff) | ack_emit;

`ifdef USE_STACK_UNDERFLOW_RESTART
			if ((i2 == 639) && do_return && ack_emit) line_done <= 1; // TODO: don't hardcode 639 as final i2 value
`else
			if ((stack_pointer == 0) && do_return && ack_emit) line_done <= 1;
`endif

			last_ascending <= ascending;
		end

		if (reset_i_d2) begin
			//i_d2 <= 0;
			i_d2 <= i_d2_init;
		end else begin
			// OPT: combine with update below?
/*			if (reset) begin
				if (update_dx_ext) begin
					if (ddx_sign_ext) i_d2 <= i_d2 - (1 << ddx_shl_ext);
					else              i_d2 <= i_d2 + (1 << ddx_shl_ext);
				end
			end else begin*/
				//if (update_i_d2 && (en_eff || force_update_i_d2)) begin
				if (update_dx2) begin
					// OPT: share adder
					//if (ddx2_sign) i_d2 <= i_d2 - (1 << ddx2_shl);
					//else           i_d2 <= i_d2 + (1 << ddx2_shl);
					i_d2 <= i_d2 + ((1 << ddx2_shl) ^ (ddx2_sign ? '1 : 0)) + ddx2_sign;
				end
//			end
		end
	end


	assign update_dx1 = update_i_d1;
	assign next_update_dx1 = next_update_i_d1;

	assign decision_side_out = decision_side;
	//assign i_d_out = decision_side ? i_d2 : i1;
	assign i_d_out = decision_side ? i_d2 : i_d1;
	assign i_d2_out = i_d2;

	// emit should be valid as soon as it goes high, at which point ascend should go high as well.
	// It might keep being valid during the ascend, or it might become invalidated?
	// It should only be counted once during the ascend, such as when it is first encountered,
	// or maybe when the ascend is finished?
	// TODO: We can use the hit as soon as we have it, but make sure to use each hit only once.
	//assign emit = curr_hit_eff && en_eff;
	assign emit = do_return && !emit_acked && !line_done;
	assign i1_emit = i1;
	assign length_m1_emit = i2 - i1; // OPT
	assign i2_emit = i2;

	assign level_out = level;
	assign level_decisions_out = level_decisions & ~('1 << level);

	//assign ascend = en_eff && do_return;
	// Anding with en_eff would cause a combinational loop, and ascend should be high until the return has been completed,
	// which might involve a number of cycles of en_eff = 0
	assign ascend = do_return;
	assign descend = en_eff && do_descend && !do_return;


	assign descend_decision = curr_d1;
	assign state_out = state;
	assign d1_out = d1;
	assign adjusting_out = adjusting;

	assign line_done_out = line_done;

	assign stack_pointer_out = stack_pointer;
	assign stack_depth_out = stack_depth;
endmodule : subdivider_pl
