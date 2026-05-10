
//`define USE_OLD_TRACE_STATE

`define COMPRESS_FA_STACK
`define VIEW_CALC_PL_DELAY_STAGE_DONE // needed to put dx1 into latches
//`define INTERVAL_STACK_USE_BIDIR

`define USE_STACK_UNDERFLOW_RESTART
`define USE_TTF

`define USE_MUSIC
`define USE_SCALES
//`define USE_BDRUM
`define USE_WF_PWM

//`define DUPLICATE_SYNTH

`define USE_TUNNEL

`define USE_CURR_X_FIX_BITS

//`define CYCLE_FLAGS

//`define USE_LOCK_DX2


`ifdef USE_CURR_X_FIX_BITS
	`define CURR_ROOM_FIX_MASK 'b100001111
	`ifdef USE_TUNNEL
		`define CURR_X_E0_FIX_MASK 63
		`define CURR_X_E1_FIX_MASK 63
	`else
		`define CURR_X_E0_FIX_MASK (-1)
		`define CURR_X_E1_FIX_MASK (-1)
	`endif
`else
	`define CURR_ROOM_FIX_MASK 0
	`define CURR_X_E0_FIX_MASK 0
	`define CURR_X_E1_FIX_MASK 0
`endif

`define CURR_ROOM_FIX_VALUE 4
`define CURR_X_E0_FIX_VALUE 0
`define CURR_X_E1_FIX_VALUE ((-128+16)*2)



`ifndef PURE_RTL
//`define USE_LATCHES
`endif


`define CTRL_FLAG_LOCK_DX2_UPDATE 0
`define CTRL_FLAG_ALT_SHADING     1
`define CTRL_FLAG_BITS            2


`define SCENE_FLAG_CEIL_DEC    0
`define SCENE_FLAG_PORTALS     1
`define SCENE_FLAG_BLOCKAGES   2
`define SCENE_FLAG_ALT_HEIGHTS 3
`define SCENE_FLAG_TUNNEL      4
`define SCENE_FLAG_NARROW      5
`define SCENE_FLAG_BITS        6


`define SRC1_BITS 2
`define SRC1_ZERO     2'd0
`define SRC1_ACC      2'd1
`define SRC1_MINUS1   2'd2
//`define SRC1_ACC_SHL1 2'd2
//`define SRC1_INV_ACC  2'd3

`define SRC2_BITS 4
`define SRC2_NOTE_MUL      4'd0
`define SRC2_PWM_OFFS      4'd1
`define SRC2_VOL           4'd2
`define SRC2_SLOPE_FRAC    4'd3
`define SRC2_OUT_ACC_LOW   4'd4
`define SRC2_OUT_ACC_HIGH  4'd5
`define SRC2_OUT_ACC_LOW0  4'd6
`define SRC2_OUT_ACC_HIGH0 4'd7
`define SRC2_ACC_SHL1      4'd8
`define SRC2_GPHASE_LOW    4'd9
`define SRC2_GPHASE_HIGH   4'd10
`define SRC2_BDRUM_PHASE   4'd11

`define SRC2MOD_BIT_NEG      0
`define SRC2MOD_BIT_SHL1     1
`define SRC2MOD_BIT_BOOTH    2
`define SRC2MOD_BIT_CARRY_IN 3  // no effect when SRC2MOD_BIT_NEG is set
`define SRC2MOD_BIT_ZERO     4
`define SRC2MOD_BIT_SEXT     5
`define SRC2MOD_BIT_CARRY_IN_CONTROL 6
`define SRC2MOD_BITS         7

`define FLAG_BIT_SATURATE 0
`define FLAG_ZEXT_ACC     1
`define FLAG_BITS         2

`define RES_BITS  1
`define RES_SUM   1'b0
`define RES_BOOTH 1'b1

`define WE_BIT_ACC          0
`define WE_BIT_GPHASE_LOW   1
`define WE_BIT_GPHASE_HIGH  2
`define WE_BIT_OUT_ACC_LOW  3
`define WE_BIT_OUT_ACC_HIGH 4
`define WE_BITS             5


`define SYNTH_STATE_BITS 6
`define GAIN_SHR_BITS 2


`define FRAME_T_BITS 14
//`define MUSIC_T_INT_BITS 9
`define MUSIC_T_INT_BITS 11


`define T1T2FOV_BIT_T2  0 // set if t2
`define T1T2FOV_BIT_FOV 1 // set if fov_factor; overrides t2


// General definitions
`define propagated_parameter_definitions \
		parameter DX_BITS=10, X_BITS=9, DYNAMIC_RSHIFT_BITS=0, ROOM_X_BITS=9, DEPTH_BITS=3, LEVEL_BITS=3, POS_BITS=10, QUEUE_SIZE=8, VALUE_BITS=2, SHORT_LENGTH_BITS=6, TAIL_LENGTH_BITS=SHORT_LENGTH_BITS, \
		ROOM_BITS=8, \
		DDX_BITS=9, DXF_FRAC_BITS=8, \
		LOG_N_HURRY_THRESH=5, MAX_DEPTH=8, STACK_DEPTH=16, \
		DET_RED_X=0, DET_RED_DX=0, \
		AXIS_SIZES_BITS=X_BITS, AXIS_SIZES_LSB_SKIP=0, \
		MAX_LOG_N = POS_BITS

