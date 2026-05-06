/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none


module hold_buffer #(parameter BITS=1) (
		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out
	);
	genvar i;
`ifdef SCL_sky130_fd_sc_hd
	generate
		for (i = 0; i < BITS; i++) begin
			sky130_fd_sc_hd__dlygate4sd3_1 hold_buf(.A(in[i]), .X(out[i]));
		end
	endgenerate
`else
	assign out = in;
`endif
endmodule


// TODO: what if head_length becomes too negative?

module interval_buffer2 #(
		parameter QUEUE_SIZE=1,
		LENGTH_BITS=8,
		SHORT_LENGTH_BITS=6, // should be < LENGTH_BITS (Or at most equal? But then we can use interval_buffer instead?)
		TAIL_LENGTH_BITS=SHORT_LENGTH_BITS, // must be equal
		//INTERVAL_N_BITS=4,
		VALUE_BITS=2
	) (
		input wire clk, reset, restart,
		input wire [VALUE_BITS-1:0]  initial_value,
		input wire signed [LENGTH_BITS+1-1:0] initial_length, // actually initial length-1

		input wire consume_pixel,
		output wire [VALUE_BITS-1:0] curr_value,
		output wire behind,

		input wire emit,
		//input wire [INTERVAL_N_BITS-1:0] n_emit,
		input wire [LENGTH_BITS-1:0] length_m1_emit, // length-1 of the emitted interval
		input wire [VALUE_BITS-1:0] value_emit,
		output wire ack_emit, // when low, current emit must be kept

		output wire [$clog2(QUEUE_SIZE + 2)-1:0] tail_index_out
	);

	localparam HEAD_LENGTH_BITS = LENGTH_BITS + 1;
	localparam INDEX_BITS = $clog2(QUEUE_SIZE + 2);

	genvar i;


	reg [VALUE_BITS-1:0] head_value, tail_value;
	reg [HEAD_LENGTH_BITS-1:0]  head_length; // actually length-1
	reg [SHORT_LENGTH_BITS-1:0] tail_length; // actually length-1

	(* mem2reg *) reg [SHORT_LENGTH_BITS-1:0] queue_lengths[QUEUE_SIZE]; // actually length-1
	(* mem2reg *) reg [VALUE_BITS-1:0]        queue_values[QUEUE_SIZE];

	// queue_values[tail_index] is the first valid index in queue_values
	//                              total queue:
	// tail_index = 0:              tail, queue[0], queue[1], ..., queue[QUEUE_SIZE-1], head
	// tail_index = QUEUE_SIZE-1:   tail, queue[QUEUE_SIZE-1], head
	// tail_index = QUEUE_SIZE:     tail, head
	// tail_index = QUEUE_SIZE+1:   head
	reg [INDEX_BITS-1:0] tail_index;


	wire queue_full          = (tail_index == 0); // do not add when queue_full (unless consuming at the same time)
	wire head_only           = (tail_index == QUEUE_SIZE + 1); // do not consume when head_only (unless adding at the same time?)
	wire head_and_tail_only  = (tail_index == QUEUE_SIZE);

	wire consume_head_pixel = head_only && consume_pixel;
	wire head_length_positive = !head_length[HEAD_LENGTH_BITS-1]; // true if the actual length is > 0

	wire long_head = head_length_positive && (head_length[LENGTH_BITS-1:SHORT_LENGTH_BITS] != '0);
	wire split_interval = long_head && !queue_full && !consume_head_pixel; // OPT: not used when consume_head_pixel, can remove that condition?

	//wire [LENGTH_BITS-1:0] length_emit = 1 << n_emit;
	// actually length-1
	//wire [LENGTH_BITS-1:0] length_m1_emit = ~('1 << n_emit); // = (1 << n_emit) - 1



	wire [SHORT_LENGTH_BITS-1:0] tail_length_dec = tail_length - consume_pixel;

	wire consume_interval = (tail_length == 0) && consume_pixel && !head_only;

	wire ignore_value_match = head_only && !head_length_positive;

	// not a register
	reg [HEAD_LENGTH_BITS-1:0] delta_head_length;
	reg delta_head_length_extra;
	always_comb begin
		delta_head_length = 'X;
		delta_head_length_extra = 0;
		if (consume_head_pixel) delta_head_length = -1;
		else if (split_interval) delta_head_length = -(1 << SHORT_LENGTH_BITS);
		else begin
			delta_head_length = length_m1_emit;
			delta_head_length_extra = 1; // since length_m1_emit is the length - 1
		end
	end

	wire [HEAD_LENGTH_BITS-1:0] next_head_length = head_length + delta_head_length + delta_head_length_extra;
	wire no_match = !head_length[HEAD_LENGTH_BITS-1] && next_head_length[HEAD_LENGTH_BITS-1]; // no match if it would wrap from positive to negative

	// not registers
	reg add_interval, consume_emit, update_head_length;
	always_comb begin
		add_interval = 0;
		consume_emit = 0;
		update_head_length = 0;

		if (consume_head_pixel) begin
			// delta_head_length = -1;
			update_head_length = 1;
		end else if (split_interval) begin
			update_head_length = 1;
			add_interval = 1;
		end else if (emit) begin
			if ((value_emit == head_value || ignore_value_match) && !no_match) begin
				consume_emit = 1;
				// delta_head_length = length_m1_emit + 1;
				update_head_length = 1;
			end else if (!queue_full) begin
				consume_emit = 1;
				add_interval = 1;
			end
		end
	end



	wire [SHORT_LENGTH_BITS-1:0] short_head_length = split_interval ? (1 << SHORT_LENGTH_BITS) - 1 : head_length;

	wire [VALUE_BITS-1:0]        ext_queue_values[ QUEUE_SIZE+1];
	wire [SHORT_LENGTH_BITS-1:0] ext_queue_lengths[QUEUE_SIZE+1];
	generate
		for (i = 1; i < QUEUE_SIZE; i++) begin
			wire [VALUE_BITS-1:0]        hold_value;
			wire [SHORT_LENGTH_BITS-1:0] hold_length;
			hold_buffer #(.BITS(VALUE_BITS))        hbuf_value( .in(queue_values[ i]), .out(hold_value));
			hold_buffer #(.BITS(SHORT_LENGTH_BITS)) hbuf_length(.in(queue_lengths[i]), .out(hold_length));
//			assign ext_queue_values[ i] = queue_values[ i];
//			assign ext_queue_lengths[i] = queue_lengths[i];
			assign ext_queue_values[ i] = hold_value;
			assign ext_queue_lengths[i] = hold_length;
		end
	endgenerate
	// head is at index QUEUE_SIZE
	assign ext_queue_values[ QUEUE_SIZE] = head_value;
	assign ext_queue_lengths[QUEUE_SIZE] = short_head_length;
	//assign ext_queue_values[ QUEUE_SIZE+1] = head_value;
	//assign ext_queue_lengths[QUEUE_SIZE+1] = head_length;

	generate
		for (i = 0; i < QUEUE_SIZE; i++) begin
			always_ff @(posedge clk) begin
				if (add_interval) begin
					queue_lengths[i] <= ext_queue_lengths[i+1];
					queue_values[ i] <= ext_queue_values[ i+1];
				end
			end
		end
	endgenerate

	//wire [VALUE_BITS-1:0]  queue_tail_value  = ext_queue_values [tail_index];
	//wire [SHORT_LENGTH_BITS-1:0] queue_tail_length = ext_queue_lengths[tail_index];
	wire no_q = head_only || head_and_tail_only;
	wire [VALUE_BITS-1:0]        queue_tail_value  = no_q ? head_value        : queue_values[ tail_index];
	wire [SHORT_LENGTH_BITS-1:0] queue_tail_length = no_q ? short_head_length : queue_lengths[tail_index];

	always_ff @(posedge clk) begin
		if (reset || restart) begin
			head_value  <= initial_value;
			head_length <= initial_length;
			tail_index  <= QUEUE_SIZE + 1;
		end else begin
			if (consume_emit) head_value <= value_emit;
			if (update_head_length) head_length <= next_head_length;
			else if (add_interval) head_length <= length_m1_emit;

			if (consume_interval || (head_only && add_interval)) begin
				tail_value  <= queue_tail_value;
				tail_length <= queue_tail_length;
			end else begin
				tail_length <= tail_length_dec;
			end
			tail_index <= tail_index + consume_interval - add_interval;
		end
	end

	assign curr_value = head_only ? head_value : tail_value;
	assign ack_emit = consume_emit;
	//assign behind = !head_length_positive; // assume we're behind if head_length is negative
	assign behind = ignore_value_match;

	// For debugging
	wire [HEAD_LENGTH_BITS-1:0] curr_length = head_only ? head_length : tail_length;
	int counter_x;
	always_ff @(posedge clk) begin
		if (reset || restart) counter_x <= -initial_length;
		else counter_x <= counter_x + consume_pixel;
	end
	assign tail_index_out = tail_index;
endmodule : interval_buffer2
