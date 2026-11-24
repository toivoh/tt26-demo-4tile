`default_nettype none

/*
Assumptions;
* You're not trying to emit more than 2^LENGTH_BITS-1 pixels into one line
* When do_swap activatives, there has been time to emit to the buffer down to head_length_m1 < 2**SHORT_LENGTH_BITS ==> can emit the last part in one cycle
	- Otherwise the whole emit will not have time to finish (but maybe that's ok, if it's just more of the same color, the read will repeat it at the end of the line)
*/

/*
Usage:
- For each display line
	- Start on a new line
		- raise return_mode_en for at least DEPTH+1 cycles
		- keep return_mode_en=0 for at least one cycle to load the first tail value from the read buffer
	- Write new intervals, read out pixels
		- emit intervals to write, wait for them to be acked
		- read curr_value, raise consume_pixel when wanted
- After a line has been displayed for the last time
	- raise do_swap for one cycle
*/

module line_double_buffer #(
		parameter LENGTH_BITS = 10, SHORT_LENGTH_BITS = 6, VALUE_BITS = 2, DEPTH = 24
	) (
		input wire clk, reset,
		input wire do_swap,
		input wire return_mode_en, // raise for at least DEPTH(+1?) cycles after do_swap=1 before starting to use curr_value

		// Write interface
		input wire emit,
		input wire [LENGTH_BITS-1:0] length_m1_emit, // length-1 of the emitted interval
		input wire [VALUE_BITS-1:0] value_emit,
		output logic ack_emit, // when low, current emit must be kept

		// Read interface
`ifdef USE_DOUBLE_CONSUME_PIXEL
		input wire [1:0] consume_pixel, // can be 0-2, don't use 3
