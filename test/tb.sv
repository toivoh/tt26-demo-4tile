`default_nettype none
`timescale 1ns / 1ps

`include "../src/common_pl.vh"

module tb ();


	initial begin
		$dumpfile("tb.fst");
		$dumpvars(0, tb);
		#1;
	end


	// Wire up the inputs and outputs:
	reg clk;
	reg rst_n;
	reg ena;
	reg [7:0] ui_in = 0;
	reg [7:0] uio_in = 0;
	wire [7:0] uo_out;
	wire [7:0] uio_out;
	wire [7:0] uio_oe;
`ifdef GL_TEST
	wire VPWR = 1'b1;
	wire VGND = 1'b0;
`endif

	logic [7:0] ui_in_modified;

	tt_um_toivoh_demo_4tile user_project (

	// Include power ports for the Gate Level test:
`ifdef GL_TEST
		.VPWR(VPWR),
		.VGND(VGND),
`endif

		.ui_in  (ui_in_modified),    // Dedicated inputs
		.uo_out (uo_out),   // Dedicated outputs
		.uio_in (uio_in),   // IOs: Input path
		.uio_out(uio_out),  // IOs: Output path
		.uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
		.ena    (ena),      // enable - goes high when design is selected
		.clk    (clk),      // clock
		.rst_n  (rst_n)     // not reset
	);

	wire [8:0] out = {uio_out[7], uo_out};

	int counter;
	always_ff @(posedge clk) begin
		if (!rst_n) counter <= 0;
		else counter <= counter + 1;
	end

	// Raster scan
	// ===========
	localparam SCAN_X0_BITS = 11;
	localparam SCAN_X_BITS = 10;
	localparam SCAN_Y_BITS = 10;//9;

	wire signed [SCAN_X0_BITS-1:0] x0;
	wire signed [SCAN_X_BITS-1:0] x = x0[SCAN_X0_BITS-1:1];
	wire new_pixel = x0[0];
	wire signed [SCAN_Y_BITS-1:0] y;
	//wire active, x_active, y_active;
//	wire new_line, x_active_start, y_hit;
	//raster_scan_c rs(
	wire new_frame;
	wire [1:0] x_state, y_state;
	raster_scan #(
`ifdef USE_1_CYCLE_PER_PIXEL
		//.USE_DOUBLE_X(0),
		.USE_DOUBLE_X(1), .HALVE_XRES(1),
`else
		.USE_DOUBLE_X(1),
`endif

`ifdef USE_LINE_BUFFER
		.USE_LBUF(1)
`else
		.USE_LBUF(0)
`endif
	) rs (
		.clk(clk), .reset(!rst_n), .en(1'b1), .speedup('0),
		.force_x_at_thresh(ui_in_modified[6]), .force_y_at_thresh(ui_in_modified[7]),
		.x(x0), .y(y), .x_state(x_state), .y_state(y_state), .new_frame(new_frame)
	);

	int wanted_start_frame = 0, curr_frame = 0;
	wire caught_up = (curr_frame >= wanted_start_frame);

	int wait_counter;

	logic force_x_at_thresh, force_y_at_thresh;
	always_ff @(posedge clk) begin
		wait_counter <= force_x_at_thresh ? 0 : wait_counter + 1;
		curr_frame <= curr_frame + new_frame;
	end
	always_comb begin
		force_x_at_thresh = 0;
		force_y_at_thresh = 0;
		if (curr_frame < wanted_start_frame) begin
			force_y_at_thresh = 1;
			force_x_at_thresh = (!(y_state == 3 && x_state == 3) || wait_counter >= 8);
		end

		ui_in_modified = ui_in;
		ui_in_modified[6] |= force_x_at_thresh;
		ui_in_modified[7] |= force_y_at_thresh;
	end

endmodule
