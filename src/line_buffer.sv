`default_nettype none

/*
Usage:
- Reset for at least one cycle
- Write/fill:
	- write_mode_en = 1
	- rw_en = 1 when wdata is valid
- Read out:
	- return_mode_en = 1 for at least DEPTH cycles
	- then take data from rdata, raise rw_en to get next data

Read-out can be repeated any number of times.
*/
module line_buffer #(
		parameter BITS = 9, DEPTH = 24
	) (
		input wire clk, reset,

		input wire write_mode_en,
		input wire return_mode_en,

		input wire rw_en, // Raise for reading in read mode and writing in write mode
		input wire [BITS-1:0] wdata,
		output wire [BITS-1:0] rdata
	);

	localparam COUNTER_BITS = $clog2(DEPTH + 1);

	reg [COUNTER_BITS-1:0] counter;

	wire counter_at_max = (counter == DEPTH);

	logic shift_en;
	logic reset_counter;
	always_comb begin
		shift_en = rw_en;
		reset_counter = 0;
		if (write_mode_en) begin
			if (counter_at_max) shift_en = 0; // Don't overfill the shift register
		end else if (return_mode_en) begin
			// Rotate until we reach counter = DEPTH or 0, then reset counter to zero
			shift_en = (counter != 0) && !counter_at_max;
			reset_counter = counter_at_max;
		end else begin // Read mode
			if (counter == DEPTH-1) shift_en = 0; // Don't go beyond the last entry in read mode
		end
	end

	always_ff @(posedge clk) begin
		if (reset || reset_counter) begin
			counter <= '0;
		end else begin
			counter <= counter + shift_en;
		end
	end

	wire [BITS-1:0] data_in = write_mode_en ? wdata : rdata; // recirculate in read mode
	shift_register #(.BITS(BITS), .DEPTH(DEPTH)) sreg(.clk(clk), .reset(reset), .shift_en(shift_en), .data_in(data_in), .data_out(rdata));
endmodule : line_buffer
