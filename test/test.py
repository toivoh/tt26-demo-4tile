# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from ref_data import ref_data

@cocotb.test()
async def test_project(dut):
	preserved = True
	try:
		demo_top = dut.user_project.vtracer
	except AttributeError:
		preserved = False

	#NUM_SKIP_FRAMES = 0
	#NUM_SKIP_FRAMES = 30
	#NUM_SKIP_FRAMES = 15
	#NUM_SKIP_FRAMES = 64
	#NUM_SKIP_FRAMES = 7*64

	part = 0; pattern = 0; measure = 0; sub_frames = 0
	#part = 0; pattern = 0; measure = 0; sub_frames = 1
	#part = 1; pattern = 0; measure = 2; sub_frames = 127 # last frame before 2d
	#part = 1; pattern = 0; measure = 3; sub_frames = 0 # first frame of 2d
	#part = 4; pattern = 2; measure = 1; sub_frames = 127 # last frame of distorsion of cubes + pillars


	assert 0 <= part <= 6
	assert 0 <= pattern <= 3
	assert 0 <= measure <= 3
	assert 0 <= sub_frames <= 127

	NUM_SKIP_FRAMES = 2048*part + 512*pattern + 128*measure + sub_frames

	##NUM_LINES = 4*4; dut.uio_in.value = 2
	#NUM_LINES = 1
	#NUM_LINES = 10
	#NUM_LINES = 25
	NUM_LINES = 60
	#NUM_LINES = 525
	#NUM_LINES = 525*2

	#CYCLES_PER_LINE = 1600
	CYCLES_PER_LINE = 800

	output_filename_postfix = f"output-{part}-{pattern}-{measure}-{sub_frames}-l{NUM_LINES}-data.txt"
	prefix = "rtl" if preserved else "gl"
	output_filename = f"{prefix}-{output_filename_postfix}"
	#output_filename = f"{prefix}-output-{section}-{subsect}-{subsubsect}-{sub3sect}-{sub_frames}-l{NUM_LINES}-data.txt"
	#output_filename = f"{prefix}-output-skip{NUM_SKIP_FRAMES}-l{NUM_LINES}-data.txt"


	dut._log.info("Start")

	clock = Clock(dut.clk, 10, unit='ns')
	cocotb.start_soon(clock.start())

	dut.rst_n.value = 0
	dut.ui_in.value = 0
	await ClockCycles(dut.clk, 32) # Should be enough to reset the shift registers in line_double_buffer
	dut.rst_n.value = 1


	if NUM_SKIP_FRAMES > 0:
#		dut.ui_in.value = 128
#		await ClockCycles(dut.clk, CYCLES_PER_LINE*4*NUM_SKIP_FRAMES)
#		dut.ui_in.value = 0

		print(f"Skip {NUM_SKIP_FRAMES} frames...")
		dut.wanted_start_frame.value = NUM_SKIP_FRAMES
		for i in range(32*NUM_SKIP_FRAMES):
			await ClockCycles(dut.clk, 1)
			if int(dut.caught_up.value) != 0: break
		assert int(dut.caught_up.value) != 0

	print("Wait 800 cycles extra")
	#await ClockCycles(dut.clk, 224+1) # wait for vsync to become non-X
	await ClockCycles(dut.clk, 800+1) # wait for vsync and pwm_out to become non-X

	print("output_filename =", output_filename)
	print(f"diff rtl-{output_filename_postfix} gl-{output_filename_postfix}")

	data = []
	with open(output_filename, "w") as text_file:
		for j in range(NUM_LINES):
			line_data = []
			for i in range(CYCLES_PER_LINE):
				out = dut.out.value.integer
				text_file.write(f"{out} ")
				line_data.append(out)

				await ClockCycles(dut.clk, 1)
			text_file.write("\n")
			data.append(line_data)

	print("data = ")
	print(data)

	print("ref_data = ")
	print(ref_data)

	assert data == ref_data
