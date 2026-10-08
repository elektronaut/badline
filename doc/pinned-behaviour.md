# Pinned behaviour

These timing rules were derived empirically against a named test, not from
a datasheet. Each entry states the rule, the test that forced it and, where
there is one, the fast spec that guards it. Specs carrying a guard say
`Pinned by <test>` in a comment.

The constraint list is the artifact; the implementation is not. When you
change code a rule governs, re-derive the rule against its pinning test. A
green suite is not enough, because a suite can stay green while the rule
breaks: a spec guard catches the rule's own failure mode, and a baseline
only catches the rows that happen to move.

- [CPU interrupt recognition](#cpu-interrupt-recognition)
- [CPU JAM](#cpu-jam)
- [CPU unstable stores under DMA](#cpu-unstable-stores-under-dma)
- [CPU ANE constant](#cpu-ane-constant)
- [VIC raster IRQ phase](#vic-raster-irq-phase)
- [VIC mid-line register visibility](#vic-mid-line-register-visibility)
- [VIC sprite display](#vic-sprite-display)
- [VIC sprite collisions](#vic-sprite-collisions)
- [VIC border and idle state](#vic-border-and-idle-state)
- [VIC bad line and DMA](#vic-bad-line-and-dma)
- [VIC graphics pipeline](#vic-graphics-pipeline)
- [VIC phi1 bus](#vic-phi1-bus)
- [VIC light pen](#vic-light-pen)
- [VIC-II 8565](#vic-ii-8565)
- [VIC-IIe 2 MHz and TEST bit](#vic-iie-2-mhz-and-test-bit)
- [VIC-II NTSC](#vic-ii-ntsc)
- [VIC-II 6572 (Drean)](#vic-ii-6572-drean)
- [CIA 6526 timer pipeline](#cia-6526-timer-pipeline)
- [CIA 6526A interrupt register](#cia-6526a-interrupt-register)
- [CIA serial shift register](#cia-serial-shift-register)
- [VIA shift register](#via-shift-register)
- [6510 I/O port](#6510-io-port)
- [RAM power-on pattern](#ram-power-on-pattern)
- [VIC-20 RAM power-on pattern](#vic-20-ram-power-on-pattern)
- [VIC-I fetches and the V-bus](#vic-i-fetches-and-the-v-bus)
- [VIC-I sound](#vic-i-sound)
- [1541 serial port](#1541-serial-port)
- [1541 disk mechanism](#1541-disk-mechanism)
- [REU DMA](#reu-dma)
- [SID oscillator](#sid-oscillator)
- [SID register writes](#sid-register-writes)
- [SID data bus](#sid-data-bus)
- [SID envelope](#sid-envelope)
- [`.sid` tune banking](#sid-tune-banking)

## CPU interrupt recognition

- `poll` runs at the head of every `CPU#cycle!`, before that cycle's
  micro-operation, and shifts `irq && !I` and the NMI latch through a
  two-stage pipeline (`pending ← sample ← line`). The instruction boundary
  consumes `pending` *before* its own poll, which is the
  second-to-last-cycle sample (64doc: "2 or more cycles before the end").
  `end_sequence` latches that value into `@boundary_irq`/`@boundary_nmi` as
  the instruction ends. That is the same read, because nothing but `poll`
  moves `pending`.
- A taken same-page branch sets `@skip_poll`, skipping one poll, so the
  interrupt must arrive before clock 1. The CLI/SEI/PLP delays fall out of
  sampling `!I` at poll time.
- An NMI before cycle 4 hijacks a BRK or IRQ sequence: the vector swaps at
  the `@nmi_pending` check before the vector fetch, and the B flag stays on
  the stack. Interrupt sequences, BRK included, clear the pipeline at their
  end, so the handler's first instruction always runs.
- The sequence is a true 7 cycles. The CPU does *not* clear `@irq` on
  service, because the line belongs to the device.
- Pinned by Lorenz `irq` and `nmi` (`nmi` subtest `00/5` for the pipeline
  clear).
- A cycle the VIC stalls through BA (`CPU#stall!`) keeps sampling the lines
  but doesn't advance the pipeline: `irq_sample ||= irq && !I` and
  `nmi_sample ||= nmi`, OR-ed with the sample it held, while `pending`
  doesn't shift and `@skip_poll` stays owed to the next real cycle. The I
  used is the one the stalled step leaves when it comes from the opcode: a
  stalled CLI execute cycle masks with I = 0 and a stalled SEI with I = 1.
  Every other step uses the current I. PLP too: its pulled I only arrives
  with the stalled stack read.
  - Each piece is forced by an `interrupts/irqdma` case. A NOP stalled on
    its last cycle with the IRQ rising in the stall is taken after that NOP
    (test 1). An SEI whose fetch sampled the IRQ, stalled on its execute
    cycle, is still taken after the SEI (`||=`), while an IRQ rising in the
    SEI stall is masked (test 7, `$d015=03`). A CLI stalled with the IRQ
    rising is taken after the CLI (test 7, `$d015=01`). A PLP stalled on its
    stack read pulling I = 1 is taken after the PLP (test 6, `$d015=40`
    offset 106). Consuming `@skip_poll` in the stall breaks test 5.
  - Pinned by `interrupts/irqdma` (all 16 rows) and Lorenz `irq` and `nmi`.
  - Spec guard: *interrupts sampled while stalled by the VIC* in
    [`cpu_spec.rb`](../spec/badline/cpu_spec.rb), one example per piece.
- Spec guard: the *interrupt recognition timing* group in
  [`cpu_spec.rb`](../spec/badline/cpu_spec.rb), one example per quirk.

## CPU JAM

- JAM reads the opcode, a dummy byte, `$FFFF`, `$FFFE` and `$FFFE`, then
  `$FFFF` on every cycle until reset. It never reaches an instruction
  boundary, so a pending IRQ or NMI is never taken.
- Pinned by `CPU/cpujam` (the halt) and `jamirq`/`jamnmi`.
- Spec guard: the *JAM* group in
  [`cpu_spec.rb`](../spec/badline/cpu_spec.rb).

## CPU unstable stores under DMA

- A cycle the VIC holds the CPU through BA is not a CPU cycle.
  `Computer#cycle!` calls `CPU#stall!` instead of `CPU#cycle!`, which
  records `@cycles`. The interrupt pipeline's `pending` stage doesn't
  advance, but the line sample does (see *CPU interrupt recognition*).
- SHA, SHX, SHY and SHS/TAS drop the `& (H+1)` from the stored value when
  the CPU is stalled **immediately before the dummy read**, the
  second-to-last cycle (VICE x64sc's `LOAD_CHECK_BA_LOW_DUMMY`). A stall at
  any earlier cycle leaves it in. The high byte of a page-crossing target
  is still `value & (H+1)` either way.
  - The rule is that one cycle, not "RDY went low during the instruction".
    In the `*4`/`*5` timing tables the drop falls exactly one position after
    each cycle-steal dip and on no other position. A whole-instruction rule
    would drop on the positions after it too.
  - Pinned by `CPU/sha`, `CPU/shxy` and `CPU/shs`, variants 2–5, with
    variant 1 as the stall-free guard. They measure against VIC BA timing:
    the `*2`/`*3` variants (sprite DMA) and `shxy4`/`shyx4`/`shx-test`
    need sprite BA at `54 + 2n`, and the `*4`/`*5` variants (sprite and
    character DMA) also need the bad-line and sprite-DMA-end BA to match.
- Spec guard: *SHX stalled by the VIC* in
  [`cpu_spec.rb`](../spec/badline/cpu_spec.rb).

## CPU ANE constant

- ANE computes `A = (A | CONST) & X & imm`. `CONST` varies from chip to
  chip; `CPU.new` takes it as `ane_constant:` and defaults to the C64
  6510's `$EF`, VICE's value. A stall between the opcode and operand
  fetches clears bits 0 and 4 of it (`CONST & $EE`).
- Pinned by `CPU/ane` (`ane`, `ane-border` and `ane-none`), which fails any
  constant without bits 0 and 1 set and a high nybble of `$4`, `$5`, `$E`
  or `$F`. The stall variant follows VICE: the testprog only displays the
  RDY-cycle result, so no exit code pins it.
- SingleStepTests recorded an NMOS 6502 whose constant is `$EE`, so
  `test/test_cpu.rb` builds its CPU with `ane_constant: 0xee` and checks
  `$8B` as strictly as every other opcode.
- Spec guard: *ANE* in [`cpu_spec.rb`](../spec/badline/cpu_spec.rb).

## VIC raster IRQ phase

- The raster compare happens at the line wrap (the end of the old line's
  last cycle), except on line 0, which compares at column 0. This is Bauer
  3.12's "cycle 0 of every line, cycle 1 of line 0".
- The bad line compare picks up the same wrap (see
  [VIC bad line and DMA](#vic-bad-line-and-dma)). It was re-derived against
  the tests below when that landed.
- Pinned by `greydot`, `ss-*-color` and `den01-49-*`, with `denrsel-s0` as
  the guard that must keep passing. This rule is coupled to
  [CPU interrupt recognition](#cpu-interrupt-recognition), so recalibrate
  the two together.
- Spec guard: *with the compare at the line wrap* and *with line 0 as the
  target* in [`vic_spec.rb`](../spec/badline/vic_spec.rb). They are the
  only examples that separate this phase from a uniform column-0 compare.
- `$d011` bit 7 and `$d012` follow the same phase. Every line reads as the
  new line from the CPU cycle paired with column 62 of the old one. Line 0
  reads a cycle later: that cycle still reads 311. VICE resets the counter
  at cycle 2 of line 0 but increments it at cycle 1 of every other line.
  - Pinned by `split-tests/lightpen`, whose `$d011`/`$d012` pages match
    `dump6569` byte for byte only with the delay. Without it, index `$47`
    reads `$1b`/`$00` where the chip reads `$9b`/`$37`, and the test exits
    `$ff`.
  - Spec guard: *when the counter wraps to line 0* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- The compare latches the flag only on a change from no match to match,
  and it runs again after every `$d011`/`$d012` write as well as at each
  line step (VICE x64sc compares in every cycle). A write after column 61
  is left to the line step, so a target moved to the next line there
  still matches when the line steps: the match holds and nothing latches.
  A write that moves the target onto the current line latches at once.
  - Pinned by `rasterirq_hold` (11672 px → pass). It goes back to 11672 px
    when the line step latches on any match, and to 345 px when writes
    don't run the compare, which also breaks `greydot` (1576 px), because
    the stale match state then swallows a later edge.
  - The latch on a write that moves the target onto the current line is
    VICE's behaviour. No test pins it: `rasterirq_hold` and `greydot` still
    pass when a write only updates the match state.
  - Spec guard: *with the target stepped along with the raster line* and
    *when a write moves the target onto the current line* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).

## VIC mid-line register visibility

- Sprite registers written mid-line are logged against
  `(write cycle + 1) * 8` and take hold after a per-signal delay: **+1 px**
  for the colors ($d025/$d026/$d027–$d02e), **+6 px** for priority
  ($d01b) and **+7 px** for the sequencer inputs ($d000–$d010, $d01c,
  $d01d). The color delay is the same +1 px that `greydot` pins for
  $d020–$d024 below.
  - Pinned by the `spritesplit` staircases. `ss-hires-color`/`ss-mc-color*`
    fix the color delay and `ss-pri*` the priority one (only the bands where
    the sprite sits on an odd X can tell 6 from 7).
    `ss-hires-mc`/`ss-mc-hires`/`ss-*exp*` fix the sequencer one.
  - These were +9/+14/+15 until the sprite BA windows moved a column
    earlier (see *VIC sprite display*). `spritesplit` syncs on a raster IRQ
    whose line starts a sprite DMA. With the window where `spritesteal` puts
    it, that line's stall catches a read it used to miss, so the CPU loses 5
    cycles there, not 4, and every write in the staircase lands one cycle
    later. The old delays were 8 px of that phase error on top of the real
    delay.
  - Spec guard: *mid-line write delays* in
    [`vic/sprites_spec.rb`](../spec/badline/vic/sprites_spec.rb), one example
    per path, each failing on a one-pixel change.
- $d020–$d024 writes become visible 1 px into the next column.
  `ColorPatches` restores the boundary pixel at `finish_line`.
  - Pinned by `greydot`.
  - Spec guard:
    [`vic/color_patches_spec.rb`](../spec/badline/vic/color_patches_spec.rb).
- `apply_border` restores a pre-composite snapshot (`BorderMask`) instead of
  repainting with the end-of-line $d020, so mid-line border splits survive
  sprite compositing.

## VIC sprite display

- Sprite display starts at **Y+1**: the Y match turns DMA on, and the first
  row renders on the next line.
- DMA compares at cycles 55/56 (**VIC columns 53/54**, with BA rebuilt
  mid-line). Display turns on at cycle 58 (column 57), **but only while both
  MxE and Y still match**. That is Bauer §3.8 rule 6 plus the enable bit his
  wording omits. A write to either register between the compares and cycle
  58 keeps DMA running invisibly.
  - Pinned by all five `spriteenable` rows. `3` and `5` move Y and `4`
    clears MxE. `1` and `2` write $d015 *between* the two compares, which
    only lands on that column pair.
- Each sprite's BA window is five columns, three ahead of its two s-access
  columns, stepping two columns per sprite from column 54
  (`SPRITE_BA_WINDOWS`). `ba_low?` is asked after the VIC has advanced, so
  the CPU cycle that follows VIC column 53 is the first one sprite 0 halts.
  From sprite 3 on, the window runs past the end of the line and splits: the
  tail falls on the line whose compare started the fetch, and the head on
  the next one. One sprite therefore costs the CPU 5 cycles, and sprites 0–3
  together cost 11. A write cycle still completes under BA.
  - Pinned by `spritesteal`, whose `sprite_steal_table` (`core.asm:759`)
    lists the stolen cycles for each sprite alone and all eight together,
    one cycle at a time, on the line that starts the DMA.
  - The `spriteenable` raster markers land on their printed `x`/`y` columns
    only with these windows *and* the bad-line stall in *VIC bad line and
    DMA*: on their line 51, a bad line meets the head of the sprite 3
    window, and the CPU gets 9 cycles between the two.
  - Spec guard: *sprite DMA cycle stealing (#ba_low?)* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- A DMA started on the *second* compare leaves sprite 0 a column short of
  AEC, because sprite 0 alone has its accesses immediately after the
  compares. The first of its three s-accesses therefore reads back the $ff
  the CPU is still driving.
  - Pinned by `spriteenable2`.
  - Spec guard: *the first s-access of a new DMA* in
    [`vic/sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb).
- Rows come from MCBASE/MC, not from a line counter (Bauer §3.8). MC
  steps once per s-access, so it stands three past MCBASE after a row's
  fetch. At Bauer cycle 16 (**VIC column 14**) MCBASE takes MC while the
  expansion flip-flop is set, and MC reloads from MCBASE at cycle 58. The
  end-of-sprite compare runs a column later, at column 15, where the BA
  columns are rebuilt. The sprite ends only when MCBASE lands on
  **exactly** 63, so a crunched sprite steps over it and runs on through
  the rest of its block.
  - Pinned by `spritecrunch2-09`, whose $d017 clears land in the CPU cycle
    after column 14. The reference repeats one row for 48 lines, so MCBASE
    has already moved when the flip-flop is set. Moving MCBASE with the
    compare at column 15 fails it (804 px).
- The expansion flip-flop is set by the Y match that starts the DMA, and
  set **at once** by a $d017 write that clears MxYE, not at a column hook
  (VICE `d017_store`). At Bauer cycle 56 (**VIC column 54, after the second
  Y compare**) it inverts for each sprite with DMA running and MxYE set.
  - Pinned by `spritecrunch2-25`–`29`. Their $d017 sets land from the CPU
    cycle after column 48 to the one after column 55, one column later
    every 8 lines, so they straddle the inversion. Inverting at column 53
    fails all five (228–472 px), and inverting ahead of the compare breaks
    `spritedma/d017-54` and `d017-57` as well.
- **Sprite crunch**: a $d017 write that clears MxYE in Bauer cycle 15 (the
  CPU cycle after VIC column 13) while the flip-flop is reset steps MC to
  `(0x2a & (MCBASE & MC)) | (0x15 & (MCBASE | MC))`, which column 14 then
  hands to MCBASE. From MCBASE $00 that is $01, from $01 or $04–$06 it is
  $05, from $03 it is $07, as the `spritecrunch` readme's table has it.
  - Pinned by `spritecrunch-3b/3c/3d-00` (the same program, whose clear
    lands in that cycle once), `spritecrunch2-08` and `sequencer-bug`. There
    the crunch on line 52 steps MCBASE from $03 to $07, off the multiples of
    three, so the expanded sprites wrap through their block and run for 84
    lines instead of 42. Without the formula, or with the window a column either side,
    all five fail (`sequencer-bug` 8064 px, 384 px a column early).
  - `spritedma/d017-54` and `d017-57` pass with and without it.
  - Spec guard: *sprite crunch* in
    [`vic/sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb), one example
    per row of the readme's table.
- Sprite pixels come from a per-pixel sequencer, not from a decoded row. A
  live X comparator fires one pixel before the sprite's first pixel, the
  expansion flip-flop gates the shift, and in multicolor a two-bit latch
  reloads on every second shift. Both flip-flops idle while their register
  bit is clear, so the first pixel after a mid-sprite $d01c/$d01d change
  repeats the last latched value, and the pairs restart on the pixel after
  that.
  - Pinned by all 17 `spritesplit` tests, and `ss-xpos` for the comparator
    in particular.
- X coordinates ≥ $1f8 never match the VIC's 504-step X counter, so those
  sprites stay dark. The `spritegap` dumps show this boundary.
  - Spec guard: *X comparator* in
    [`vic/sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb).
- Each sprite's s-accesses **reload its shift register** at raster pixel
  K = 459 + 16*m (mod 504). That is late in the line for sprites 0–2 and
  early in the next one for 3–7.
  - A sprite still shifting at K loses the rest of its row. Its output
    holds its last pixel from K through **K+6**, then goes dark.
  - A comparator hit in K..K+11 shows nothing. Where K falls in the
    last 11 pixels of the line, as sprite 3's does on a 65-cycle line,
    the twelve run on into the next line's first pixels.
  - A hit from K+12 on shows the row the reload brought. For sprites 0–2
    that is the *next* line's row, a line early. For sprites 3–7 it is the
    current row, and a hit ahead of their K shows the previous line's row.
  - The row can be shown once on each side of K, so a sprite moved past
    the beam fires a second time on the same line.
  - Pixels that run past the end of the line are drawn at the start of the
    next one.
  - Pinned by `split-tests/spritescan`, a byte-exact dump over all eight
    sprites, 512 X positions and four patterns. `spritex/testsuite`
    (entries 14–16: 469/470 dead, 471 = K+12 fires again),
    `spritex/demusinterruptus` and `spritegap2` pass on it too.
  - Spec guard: *the reload* in
    [`vic/sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb).
  - The run into the next line is pinned by `spritescan_drean`'s 6572
    dump, where sprite 3 shows nothing for X = $193 to $19e, the twelve
    pixels from K = 515 on a 520-pixel line. Without it a hit at $198 to
    $19e collides. Spec guard: *the reload near the end of a 65-cycle
    line*. The `testbench-ntsc` sprite rows pass either way.
  - The hold's length is pinned by `spritefetchbug/test-136-2a`, whose
    X-expanded sprite 0 sits at X = $136 and is still shifting at 459. Its
    reference holds the last pixel through 465. Holding it for one pixel
    fails the test by 134 px. `spritescan` passes either way, because it
    records only whether a collision happened at each X position.
- A multicolor pair that the latch loads on **K−1**, the last pixel before
  the reload, keeps only its high bit, as a hi-res pixel does: %11 shows the
  sprite's own color and %01 is transparent. The hold then repeats that
  pixel.
  - Pinned by `spritefetchbug/test-136-2a`. Its X-expanded multicolor
    sprite at $136 loads its last pair on pixel 458. Without the rule the
    test fails by 168 px. The readme lists 136, 13a, 13e, 142, 146 and 14e
    as the positions where the bug stops being multicolor. Those are the X
    positions ≡ 2 mod 4, where an X-expanded sprite's pair loads land on
    458.
  - Spec guard: *a multicolor pair loaded on the pixel before the reload*
    in [`vic/sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb).
- Sprites 3–7 run their s-accesses at the start of the line, so on the line
  whose compare starts their DMA, those accesses ran with the DMA still
  off. The shift register loads what the VIC saw anyway. The first and third
  bytes come from the VIC's internal bus in phi2, which reads $ff unless
  the CPU reads or writes a VIC register in that cycle, in which case it
  holds that byte. The middle byte is the idle phi1 fetch at $3fff. A hit
  after the display turns on at cycle 58 (raster pixel 460 on, X ≥ $164)
  shows this row on the same line.
  - Pinned by `sbsprf24-164`. Its sprite 6 at $164 shows `BYTE_S0`, the
    ghost byte and `BYTE_S2` on line $7a, which the program puts on the bus
    with the dummy read and the write of `sta $d000,y` in Bauer cycles 7
    and 8. Without the rule the test goes back from 42 to 51 px. With $ff
    in place of the bus bytes it is 49 px, and with $ff in place of the
    ghost byte, 46. `sbsprf24-163`, one pixel to the left, shows nothing
    on that line.
  - `Sprite::InternalBus` samples $3fff as the line starts rather than in
    the sprite's own cycle, which `sbsprf24` can't tell apart.
  - Spec guard: *the s-accesses before the DMA starts* in
    [`vic/sprites_spec.rb`](../spec/badline/vic/sprites_spec.rb).
- On the line that shows its last row, where MCBASE reached 63 and the DMA
  ended at cycle 16, the sprite loses its display at cycle 58: no hit from
  raster pixel **460** on starts it, though one already shifting runs on,
  and it shows no row on the line after. VICE x64sc does the same, pending
  bits cleared at xpos $164.
  - Pinned by `spritegap3`'s collision log, where every pair stops at X =
    $164 whatever the lower sprite.
- MCBASE reaching 63 at cycle 16 stops only the **DMA**. The display turns
  off at cycle 58, and only if the DMA is still off. A Y match at the
  cycle 55/56 compare on the last row's line restarts the DMA under a
  display that is still on, so the new run shows even though Y no longer
  matches at cycle 58.
  - Pinned by `spriterestart`.
  - Spec guard: *when Y matches only at the compare on the last row's line*
    in [`vic/sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb).
- The DMA end also drops the sprite's BA tail on that line, because the
  BA columns are rebuilt at cycle 16. Pinned by `CPU/sha*`, `shs*` and
  `shxy*`, variants 4 and 5.
  - Spec guard: *sprite BA on the line its DMA ends* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- The Y comparator is **eight bits** wide, so a coordinate of 0–55 matches a
  second time on PAL lines 256–311 and starts a second DMA run there.
  - Pinned by `spritey`, whose reference collides on every one of the 312
    lines.
  - Spec guard: *the eight-bit Y compare* in
    [`vic/sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb).

## VIC sprite collisions

- $d01e/$d01f latch **as the beam crosses each sprite pixel**, not at the
  end of the line. A read reports the pixels drawn before its own cycle and
  nothing after them. The VIC runs ahead of the CPU inside a machine cycle,
  so the column the read lands on has not latched yet.
  - Pinned by `sprite-sprite-collision-cycle` and
    `sprite-gfx-collision-cycle`, which step the sprite one pixel per
    subtest across that boundary.
- The reset a read asserts outlives the read by **12 pixels**. Pixels drawn
  under it never reach the register, so two reads four cycles apart report
  a 20-pixel window instead of the 32 pixels between them. The two
  registers reset independently.
  - Pinned by `spritevssprite`'s 20-column bands, which place the boundary
    to the pixel.
- The comparator runs wherever the sprites do, including the vertical
  blank, where there is no line to paint them over.
  - Pinned by `spritey`. Its sprites carry a single lit pixel on their first
    row, so they only collide on the line after the Y match: line 1 for a
    coordinate of 0.
- The $D019 collision bits rise on the **cycle that draws the colliding
  pixel**, on the edge out of an empty register, whether or not $D01A
  enables them. The fold keeps up with the beam while an enabled collision
  IRQ is unlatched, and a $D019 read folds first, so neither waits for the
  end of the line.
  - Pinned by `irq-ack-vicii`'s sprite-sprite half. Its `STA $D019` row
    acknowledges the flag before the CPU takes the IRQ (`-`) at exactly the
    fourth of six delays. Folding a cycle early moves the `-` to the third,
    folding a cycle late moves it to the fifth, and folding only at the end
    of the line loses it. The read fold matters only with the IRQ disabled,
    which no testprog covers; it follows VICE, which sets the bit
    regardless of $D01A.
  - Spec guard: *when the beam crosses the colliding pixel* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- Spec guard: *#collide_upto* in
  [`vic/sprites_spec.rb`](../spec/badline/vic/sprites_spec.rb). Its first
  four examples each fail on a one-pixel change.
- $D01E and $D01F are read-only. A write, including the write-back of a
  read-modify-write such as `LSR $D01E`, changes neither register.
  - Pinned by `general/fuxxortest/ef2-inst4a`, which shifts each frame's
    collision out of $D01E with `LSR`. Storing the shifted value back
    leaves bit 0 set for the next frame, which reads as a collision one
    pixel to the right of every real one.
  - Spec guard: *with a collision register* in
    [`vic/registers_spec.rb`](../spec/badline/vic/registers_spec.rb).

## VIC border and idle state

- The vertical border compares run in every cycle of a line, as VICE x64sc
  runs them. The top compare (line 51 with RSEL set, 55 with it clear, and
  DEN set) resets the flip-flop at once. The bottom compare (251 or 247)
  only arms it, and the armed state takes hold at the line's first cycle
  and at the left window edge (Bauer §3.9 rules 2–5). Between writes
  nothing changes, so the VIC compares at each line's first cycle and after
  each `$d011` write.
  - The line's first cycle is the previous line's column 62 (Bauer cycle 1,
    the column the bad line compare also gives to the next line), and it
    compares the line about to start. A `$d011` write after column 61 is
    compared there, against the next line. A write after column 62 has
    missed it.
    - Pinned by `denrsel-s0`/`-s1`: s1 clears RSEL and DEN one cycle later
      than s0, just after line 51's first-cycle compare, so the border
      opens. Pinned with them by `denrsel-1`/`-2`/`-s2`, `den10-51-1` (all
      64000–87040 px → pass), `vborder-33-08`/`-09`, `vborder2-22` and
      `vborder2-64`, which fail again when column 62 compares the line
      ending. `border-bm-idle` (8057 → 9 px) goes back too.
  - A write is compared in the next column, so RSEL touching a bottom
    compare line mid-line closes the border from the next line.
    - Pinned by `vborder2-63` and `vborder-32-08`/`-09`, which fail when
      only the line start and the left edge compare, and `vborder-33-08`
      and `vborder2-36`, which move further.
  - The 40-column left compare runs in column 15 (Bauer 17), a column
    before the column that draws its pixel, so a `$d011` write after
    column 15 misses it. The 38-column one (Bauer 18) runs in column 16.
    - Pinned by `vborder2-36` (320 px → pass), which fails alone when the
      compare sees `$d011` as of column 16. `vborder2-35` is the other side
      of the pair.
  - Spec guard: *vertical border flip-flop* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb), one context per rule,
    each failing under its knock-out, and *vertical border flip-flop* in
    [`vic/sequencer_spec.rb`](../spec/badline/vic/sequencer_spec.rb) for
    the armed bottom compare and the 40-column left compare.
- The side border compares see CSEL a pixel late, as the colour registers
  do. The 40-column compares fall on the first pixel of their group (raster
  x 128 on the left, 448 on the right), and that pixel still sees CSEL as
  the column before had it. The 38-column compares fall on a group's last
  pixel (135 and 439), so they see a write made in the CPU cycle before
  the group. A CSEL clear in the CPU cycle after column 55 therefore misses
  the 38-column compare and still meets the 40-column one: the border
  closes.
  - Pinned by `vicii_reg_timing` (71 px → pass, and 78 → 7 px for `-a5`
    and `-ff`), whose line 232 clears CSEL there and shows a closed right
    border. Lagging the 38-column compares as well breaks `border-bm-ysh`,
    `border-bm-ysh2`, `border-mcbm` and `hvborder1` (71–73 px each), which
    clear CSEL in the cycle after column 53 and close at 439.
  - Spec guard: *closes the right border when CSEL clears in the compare's
    column* and *closes the right border at the 38-column compare in the
    column CSEL clears* in
    [`vic/sequencer_spec.rb`](../spec/badline/vic/sequencer_spec.rb).
- The border colour shows where the **main** flip-flop is set, and only
  there. The vertical flip-flop keeps the main one from clearing at the
  left compare and withholds the graphics data, but it does not paint
  border itself. So with the side border held open, the lines inside the
  vertical border show zero data in the latched colours (VICE x64sc
  `draw_border8`).
  - Pinned by `hvborder2`, `border-bm-ysh`, `border-bm-ysh2` and
    `border-mcbm`, which go back to 8134, 5575, 4598 and 5595 px when
    either flip-flop paints border (knock-outs measured before the sprite
    shifter landed; all four pass since the
    [graphics pipeline](#vic-graphics-pipeline) rules).
  - Spec guard: *shows the vertical border only through the main
    flip-flop* in
    [`vic/sequencer_spec.rb`](../spec/badline/vic/sequencer_spec.rb).
- An idle-state g-access reads $3fff, or $39ff with ECM set, and the byte
  is painted through the current mode with a zero screen byte and colour
  nibble (foreground black, background per mode). A guard keeps
  closed-border lines on the bulk path.
  - Pinned by `ss-pri*`, whose diffs collapsed from ~85k px to 220–440 px.
  - Spec guard: *renders the idle byte at $3fff in black* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- A column with no g-access (outside columns 14–53), or one whose
  g-access falls while the vertical border stays closed for the rest of
  the line, shifts out **zero data**. It is painted through the current
  mode with the screen byte and colour nibble the last g-access latched:
  a display-state one latches its buffer cell, an idle one latches 0/0,
  and the value carries across lines. So a zero pixel is $d021 in the text
  and multicolour bitmap modes, the kept screen byte's low nibble in
  standard bitmap, the ECM background it selects, and black in the
  invalid modes (VICE x64sc `draw_graphics8`).
  - Pinned by `sbsprf24-163`/`-164` (401/428 → 34/51 px),
    `spritefetchbug` (302 → 174), `hvborder1` (191 → 43) and
    `vicii_reg_timing` (8865 → 1773), which decoded memory at VC there
    before. The kept colours are pinned by
    `border-bm-ysh`/`-ysh2`, which go back to 5580/4741 px with 0/0
    instead.
  - The top compare line counts as open for the whole line, because the
    vertical flip-flop only clears at the left compare, two columns after
    the first g-accesses are sampled. Without that, every picture loses
    the start of its first line (`greydot`, `dmadelay`, `dentest`).
  - Spec guard: *a column with no g-access* in
    [`vic/sequencer_spec.rb`](../spec/badline/vic/sequencer_spec.rb).
- The XSCROLL bleed at column 0 takes its pixels from the group before
  it, the zero-data group, rather than filling with $d021. Only
  `border-bm-ysh2` separates the two (+6 px).

## VIC bad line and DMA

- The display state counts columns two ahead of Bauer's cycles: column
  `c` is his cycle `c + 2`. This is the frame the CPU sees, where the
  bad-line stall `bascan` pins starts in the CPU cycle after column 10
  (Bauer 12). It is also VICE x64sc's order, where the VIC's logic for a
  cycle runs before the CPU's bus access in it. A `$d011` write in Bauer
  cycle `n` runs after column `n − 2` and is first compared in column
  `n − 1`, which is Bauer `n + 1`.
- The bad line condition is compared in **every** column. The last column
  of a line (Bauer cycle 1 of the next) compares against the line about to
  start.
- A match enters display state **in its own column**, not when AEC falls.
  - Pinned by 12 of the `dmadelay` rows, `screenpos`, `fldscroll-20-60`
    and `colorfetchbug/bitmap`, which all fail when display state waits
    for AEC.
- The first match in columns 10–52 (Bauer 12–54) pulls BA low, and the VIC
  owns the bus three columns later. The c-accesses run in columns 13–52
  (Bauer 15–54) for as long as the condition stands, so a condition
  withdrawn mid-line stops them. The ones before AEC read `$ff` off a bus
  the CPU still drives.
  - Pinned by `flibug/blackmail*`. Their `$d011` writes land in column 12
    (Bauer 14), so the match comes in column 13 and three cells read
    `$ff`, as in the reference.
- The g-accesses run in columns 14–53 (Bauer 16–55), in the first half
  of the column, ahead of that column's compare. Their pixels leave the
  sequencer two columns later (`VIC::GRAPHICS_DELAY`), so cell 0 still
  draws at column 16.
  - Pinned by `dmadelay` `test*-18`/`-1a`, `screenpos` and
    `colorfetchbug/bitmap`, which fail when the compare runs first.
- VC and VMLI reload in column 12 (Bauer 14). The row counter resets there
  **only** if the condition stands in that column, so a row opened later
  keeps the row counter it had. It steps in column 56 (Bauer 58). This
  replaces the curve-fitted 11–15 reset window, and matches Bauer and
  VICE.
  - Pinned by `colorfetchbug` (its bad lines start at Bauer 17), the
    `dmadelay` `test*-17`/`-18`/`-19`/`-1a` rows, `flibug/blackmail*` and
    `screenpos`, which all fail when a later match resets the counter.
- The CPU halts on the bad line condition **as it stands**, not on the
  latched match. `ba_low?` holds it for the columns BA covers, 10–52, which
  it sees as `@column` 11–53 because it is asked after the VIC advances.
  That is 43 cycles, the gap Bauer leaves between bad-line BA (cycle 12)
  and sprite 0's BA (cycle 55). A condition that goes away mid-line
  releases the CPU.
  - Pinned by `split-tests/bascan`, a per-cycle dump of when the stall
    first catches a CIA timer read. Its `$d012` reads are the same dump's
    check that the raster sync itself did not move.
  - The end is pinned too. Re-measured in this frame, a 45-cycle stall
    (CPU halted through the cycle after column 54) breaks `bascan`
    itself, all five `colorfetchbug` rows, `flibug/blackmail*`,
    `spriteenable3`–`5` and several `vborder*` rows.
  - Spec guard: *#ba_low?* in [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- The DEN latch is level-sensitive across the raster counter's increment,
  so its window runs from the last column of line 47 through the last
  column of line 48. The wrap column counts for both the line ending and
  the line starting. Derived against `dentest`'s `den01-48-*`, `den01-49-*`
  and `den10-48-*`, which bracket both edges one cycle at a time.
- A condition still standing at column 56 puts the logic straight back
  into display state after the counter wraps (Bauer 3.7.2 step 5), so RC
  rolls 7 → 0 instead of leaving the line idle. This is what holds an FLI
  picture together.
- VC and VMLI advance per g-access in display state, and VCBASE takes VC at
  the wrap. A row that opens late therefore carries its shortfall into the
  next one instead of a fixed +40.
- All 21 `dmadelay` rows pass under these rules, and they sweep the match
  across the whole line. `D011Test/disable-bad` pins the too-late match.
- Spec guard: [`vic/display_state_spec.rb`](../spec/badline/vic/display_state_spec.rb),
  one group per rule.
- The colour nibble of a c-access before AEC is the low nibble of the byte
  at the CPU's PC, which is the opcode it is halted on, as VICE reads it.
  `Computer` hands the VIC a lambda for it (`VIC#open_bus=`), called only
  on those accesses. A bare VIC reads colour RAM instead.
  - Pinned by `flibug/blackmail*` and `colorfetchbug/main*`, whose bug
    cells take their colour from the halted opcode.
  - Spec guard: *an FLI match in column 13* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- On the 6569, a match that opens display state in a g-access column, which
  is a DMA delay out of idle state, moves that column's idle g-access from
  `$3fff` (or `$39ff`) to `$38ff`, but only when YSCROLL is nonzero, so
  only when the trigger line's low three bits are nonzero. The address wins over
  ECM's `$39ff`. Nothing else enters the condition: not the column, BMM,
  RC, VC or the previous fetch. The column is the one just before the
  first display-state g-access. This rule is empirical and fitted to the
  two tests below. It is the same condition the Denise emulator converged
  on, and no hardware explanation for the YSCROLL gate is known. The
  readme lists `$38ff` for every 6569 it measured. Among 8565s it lists
  `$3807`, `$38c7`, `$38d7` and `$38ff`, varying from chip to chip, and no
  testbench row pins one, so the 8565 keeps `$3fff` there.
  `VIC::DMA_DELAY_IDLE_ADDRESS` holds the 6569's address.
  - Pinned by `vsp-tester`, which triggers on raster `$32` with YSCROLL 2
    and reads the address back through sprite collisions. It passes on
    `$38ff`, `$3807`, `$38c7` or `$38d7`, and reports `$3fff` (exit `$ff`)
    without this rule.
  - Pinned by `colorfetchbug/main`, whose only idle trigger is on raster
    `$30` with YSCROLL 0 and whose reference shows `$3fff` there. Without
    the YSCROLL gate it fails by 7 px. `sequencer-bug` (YSCROLL 3) reads
    `$38ff` and passes either way.
  - Spec guard: *reads the idle byte at $38ff when YSCROLL is nonzero* and
    *reads the idle byte at $3fff when YSCROLL is 0*, plus the 8565's
    *reads the idle byte at $3fff when YSCROLL is nonzero*, in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- These rows can't be read as pixel counts. The sweep became readable by
  OCRing each reference PNG against `lib/badline/roms/character.rom` and
  matching every display row back to its offset in screen memory, so a diff
  reads as "row 0 starts 40 cells in" instead of "11,376 px". Rebuild that
  as a scratch script before touching these tests again.

## VIC graphics pipeline

The column frame is the one in [VIC bad line and DMA](#vic-bad-line-and-dma).
A register write in the CPU cycle after column `c - 1` is seen by column
`c`, and a g-access in column `c` draws in column `c + 2`. The rules follow
VICE x64sc's `vicii_fetch_graphics` and `draw_graphics8` for the 6569.

- The g-access reads its byte **in its own column**, through the mode,
  `$d018` and VIC bank of that cycle, not when the sequencer draws it two
  columns later. `VIC#fetch_graphics` reads it, and `GraphicsMode` only
  paints.
  - Pinned by `gfxfetch` (224 px → pass), which flips the character data
    between the g-access and the draw, and `fetchsplit` (2939 → 2890 px
    without it), which splits `$d018` and `$dd00` mid-line.
  - Spec guard: *reads the byte in its own column* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- The g-access still sees BMM for one column after it falls: it addresses
  with `$d011` OR-ed with the BMM bit of the column before
  (`VIC::FETCH_HOLD`). When BMM changes and the access moves from RAM onto
  the character ROM, the low address byte comes from the old mode and the
  rest from the new one.
  - The hold is pinned by `vicii_reg_timing` (pass → 56 px without it, and
    7 → 63 px for `-a5` and `-ff`). The address mix is pinned by
    `modesplit` (48 → 202 px) and `videomode-v`, `-x` and `-y` (5/10/1 →
    13/14/9 px).
  - Spec guard: *addresses with a BMM that fell in the same column* and
    *mixes the addresses when BMM falls onto the character ROM* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- ECM is held for that column too, but only when the access it leaves,
  addressed through the old mode, read the character ROM
  (`VIC::FETCH_HOLD_ROM`). A falling ECM reaches a RAM access at once.
  - Pinned by `modesplit` (348 → 48 px). Its section 2 drops ECM in text
    mode with the characters in the ROM, and its section 1 goes from
    ECM text on the ROM to bitmap in RAM. Both need the mask held.
    `videomode-v` makes the second move too (6 → 5 px).
  - The RAM side is pinned by `vicii_reg_timing`, whose ECM row drops ECM
    in text mode with the characters in RAM: holding ECM there as well
    takes it from pass to 32 px (7 → 39 px for `-a5` and `-ff`), and
    `videomode-z`, a `$7b` → `$3b` fall in RAM, from pass to 3 px.
    `videomode-x` makes the same fall in RAM and would prefer the hold
    (10 → 2 px), but its readme says its reference doesn't match every 6569
    capture. VICE holds BMM only.
  - Spec guard: *drops a falling ECM at once when the access left RAM* and
    *holds a falling ECM when the access left the character ROM* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- The byte a group draws loads into the shift register at pixel XSCROLL,
  and that XSCROLL is the one the **column before** saw. It is latched in
  each g-access column with the vertical border open (VICE
  `xscroll_pipe`), so a `$d016` write shows a column later than a colour
  or mode write in the same cycle.
  - Pinned by `sbsprf24-163`/`-164` (34/42 px → pass, 40/44 without it),
    `modesplit` (48 → 144) and `vicii_reg_timing` (pass → 720), and by
    `border-bm-idle`, `border-bm-ysh` and `border-mcbm`.
  - Spec guard: *loads the byte at the XSCROLL the column before saw* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- A mode change takes hold **inside** the group. ECM and BMM rising show
  at pixel 4 and falling at pixel 6, so a change that clears one bit while
  it sets the other shows the invalid mode's black on pixels 4 and 5. MCM
  changes the colour lookup at pixel 4 but how the shift register is read
  only at pixel 7, where a rising MCM also resets the multicolour
  flip-flop. The mode applies to the pixels as they leave the shift
  register, so the boundaries stay put whatever XSCROLL is.
  - `VIC::GraphicsShifter` runs these groups pixel by pixel: a group where
    the mode or the load point changes, and the group after it. Every other
    group paints whole bytes, which comes to the same pixels.
  - Pinned by `modesplit` (48 → 1222 px painting whole groups, 428 with
    MCM read at pixel 4), the `videomode` rows and `vicii_reg_timing`
    (pass → 274).
  - A falling BMM shows at pixel 5 instead of 6 unless it leaves hi-res
    bitmap: out of multicolour bitmap, and out of the invalid ECM+BMM
    modes, whether ECM falls with it or stays.
    - Pinned by `modesplit` (48 px → pass), whose first section drops BMM
      out of ECM+BMM, by the E+B row of `vicii_reg_timing-a5` and `-ff`
      (7 px each → pass), which drops ECM and BMM together, and by
      `videomode-y` (1 px → pass), which drops it out of multicolour
      bitmap. The hi-res exception is pinned by `videomode2` and the BMM
      row of `vicii_reg_timing` (pass → 1 and 7 px without it).
    - Two references disagree, and both are marked unsafe in the
      testlist: `videomode-v` drops BMM out of multicolour bitmap and
      `videomode-w` out of ECM+BMM, and both want pixel 6 (+1 px each).
      The readme says these delays vary with the chip and its
      temperature.
    - Spec guard: *takes a BMM falling out of hi-res bitmap at pixel 6*,
      *out of ECM+BMM at pixel 5* and *out of multicolour bitmap at
      pixel 5* in
      [`vic/graphics_shifter_spec.rb`](../spec/badline/vic/graphics_shifter_spec.rb).
  - An MCM that falls out of the invalid ECM+MCM text mode is a pixel
    later on both counts. The lookup stays black through pixel 4 and
    changes at pixel 5, and the pairs are read through pixel 7, with
    hi-res reads starting at the next group's pixel 0.
    - Pinned by `videomode1` and `videomode-z` (2 px each → pass), whose
      illegal → ECM text split drops MCM. With the fall at pixels 4 and 7,
      the reference's black pixel 4 and last-pair foreground on pixel 7
      are both lost. Applying the late timing to every falling MCM breaks
      `videomode2`, `vicii_reg_timing`, `modesplit` and `videomode-v`,
      `-w`, `-x` and `-y`.
    - Spec guard: *takes an MCM falling out of ECM+MCM a pixel late* in
      [`vic/graphics_shifter_spec.rb`](../spec/badline/vic/graphics_shifter_spec.rb).
  - Spec guard: [`vic/graphics_shifter_spec.rb`](../spec/badline/vic/graphics_shifter_spec.rb),
    one example per pixel, and *a mode change inside a group* in
    [`vic/sequencer_spec.rb`](../spec/badline/vic/sequencer_spec.rb).
- The pixels XSCROLL keeps from the previous byte take the **current**
  colour registers: a `$d021`–`$d024` write repaints that byte before it
  shows. The `ColorPatches` +1 px still applies on top.
  - Pinned by `modesplit` (48 → 114 px without it) and
    `vicii_reg_timing` (pass → 212). `colorsplit` (64 px → pass) and
    `spritefetchbug/test-136-2a` (8 px → pass) go back only when both this
    and the XSCROLL latch are knocked out.
  - Spec guard: *a background write under XSCROLL* in
    [`vic/sequencer_spec.rb`](../spec/badline/vic/sequencer_spec.rb).

## VIC phi1 bus

- A CPU read of open I/O ($DE00–$DFFF) returns the byte the VIC fetched in
  the phi1 half of the same cycle, and a colour RAM read takes its upper
  nibble from it. `VIC#phi1_data` works the byte out when it is asked for,
  from the VIC's state at that moment. The CPU cycle after column `c` is
  Bauer cycle `c + 2` (the display-state frame in
  [VIC bad line and DMA](#vic-bad-line-and-dma)), which is `@column + 1`
  once the VIC has advanced. Each Bauer cycle has a fixed access, as in
  VICE `cycle_phi1_fetch`:
  - 1–10 and 58–63: two cycles per sprite from sprite 0 at 58, the
    p-access at `screen_base + $3f8 + n` and then the middle s-access,
    `pointer * 64 + MC + 1` with DMA on and `$3fff` with it off.
  - 11–15: refresh at `$3f00 | REF`. REF is `$ff` at line 0 and steps
    down once per refresh access, five per line.
  - 16–55: the g-access of the column just run, read at column time, not
    when the sequencer draws it two columns later. In display state that
    is the address the sequencer uses, with the VC and VMLI the access
    stepped past (`& $39ff` with ECM). In idle state it is `$3fff`, or
    `$39ff` with ECM, whatever the vertical border does.
  - 56–57: `$3fff`, with or without ECM.
  - Pinned by `phi1timing`, which reads $DEAD once per cycle across a
    line in idle state with ECM set. A one-cycle shift of the frame either
    way fails it on 19 of its 63 columns. The refresh counter, display-state
    g-accesses and the DMA s-access follow VICE: `phi1timing` fills
    $3f00–$3ffe with one value and runs with DEN clear and no sprites.
  - Spec guard: *#phi1_data* in [`vic_spec.rb`](../spec/badline/vic_spec.rb).

## VIC light pen

- CIA1 PB4 level changes (`CIA#on_port_b4_change`) drive
  `VIC#lightpen_level`. The first falling edge per frame latches LPX/LPY one
  cycle later (plus the 6569's 2 half-pixel offset) and raises the `$D019`
  bit 3 IRQ.
- Triggers on the last line are consumed without latching (except at cycle
  0). A line held low across frame start retriggers with a fixed LPX of
  `$d1`.
- Calibrated byte-exact against the `split-tests/lightpen` `dump6569`
  reference, as `makeref` corrects it: the test fixes up the tail bytes of
  pre-R03 dumps before comparing. All five pages match, the raster-read
  pages included (see [VIC raster IRQ phase](#vic-raster-irq-phase)).
- The 6569's offset is 2 half-pixels and the 8565's is 1 (see
  [VIC-II 8565](#vic-ii-8565)).
- Pinned by `lplatency`, `lp-trigger`, and the `fldscroll` tests, which sync
  through the light pen instead of the double IRQ.

## VIC-II 8565

The 8565 (`VIC.new(model: :mos8565)`, `Computer.new(vic_model:
:mos8565)`), fitted to the C64C, runs every rule above except the ones
below. They follow VICE x64sc's model checks (`color_latency` clear), and
each is gated on the model and was knocked out: removing it fails the rows
named, all in `testbench-vicii-new`, and moves no 6569 row. Pixel counts
are the row's diff with the rule removed.

- **Grey dots.** Where the 6569 still shows a colour register's old value
  on the first pixel after a write, the 8565 shows light grey
  (`VIC::GREY_DOT`, `$f`), for the border, the background registers
  (`VIC::ColorPatches`) and the sprite colours (`VIC#log_sprite_change`).
  A write that leaves the value as it was shows its dot too.
  - The background and border dot is pinned by `rmwtest` (1655 px), every
    spritesplit row whose `$d021` staircase it crosses (60 px each) and
    `vicii_reg_timing` (275 px, 282/289 for `-a5`/`-ff`). The sprite dot
    by `ss-hires-color` and `ss-mc-color0`/`1`/`2` (44 px each) and
    `vicii_reg_timing` (136 px). The same-value dot by `rmwtest` (775 px)
    and `vicii_reg_timing` (22 px), whose read-modify-write instructions
    store each value twice.
  - Spec guard: the *on the 8565* group in
    [`color_patches_spec.rb`](../spec/badline/vic/color_patches_spec.rb),
    *shows a grey dot on the pixel before a new sprite color* in
    [`sprites_spec.rb`](../spec/badline/vic/sprites_spec.rb) and *shows a
    grey dot for a background write of the same color* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- **Sprite multicolour.** `$d01c` reaches the sprite sequencers a pixel
  sooner, 6 pixels on instead of 7, and works on the multicolour
  flip-flop (VICE `update_sprite_mc_bits_8565`). The X match leaves the
  flip-flop set in hi-res as well as clear after the first multicolour
  pixel. A change flips it only when it lands between the two halves of
  an expanded pixel, where a switch to hi-res sets it instead. A hi-res
  pixel with the flip-flop clear sets it and loads nothing, so the latch
  holds its last pixel.
  - The delay is pinned by `ss-hires-mc`, `ss-mc-hires` and their `-exp`
    twins (528/88/1452/88 px at 7). The flip-flop after the X match by
    `ss-hires-mc`, `ss-pri`, `ss-unexp-exp-hires` (168 px each) and
    `ss-hires-mc-exp`, `ss-pri-exp`, `ss-exp-unexp-hires` (336 px each).
    The flip on a change by `ss-hires-mc-exp` (1364 px) and
    `ss-mc-hires-exp` (44 px), and the hi-res hold by `ss-mc-hires` and
    `ss-mc-hires-exp` (44 px each).
  - Spec guard: *reaches the multicolor flip-flop six pixels on* in
    [`sprites_spec.rb`](../spec/badline/vic/sprites_spec.rb) and the *with
    an 8565* group of *mid-line writes* in
    [`sprite_spec.rb`](../spec/badline/vic/sprite_spec.rb).
- **The g-access addresses with the `$d011` of the column before**,
  whole, instead of the 6569's hold of BMM and, on the character ROM, ECM.
  - Pinned by `modesplit` (598 px), `vicii_reg_timing` (92, 99/106 px),
    `fetchsplit` (180 px) and every videomode row but `videomode1` (3 to
    16 px).
  - Spec guard: *addresses with the $d011 of the column before* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- **ECM and BMM take hold at the next group's pixel 0**, rising or
  falling, where the 6569 takes them at pixel 4 as they rise and 5 or 6 as
  they fall. MCM keeps the 6569's timing, but an MCM that falls out of
  ECM+MCM does so on time instead of a pixel late.
  - The pixel 0 is pinned by `modesplit` (916 px), `vicii_reg_timing` (86,
    100/114 px) and every videomode row (6 to 13 px). The on-time MCM by
    `videomode1` and `videomode-z` (2 px each).
  - Spec guard: the *on the 8565* group in
    [`graphics_shifter_spec.rb`](../spec/badline/vic/graphics_shifter_spec.rb).
- **Out of an invalid mode into multicolour bitmap, a background pixel 0
  is still black, and into hi-res text any pixel 0 is.** Into multicolour
  text and ECM text it shows on time.
  - The multicolour bitmap case is pinned by `videomode-v` and `videomode2`
    (1 px each) and `modesplit` (92 → 124 px), whose `%00` and `%01` pairs
    after an ECM+MCM or ECM+BMM+MCM split keep their first pixel black.
    `videomode-y` shows a `%01` pair on time into multicolour text.
  - The hi-res text case is empirical, pinned by the E+B row of
    `vicii_reg_timing-a5` and `-ff` (pass and 7 px, 7 and 14 px without
    it), which drops ECM+BMM back to text. All three `vicii_reg_timing`
    references keep that pixel 0 black, a foreground pixel in `-a5` and
    `-ff`. `$d021` is black there, so no reference tells a background
    pixel 0 apart, and the rule blackens both.
  - `videomode-w` shows ECM+BMM into ECM text on time (1 px if it goes
    black), while `modesplit`'s section 1 keeps the same move black (48 of
    its 92 px). The two references disagree about the same move, and the
    videomode one is kept.
  - Spec guard: *keeps a background pixel 0 black out of an invalid mode
    into multicolour bitmap*, *keeps pixel 0 black out of an invalid mode
    into hi-res text*, *shows pixel 0 on time out of an invalid mode into
    multicolour text* and *shows pixel 0 on time out of an invalid mode into
    ECM text* in
    [`graphics_shifter_spec.rb`](../spec/badline/vic/graphics_shifter_spec.rb).
- **The light pen latches one extra half-pixel**, where the 6569 adds two.
  - Pinned by `lp-trigger/test2new`, which measures the trigger delay and
    fails with two.
  - Spec guard: *adds one extra half-pixel on the 8565* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- **A `$dd00` write that swaps the bank lines shows bank 3 for a cycle.**
  Where one bank line goes high as the other goes low, every VIC access in
  the cycle after the write reads bank 3 (both lines low), and the new bank
  from the cycle after that (`VIC::Bank#sample_lines`). A swap the DDR
  makes, releasing a line to float high, shows nothing, and neither does a
  write that moves one line or both the same way.
  - Pinned by `fetchsplit` (154 → 16 px): every 8565 capture its readme
    lists shows `3` in the first character after each `$dd00` swap, while
    the 6569 reference shows none. `M1` also shows it after the DDR swaps;
    `M7`, which the `-8565` reference is made from, doesn't.
  - Spec guard: the `#sample_lines` group in
    [`bank_spec.rb`](../spec/badline/vic/bank_spec.rb).

What the 8565 references don't settle, and so what stays as it is:

- The pixel 0 of a group that leaves ECM or BMM is not consistent across
  the references. Moving every falling edge to pixel 1 passes `modesplit`
  but fails every videomode row but `videomode1` and all three
  `vicii_reg_timing` rows, and the same move out of hi-res bitmap into
  text is the new mode in `vicii_reg_timing-a5` and the old one in `-ff`.
  The videomode readme says these delays "may depend on the type of VICII,
  and the temperature of the chip". So `modesplit` (92 px) and
  `vicii_reg_timing-ff` (7 px, the hi-res bitmap into text row) stay FAIL.
  No emulator in the testbench results passes `vicii_reg_timing-a5` or
  `-ff` on the 8565, and only Hoxs64 passes `modesplit`, against the
  `8565early` reference. Listed by transition, the references disagree
  on the same pixel: out of ECM+BMM into ECM text a foreground pixel 0 is
  on time in `videomode-w` and black in `modesplit`; out of ECM into hi-res
  text a background pixel 0 selecting `$d022` shows the new mode in the
  `vicii_reg_timing` ECM row and the old one in `modesplit`; out of hi-res
  bitmap into text a foreground pixel 0 is new in `-a5` and old in `-ff`,
  with the same screen, colour and pixel values. Each test's position is
  independent of where it starts: booting 0 to 20000 cycles longer before
  attaching gives the same diff.
- `fetchsplit` (16 px) stays FAIL on the one swap the DDR makes that the
  `-8565` reference shows as bank 3: the swap in column 34 of the `line1c`
  rows, in the text and ECM blocks but not the bitmap one, while the same
  swap in column 4 of `line1b` shows nothing. The readme says its 8565
  artefacts differ from chip to chip and change as the machine warms up,
  and its `M1` capture shows bank 3 after every DDR swap.
- VICE's idle g-access also reads ECM from the `$d011` of the column
  before on the 8565. No testprog tells it apart, so the 8565 keeps the
  6569's idle access, without the 6569's `$38ff` read where a DMA delay
  starts.

## VIC-IIe 2 MHz and TEST bit

The C128's VIC-IIe (`:mos8566`, `:mos8564`) adds $D030: bit 0 (FAST)
runs the 8502 at 2 MHz, and bit 1 (TEST) clocks the raster counter in
every cycle. `C128#cycle!` and `#clock_fast` drive both, through
`VIC#take_cpu_bus`, `#test_step!` and `#refresh_cycle?`. The oracles are
the testprogs' own references for `c128/2mhzVIC` (3 rows, from the
author's machine) and `c128/d030tester` (33 rows), and the real-machine
photos in `c128/2mhztest`. Those are C128-mode programs that switch to C64
mode as they start, so no testbench list runs them yet: `spec/badline/
c128_2mhz_spec.rb` runs six d030tester builds from their machine code at
$1C0E and checks the readings they print.

- FAST and TEST take hold in the second cycle after the write that sets
  or clears them. Pinned by d030tester's "Lines cut": STA/STX $D030 keeps
  TEST on for 4 cycles, but for 3 when the STA also sets FAST, because
  the STX then runs its operand fetches at 2 MHz. With the delay at 0
  the FAST builds cut 2 lines, not 3. Spec guard: `c128_spec.rb`.
- In FAST mode the CPU runs in both halves of every cycle but Bauer's
  refresh cycles 11-15, whose phi1 stays with the VIC: 121 CPU cycles a
  PAL line. BA doesn't halt it. Pinned by `2mhz-vic-hires`,
  `-multicolor` and `-extended`, whose drawing code assumes 121 cycles a
  line.
- An access to $D000-$DFFF waits for phi2: one in phi1 takes the whole
  cycle. Pinned by `timing-change0`, whose `INC $D020` takes 8 half
  cycles (its comment says "6 cycles + 2"). The machine finds out after
  the CPU's step that it reached I/O, so `CPU::Core` needn't say where
  its next access goes.
- The VIC's accesses in a FAST cycle latch the CPU's bytes: the g-access,
  or idle access, the byte of phi1, and a c-access the byte of phi2, as
  one made before AEC does on the C64: $FF for the video matrix and the
  byte's low nibble for colour. Pinned by `2mhz-vic-*` (the operands are
  the pixels and the opcodes' low nibbles the colours) and by the "VIC
  internal data" row of d030tester, which shows char $FF's glyph in
  slow-mode lines after a FAST bad line.
- A c-access in a cycle where the CPU reads or writes a VIC register
  takes that byte for the video matrix as well. Pinned by d030tester:
  `STX $D030` with X=0 leaves an `@` (McCabe's readme: "the `@`
  represents a 0 written to $D030"), and the `DEC $D030` build (2mhzdec)
  leaves char $FD, the byte it reads.
- In the phi1 an I/O access waits through, the VIC sees the byte the CPU
  writes, or the last byte the bus held for a read. Pinned by d030tester
  and 2mhzdec, whose g-access there shows $00 (X) and $D0 (the operand's
  high byte).
- AEC can't follow BA down in FAST mode, so on a bad line it falls three
  cycles after the last FAST cycle, and the c-accesses before it read
  $FF and the halted CPU's nibble (`DisplayState#keep_bus`). Pinned by
  d030tester's "VIC internal data" row, where three cells after the FAST
  cycles show colour 0 (the halted read's $D0) and the rest the screen.
- The TEST bit steps the raster counter ahead of each cycle it is set
  in, except the line's last cycle, which steps it anyway, and the step
  from the frame's last line to line 0 takes two cycles. Pinned by
  d030tester: TEST across the line end (`32c_02_00`, `32c_03_00`) cuts
  one line fewer, and the frame it keeps 312 lines long with two TEST
  windows of a whole frame each reads 19656 cycles ($4CC8) only with the
  two-cycle wrap. A step into a bad line's raster halts the CPU through
  BA for the one cycle the raster matches: `2ae_02_00` and `2ed_02_00`
  cut 5 lines for 4 cycles. Spec guard: `vic_iie_spec.rb`.
- The beam doesn't follow the raster counter's steps: it draws the next
  display line after the last one (`VIC#output_line`), so the lines TEST
  skips move the picture up, until a line that ends in the vertical sync
  (PAL lines 303-305, three lines from the fourth blanked one) puts the
  beam back on the raster line. A blanked line the beam draws off the
  raster line shows black. Pinned by d030tester's `vadjust` builds, which
  move the picture up a line per cycle of TEST, `vadjust1` included,
  where the first window leaves the raster counter on line 304, and by
  the colour bar that `173_02_00` draws four lines taller.
- Not matched: the d030tester references come from an emulator that
  models PAL decoding. A line cut an odd number of times flips the colour
  phase, so every row below it shows other hues (all 11 builds whose cut
  is odd), and lines drawn while TEST runs show alternating hues and
  per-cycle blanking. Their 8566 shows no grey dots. The 2mhzVIC
  references have none either.

## VIC-II NTSC

The 6567R8 (`Region::NTSC`) and the 6567R56A (`Region::NTSC_OLD`) run
every VIC rule above, on a line of 65 or 64 cycles, except where the
region moves the sprites. The positions live in `Region::Profile` and
`VIC::Sprite::Timing`.

- **Sprite fetches.** Sprite 0's p-access runs in cycle 59 instead of
  58, and everything that hangs off the fetches moves with it: the BA
  windows (`VIC#layout_columns`), the DMA compares (columns 54 and 55
  instead of 53 and 54), the phi1 accesses (`VIC#phi1_address`, where the
  6567R8 idles in cycle 10), the column whose BA a late DMA start misses
  (`Sprite::Timing#ba_column`), the reload pixels
  (`Sprite::Timing#reload_x`) and the idle-bus row of sprites 3-7
  (`Sprite::InternalBus#row`). On the 6567R8 sprite 3's fetch then falls
  in the last two cycles of the line, so it reloads with the next line's
  row as sprites 0-2 do. The expansion flip-flop still toggles in column
  54.
  - Pinned by `spritesteal_ntsc` and `_ntscold`, `spritex/testsuite_ntsc`
    and `_ntscold`, `phi1timing_ntsc` and `_ntscold`, and
    `spriteenable1_ntsc` and `2_ntsc` and their `_ntscold` twins (235 and
    458 px), all in `testbench-ntsc`: with sprite 0 back in cycle 58 each
    of them fails, and every other row of the sprite, phi1, dmadelay, vsp
    and screenpos subsets passes as before.
  - Spec guard: *sprite DMA cycle stealing on NTSC* and *#phi1_data on
    NTSC* in [`vic_spec.rb`](../spec/badline/vic_spec.rb), and
    [`timing_spec.rb`](../spec/badline/vic/sprite/timing_spec.rb).
- **Display compare.** The 6567R8 turns a sprite's display on and off in
  cycle 59 (`sprite_display_cycle`), where the 6567R56A keeps the 6569's
  cycle 58. This isn't pinned yet: moving the 6567R8's to 58 or the
  6567R56A's to 59 fails no row of those subsets.
- **X counter.** The 6567R8's X counter spends 8 pixels more on a line
  (`x_hold`): after $187 it runs over $180-$187 a second time, then on
  from $188, so it reaches $1ff on a 520-pixel line. The 6567R56A's runs
  straight through 512 pixels.
  - Pinned for the 6572, which shares the line, by `spritescan_drean`'s
    dump (see [VIC-II 6572 (Drean)](#vic-ii-6572-drean)).
  - The 6567R8's own lightpen dump (`split-tests/lightpen`'s
    `dump6567.prg`, run by hand on `--model ntsc`) agrees: the sample the
    test takes 8 pixels into the hold reads $c2 ($180-$181). Reading
    $184-$187 there instead, as badline did before, gives $c4. The 6572's
    `dump6572.prg` has the same values. The `testbench-ntsc` rows pass
    either way.
- **Blanking and crop.** The blanked lines are the ones VICE's NTSC view
  leaves out, 12-27 on the 6567R8 and 13-27 on the 6567R56A, so the
  `testbench-ntsc` screenshots, VICE's 247 lines from line 28 running on
  into the next frame, see every line they show painted.

What the NTSC references don't settle, and so what stays as it is:

- `modesplit` on the 6567R56A (62 px) is compared against the PAL
  reference, since there is no `-ntscold` one, and every pixel of its
  diff sits in the label bar, where the test prints the line length and
  line count it measured, and the reference shows the PAL ones.
- `modesplit` on the 6567R8 (458 px) matches the PAL reference on every
  row but the label bar. Its `-ntsc` reference differs from the PAL one
  in ways no 6567R8 rule here produces: light grey on the first pixel
  after each `$d021` write (a grey dot, 20 px), the ECM split of section
  2 alone starting and ending a character later (most of the diff) while
  sections 1 and 3 keep their PAL positions, and single pixels in
  section 1. The
  readme says it was matched against screenshots, and the one 6567R8
  photograph in the testprogs is of revision R01.

## VIC-II 6572 (Drean)

The 6572 of the Drean C64 (`Region::DREAN`) runs the 6567R8's line, 65
cycles with its sprite fetches in cycle 59, its display compare in cycle
59 and its X counter running over $180-$187 twice, on PAL-N's 312 lines at
1,023,440 Hz. The oracle is `split-tests/spritescan/spritescan_drean.prg`,
which checks itself against its `dump6572.bin`, from a real 6572R1. The
testlist comments that row out, and `testbench-drean`
(`bin/testbench --drean`) runs it.

- Pinned by that dump: every byte the test compares matches, and the
  test passes.
- The X counter's second run over $180-$187 is pinned by sprite 1,
  pattern C (a one-pixel sprite against one shifted a pixel left), which
  collides for X = $180 to $186 on the 6572. Those are inside sprite 1's
  twelve dead pixels (K = 483), so the sprite only shows from the second
  time the counter reads its X. Repeating $184-$187 in the hold instead
  misses $180-$183 (4 bytes), repeating $180-$183 misses $184-$186 (3),
  and repeating $17c-$183 or $184-$18b moves 18 bytes. Spec guard: the
  6567R8 and 6572 examples in
  [`timing_spec.rb`](../spec/badline/vic/sprite/timing_spec.rb).
- The display compare isn't pinned: the dump matches with it in cycle
  58 as well as 59.
- Not matched: `spritegap3`'s 6572 dump has sprite 0 at X = 0 miss the
  sprite at X = 1 for every pair it is in, where badline, like the
  6567R8 dump, has them collide. The test still passes, because it
  accepts the 6567R8's dump too.

## CIA 6526 timer pipeline

- Start and stop go through two stages. A force load lands one tick after
  it becomes visible, then swallows a pulse and lands after that tick's
  count. The timer underflows on reaching zero, with the reload on the next
  tick. Other rules: a zero counter underflows prematurely; draining to zero
  on stop does not raise the flag; zero latches chain; a one-shot lingers
  when cleared at t-1; PB6/PB7 toggle only on a start transition.
- Old-CIA IR delay: IR rises 1 cycle after the flag, or 2 cycles after a
  mask write hits a pending flag, and an ICR read cancels the pending
  assert.
- Old-CIA acknowledge: an ICR read releases the interrupt line at once, but
  its IR acknowledge lands a cycle late. A read on the next cycle still
  sees IR (`$80`) if it was set at the first read, or was due to rise on
  the next cycle. The line stays released either way, and the cycle after
  that IR reads clear. Pinned by `CIA/dd0dtest/dd0dtest` tests 0c, 0d
  and 0e: the dummy read of `inc $dd0d,x` acknowledges, and the real read
  one cycle later sees `$80`, so the RMW writes `$80`/`$81` back and the
  mask survives, where `$00`/`$01` would clear timer A's mask bit.
- Old-CIA mask cancel: a write that masks every pending source on the
  cycle the flag rises cancels the IR assert only if an ICR read happened
  two cycles earlier. Without that read, IR still rises. Pinned by
  `dd0dtest` test 11 (`inc $dd0d,x` reads at F-2 and writes the clearing
  `$01` at F). This is VICE `ciacore.c`'s `CIA_IRQ_ACK_1` branch (its
  NOTE_1).
- Timer B bug (6526 only): a timer B underflow on the cycle right after an
  ICR read raises the flag, and IR if armed, but the next ICR read drops
  the TB bit unseen. Timer A has no such bug. Pinned by
  `CIA/ciavarious/cia3` K/L, `cia3a` D/H, `cia4` X, `cia8` A/C/F/J/L
  (the readme's old-versus-new CIA cells) and `CIA/cia-timer/cia-timer-oldcias`,
  and ported from VICE's `CIA_IM_TBB`.
- Every rule in this section is the **6526**'s, the chip `CIA.new`
  builds unless given `model: :mos6526a`, and the one `Lorenz.d81`
  expects. That is all the `(*1)` cells of `cia1ta`/`cia1tb` measure, and
  it is an ICR difference, not a counter one. Those cells read the ICR on
  the very cycle the underflow flag rises, so the source bit is up while
  IR is not: they read `$01`/`$02`, where a 6526A reads `$81`/`$82`.
  Counter readback is identical on both revisions. `Lorenznew.d81` expects
  the 6526A and must not be mixed into the `lorenz` chain. Its tests run
  one at a time on a 6526A machine in `testbench-cia-new` instead. See
  [CIA 6526A interrupt register](#cia-6526a-interrupt-register) for what
  changes.
- Timer B's cascade decodes CRB, not CRA. Every count source (ø2, a CNT
  edge, a cascaded timer A underflow) drives the same two-stage
  count-enable pipeline, so a timer A underflow decrements timer B two
  cycles later, and switching the source mid-flight leaves up to two
  enables in the pipe. `cia1tab` is what rules out feeding the underflow
  straight in. With both latches at 2, it wants timer B to read `00` for
  exactly two cycles, with the flag, the PB7 toggle and the reload all
  landing on the cycle after: the premature underflow of a zero counter,
  one pipeline stage ahead of the decrement.
- Pinned by the Lorenz `irq` header, `cia1tb123`, `cia2tb123`, `cia1pb6`,
  `cia1pb7`, `cia2pb6`, `cia2pb7`, `flipos`, `oneshot`, `cntdef`, `loadth`,
  `icr01`, `cia1tab`, `imr`, `cputiming`, `cia1ta`, `cia1tb`, `cia2ta` and
  `cia2tb`.
- Both timers power on with latch and counter at `$ffff`, as VICE's
  `ciat_reset` does. The KERNAL never writes CIA2's timer latches, so a
  program that writes only the high byte while the timer is stopped loads
  the counter with `$00ff`, not zero. A zero there underflows as soon as the
  timer starts and raises a spurious NMI. Pinned by
  `interrupts/branchquirk/branchquirk-nmiold` (first cell only) and
  `CPU/Acid800/cpu_bugs` (NMI lands before the BRK instead of hijacking it).
- Spec guard: [`cia/timer_spec.rb`](../spec/badline/cia/timer_spec.rb) runs
  the eight `(*1)` cells and the `cia1tab` table. It fails if the IR delay
  is dropped. Its *power-on state* group guards the `$ffff` reset.
  [`cia_spec.rb`](../spec/badline/cia_spec.rb)'s *6526 interrupt
  acknowledge* and *6526 timer B bug* groups guard the three ICR rules
  above, on a bare CIA.

## CIA 6526A interrupt register

The 6526A (`CIA.new(model: :mos6526a)`, `Computer.new(cia_model:
:mos6526a)`), fitted to the C64C, differs from the 6526 only in its
interrupt control register. Its timers and shift register run the rules
above unchanged: every `testbench-cia-new` row passes on the 6526's
timer and serial code, the long counter sweeps `cia1tanew`, `cia1tbnew`,
`cia2tanew` and `cia2tbnew` included. VICE's `ciatimer.c` has no model
check either. Each rule below is gated on the model in
[`cia/interrupt_register.rb`](../lib/badline/cia/interrupt_register.rb),
and each was knocked out: removing it fails the rows named.

- **IR on the flag's cycle.** A source flag whose mask bit is set raises
  IR on the cycle the flag rises, not a cycle later. The exception is a
  flag that rises on the cycle after an ICR read: that one raises IR a
  cycle later, as on the 6526 (VICE's `rdi + 1 == rclk`).
  - The early IR is pinned by `CIA/irqdelay/irqdelay-new`,
    `irqdelay-oneshot-new`, `irqdelay2-new`, `irqdelay-cia1-4-new` and
    `irqdelay-cia1-oneshot-4-new`, `interrupts/branchquirk/branchquirk-new`
    and `branchquirk-nminew`, `interrupts/cia-int/cia-int-irq-new` and
    `cia-int-nmi-new`, `interrupts/irq-ackn-bug/cia1new` and `cia2new`,
    `interrupts/irqnmi/irqnmi-new`, `CIA/CIA-AcountsB/cmp-b-counts-a-new`,
    `CIA/cia-timer/cia-timer-newcias`, `CIA/timerbasics/timer_test1_new`
    and `CIA/dd0dtest/dd0dtest`.
  - The exception after a read is pinned by `cia-int-irq-new`,
    `cia-int-nmi-new` and `dd0dtest` test 17, which fail when every flag
    raises IR at once.
- **A read sees an IR about to rise.** A read on the cycle before IR is
  due returns IR set, and cancels the assert as on the 6526. On the 6526,
  only a read on the next cycle sees it.
  - Pinned by `dd0dtest` test 17. The two reads of `inc $dd0d,x` land on
    the cycles before and of timer A's flag, so the second sees `$81` and
    the RMW writes `$81`/`$82` back, arming timer B, whose NMI handler
    then reads `$82`. Without the rule the second read sees `$01`, timer B
    stays masked and no NMI comes.
- **The acknowledge holds every bit.** A read releases the interrupt line
  at once, but the bits it read, sources and IR alike, stay readable on
  the next cycle, along with anything flagged since. They clear the cycle
  after that. The 6526 holds only IR (see *Old-CIA acknowledge* above).
  - Pinned by `dd0dtest` tests 18 and 19. Their `inc $dd0d,x` reads `$81`
    on the flag cycle and again on the next cycle, where a 6526 reads
    `$80`, so the RMW writes `$82` and arms timer B.
- **A mask write raises IR a cycle later**, where the 6526 takes two.
  - Pinned by Lorenz `imrnew`.
- **No timer B bug.** An underflow on the cycle after an ICR read keeps
  its flag.
  - Pinned by `CIA/ciavarious/cia3new`, `cia3anew`, `cia4new` and
    `cia8new` (the readme's old-versus-new cells) and
    `CIA/cia-timer/cia-timer-newcias`.
- Two of VICE's model checks are left out, because no testprog tells
  them apart. VICE stops a mask write from raising IR on the cycle after
  an ICR read, and applies the 6526's mask cancel (*Old-CIA mask cancel*
  above) only to the 6526. Adding the first, or dropping the second for
  the 6526A, passes every `testbench-cia-new` row, so the 6526A keeps the
  6526's behaviour on both.
- Spec guard: *the 6526A interrupt register* in
  [`cia_spec.rb`](../spec/badline/cia_spec.rb), one example per rule,
  each failing when its rule is knocked out.

## CIA serial shift register

- The register counts itself empty on the 15th timer A underflow, when the
  eighth bit reaches SP, not on the 16th that raises CNT over it. The
  serial ICR flag rises 4 cycles after that 15th underflow. VICE waits for
  the 16th, which is the "4 cycle delay" in `cia-sdr-delay`'s readme.
- A byte waiting in the data register loads from that same point
  (`@steps <= 1`) and goes out on the next underflow, so CNT stays low
  between the two bytes. Waiting for the 16th costs a whole timer period,
  the 49 cycles `cia-sdr-load` measured.
- An in-flight level runs through a delay line. It rises 1 cycle after a
  bit lands on SP, drops at 2 and rises again at 3. The eighth bit skips
  straight to 3. The level drops 4 cycles after CNT rises over the bit.
- A CRA bit 6 change is not symmetric. Switching the port to input tears
  the transmission down. If the register is busy, from 4 cycles after the
  first bit reaches SP until it reports empty over the eighth, the byte is
  flagged gone. The same change latches the in-flight level, and switching
  back to output flags the byte gone if the latch is set. Reading the live
  level at the output change instead leaves it stuck high whenever a byte
  never finishes, and the single-baud `cia?-sdr-icr-*` rows catch that.
- A zero timer A latch holds the underflow line asserted rather than
  pulsing it. A waiting byte is still picked up on the level, but every
  later half-step needs a fresh edge, so the byte stops after one bit, CNT
  stays low and the flag never rises.
- Pinned by the `CIA/shiftregister` rows below. Each was checked by
  breaking the rule and rerunning the rows:
  - Empty at the 15th: `cia-sdr-delay`, `cia-sdr-init`, `cia-sdr-load`,
    `cia-sp-test-oneshot-old` and the `-3`/`-19`/`-39` `cia-sdr-icr` rows.
  - Loading from the same point: `cia-sdr-load` alone.
  - The in-flight delay line: the `-3`/`-19`/`-39` `cia-sdr-icr` rows.
  - The latched level: every single-baud `cia-sdr-icr` row, `-0`
    included.
  - The busy report on the switch to input: only
    `cia1-sdr-icr-test2-0_7f` and `cia2-sdr-icr-test2-0_7f`.
  - The zero-latch stall: the `-0` `cia-sdr-icr` rows.
- Nothing pins whether the delay line keeps moving while timer A is
  stopped. It is clocked every cycle, and freezing it passes every row too.
- Don't read `cia-sdr-icr/generate.c` as the spec. Its `reset1` sets
  `delaysetsdr1 = baud` for baud > 3, but `cia-sdr-icr-v3.asm`, which is
  what runs, leaves it at 3 for every baud ≥ 3 (`lda #$03 / cpx #$03 /
  bcs +`). That byte is the difference between the first rule and VICE's
  behaviour. `generate-test2.c` states the rule in a comment: "SP INT is
  raised 4 cycles after TA INT".
- The twelve `-4485` rows other than `-4485-0` are `expect:error`: they
  pass because the model does not match the 4485-batch CIA's reference.
  Baud 0 behaves the same on that batch, so the two `-4485-0` rows must
  pass outright.
- An offline replay that starts each baud on a fresh CIA cannot see the
  state one baud carries into the next through the mode-change latch. Run
  the test2 sweeps for real (about 5 min each) after changing that path.
- Spec guard: the "serial port in output mode" block in
  [`cia_spec.rb`](../spec/badline/cia_spec.rb) covers the flag timing, the
  waiting byte, both mode-change reports and the zero-latch stall.

## VIA shift register

- A read or write of SR starts a byte only while the register is idle
  and enabled. An access in mode 0 starts nothing, even once the mode
  changes, and an access before the eighth bit is in leaves the count
  alone. The byte in progress runs on, and the first access after it
  ends starts the next.
- In the φ2 modes (2 and 6) CB1 falls on the second cycle after the
  access, rises on the third, and so on. Mode 6 puts a bit out on cycles
  +2, +4 … +16, mode 2 takes one in on cycles +3, +5 … +17, and the flag
  rises with the eighth rising edge, on cycle +17.
- In the timer 2 modes (1, 4 and 5) each clock edge comes two cycles
  after the timer 2 low byte underflows, on the cycle after the low byte
  reloads from its latch. The half period stays N + 2 cycles.
- Pinned by the `VIC20/via_sr` rows, each checked by breaking the rule and
  rerunning all 32. The plain and `exp` rows dump SR every 7 cycles, the
  `ifr` and `iex` rows dump IFR, and the SR write comes before the ACR
  write that sets the mode:
  - Mode 0 starts nothing: `viasr08` and `viasr18`, and the `ifr`/`iex`
    rows of modes 04, 08, 14 and 18, which would see the SR flag.
  - No restart before the eighth bit: `viasr14` and `viasr18`. Their
    reads come every 7 cycles, faster than a byte.
  - The φ2 start a cycle late: `viasr08` and `viasr18`. Ticking from the
    first cycle, or from the third, fails both.
  - The timer 2 edge two cycles late: `viasr04`, `viasr10` and `viasr14`.
    A delay of 0, 1 or 3 cycles fails all three.
  - Every rule also fails the row's `exp` twin, the same test on an
    expanded VIC-20.
- Nothing pins whether the timer 2 delay keeps running while the register
  is idle. It does, and freezing it passes every row too. Nothing pins
  the flag's cycle in the φ2 modes either: no row starts a byte and then
  reads IFR.
- Spec guard: the mode blocks in
  [`shift_register_spec.rb`](../spec/badline/via/shift_register_spec.rb)
  and *the shift register* in
  [`via_spec.rb`](../spec/badline/via_spec.rb).

## 6510 I/O port

- DDR at `$00`/`$01`: inputs are pulled up, bit 5 reads low, and bits 3, 6
  and 7 float.
- Pinned by Lorenz `mmu` and `cpuport`.
- DDR and data both power on at `$00`, so `$00` reads `$00` and `$01` reads
  `$17` until the KERNAL sets them.
  - Pinned by `CPU/cpuport/initvalue.crt`, which runs from a cartridge
    before the KERNAL does.
  - Spec guard: *when powered on* in
    [`address_bus_spec.rb`](../spec/badline/address_bus_spec.rb).
- A write to `$00` or `$01` goes to the port, and the RAM below takes the
  byte the VIC fetched in the phi1 half of the same cycle, as in VICE's
  `zero_store`. Only the VIC reads that RAM.
  - Pinned by `general/ram0001/test1`, which puts the byte in `$3fff` for
    the idle fetch, and `general/fuxxortest/ef2-inst4a`, which uses two
    sprite pointer fetches. Both read the RAM back through sprite
    collisions.
  - Spec guard: *when a program writes to the port* in
    [`address_bus_spec.rb`](../spec/badline/address_bus_spec.rb).

## RAM power-on pattern

- RAM powers on in runs of `$00,$00,$ff,$ff,$ff,$ff,$00,$00`, inverted in
  `$4000-$7fff` and `$c000-$ffff`, on every power cycle. The RAM under
  `$00`/`$01` follows the pattern like the rest. It is the pattern of a
  C64C (ASSY 250469 R4) in `C64/raminitpattern/readme.txt`
  (`-raminitstartvalue 0 -raminitvalueinvert 4 -raminitvalueoffset 2
  -raminitpatterninvert 16384 -raminitpatterninvertvalue 255`), without
  that machine's occasional random bytes. `AddressBus::RAM_POWER_ON`
  holds it.
  - Pinned by `C64/raminitpattern`: `cyberloadtest` fails when
    `$f379-$f478` holds one value, `darkstarbbstest` when the first ten
    bytes of one of the pages `$4000`, `$5000` … `$9000` do, `platoontest`
    when `$1000-$10ff` holds five equal bytes in a row and 140 or more
    bytes of one value, and `typicaltest`
    checks `$3fff` against a table of values the Typical demo survives.
    All-`$00` fails the first three, and each other pattern the readme
    lists fails at least one of the four.
  - Spec guard: *RAM at power-on* in
    [`address_bus_spec.rb`](../spec/badline/address_bus_spec.rb).
- The RAM expansions' extra banks still power on at `$00`.

## VIC-20 RAM power-on pattern

- The VIC-20's RAM powers on in alternating bytes, `$ff` at the even
  addresses and `$00` at the odd ones, on every power cycle. The internal
  RAM and the expansion blocks (RAM1-3, BLK1-3, BLK5) all follow it.
  Colour RAM powers on at zero. `Vic20::Bus::RAM_POWER_ON` holds it.
  - Pinned by `VIC20/raminitpattern`: `ae.crt` fails unless `$0288` reads
    `$ff` and `jellymonsters.crt` unless `$1046` does, read from a
    cartridge before the KERNAL clears RAM. The readme says AE and Jelly
    Monsters need `$ff` there. Its dumps of real machines' `$1000-$1fff`
    show bytes alternating `$00` and `$ff` on most machines, with either
    phase, and noise or other patterns on the rest. They show nothing
    for colour RAM or expansion RAM that a pattern could be read from.
  - Spec guard: *RAM at power-on* in
    [`vic20/bus_spec.rb`](../spec/badline/vic20/bus_spec.rb).

## VIC-I fetches and the V-bus

- On a line of the text window the 6561 fetches the first character code
  4 cycles after the column in `$9000`, 16 cycles after the raster count
  moves with the KERNAL's origin of 12, then the code's pattern byte in
  the next cycle, two cycles a character. Outside the window it fetches
  nothing.
- A read where no chip answers in I/O 0 (`$9100`, `$9200`) returns the
  V-bus's last byte: the VIC's fetch in a cycle it fetches in, and the
  CPU's own last byte on the V-bus in the other cycles.
  - Pinned by `VIC20/split-tests/timing`: all 1,024 bytes of its readings
    of `$9003`, `$9004`, `$9100` and `$9200` over 256 cycles match
    `dumps/dump6561e.prg`, a real 6561E. The later 6561-101's dump reads
    `$20` in the idle cycles instead; badline follows the 6561E.
  - Spec guard:
    [`vic20/vic_split_tests_timing_spec.rb`](../spec/badline/vic20/vic_split_tests_timing_spec.rb)
    (`:slow`), and *the fetches* in
    [`vic20/vic_video_spec.rb`](../spec/badline/vic20/vic_video_spec.rb).
- A write to `$900F` or `$900E` takes hold from the second of the four
  pixels of the cycle it lands in, the reverse bit two pixels later, and
  a character's pixels come out in the two cycles after its pattern
  fetch. These match xvic's screenshots of a test of cycle-timed writes
  pixel for pixel; no testprog or hardware capture checks them.
  - Spec guard: *a colour write* in
    [`vic20/vic_video_spec.rb`](../spec/badline/vic20/vic_video_spec.rb).

## VIC-I sound

No testprog checks the VIC-I's sound, so these rules are pinned by xvic
(VICE 3.10) recordings, run as a black box: `-sounddev wav` at 44.1 kHz of
programs that set the registers, the same programs run on badline, and
the two compared by period, harmonics and spectrum. xvic's own source
wasn't read.

- A voice's counter comes round every 128 - ((value + 1) & 127) ticks of
  16, 8, 4 and 2 cycles from bass to noise, and a tone voice's shift
  register plays 16 shifts a period, as Marko Mäkelä's `VIC-I.txt`
  (revision 1.2, Levente Hársfalvi's measurements) gives the frequencies.
  - Pinned by xvic: `$900A` = `$FE`, `$80` and `$FF` measure 4329.70,
    34.0922 and 33.8256 Hz, `$900B` = `$F0` 577.29 Hz, and `$900C` = `$F0`
    and `$A0` 1154.59 and 182.30 Hz, each within 0.001 Hz of the formula
    on the PAL clock.
  - Spec guard: *a tone voice's counter* in
    [`vic20/sound_spec.rb`](../spec/badline/vic20/sound_spec.rb).
- A tone voice's shift register takes bit 7 back into bit 0 inverted while
  the voice is on and a zero while it's off, and keeps shifting either way.
  Bit 0 is the output, not gated by the enable bit. This is the die-shot
  reading of the 6561 on the Denial forum (Lance Ewing: the feedback is a
  NOR of bit 7 and the inverted enable bit, and the counter keeps shifting
  a voice that's off).
  - Pinned by xvic: a bass voice loaded with 10101010, 11000000, 10000000
    and 11101000 by turning it on and off a shift at a time, then left
    on, has the same harmonics in xvic's recording and badline's to
    0.1 dB through the 12th. 10101010 puts the 7th and 9th harmonics
    above the fundamental, which a register cleared while off couldn't.
  - Spec guard: *a tone voice* in
    [`vic20/sound_spec.rb`](../spec/badline/vic20/sound_spec.rb).
- The noise voice's counter steps a 16-bit LFSR: bit 0 takes the XOR of
  bits 3, 12, 14 and 15 while the voice is on and a one while it's off.
  Each rise of the LFSR's bit 0 shifts the noise voice's own shift
  register, bit 7 back into bit 0, inverted while the voice is on, and
  its bit 0 is the output while the voice is on. These are the die-shot
  readings on the Denial forum (Lance Ewing and nippur72), which also
  say the voice is silent while off.
  - Pinned by xvic: noise at `$FE` and `$FD` repeats every 0.11825 s and
    0.2365 s (autocorrelation 0.98 at those lags, in both xvic's
    recording and badline's), 65535 steps of 2 and 4 cycles. The octave
    band levels of noise at `$FE`, `$FD`, `$F0`, `$C0` and `$80` match
    xvic's within 0.5 dB up to 8 kHz.
  - Spec guard: *the noise voice* in
    [`vic20/sound_spec.rb`](../spec/badline/vic20/sound_spec.rb).
- The output is the voices that are high plus 2/9 of a voice, times the
  volume, so a volume write steps the output with every voice off, as
  4-bit samples played through `$900E` need.
  - Pinned by xvic: a volume step from 0 to 15 with every voice off peaks
    at 0.218 of a voice turned on at volume 15.
  - Spec guard: *the volume* in
    [`vic20/sound_spec.rb`](../spec/badline/vic20/sound_spec.rb).
  - Not pinned: the volume scales the output linearly. xvic's tone level
    per volume step isn't linear (volume 1 is 0.099 of volume 15 and 14
    is 1.015), and nothing here says whether the hardware is.
- The output stage is a one-pole low-pass at 1,420 Hz and a one-pole
  high-pass at 158 Hz.
  - Pinned by xvic: a bass voice turned on at volume 15 fits those two RC
    stages at 1,417 and 158.0 Hz, with an RMS error of 6 against a peak of
    11,280. badline's own recording fits 1,420 and 157.6 Hz.
  - Spec guard: *a step* in
    [`vic20/sound/output_spec.rb`](../spec/badline/vic20/sound/output_spec.rb).

## 1541 serial port

- The drive sees the C64's side of the serial bus a host cycle late. The
  drive runs after the C64 in each host cycle, so `SerialPort` reads the
  C64's lines as `latch_host` took them at the end of the previous host
  cycle, both on VIA 1's port B (DATA IN, CLK IN, ATN IN) and on CA1,
  which ATN reaches. A CIA 2 write lands for the drive's cycles of the
  next host cycle, the way the CIA's pins change at the end of the cycle
  that writes them. The drive's own lines, and what the C64 reads back,
  stay live.
- The 2-bit loader that uploads the drive tests' code times its transfer
  from an ATN edge, and seeing that edge a cycle early loses the first bit
  pair.
- Pinned by the `testbench-drive` rows below. Each was checked by having
  the drive read the live lines (`@bus.atn_low?` and `@bus.low_lines`
  with no argument) and rerunning the rows:
  - Fail without the latch (`exit=$ff`): `drive/selftest`,
    `drive/diskid/diskid1`, `drive/interrupts/timera`, all six
    `drive/scanner` rows, both `drive/openbus` rows and
    `drive/viavarious/via1`, `via3a` and `via10`.
  - Pass either way: `drive/defaults`, `drive/rpm/rpm1` and `rpm2`,
    `drive/skew/skew1` and `drive/iecdelay/iec-bus-delay-auto`.
- Spec guard: *sees an assertion from the host cycle after the one it
  lands in* and *shows the drive the C64's CLK from the host cycle after
  the write* in [`iec_bus_spec.rb`](../spec/badline/iec_bus_spec.rb).

## 1541 disk mechanism

- A step out against the stop at track 1 slips the stepper's phases: the
  head stays on half track 2, and the phase that pulled it outwards
  becomes that half track's. The DOS's bump steps out 92 half tracks, a
  whole number of phase turns, and then takes the phase it ends on as
  track 1's: `N:` formats track 1 there and steps in two phases a track.
  With each half track holding its own phase from power-on instead, the
  bump ended two half tracks off track 1's phase, the first step in
  pulled the head against the stop, and the DOS wrote track 2 over track
  1 and every later track one track out, at half track 2n - 2.
  - The DOS reads its own format back either way, since each header
    carries the track the DOS thought it was on: `drive/format` passes
    without the slip, and so doesn't pin it. Reading the disk back into a
    D64 does, since each header has to name the track the image holds it
    on.
  - Spec guard: *steps in from the stop with the first phase after the
    bump* in
    [`mechanism_spec.rb`](../spec/badline/drive1541/mechanism_spec.rb),
    and the `format/name-and-id`, `format/bam-free` and
    `format/trap-readable` rows of the `drive-scenarios` suite
    ([`drive_scenarios.rb`](../test/drive_scenarios.rb)), which read the
    formatted disk back from its image.
- The disk turns at 300 rpm whatever bit rate VIA 2's PB5-6 select: a
  turn is 200,000 drive cycles over every track and over a half track
  without data. Each track's bits pass under the head at the rate they
  were written at: spread evenly over the turn, so a track as long as a
  turn holds at its zone's rate passes at that rate and a `.g64` track
  longer or shorter than that passes faster or slower, and a `.g64`
  speed map widens each byte's cells by its zone. The read clock runs at
  the selected rate and each flux transition brings it back into step,
  so a track read in its own zone reads clean and one read far enough
  off garbles (zone 0 against zone 3). With the rate selected turning
  the disk instead, a zone 3 track read in zone 0 read clean and took
  246 ms a turn, and a `.g64` track turned in its length of bytes.
  - Pinned by `drive/rpm` (`rpm1`, `rpm2` and `rpm3`, on the `.d64` and
    the `.g64`): each times a turn and passes within 297 to 303 rpm.
  - Pinned by `drive/skew/skew2`, on a `.g64` whose tracks all start
    sector 0 at the same angle: the head keeps the disk's angle across
    the tracks and half tracks it steps over only while every track
    turns in the same time.
  - Pinned by `drive/scanner` (all six programs, on the `.d64` and the
    `.g64`), which reads every track and each track's error map.
  - Spec guard: the *at 300 rpm* examples and *turns once in 200 ms* in
    [`mechanism_spec.rb`](../spec/badline/drive1541/mechanism_spec.rb),
    and *#cell_at* in
    [`track_spec.rb`](../spec/badline/drive1541/track_spec.rb).
- A write lays its bits one to a cell from the cell under the head. A
  half track without data gets a blank track first, as long as a turn at
  the rate the drive writes at, not at the rate of the track's own zone,
  and a track written in another zone is laid out again as a turn at the
  rate written, its flux kept at its angle to within a cell. A track
  written in the selected zone keeps its length, so a `.g64` track
  longer or shorter than a turn keeps the sectors around the one written.
  - Pinned by `drive/rpm/rpm3`, which writes track 36, past a 35-track
    D64, at the zone 2 rate the DOS leaves selected there: a turn and a
    half of SYNC and five bytes, and times a turn by reading it back.
    With a zone 0 track of 6250 bytes a turn took 175,001 cycles
    (342.86 rpm, `exit=$ff`). With the last byte's leftover part of a
    cell widening the track's last cell, instead of the cells spread
    evenly over the turn, the SYNC broke there and the turn read as
    194,728 cycles (`exit=$ff`).
  - Spec guard: *gives a half track a blank track 7142 bytes around,
    written in zone 2* in
    [`disk_spec.rb`](../spec/badline/drive1541/disk_spec.rb), and *lays
    a track written in another zone out again as a turn at the zone
    written* and *writes a turn of SYNC that reads back without a break*
    in [`mechanism_spec.rb`](../spec/badline/drive1541/mechanism_spec.rb).
- A disk made from a `.d64` starts sector 0 of each track where the DOS's
  `N:` leaves it: track 1 at the index angle, and each track after it
  round from the last by the skew `N:` leaves in its zone, 0.6869 of a
  turn in zone 3, 0.8915 in zone 2, 0.0897 in zone 1 and 0.2916 in zone
  0. Those are measured off a disk formatted here with `N:`.
  - Pinned by `drive/skew/skew1`, which expects a `.d64` to read with
    the skew a DOS format leaves. With every track starting sector 0 at
    the same angle it read `kernal format, tracks are aligned`
    (`exit=$ff`).
  - The skew moves which block the DOS meets first on each track, and
    `drive/scanner`'s three error-map rows (`scanner35e`, `40e`, `42e`)
    read track 4's error 22 only when the header comes first. They pass
    with this skew at 300 rpm. With the rate selected turning the disk,
    the same skew made them read track 4 as error 27, which is why
    `skew1` failed before.
  - Spec guard: *starts sector 0 of track N where the DOS's N: leaves
    it* in [`disk_spec.rb`](../spec/badline/drive1541/disk_spec.rb).
- The CPU sees BYTE READY on SO a cycle late: BYTE READY sets V for the
  next cycle's instruction step, not the one in the cycle it falls in.
  - Pinned by `drive/hls-protection`. Its drive code counts the bytes
    from one SYNC mark to the next, reading `$1C00` for SYNC once per
    byte, 20 to 22 cycles after each BYTE READY with the delay (19 to 21
    without). The SYNC marks it has to find follow an `$AF`, whose four
    trailing 1 bits make SYNC six bits, 19 cycles in zone 3, after its
    BYTE READY; the ones it has to miss follow a `$2B`, eight bits on.
    With V set in the same cycle, the read sometimes came a cycle
    before SYNC, depending on the bit phase: on track 1 two of the 16
    counts read `$02C8`, two sectors' worth, and the testbench row failed
    (`exit=$ff`) on track 17. With the delay, tracks 1, 5, 10, 12 and 17
    (the 4-cycle loop) and 18, 20 and 24 (the 6-cycle loop) all read as
    the test expects.
  - Spec guard: *sets V through SO while CA2 is high, a cycle after BYTE
    READY* in
    [`mechanism_spec.rb`](../spec/badline/drive1541/mechanism_spec.rb).

## REU DMA

The REC's timing against the VIC, each rule derived from the REU
testprogs named.

- A requested transfer takes the bus on the next cycle with BA high, and
  moves its first byte there. Starting a cycle later moves every
  `REU/xfertiming` row and `REU/reutiming/reutiming`. /DMA takes the bus
  from the CPU from the cycle after the request, even while the REC waits
  for BA, and RDY only halts the CPU on a read, so a write the CPU makes
  then goes nowhere (`AddressBus#cycle_cpu_off_bus`). That is how an `INC
  $FF00` starts an armed transfer without its second write reaching RAM.
  Pinned by `REU/rmw-trigger/rmwtrigger-ram` and `rmwtrigger-rom`.
- After reading C64 memory the REC waits out every BA-low cycle. After
  writing it goes on through the first BA-low cycle and waits from the
  second, and a fetch or swap whose last write it waited out takes one
  more cycle before handing the bus back (`REU::DMA#note_ba`,
  `#wind_down`). Pinned by `REU/bonzai/spritetiming`, whose 45 bytes a
  line with eight sprites on is 63 less the 18 cycles this leaves.
- A fetch's last write doesn't go through the first BA-low cycle: the REC
  waits for BA to rise and writes it then. Pinned by `REU/reutiming2/d`
  and `d2`, and it takes `REU/reutiming2/c` from 6,403 px to 337.
- A fetch requested on the last cycle before BA falls writes its first
  byte on the first BA-low cycle, without counting it, then waits for BA
  and writes the same byte again when it starts (`REU::DMA#write_ahead`).
  One requested on a BA-low cycle writes nothing until BA rises. Pinned by
  `REU/badoublewrite`, whose sixth transfer a frame, requested on the
  cycle before BA falls for raster `$63`, a bad line, holds `$d021` at its
  first byte for the whole line, where the program's text says "d021
  doublewrite on this line". The row captures its screen too early to
  show this (see below), but the frame after matches the reference to the
  pixel, and without the rule that line is 199 px off.
- `REU/badoublewrite` writes `$D7FF` from its raster interrupt on the
  third transfer of the first frame it runs them in, at raster 77, so the
  screenshot taken at that write shows the frame before below it, with
  the text half printed and the background still blue. Its reference
  shows a whole frame of twelve transfers on black, which only a
  screenshot a frame or more later can. The exit is locked to the raster:
  starting the program anywhere up to a frame later leaves it on raster
  77 with the same 58,880 px. VICE's own x64sc and x64 fail the row in every result the
  testbench keeps, r41951 to r45942, while Denise passes it from 2023.
  The row stays at 58,880 px.
- `REU/reutiming2/c`'s reference shows its last transfer, from raster 250
  into 251 (`$fb`), waiting on raster 251 as the transfers above it wait
  on their bad lines: the border holds the transfer's byte `$11` up to
  x 336 and `$12` from x 337, where BA rises on a bad line. Raster 251 is
  past the bad line range, `$30`–`$f7`, and the program turns on no
  sprites, so nothing pulls BA there, and badline writes `$12` on the
  cycle after `$11`, before the line's visible part starts. The 8565 and
  8565early references show the same wait. No emulator or FPGA core in
  the testbench's 59 kept results passes the row, VICE, the Ultimate 64
  and the Chameleon included, and the testlist marks it `warn:vicefail`.
  badline keeps the bad line range, and the row stays at 337 px, all of
  them on raster 251.
- On the line whose raster matches sprite 0's Y, a REC that read or wrote
  on the cycle before doesn't see BA fall on the first cycle of sprite
  0's window (`VIC#reu_ba_late?`). Without it `REU/bonzai/spritetiming`
  reads `$5a,$87` where a real REU gives `$5b,$88`. A swap's read on that
  cycle still sees BA low, and is held as the next rule says (pinned by
  `REU/reutiming2/e4-m2` and `e6-m2`).
- A swap's read that falls on the first BA-low cycle, after its write, is
  held open while AEC stays high and takes the byte on the bus two cycles
  later. If it is the transfer's last byte it is read there instead, its
  write follows on the next cycle, and the REC hands the bus back
  (`REU::DMA#swap_read_on_ba`). Pinned by `REU/reutiming2/e5-m2`, `f3-m2`
  and `f4-m2`, whose patterns were captured on a breadbin.
- A swap's read made with BA high, when BA falls on the next cycle before
  its write, is made again when BA rises, and the write follows it
  (`REU::DMA#read_swap_again`). So is a held read when BA runs straight
  from a bad line's window into sprite 0's (`VIC#reu_ba_handed_on?`).
  Pinned by `REU/reutiming2/e4-m2`, `e6-m2`, `g3-m2` and `g4-m2`.
- The `reutiming2` references without `-m2` read `$42`, the RAM under
  `$DC04`, on some of the cycles a swap's or stash's read starts with the
  VIC's DMA. The readme puts that down to a C64C board or an 8565, while
  the testlist runs those rows on the 6569, the same machine as the `-m2`
  rows, whose references read the timer there. The two sets can't both
  pass on one machine, and badline follows the breadbin `-m2` ones.

## SID oscillator

- The phase accumulator powers on at `$555555` (all bits high, with the odd
  ones stored inverted) and survives reset. `SID/osc3-wave0` only reads the
  documented `$00`/`$ff` because of it.
  - Pinned by `SID/oscinit` (all three).
  - Spec guard: *leaves the SID's accumulators alone* in
    [`computer_spec.rb`](../spec/badline/computer_spec.rb). The testbench
    only runs `SID/oscinit` from power-on, so only the spec catches a reset
    that rebuilds the voices.
- Ring modulation substitutes the triangle's MSB with
  `!Saw & ((!V3 & Ring) ^ bit23)`, where `V3` is the modulating voice's MSB.
  That is an XNOR where reSID uses an XOR.
  - Pinned by `SID/ringmod`, which expects OSC3 to read `$ff` with both
    oscillators stopped at zero.
- The noise LFSR is 23 bits wide. It feeds bit 0 back from bits 22 ^ 17.
  Its eight output taps are bits 20, 18, 14, 11, 9, 5, 2 and 0, driving
  waveform bits 11 down to 4 (Dag Lem's diagram in `SID/noise-reset_new`).
  It powers on at `$7ffffe`, which is what makes `SID/oscinit`'s
  `noiseinit` read `$fe`.
- Each rise of accumulator bit 19 shifts the LFSR two cycles later, in two
  phases (libresidfp's shift pipeline). The cycle after the rise is phase
  1: the register bits float, so a combined waveform pulls nothing down and
  its output is latched instead. The cycle after that is phase 2: the
  latched output is written over the taps, then the register shifts.
  Phase 2 writes back by the test bit release rule below, with the old and
  new waveform the same: noise combined with anything but pulse alone. On
  the 6581, phase 2 also writes pulse+noise's lines (below).
  Setting the test bit drops a shift in flight.
  - Pinned by `SID/noisewriteback`'s `noise_writeback_test2` (both chips).
    It releases the test bit into noise+triangle, which pulls every tap low,
    then sets the frequency to `$ffff`. Bit 19 rises on the 9th cycle and
    the read lands on the 11th, the first output after the shift has filled
    the taps from the bits below: `$14` on the 6581 and `$12` on the 8580,
    whose OSC3 reads the triangle a cycle late. Shifting on the rise itself
    lets the triangle pull the new taps down first, and the read is `$10`.
    The test pins the delay only. Phase 1's float differs from pulling down
    only when pulse+noise is selected across it, and nothing pins that.
  - Spec guard: *two cycles after accumulator bit 19 rises* and *around a
    shift* in [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb),
    and *carries a noise shift pending across a span edge* in
    [`sid_spec.rb`](../spec/badline/sid_spec.rb): a catch-up that
    fast-forwards across a rise carries the shift still in flight into the
    next span.
- Setting the test bit onto noise combined with another waveform writes
  that combination's output back into the LFSR first, from the accumulator
  it had, before the bit clears it.
  - Pinned by `SID/noiselfsrinit`'s `simple` and `scan` (both chips). Their
    `$f8`/`$80` pairs set the test bit onto all four waveforms from noise
    alone, and zero the register only if this writes back. The release that
    follows goes to noise alone, which writes nothing back (below).
  - On the 6581, pulse+noise writes its `$00` read back here, as in a
    shift's phase 2 (below). Pinned by `SID/wf12nsr`'s pulse+noise row,
    which sets the test bit onto pulse+noise.
  - Spec guard: *as the test bit rises* in
    [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb).
- The test bit does not clear the LFSR. It stalls it halfway through a
  shift with bit 22 forced high. While the bit is held, every bit bleeds up
  to `$7fffff`: after `$950000` cycles on the 8580 (`SID/bitfade`'s
  `delaynoise` on a real 8580; VICE's `~8000` there is its own emulation)
  and after `$80000` on the 6581. On release, one bit clocks in.
  - Pinned by `SID/resid-test`'s `oscsample0`/`oscsample1` (both chips).
    They hold the test bit about `$8800` cycles between their eight noise
    runs, and the real chips' dumps read each run on from the register the
    last one left, so the bleed has to take longer. The old `$8000` fails
    all four rows. The 6581 value is not measured anywhere: it only has to
    fall between that hold and the second `SID/noise-reset_old` allows the
    6581 (60 frames, about `$120000` cycles), and `$80000` sits between
    them. The scored tests that wait for the bleed hold the bit far longer
    (`resid-test/noisetest` about `$1680000`, `waveforms-80` and
    `noise_writeback_test1` about `$f60000`), so the 8580's `$950000`
    passes them too. On a real chip the bits rise one at a time, at a rate
    that varies with the chip's temperature (`SID/wf12nsr`'s
    `quicktest.prg` on a 6581), which nothing scored depends on.
  - Spec guard: *bleeding through a held test bit* in
    [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb).
- Before the bit clocks in on release, the old waveform's output is
  written back only for some waveform changes. Noise has to have been
  combined before the release and still be combined after it, so a change
  to noise alone writes nothing back. A change to pulse+noise writes
  nothing back, nor does a change from pulse+noise to sawtooth+noise. On
  the 6581, trading triangle for sawtooth or back writes nothing back. The
  rule follows libresidfp's `do_writeback`. What is written is the
  writeback shape below, not the OSC3 read. Two more cases are not in that
  rule. On the 6581, a change that keeps only pulse+noise of the old
  waveform (`D`/`E`/`F`→`C`, `D`→`E`) writes the three lowest noise lines
  low (`$f8`). On the 8580, a change from pulse+noise to all four
  (`C`→`F`) writes every line low.
  - Pinned by `SID/wb_testsuite` (the `9`/`A`/`D`/`E`/`F`→`8` rows on both
    chips, and the 6581's `9`↔`A`, `9`/`A`→`C` and `D`→`A` rows) and by
    `SID/noisewriteback`'s `noise_writeback_test1`. The 6581's `$f8` case
    is pinned by its `D`→`C`, `D`→`E`, `E`→`C` and `F`→`C` rows, and
    dropping it fails all four. The 8580's `C`→`A` row pins the
    pulse+noise to sawtooth+noise exception: without it the release writes
    the 8580's `$fc` and the row fails. The 8580's `C`→`F` row pins the
    all-low case: writing the old waveform's `$fc` back makes the first read
    `$fc`, where the row expects the `$6c` that `F`→`F` reads. Both 8580
    samplings in `SID/wb_testsuite/samplings` read `$6c` for `C`→`F`.
  - `F`→`8` wrote back until the test bit's rise (above) took over
    zeroing the register for `SID/noiselfsrinit`. Every sampling in
    `SID/wb_testsuite/samplings`, both chips, reads `F`→`8` as a plain
    shift.
  - Spec guard: *as the test bit falls* in
    [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb).
- A combined waveform shorts the shapers onto the lines the oscillator reads
  back. A low top bit reaches the accumulator MSB through the sawtooth
  switch and clears it (`SID/osc_topbit`, all three). With noise selected,
  the result is written into the LFSR, where a bit pulled low never comes
  back. Together these run Dag Lem's fast LFSR reset exactly as documented:
  three `$b8`/`$b0` pairs zero the register, and 18 `$88`/`$80` pairs set
  bits 0–17.
- The shape of a combined waveform without noise comes from a fitted model
  (`SID::Waveform::Combined`), not from ANDing the shapers: each line is
  high when its own drive and its neighbours', weighted by distance, clear
  a threshold. `bin/sidwavefit` fits it to `SID/resid-test`'s oscsample
  dumps and `bin/sidwavecheck` scores it. A low pulse grounds every line.
  Noise is ANDed over triangle and sawtooth mixes; pulse+noise is below.
  - Not pinned by an exit code: oscsample only scores the single
    waveforms, and no scored test reads a combined shape without noise.
  - Spec guard: [`sid/waveform/combined_spec.rb`](../spec/badline/sid/waveform/combined_spec.rb)
    checks spot values against the dumps.
- Noise in a combined waveform writes its lines back into the LFSR by a
  lower threshold than OSC3 reads them by. Two rules follow, both fitted to
  the tests' own reference data (`SID::Waveform::NoiseWriteback`):
  - With triangle or sawtooth, OSC3 reads the plain AND, but a line left
    high between two low ones is written low. `SID/noisewriteback`'s
    `noise_writeback_test2` reads such lone lines (`$14` is output bits 8
    and 6), and `SID/wf12nsr`'s noise+triangle and noise+sawtooth rows need
    them written low: at the end of the `$ffff` period the real register
    holds `$020100`, and a writeback of the plain AND leaves `$024100`.
  - Pulse+noise with the pulse high loses its lowest noise lines, next to
    the four below them that nothing drives. The 8580 reads `$f8` of a full
    register and writes `$fc` back, the only pair among `$f8`, `$fc` and the
    full noise that passes `SID/wf12nsr`'s pulse+noise row. That `$fc` is what
    `SID/wb_testsuite`'s `C`→`9` and `C`→`E` rows need written at release.
    The 6581 reads `$00` of a full register, and pulls nothing down while
    the register holds. Its lines land only part way through a shift: in
    a shift's phase 2, and as the test bit rises onto pulse+noise. Both
    write the `$00` read, so every tap goes low.
  - Pinned by `SID/wf12nsr` (wf9/wfa on both chips, wfc on the 8580) and
    the `SID/wb_testsuite` rows above. Knock-outs: writing back the plain
    AND fails wf9 and wfa on both chips; on the 8580, reading and writing
    `$fc` fails wfc, and reading and writing `$f8`, or the full noise,
    fails wfc and the `C`→`9`/`C`→`E` rows; applying the lone-line rule to
    the read as well makes `noise_writeback_test2` read `$00` on both
    chips.
  - The 6581's pulse+noise is pinned by `SID/wf12nsr`'s wfc row and
    `SID/wb_testsuite`'s `8`→`C` and `C`→`C` rows. The wfc row releases the
    test bit into pulse+noise at frequency `$ffff` with the pulse width
    never written, so zero and the pulse high, and reads `$00` on the next
    instruction, before bit 19 first rises. That read is of a full
    register, so the `$00` is the read itself. Its noise run afterwards
    matches the other combined rows, whose taps were all pulled low. The
    `8`→`C` and `C`→`C` rows hold pulse+noise at frequency zero, where no
    shift comes, and leave the register alone. Knock-outs: writing the
    `$00` back every cycle and at release fails `8`→`C`, `C`→`C` and ten
    more 6581 rows (the recorded VICE r45942 results pass wfc and fail
    `8`→`C` and `C`→`C`); dropping the phase 2 write or the write as the
    test bit rises fails wfc. The readme
    of `SID/wf12nsr` has a warmed-up 6581 reading `$fc` with the test bit
    held (`quicktest.prg`, unscored), which this model doesn't reproduce.
  - Spec guard: *writes a lone line of a noise combination back low*, *with
    pulse+noise on the 8580*, *reads nothing of pulse+noise on the 6581*,
    *with pulse+noise on the 6581*, *as the test bit rises* and *as the
    test bit falls* in
    [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb).
- The pulse comparator's output reaches the lines a cycle after the
  accumulator it compared, on both chips. Setting the test bit forces it
  high at once.
  - Pinned by `SID/waveforms`' `waveforms-40` (both chips) and the pulse
    rows of `SID/resid-test`'s `oscsample1` dumps, where the width of `$100`
    first reads high at phase `$101` on the 6581, and at `$100` on the 8580
    whose OSC3 reads the phase itself a cycle late. Comparing on time fails
    both `waveforms-40` rows.
  - Spec guard: *reaches the output a cycle after the accumulator it
    compared* in [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb).
- Waveform 0 leaves the DAC input floating. It holds the last value a shaper
  drove onto it and drains to `$000` after `$4000` cycles.
  - Pinned by `SID/osc3-wave0`. `SID/oscinit`'s `allinit` pins the power-on
    `$00`, before anything has driven the line.
- The 8580 delays the triangle and sawtooth shapers by half a cycle. OSC3
  latches in the first phase of the clock, so it reads them a whole cycle
  late, while pulse and noise still reach the lines on time (the pulse with
  its own cycle of lag, above). The audio output is not delayed. This
  follows libsidplayfp's `tri_saw_pipeline`.
  - Pinned by `SID/detect`'s `detect-2-new`. It releases the test bit into
    a `$ffff` sawtooth and reads OSC3 four cycles later: `3` on the 6581,
    `2` on the 8580.
  - Spec guard: *#osc3 on the 8580* in
    [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb) and
    *the 8580* in [`sid_spec.rb`](../spec/badline/sid_spec.rb).

## SID register writes

- The 6581 latches a register write one cycle late. That falls out of the
  bus order, not from any delay line inside `SID`. `Computer#cycle!` clocks
  the SID ahead of the CPU, so a write on cycle N first reaches the DSP on
  cycle N+1, while a read on cycle N sees N cycles of clocking. Moving
  `sid.cycle!` after `cpu.cycle!` breaks this.
- Pinned by `SID/writedelay`, which reads OSC3 four cycles after releasing
  the test bit and expects the pulse already high.
- Spec guard: *SID writes against the clock order* in
  [`computer_spec.rb`](../spec/badline/computer_spec.rb). It runs an
  `STA $d400` and checks that the DSP has not clocked the new frequency on
  the store's own cycle, over both the synthesizing and the idle-replay
  paths.

## SID data bus

- Reading a write-only or unconnected register returns the latch without
  draining it. reSID halves what is left of the charge on such a read,
  which would cut the 6581 measurement below to `$52`–`$7d`.
- Pinned by `SID/bitfade`'s `delayfrq0`, which polls `$d400` every nine
  cycles while it waits and still measures the full TTL: `$1d02` here
  against `~$01d00` on a real 6581, and `$a2005` for the 8580 against
  VICE's `~$a2000`.

## SID envelope

- The envelope follows reSID's rate-counter model: a 15-bit counter compared
  against a per-nibble period, and a second level-dependent divider (`$ff`→1,
  `$5d`→2, `$36`→4, `$1a`→8, `$0e`→16, `$06`→30) that the attack phase
  bypasses and resets. Zero freezes the envelope until the next gate edge.
- Lowering the rate period below the running counter sends the counter the
  long way round through `2^15`. Hard restarts depend on this ADSR delay
  bug.
- Pinned by `SID/envelope` (`testADSRDelayBug`, `testFlip00toFF`,
  `testFlipFFto00`, `lft-adsr-test`) and `SID/exp_counter_reset`.
- Each stage runs a cycle or more behind the one feeding it, after reSID
  1.0's single-cycle pipeline (VICE's `resid/envelope.h`), not reSID 0.16's
  step-on-match:
  - The rate counter compares against `PERIODS` (8, 31, 62, …) *before* it
    counts. A match holds the counter for a cycle and resets it to 0 on the
    next, so the period is one cycle longer than the comparison value.
  - An attack step lands two cycles after that reset. A decay or release
    step with the divider at 1 also lands two cycles after it, through a
    one-cycle divider stage. With the divider above 1, it takes one cycle
    more.
  - ENV3 reads the counter as it stood at the start of the cycle, one cycle
    behind the audio path.
  - A rising gate runs the decay state and decay rate for one cycle and
    enters attack on the second. A step already set off by a pending reset
    or divider still lands, as an attack step, two cycles after the edge
    (four with the divider above 1), and a divider one cycle from landing
    holds the attack off a cycle more.
  - A falling gate switches the rate over on its second cycle, or its third
    with a step in flight. Out of decay it switches a cycle sooner.
  - Pinned by `SID/env_test`, all seven. The readme says they pass on a
    real 6581 and 8580. Knock-outs, each failing the listed tests:
    attack step one cycle after the reset (all seven), divider stage
    always one cycle (all seven), ENV3 reading the live counter (all
    seven), a rising gate ignoring the pending step (`ra_0000`, `ra_0100`,
    `adra_1`, `adra_2`), attack on the first cycle after the edge
    (`ra_0100`, `adra_1`, `adra_2`), no decay rate on that first cycle
    (`ra_0100`), and a falling gate always taking two cycles (`ar_1`,
    `ar_2`). `SID/envelope`, `SID/exp_counter_reset` and the four
    `resid-test/env*` programs pass either way.
  - Spec guard: *gate edge*, *attack*, *#env3*, *exponential divider*,
    *gate falling with a step in flight* and *gate rising as the rate
    counter matches* in
    [`sid/envelope_spec.rb`](../spec/badline/sid/envelope_spec.rb). Its
    *#fast_forward* examples hold the batched catch-up to the same timing:
    between steps a span jumps from one match to the next, and the cycles
    around each step run whole.

## `.sid` tune banking

- A tune's init and play routines must run with the ROMs banked to match
  the address they live at, following libsidplayfp's iomap: `$37` below
  `$a000`, `$36` under BASIC, `$34` in the `$d000` I/O window, `$35` under
  the KERNAL. A routine below `$a000` gets `$36` too when the tune's image
  reaches under BASIC, as VSID does, since it may call into that part.
  Restore `$01` afterwards so the caller's banking survives. This entry is
  the rule, and it should outlive whichever code carries it.
- Derived against six OneLoad64 tunes (Galway, Tel, Gray, Dunn, Cooksey).
  Green Beret's init sits at `$9fe3` and calls its own code at `$aaca`,
  which forces the `$36` below `$a000`.
  `SIDFile#bank_for` is the one copy of the map: `Driver` wraps both calls
  in a `$01` save/bank/restore, and `BarePlayer#dispatch` pokes it before
  handing the CPU the stub.
- Spec guard, at both ends: *a tune living under the BASIC ROM* in
  [`audio/renderer_spec.rb`](../spec/badline/audio/renderer_spec.rb) (a
  fixture at `$a000` that reads peak=0 without the `$01` write), and the
  *#driver for a tune under BASIC* and *#bank_for* groups in
  [`storage/sid_file_spec.rb`](../spec/badline/storage/sid_file_spec.rb).
- The boot stub never returns to its caller: after `cli` it spins on
  `jmp *` (PSID and RSID). BASIC's READY loop reuses zero page `$19`–`$21`,
  which a tune owns. Wizball (Ocean Loader 1) keeps its music-enable flag
  in `$19` and goes silent when BASIC writes `$0a` there.
  - Spec guard:
    [`storage/sid_file/driver_spec.rb`](../spec/badline/storage/sid_file/driver_spec.rb).
