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
- [CIA 6526 timer pipeline](#cia-6526-timer-pipeline)
- [CIA serial shift register](#cia-serial-shift-register)
- [6510 I/O port](#6510-io-port)
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
  - A comparator hit in K..K+11 shows nothing.
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
  - The hold is pinned by `vicii_reg_timing` (71 → 127 px without it). The
    address mix is pinned by `modesplit` (348 → 502 px) and `videomode-v`,
    `-x` and `-y` (6/10/1 → 14/14/9 px).
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
    takes it from 71 to 103 px (from pass to 32 px once the side border
    compares see CSEL late), and `videomode-z`, a `$7b` → `$3b` fall in
    RAM, goes from 2 to 5 px. `videomode-x` makes the same fall in RAM and
    would prefer the hold (10 → 2 px), but its readme says its reference
    doesn't match every 6569 capture. VICE holds BMM only.
  - Spec guard: *drops a falling ECM at once when the access left RAM* and
    *holds a falling ECM when the access left the character ROM* in
    [`vic_spec.rb`](../spec/badline/vic_spec.rb).
- The byte a group draws loads into the shift register at pixel XSCROLL,
  and that XSCROLL is the one the **column before** saw. It is latched in
  each g-access column with the vertical border open (VICE
  `xscroll_pipe`), so a `$d016` write shows a column later than a colour
  or mode write in the same cycle.
  - Pinned by `sbsprf24-163`/`-164` (34/42 px → pass, 40/44 without it),
    `modesplit` (348 → 444) and `vicii_reg_timing` (71 → 791), and by
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
  - Pinned by `modesplit` (348 → 1222 px painting whole groups, 716 with
    MCM read at pixel 4), the `videomode` rows and `vicii_reg_timing`
    (71 → 377).
  - `videomode2` and `videomode-y` disagree on where a falling BMM shows:
    pixel 6 in `videomode2`, pixel 5 in `videomode-y` and in `modesplit`'s
    ECM+BMM → ECM split. The readme says these delays vary with the chip
    and its temperature. badline keeps VICE's pixel 6, which passes
    `videomode2` and leaves `videomode-y` 1 px off and all 48 px left in
    `modesplit`, one pixel on each of its first-section lines.
  - Spec guard: [`vic/graphics_shifter_spec.rb`](../spec/badline/vic/graphics_shifter_spec.rb),
    one example per pixel, and *a mode change inside a group* in
    [`vic/sequencer_spec.rb`](../spec/badline/vic/sequencer_spec.rb).
- The pixels XSCROLL keeps from the previous byte take the **current**
  colour registers: a `$d021`–`$d024` write repaints that byte before it
  shows. The `ColorPatches` +1 px still applies on top.
  - Pinned by `modesplit` (348 → 414 px without it) and
    `vicii_reg_timing` (71 → 283). `colorsplit` (64 px → pass) and
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
- The 6569's offset is 2 half-pixels and the 8565's is 1, so
  `lp-trigger/test2new`, which wants the 8565, would fail by design.
  badline models only the 6569, and `bin/testbench` skips `vicii-new` rows.
- Pinned by `lplatency`, `lp-trigger`, and the `fldscroll` tests, which sync
  through the light pen instead of the double IRQ.

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
- The modelled revision is the **6526**, not the 6526A, matching
  `Lorenz.d81`. That is all the `(*1)` cells of `cia1ta`/`cia1tb` measure,
  and it is an ICR difference, not a counter one. Those cells read the ICR
  on the very cycle the underflow flag rises, so the source bit is up while
  IR is not: they read `$01`/`$02`, where a 6526A reads `$81`/`$82`. Counter
  readback is identical on both revisions. `Lorenznew.d81` expects the
  6526A and must not be mixed in.
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

## SID oscillator

- The phase accumulator powers on at `$555555` (all bits high, with the odd
  ones stored inverted) and survives reset. `SID/osc3-wave0` only reads the
  documented `$00`/`$ff` because of it.
  - Pinned by `SID/oscinit` (all three).
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
  new waveform the same: noise combined with anything but pulse alone.
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
- The test bit does not clear the LFSR. It stalls it halfway through a
  shift with bit 22 forced high. While the bit is held, every bit bleeds up
  to `$7fffff` over `$8000` cycles (`SID/wf12nsr` reads `$ff` off one). On
  release, one bit clocks in. Before it does, the old waveform's output is
  written back only for some waveform changes. Noise has to have been
  combined before the release and still be selected after it. A change to
  noise alone writes nothing back unless all four waveforms were selected
  before. A change to pulse+noise writes nothing back. On the 6581, trading
  triangle for sawtooth or back writes nothing back. The rule follows
  libresidfp's `do_writeback`.
  - Pinned by `SID/wb_testsuite` (the `9`/`A`/`D`/`E`→`8` rows on both
    chips, and the 6581's `9`↔`A`, `9`/`A`→`C` and `D`→`A` rows) and by
    `SID/noisewriteback`'s `noise_writeback_test1`.
  - Spec guard: *as the test bit falls* in
    [`sid/waveform_spec.rb`](../spec/badline/sid/waveform_spec.rb).
- A combined waveform shorts the shapers onto the lines the oscillator reads
  back. A low top bit reaches the accumulator MSB through the sawtooth
  switch and clears it (`SID/osc_topbit`, all three). With noise selected,
  the result is written into the LFSR, where a bit pulled low never comes
  back. Together these run Dag Lem's fast LFSR reset exactly as documented:
  three `$b8`/`$b0` pairs zero the register, and 18 `$88`/`$80` pairs set
  bits 0–17.
- Waveform 0 leaves the DAC input floating. It holds the last value a shaper
  drove onto it and drains to `$000` after `$4000` cycles.
  - Pinned by `SID/osc3-wave0`. `SID/oscinit`'s `allinit` pins the power-on
    `$00`, before anything has driven the line.
- The 8580 delays the triangle and sawtooth shapers by half a cycle. OSC3
  latches in the first phase of the clock, so it reads them a whole cycle
  late, while pulse and noise still mask the value on time. The audio output
  is not delayed. This follows libsidplayfp's `tri_saw_pipeline`.
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

## `.sid` tune banking

- A tune's init and play routines must run with the ROMs banked to match
  the address they live at, following libsidplayfp's iomap: `$37` below
  `$a000`, `$36` under BASIC, `$34` in the `$d000` I/O window, `$35` under
  the KERNAL. Restore `$01` afterwards so the caller's banking survives.
  This entry is the rule, and it should outlive whichever code carries it.
- Derived against six OneLoad64 tunes (Galway, Tel, Gray, Dunn, Cooksey).
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
