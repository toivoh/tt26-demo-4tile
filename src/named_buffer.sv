`default_nettype none

module named_buffer #(parameter BITS=1) (
		input wire [BITS-1:0] in,
		output wire [BITS-1:0] out
	);
`ifndef PURE_RTL
	genvar i;
	generate
		for (i = 0; i < BITS; i++) begin : bits
			//(* keep *) (* dont_touch *) sky130_fd_sc_hd__buf_1 named_buf(.A(in[i]), .X(out[i]));
			(* keep *) (* dont_touch *) gf180mcu_fd_sc_mcu7t5v0__buf_1 named_buf(.I(in[i]), .Z(out[i]));
			//(* keep *) (* dont_touch *) buf named_buf(out[i], in[i]);
		end
	endgenerate
`else
	assign out = in;
`endif
endmodule
