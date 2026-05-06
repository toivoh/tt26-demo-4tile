/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`include "common_pl.vh"

// for vga_pl_tracer
module tt_um_toivoh_demo_4tile #(
		`propagated_parameters_standard,
//		`propagated_parameters_reduced,
		`derived_parameter_definitions
	) (
		input  wire [7:0] ui_in,    // Dedicated inputs
		output wire [7:0] uo_out,   // Dedicated outputs
		input  wire [7:0] uio_in,   // IOs: Input path
		output wire [7:0] uio_out,  // IOs: Output path
		output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
		input  wire       ena,      // always 1 when the design is powered, so you can ignore it
		input  wire       clk,      // clock
		input  wire       rst_n     // reset_n - low to reset
	);

	localparam COLOR_CHANNEL_BITS=2;

	wire reset = !rst_n;
	wire en = 1;

	wire [COLOR_CHANNEL_BITS*3-1:0] rgb;
	wire hsync, vsync;

	wire [VALUE_BITS-1:0] value;
	wire [15:0] sound_sample;
	wire pwm_out;
	vga_pl_tracer #( `parameters_forward ) vtracer(
		.clk(clk), .reset(reset), .speedup(ui_in[2:0]), .interlace_enable(!ui_in[3]),
		.force_x_at_thresh(ui_in[6]), .force_y_at_thresh(ui_in[7]),
		.value_out(value), .rgb_out(rgb), .hsync(hsync), .vsync(vsync),
		.sound_sample(sound_sample), .pwm_out(pwm_out)
	);
	//assign rgb = value;

	wire [1:0] r, g, b;
	assign {r, g, b} = rgb;

	assign uo_out = {
		hsync,
		b[0],
		g[0],
		r[0],
		vsync,
		b[1],
		g[1],
		r[1]
	};

`ifdef USE_MUSIC
	//assign uio_out = sound_sample[13 -: 8];
	assign uio_out = {pwm_out, 7'b0};
`else
	assign uio_out = '0;
`endif

	assign uio_oe = 1 << 7;

	// List all unused inputs to prevent warnings
	wire _unused = &{ena, rst_n, ui_in, uio_in};
endmodule
