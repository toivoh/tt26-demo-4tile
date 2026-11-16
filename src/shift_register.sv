`default_nettype none

module shift_register #(
		parameter BITS = 9, DEPTH = 24, CLOCK_GATE_CHUNK = 4
	) (
		input wire clk, reset,

		input wire shift_en,
		input wire [BITS-1:0] data_in,
		output wire [BITS-1:0] data_out
	);

	genvar i, j;

`ifdef PURE_RTL
	(* mem2reg *) reg [BITS-1:0] data[DEPTH];
`else
	wire [BITS-1:0] data[DEPTH];
`endif
	wire [BITS-1:0] data_next[DEPTH];

	assign data_next[0] = data_in;
	generate
		for (i = 1; i < DEPTH; i++) assign data_next[i] = data[i-1];

`ifdef PURE_RTL
		for (i = 0; i < DEPTH; i++) begin
			always_ff @(posedge clk) if (shift_en) data[i] <= data_next[i];
		end
`else
/*
		wire clk_gated;
		gf180mcu_fd_sc_mcu7t5v0__icgtp_4 clock_gate(.CLK(clk), .E(shift_en), .TE(0), .Q(clk_gated));
		for (i = 0; i < DEPTH; i++) begin
			//always_ff @(posedge clk_gated) data[i] <= data_next[i];
			for (j = 0; j < BITS; j++) begin
				gf180mcu_fd_sc_mcu7t5v0__dffq_1 sreg_ff(.CLK(clk_gated), .D(data_next[i][j]), .Q(data[i][j]));
			end
		end
*/
/*
		wire [DEPTH-1:0] clk_gated;
		for (i = 0; i < DEPTH; i++) begin
			gf180mcu_fd_sc_mcu7t5v0__icgtp_4 clock_gate(.CLK(clk), .E(shift_en), .TE(0), .Q(clk_gated[i]));
			//always_ff @(posedge clk_gated[i]) data[i] <= data_next[i];
			for (j = 0; j < BITS; j++) begin
				gf180mcu_fd_sc_mcu7t5v0__dffq_1 sreg_ff(.CLK(clk_gated[i]), .D(data_next[i][j]), .Q(data[i][j]));
			end
		end
*/

		wire [(DEPTH-1)/CLOCK_GATE_CHUNK:0] clk_gated;
		for (i = 0; i <= (DEPTH-1)/CLOCK_GATE_CHUNK; i++) begin
			gf180mcu_fd_sc_mcu7t5v0__icgtp_4 clock_gate(.CLK(clk), .E(shift_en), .TE(0), .Q(clk_gated[i]));
		end
		for (i = 0; i < DEPTH; i++) begin
			for (j = 0; j < BITS; j++) begin
				gf180mcu_fd_sc_mcu7t5v0__dffq_1 sreg_ff(.CLK(clk_gated[i/CLOCK_GATE_CHUNK]), .D(data_next[i][j]), .Q(data[i][j]));
			end
		end

`endif
	endgenerate

	assign data_out = data[DEPTH-1];
endmodule : shift_register