// x bits used in subdeterminant: X_BITS - 1 - (2^DYNAMIC_RSHIFT_BITS - 1)
// Standard setup
`define propagated_parameters_standard \
		parameter DX_BITS=10, DDX_BITS=11, DXF_FRAC_BITS=9, X_BITS=9+3, DYNAMIC_RSHIFT_BITS=2, ROOM_X_BITS=9, \
		ROOM_BITS=9, \
		POS_BITS=10, MAX_LOG_N = POS_BITS, \
		MAX_DEPTH=8, DEPTH_BITS=4, LEVEL_BITS=3, STACK_DEPTH=4, \
		QUEUE_SIZE=8, VALUE_BITS=2, SHORT_LENGTH_BITS=6, TAIL_LENGTH_BITS=SHORT_LENGTH_BITS, \
		LOG_N_HURRY_THRESH=5, \
		DET_RED_X=0, DET_RED_DX=0, \
		AXIS_SIZES_BITS=7, AXIS_SIZES_LSB_SKIP=1

// Reduced setup
`define propagated_parameters_reduced \
		parameter DX_BITS=10, DDX_BITS=11, DXF_FRAC_BITS=9, X_BITS=9+0, DYNAMIC_RSHIFT_BITS=0, ROOM_X_BITS=8, \
		ROOM_BITS=8, \
		POS_BITS=10, MAX_LOG_N = POS_BITS, \
		MAX_DEPTH=8, DEPTH_BITS=3, LEVEL_BITS=3, STACK_DEPTH=11, \
		QUEUE_SIZE=8, VALUE_BITS=2, SHORT_LENGTH_BITS=6, TAIL_LENGTH_BITS=SHORT_LENGTH_BITS, \
		LOG_N_HURRY_THRESH=5, \
		DET_RED_X=0, DET_RED_DX=0, \
		AXIS_SIZES_BITS=7, AXIS_SIZES_LSB_SKIP=1

`define parameters_forward \
		/* for subdiv_tracer */ \
		.X_BITS(X_BITS), .DYNAMIC_RSHIFT_BITS(DYNAMIC_RSHIFT_BITS), .ROOM_X_BITS(ROOM_X_BITS), .DX_BITS(DX_BITS), .DEPTH_BITS(DEPTH_BITS), .LEVEL_BITS(LEVEL_BITS), .POS_BITS(POS_BITS), \
		.ROOM_BITS(ROOM_BITS), \
		.DDX_BITS(DDX_BITS), .DXF_FRAC_BITS(DXF_FRAC_BITS), \
		.LOG_N_HURRY_THRESH(LOG_N_HURRY_THRESH), .MAX_DEPTH(MAX_DEPTH), .STACK_DEPTH(STACK_DEPTH), \
		.DET_RED_X(DET_RED_X), .DET_RED_DX(DET_RED_DX), \
		.AXIS_SIZES_BITS(AXIS_SIZES_BITS), .AXIS_SIZES_LSB_SKIP(AXIS_SIZES_LSB_SKIP), \
		.MAX_LOG_N(MAX_LOG_N), \
		/* for buffered_tracer */ \
		.VALUE_BITS(VALUE_BITS), .QUEUE_SIZE(QUEUE_SIZE), .SHORT_LENGTH_BITS(SHORT_LENGTH_BITS), .TAIL_LENGTH_BITS(TAIL_LENGTH_BITS)

// Parameters that are derived from the forwarded ones, or are not to be overridden
`define derived_parameter_definitions \
		/* Don't override: */ \
		N_BITS = $clog2(POS_BITS+1), \
		TAG_BITS = DEPTH_BITS + LEVEL_BITS, \
		LENGTH_BITS = MAX_LOG_N, \
		DECISION_BITS = 4


