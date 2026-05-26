<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## Intro

Curly / Medieval presents **Underflow Cubed**,
my contribution to the four tile category of the TTSKY26a demo competition.
Code, graphics, and music by Curly (Toivo Henningsson) of Medieval.

The demo can be seen at https://youtu.be/m0GFAU291TQ (captured from a Verilator simulation).

## How it works

The 3d scenes use a custom per scan line rendering algorithm derived from a ray tracing formulation, but sharing computations between different pixels in the same scan line when possible.
Much more details can be found at https://possible-realities.blogspot.com/2026/05/tracing-beam.html.

The synth works in a quite similar way to the one described in https://github.com/toivoh/tt10-demo/blob/main/docs/info.md.
Many of those ideas are described further in https://github.com/toivoh/ttsky25a-pwl-synth/blob/main/docs/info.md, but that synth uses a phase accumulator per voice, instead of calculating voice phases from a shared oscillator.
The synth is sampled at 63 kHz at almost 10 bit resolution (PWM output from 0 to 800), with delta-sigma modulation to add 4 additional bits of resolution.
The synth has 24 voices, which are evaluated in turn to calculate each sample. One voice is evaluated in 32 cycles.
To support the greater number of voices (Orion Iron Ion supported 12), a faster multiplication algorithm is used to calculate the phase from the global oscillator using a radix 4 Booth multiplier.
Most notes use 4 voices with slightly different detuning (and two different octaves for the organ patch), with 2 voices per note for the chords.

The sequencer puts together the note material from a few different sources:

- the main melody,
- the current chord for the main melody (root note, sus4 or not, fourth note: nothing / 7 chord / double the root on octave up)
- patterns for the bass and accompaniment based on the current chord

All notes except the melody are derived from the curent chord.

Notes are expressed a scale of 7 notes per octave. These are translated to actual pitches using the current key, which can switch between

- A harmonic minor
- C harmonic minor
- C minor
- C dorian
- C mixolydian
- C major

When modulating at the end of many sections, the melody note is initially kept in the current key, while the rest of the notes go to the new key.

## How to test

Plug in a [TinyVGA](https://github.com/mole99/tiny-vga) compatible Pmod on the demo board's out Pmod.
Plug in a Pmod compatible with [Mike's audio Pmod](https://github.com/MichaelBell/tt-audio-pmod) on the TT08 demo board's bidir Pmod.
Set all inputs to zero to get the default behavior.
The demo starts directly after reset.

## External hardware

This project needs
-  a [TinyVGA](https://github.com/mole99/tiny-vga) VGA Pmod.
- [Mike's audio Pmod](https://github.com/MichaelBell/tt-audio-pmod).