`else
		input wire consume_pixel,
`endif
		output wire [VALUE_BITS-1:0] curr_value
	);

	localparam ENTRY_BITS = SHORT_LENGTH_BITS + VALUE_BITS;

	reg write_index;
	wire read_index = !write_index;

	reg last_return_mode_en;
	always_ff @(posedge clk) last_return_mode_en <= reset ? 0 : return_mode_en;

	reg [VALUE_BITS-1:0] head_value, tail_value;
	reg [LENGTH_BITS-1:0] head_length_m1; // length - 1
	reg [SHORT_LENGTH_BITS-1:0] tail_length_m1; // length - 1

	logic [VALUE_BITS-1:0] next_head_value;
	logic [LENGTH_BITS-1:0] next_head_length_m1; // length - 1
	logic [SHORT_LENGTH_BITS-1:0] next_tail_length_m1; // length - 1

	logic emit_to_buffer;
	logic [SHORT_LENGTH_BITS-1:0] length_m1_emit_to_buffer;

	logic consume_interval, reset_tail_length_borrow;

	logic write_mode_en0, return_mode_en0, rw_en0, write_mode_en1, return_mode_en1, rw_en1;
	logic [ENTRY_BITS-1:0] rdata0, rdata1;

	wire [ENTRY_BITS-1:0] rdata;
	wire [SHORT_LENGTH_BITS-1:0] rlength_m1;
	wire [VALUE_BITS-1:0] rvalue;
	assign {rlength_m1, rvalue} = rdata;

	wire head_empty = (head_length_m1 == '1);

	reg tail_length_borrow; // only used with USE_DOUBLE_CONSUME_PIXEL
`ifdef USE_DOUBLE_CONSUME_PIXEL
	wire [1:0] tail_length_reduction = consume_pixel + tail_length_borrow;
`else
	wire tail_length_reduction = consume_pixel;
`endif

	wire [SHORT_LENGTH_BITS+1-1:0] tail_length_m1_reduced = tail_length_m1 - tail_length_reduction;

	always_comb begin
		// Write side
		emit_to_buffer = 0;
		ack_emit = 0;
		length_m1_emit_to_buffer = 'X;

		next_head_length_m1 = head_length_m1;
		next_head_value = head_value;
		//next_tail_value = tail_value - consume_pixel;

		// Read side
		consume_interval = 0;
		reset_tail_length_borrow = 0;

		if (!head_empty) begin
			if (head_length_m1 >= 2**SHORT_LENGTH_BITS) begin // too long for one emit; emit a max length interval
				emit_to_buffer = 1;
				length_m1_emit_to_buffer = 2**SHORT_LENGTH_BITS-1;
				next_head_length_m1 = head_length_m1 - 2**SHORT_LENGTH_BITS; // TODO: merge head_length_m1 updates?
			end else if ((emit && value_emit != head_value) || do_swap) begin // emit whatever remains in head when we do a swap -- the length doesn't matter since it's the last value
				emit_to_buffer = 1;
				length_m1_emit_to_buffer = head_length_m1;
				next_head_length_m1 = '1;
			end
		end
		if (emit && !emit_to_buffer) begin
			ack_emit = 1;
			next_head_length_m1 = head_length_m1 + length_m1_emit + 1;
			next_head_value = value_emit;
		end

`ifdef USE_DOUBLE_CONSUME_PIXEL
		if (tail_length_m1_reduced[SHORT_LENGTH_BITS]) begin // if tail_length_m1 would become < 0 next cycle otherwise:
`else
		if (tail_length_m1 == '0 && consume_pixel) begin
`endif
			consume_interval = 1;
		end
		if (last_return_mode_en && !return_mode_en) begin
			consume_interval = 1; // Get first interval
			reset_tail_length_borrow = 1;
		end

		write_mode_en0 = 0; write_mode_en1 = 0;
		return_mode_en0 = 0; return_mode_en1 = 0;
		if (write_index == 0) begin
			write_mode_en0 = 1;
			rw_en0 = emit_to_buffer;

			rw_en1 = consume_interval;
			return_mode_en1 = return_mode_en;
		end else begin
			write_mode_en1 = 1;
			rw_en1 = emit_to_buffer;

			rw_en0 = consume_interval;
			return_mode_en0 = return_mode_en;
		end
	end


	always_ff @(posedge clk) begin
		if (reset) begin
			write_index <= 0;
			head_length_m1 <= '1; // empty

			head_value <= '0;
			tail_length_borrow <= 0;

			tail_value <= '0;
			tail_length_m1 <= '0;
		end else if (do_swap) begin
			write_index <= !write_index;
			head_length_m1 <= '1; // empty
			tail_length_borrow <= 0;
		end else begin
			head_length_m1 <= next_head_length_m1;
			head_value <= next_head_value;
			if (consume_interval) begin
				tail_length_m1 <= rlength_m1;
				// Max out at 1 unit of borrow. There will be edge cases where this is not enough, causing the rest of the line to shift a pixel to the right or so, but it should be uncommon.
				tail_length_borrow <= reset_tail_length_borrow ? 0 : (tail_length_m1_reduced[1:0] != '1);
				tail_value <= rvalue;
			end else begin
				tail_length_m1 <= tail_length_m1_reduced;
				tail_length_borrow <= 0;
			end
		end
	end

	wire [ENTRY_BITS-1:0] wdata = {length_m1_emit_to_buffer, head_value};

	line_buffer #(.BITS(ENTRY_BITS), .DEPTH(DEPTH)) linebuf0(.clk(clk), .reset(reset || (do_swap && read_index == 0)), .write_mode_en(write_mode_en0), .return_mode_en(return_mode_en0), .rw_en(rw_en0), .wdata(wdata), .rdata(rdata0));
	line_buffer #(.BITS(ENTRY_BITS), .DEPTH(DEPTH)) linebuf1(.clk(clk), .reset(reset || (do_swap && read_index == 1)), .write_mode_en(write_mode_en1), .return_mode_en(return_mode_en1), .rw_en(rw_en1), .wdata(wdata), .rdata(rdata1));

	assign rdata = read_index == 0 ? rdata0 : rdata1;

	assign curr_value = tail_value;
endmodule : line_double_buffer