`define subdiv_tracer_output_definitions \
		/* emit interface: output */ \
		output wire emit, \
		output wire [POS_BITS-1:0] i1_emit, i2_emit, \
		output wire [LENGTH_BITS-1:0] length_m1_emit, \
		output wire [DEPTH_BITS-1:0] depth, \
		output wire [LEVEL_BITS-1:0] level, \
		output wire [1:0] face_axis, wall_face_axis, \
		output wire dom, old_dom, \
		\
		output wire nav_working, \
		\
		/* output for debug */ \
		output wire subdiv_en, /* test assumption: evaluating next decision unless low */ \
		output wire [DEPTH_BITS+LEVEL_BITS-1:0] subdivider_level, \
		\
		output wire [X_BITS-1:0] x_corner_0, x_corner_1, x_corner_2, \
		output wire [X_BITS-1:0] axis_sizes_0, axis_sizes_1, axis_sizes_2, \
		output wire [X_BITS-1:0] room_pos_0, room_pos_1, room_pos_2, \
		output wire [ROOM_BITS-1:0] room, \
		output wire [DECISION_BITS-1:0] curr_decision, descend_decision, \
		output wire curr_hit,   /* test assumption: if subdiv_en, curr_hit says if we have an effective wall hit */ \
		output wire accept_hit, \
		output wire forced_hit, /* test assumption: high if curr_hit is high due to hurry instead of an actual wall hit */ \
		\
		output wire descend, ascend, adjusting, \
		output wire [TAG_BITS-1:0] target_tag, \
		\
		output wire updating_i_d2, \
		\
		output wire signed [DX_BITS-1:0] dx_e0, dx_e1, dx_e2, dx1_e0, dx1_e1, dx1_e2, dx2_e0, dx2_e1, dx2_e2, \
		\
		output wire [1:0] subdiv_state, \
		output wire [2:0] dx_signs_td, \
		\
		output wire subdiv_tracer_reset_out, \
		/* For free view */ \
		output wire [3*DX_BITS-1:0] dxf_out, \
		output wire signed [3*DDX_BITS-1:0] ddx_out, \
		\
		output wire [ROOM_BITS-1:0] room_initial_out, \
		output wire [3*X_BITS-1:0] x_corner_initial_out, \
		output wire [3*X_BITS-1:0] axis_sizes_initial_out, \
		\
		output wire [$clog2(STACK_DEPTH)-1:0] stack_pointer_out, \
		output wire [$clog2(STACK_DEPTH+1)-1:0] stack_depth_out, \
		output wire line_done \


`define subdiv_tracer_output_forward \
		.emit(emit), .length_m1_emit(length_m1_emit), .i1_emit(i1_emit), .i2_emit(i2_emit), .depth(depth), .level(level), .face_axis(face_axis), .wall_face_axis(wall_face_axis), .dom(dom), .old_dom(old_dom), \
		.nav_working(nav_working), \
		.subdiv_en(subdiv_en), .subdivider_level(subdivider_level), \
		.x_corner_0(x_corner_0), .x_corner_1(x_corner_1), .x_corner_2(x_corner_2), .axis_sizes_0(axis_sizes_0), .axis_sizes_1(axis_sizes_1), .axis_sizes_2(axis_sizes_2), \
		.room(room), .room_pos_0(room_pos_0), .room_pos_1(room_pos_1), .room_pos_2(room_pos_2), \
		.curr_decision(curr_decision), .curr_hit(curr_hit), .accept_hit(accept_hit), .forced_hit(forced_hit), .descend_decision(descend_decision), \
		.ascend(ascend), .adjusting(adjusting), .descend(descend), .target_tag(target_tag), .updating_i_d2(updating_i_d2), \
		.dx_e0(dx_e0), .dx_e1(dx_e1), .dx_e2(dx_e2), .dx1_e0(dx1_e0), .dx1_e1(dx1_e1), .dx1_e2(dx1_e2), .dx2_e0(dx2_e0), .dx2_e1(dx2_e1), .dx2_e2(dx2_e2), \
		.subdiv_state(subdiv_state), .dx_signs_td(dx_signs_td), \
		.subdiv_tracer_reset_out(subdiv_tracer_reset_out), \
		.dxf_out(dxf_out), .ddx_out(ddx_out), \
		.room_initial_out(room_initial_out), .x_corner_initial_out(x_corner_initial_out), .axis_sizes_initial_out(axis_sizes_initial_out), \
		.line_done(line_done), \
		.stack_pointer_out(stack_pointer_out), .stack_depth_out(stack_depth_out) \


`define buffered_tracer_output_definitions \
		`subdiv_tracer_output_definitions, \
		output wire [VALUE_BITS-1:0] curr_value, \
		output wire [VALUE_BITS-1:0] value_emit, \
		output wire hurry, \
		output wire [VALUE_BITS-1:0]  initial_value_out, \
		output wire [LENGTH_BITS-1:0] initial_length_out, \
		output wire consume_pixel_out, ack_emit, \
		output wire [$clog2(QUEUE_SIZE + 2)-1:0] tail_index_out

`define buffered_tracer_output_forward \
		`subdiv_tracer_output_forward, \
		.curr_value(curr_value), \
		.value_emit(value_emit), \
		.hurry(hurry), \
		.initial_value_out(initial_value_out), .initial_length_out(initial_length_out), \
		.consume_pixel_out(consume_pixel_out), .ack_emit(ack_emit), .tail_index_out(tail_index_out)
