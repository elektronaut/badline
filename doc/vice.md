# VICE

badline checks itself against VICE 3.10's emulators, run as black boxes:
their command lines, their remote monitor, their screenshots, sound
recordings and snapshots. VICE's source isn't read for this, and badline
holds none of its code, ROMs or data. The VICE-testprogs repository is a
separate project: its testlists, hooks and reference screenshots are what
`bin/testbench` runs (see [CLAUDE.md](../CLAUDE.md#oracles)). This page
covers what each emulator checks, how they're driven, what they get
wrong or leave out, the `.vsf` modules badline reads and writes, and
where badline knowingly does otherwise.

- [Which emulator checks what](#which-emulator-checks-what)
- [Driving them](#driving-them)
- [Quirks and bugs](#quirks-and-bugs)
- [Snapshot modules](#snapshot-modules)
- [Where badline differs](#where-badline-differs)

## Which emulator checks what

| Emulator | Machines | What it checks |
| --- | --- | --- |
| `x64sc` | C64, every `--model` | The testbench's published results, runs from an exact start, and `.vsf` both ways |
| `x128` | C128 | The VDC (`-exitscreenshot`), the MMU and both modes' boot screens. Not the C64-mode VIC-II or 2 MHz (below) |
| `xvic` | VIC-20, PAL and NTSC | The 6560's raster count and interlace, the VIC-I's sound by recording, the power-on RAM, cycle-timed writes by screenshot, `.vsf` both ways |
| `xplus4` | Plus/4, C16, C116 | The TED's fetches and picture by screenshot and trace probe, its sound by recording, the 1551's load time, the ACIA's registers and timing |
| `xpet` | Every PET and CBM model, the SuperPET | Boot banners and BYTES FREE, frame lengths, the CRTC's frame, the IEEE-488 drives' listings and error channels, `.vsf` both ways |
| `xcbm2` | The B series | Boot, the CRTC's frame, the burn-in disk on a true 8050, `.vsf` both ways |
| `xcbm5x0` | The P500 | Boot, the VIC-II's cycle stealing, `.vsf` both ways |
| `c1541` | Disk images | Blank `.d67` and `.d90` images, which `D67Image` and `D90Image` format alike byte for byte (their specs' fixtures), and listing and validating the images badline's true drives write |
| `petcat` | BASIC text | `petcat -w2 -o out.prg in.txt` turns a BASIC listing into a `.prg` |

VICE has no KIM-1. No row of VICE's testlists runs the PET's IEEE-488
floppies and hard disks, the SuperPET's 6809 or a 1581, so those rest
on badline's own drive scenarios and specs, the schematics and the ROMs.

`x128` runs older VIC-II emulation than `x64sc`: in its results for the
C64-mode testlist (r45942) about 180 rows that `x64sc` passes fail, among
them 52 `spritesplit`, 25 `irqdma` and 18 `reutiming2` rows, and it fails
all 33 `d030tester` and all 4 `2mhzVIC` screenshot rows in C128 mode. So
`testbench-c128c64` is held to badline's own C64C verdicts, and the 2 MHz
rows to the testprogs' references, which come from real machines.

## Driving them

- Run each by its full path, such as `/opt/homebrew/bin/x64sc`. A bare
  `x64sc` failed with "argv[0] is NULL". Headless, `x64sc` needs
  `-console`, or it aborts for want of GSettings schemas.
- **Exit codes.** `-debugcart` gives the program a debug register, and a
  write to it ends the run with that exit code, `$00` for a pass and
  `$FF` for a fail. It is `$D7FF` on the C64 and the C128, `$910F` on
  the VIC-20, `$FDCF` on the 264 series, `$8BFF` on the PET and `$DAFF`
  in segment 15 on the CBM-II. `-limitcycles N` ends a run that hasn't
  written it, as a timeout. `bin/testbench` installs the same register
  (`install_debug_register`) and the same cycle budgets.
- **Screenshots.** `-exitscreenshot` writes a PNG as the run ends
  (`-exitscreenshotvicii` for the C128's 40 columns, with
  `-exitscreenshot` its VDC). Sizes: 384x288 PAL and 384x242 NTSC on
  `xplus4`; 384x217 for the PET's discrete board, 384x273 for 40 CRTC
  columns and 704x273 for 80 on `xpet`; 704x267 for a 600 and 704x367 for
  a 700 on `xcbm2`; 384x272 PAL and 384x247 NTSC on `xcbm5x0`. The
  testbench hooks compare from (32,35) on the C64, the 264 and the
  CBM-II ((32,23) on an NTSC `xcbm2`), (32,33) on the PET, and (96,48)
  PAL and (40,22) NTSC on the VIC-20.
- **Typing.** `-keybuf` types into the keyboard buffer once the machine
  is up. On `xpet` keep each line under 80 characters. The monitor's
  `keybuf` with `\"` escapes typed nothing there.
- **The remote monitor.** `-remotemonitor -remotemonitoraddress
  ip4://127.0.0.1:PORT` takes monitor commands over a socket: registers
  (`r`, and `r PC = $xxxx` to set one), memory (`m`, `bsave`), `io`,
  breakpoints, the stopwatch, `dump` and `undump` for snapshots, and
  `resourceget "Name"`, with the name quoted. A breakpoint hit is
  reported only after the next command, so poll with `r`, then `x`.
  Numbers are hex unless marked, counts too (`ignore 1 36` skips 54
  hits). Its `CYC` is badline's column at the instruction boundary plus
  one. `-moncommands` with the GTK monitor waits for input at reset and
  hangs; `-nativemonitor` with the commands on stdin runs them.
- **An exact start.** `x64sc`'s autostart adds a random delay, so one run
  of a test that depends on where it starts is no reference: the
  published results show `irq-ack-vicii` passing 15 runs in 16 for that
  reason. To compare from the same place, park the CPU in a loop at
  `$C000` in both emulators, break on its first fetch on a chosen raster
  line, and resume at the program's entry through a stub of N cycles.
  badline and `x64sc` started this way agreed cycle for cycle over 91
  start positions.
- **Power-on RAM.** `xvic -default -memory all -initbreak reset
  -moncommands cmds.txt`, with `bsave "path" 0 0000 1fff` and `quit` in
  the file, dumps RAM before the KERNAL touches it.
- **Sound.** `-sounddev wav -soundarg f.wav +autostart-warp` records
  from power-on in real time. `-sounddev dummy -soundrecdev wav` writes
  an empty file, because autostart turns warp on. The Homebrew `xpet`
  has no WAV driver.
- **Models.** Use `-model vic20ntsc` for an NTSC VIC-20: `xvic -ntsc`
  keeps the PAL KERNAL. `x64sc` 3.10's default VIC-II is the 8565, so a
  6569 snapshot needs `-model c64`. The 264's RAM expansions are
  `-memoryexphack 1|2|3` (Csory 256K, Hannes 256K, Hannes 1M);
  `-ramsize` takes only 16, 32 and 64. The B series' autostart needs a
  device on 8 (`-busdevice8 +drive8truedrive`).
- **Paths.** `xpet`'s `-editor` and `-autostart` need absolute paths. A
  relative one gives a blank or stuck screen.
- **True drives.** `-drive8type T -drive8truedrive` with the disk as `-8`.
  `-attach8ro` is a flag of its own: `-attach8ro -8 <img>` mounts an
  image write-protected.

## Quirks and bugs

What follows was observed from outside. Each is a reason a row, a
recording or a snapshot from that emulator isn't a reference for the
part named.

### x64sc

- `undump` of a snapshot with any module short of what it expects resets
  the machine without saying so, beyond "pre 2.4.30 snapshot" in the log.
  MAINCPU 1.4 is 103 bytes, and 3.10 reads that layout whatever the minor
  version.
- `-limitcycles` below a snapshot's own clock exits before a frame.
- Its true 1581 caches a track and writes it back later, so a run that
  formats and exits through the debug register leaves the `.d81`
  unwritten. Send `I0` and wait before the exit.
- In the remote monitor, a condition on `RL` works, but `RL == … && CY
  >= …` never fired.

### xvic

- Its remote monitor stopped answering a new connection after an earlier
  client disconnected. Drive a session over one socket, from one script
  that starts `xvic` and stops it by its PID.
- `xvic -ntsc` keeps the PAL KERNAL (above).
- Its monitor's `LIN`, and so a breakpoint's `RL`, stays modulo 261
  under interlace, while `$9003`/`$9004` and its own snapshots follow
  the 263- and 262-line fields: a frame after a long field shows `LIN`
  2 more than the line, and so on.
- `undump` of a snapshot taken in an interlaced frame ends that frame
  after 261 lines, its own snapshots too: the field after it starts 2
  lines early after a long field and 1 after a short one. The fields
  alternate as before from there.
- It refuses a snapshot whose file isn't in format 3.1, and resets on the
  first instruction without `FSDRIVE`, `TAPEPORT`, `JOYPORT0`,
  `JOYSTICK0` and `USERPORT`. Without any drive module it keeps its own
  drives, but with `DRIVE8` and no `DRIVECPU0` and the 1541's VIAs it
  resets too.

### xplus4

- Its default drive 8 is a 1551, on the `plus4`, `c16` and `c16ntsc`
  models. `Plus4/tcbm/test.prg` passes only with it.
- It clocks a SID card only with a real sound device: with `-sounddev
  dummy`, OSC3 reads 0.
- r45284 shows a bitmap fetched from empty ROM space wrongly against the
  photo of a real machine in `Plus4/openmem`.
- It steps the TED's line about 3 single clock cycles after the
  datasheet's decode, and fails `trap10`, `trap12` and `trap14` of the
  Lorenz suite's plus4 build (below).
- Its C16 model loads no tape, not even one it saved itself, and never
  asks for PLAY: LOAD goes straight to SEARCHING. Its Plus/4 model loads
  the tapes badline saves for the 264 (#704).
- It writes a version 2 `.tap` with one byte per whole wave (`$36`, `$6B`,
  `$D5`, version 1's values), where the format and badline give one per
  half wave (`$1A`, `$35`, `$6A`). Both time the same signal.

### xpet

- **Its 6809 runs with the wrong instruction timing.** Single-stepped
  stopwatch deltas: BSR 5, PULS D 5, SUBD # 1, LDX # 0, ABX 2, JSR [,X]
  8, LEAS 3, CLRA 1, 25 cycles for a sequence the datasheet times at
  about 41. `-limitcycles` never fires under `-cpu6809`, so take 6809
  screenshots through the monitor. Its 6809 runs one cycle per PET cycle,
  16,650 cycles between the Waterloo ROM's frame interrupts.
- **The SuperPET has no software CPU select and no write protect.** With
  `-cpuprog` it boots the 6502, and no write to `$EFF4`-`$EFFF` starts
  the 6809. Writes to the bank RAM stick after any one bit written to
  `$EFF4`-`$EFFB`, with the switch at 6502 or at PROG. The
  CPU switch (`CPUswitch`) is read only at reset. `$EFFD` acts as
  `$EFFC`. Its 6702 at `$EFE0` answers 16 reads with no write with `$D6`,
  and writes and reads in turn of 0 to 15 with `d6 c6 c6 56 56 44 44 d6
  d6 84 84 15 15 01 01 91`, as badline's does. It saves the 6702 in
  PETMEM's settings (below), and every other PET's settings hold one as
  RES leaves it.
- **Its 2040 isn't usable.** On a 4032 or a 3032 `OPEN15,8,15` hangs and
  `LOAD"$0",8` never finishes; on a 2001 the directory comes back empty.
- **It runs only the interface processor of an IEEE-488 drive** with two
  processors: the 8050, 8250, SFD-1001, 4040, 3040, 2040 and its type
  9000. The floppy controller and the hard disk's SASI side run at a high
  level, in a module `FDC0`, and the 9000 loads no SASI ROM. Nothing in
  `xpet` times the second processor, the mechanism or SASI. The monitor
  reaches no device for the controller.
- On `-model 2001` its screen mirror takes the `$8BFF` write before the
  debug cartridge sees it, so `pet-pass.prg` times out with PET-PASS on
  the screen; `+screen2001` gives exit 0. On `-model 8296` the same row
  times out.
- It patches the 2001's BASIC 1 ROM at start ("patching 2001 ROM to make
  IEEE488 work!"), so a 2001's LOAD from a drive in `xpet` is no
  reference for the stock ROM.
- It repeats a CRTC row's character lines past the eighth, where the
  8032029 and 8032087 schematics blank them. Its results mark `crtc3`,
  `crtc10` and `crtc13` as errors, and `crtc13`'s reference shows `xpet`'s
  own power-on RAM. Its 8296 runs the 8032's editor, 901474-04 dated
  0283.
- Its discrete board's monitor `LIN` and `CYC` run on a 20,032-cycle
  raster, out of step with its 16,640-cycle retrace. `-pal` and `-ntsc`
  change nothing measurable on a PET.
- `-autostart` refuses ("Autostart is not available on this setup") once
  `-editor` names a ROM it doesn't know by checksum, and `-initbreak
  ready` never breaks then. Load through the monitor instead
  (`l "path.prg" 0`, `g 0410`), or break on a store.
- `undump` wants snapshot format 1.0, and with `FSDRIVE`, `TAPEPORT` or
  `USERPORT` missing it loads, then resets on the first instruction
  stepped. A snapshot it saved while its true 2031 searched for a file
  never finishes the LOAD, its own included; mid-transfer ones resume.
  Its CRTC loses a few lines on opening any snapshot.
- `-autostart` with `-limitcycles` sometimes times out on a 3032; a rerun
  passes.

### xcbm2

- **It ticks the mains once a frame of its CRTC**, as vertical sync
  ends, whatever its mains is set to: 40,064 cycles apart on a 600 at
  50 Hz, where 50 Hz is 40,000, and its 700 has no 60 Hz. Every 610 run,
  `-ntsc` and `-power60` included, used the 50 Hz CRTC table. Its 710
  defaults to `-ntsc -power60`.
- **It has no DRAM refresh**, so the burn-in disk's 6526 timer cell
  reads BAD on its 610, after one cycle of the test and after three.
- **The 610 + 2031 TALK race reproduces in it.** With a true 2031,
  `LOAD"$",8` typed at some phases after power-on gives `?FILE NOT
  FOUND`: the KERNAL's TALK puts DAV about 44 cycles after ATN, and the
  2031's DOS raises NRFD while ATNA is still set. `xcbm2` fails at
  `-keybuf-delay` 0 and 10 to 50 and lists at 5 and 100, as badline fails
  at some phases and not others. The first `LOAD"$"` after power-on gives
  FILE NOT FOUND in it too.
- **It reads the wrong top bits of TPI1's port C in mode 1.** At READY
  on a 610, with CR `$E3` (CA low, CB high) and no interrupt, its monitor
  reads `$C0` at `$DE02`, though its own `io de00` says CA is low and no
  interrupt is active. The 6525 datasheet reads the pins there, CB, CA
  and IRQ, so badline reads `$A0`: CB high, CA low and IRQ released.
- It saves no mains and no TPI priority stack. Its cursor blinks 32
  fields on and 32 off, where the 6845 blinks 16 and 16. Opening any
  snapshot costs it a couple of hundred cycles of its CRTC.

### xcbm5x0

- It runs VICE's line-based VIC-II, not `x64sc`'s, so it reads the
  raster a cycle off now and then.
- It ticks the mains every 19,656 cycles, a PAL frame, on NTSC too:
  about 52 Hz, where the NTSC 510's mains is 60.
- A sprite's phi2 bytes in text mode read the KERNAL from `$E040` on,
  where the FPLA puts the video bus.

### c1541

- It refuses `d60` as an image type, but formats a zero-filled `.d90` of
  a D9060's size.

## Snapshot modules

No VICE document lays out the `.vsf` modules, so badline's readers and
writers in `lib/badline/snapshot/vice/` were mapped from dumps: known
pokes into memory, register writes and breakpoints at known delays,
compared with the monitor at the same moment. Each file's doc comment
gives its module's layout and what maps across.
[snapshots.md](snapshots.md#vice) covers what each emulator opens and
what it leaves out.

| Emulator | Machine name, format | Modules (files) |
| --- | --- | --- |
| `x64sc` | `C64SC`, 2.0 | MAINCPU 1.4 (`main_cpu.rb`), C64MEM (`c64_mem.rb`), CIA1 and CIA2 (`cias.rb`, `cias_import.rb`), SID and SIDEXTENDED (`sid_registers.rb`, `sid_extended.rb`), VIC-II (`vicii.rb`, `vicii_import.rb`), REU1764 (`reu1764.rb`), and the empty ports it refuses a file without (`peripherals.rb`) |
| `xpet` | `PET`, 1.0 | MAINCPU 1.3 (`pet_cpu.rb`), PETMEM 1.3 (`pet_mem.rb`), CRTC 1.2 (`pet_crtc.rb`), PIA1 and PIA2 (`pet_pias.rb`), VIA 2.2 (`pet_via.rb`), CPU6809 1.1 (`pet_cpu.rb`) and Acia1 (`cbm2_acia.rb`) for the SuperPET, a 2031 (`pet_drive.rb`) and the two-processor drives (`pet_drive8050.rb`) |
| `xcbm2` | `CBM-II`, 1.0 | The PET's CPU, CBM2MEM 1.0 (`cbm2_mem.rb`), CRTC 1.2 (`cbm2_crtc.rb`), TPI1 and TPI2 (`cbm2_tpi.rb`), Acia1 1.1 (`cbm2_acia.rb`), the C64's CIA and SID, the mains (`cbm2_mains.rb`) |
| `xcbm5x0` | `CBM-II-5x0`, 0.0 | As `xcbm2`, with its own VIC-II 1.3 (`p500_vicii.rb`) and C500DATA, the cycles to the mains' next tick (`p500.rb`) |
| `xvic` | `VIC20`, 3.1 | MAINCPU 1.4 (`vic20_cpu.rb`), VIC20MEM 1.1 (`vic20_mem.rb`), VIC-I 0.4 with the colour RAM (`vic20_vici.rb`), VIA1 and VIA2 (`pet_via.rb`), and the empty ports it resets without (`vic20.rb`) |
| `x128`, `xplus4` | `C128` 1.0, `PLUS4` | None read or written |

Facts the layouts rest on that the files' comments state in full:

- CBM2MEM's header is the RAM board's size in 128K units, the RAM mapped
  into segment 15 beyond the B series' own (`$40` on a P500), the model
  line (0 a 700, 1 a 600 at 60 Hz, 2 a 600 at 50 Hz) and both segment
  registers.
- A TPI module is the eight registers, then the latched interrupts and CA
  and CB. In mode 1 `xcbm2` keeps the latches in PRC's low five bits and
  the mask in DDRC's.
- PETMEM's 24 bytes of settings at the end hold the SuperPET's 6702 from
  the fifth byte: the byte it reads, the last write that shifted it, 1
  while the last write left D0 clear, then a little-endian word per data
  line, bit k the XOR of stages k and k + 1 of its shift register. Mapped
  from dumps after 56 writes to `$EFE0`, which all decode to the
  registers badline's 6702 has after the same writes.
- CPU6809 1.1 is an 8-byte clock, X, Y, U, S and PC, DP, CC, A and B,
  then 5 zero bytes.
- xvic's MAINCPU 1.4 is 83 bytes, x64sc's without the BA flags and the
  two clocks after the interrupt counts. VIC20MEM 1.1 is a byte of the
  blocks that hold RAM (bit 0 the 3K, bits 1-3 BLK1-BLK3, bit 5 BLK5),
  both data lines' last bytes, a byte badline leaves at 0, then
  `$0000`-`$03FF`, `$1000`-`$1FFF`, the 3K and the blocks in turn.
- VIC-I 0.4 holds the interlace flag and field, the frame's first clock,
  the beam, the text window's state, its counters and the line's fetch
  state, the light pen, the colour RAM, the registers and xvic's picture
  (1,648 by 632 bytes on PAL, 1,536 by 532 on NTSC). xvic's monitor's
  cycle at an instruction boundary is badline's column.
- The two-processor drives all save the 8050's set: DRIVE8 2.0,
  DRIVECPU0 1.3 for the interface processor, RIOT1D0 and RIOT2D0, FDC0
  (8 bytes) and FSDRIVE. DRIVE8's type word tells the models apart, and
  the SFD-1001's and the 9000's DRIVE8 holds one drive. A RIOT module's
  timer flag, bit 7, is set only while the timer's interrupt is enabled.

## Where badline differs

Where VICE and a schematic, a datasheet or a test from real hardware
disagree, badline follows the hardware source. These are the places a
program can tell:

- **The CBM-II's DRAM refresh**, a cycle in about 21, which `xcbm2`
  lacks. It passes the burn-in's timer cell, and a program badline runs
  on from an `xcbm2` snapshot runs about 5% slower than in `xcbm2`.
  `refresh: false` builds a B series without it, for comparing with
  `xcbm2`. [CBM-II DRAM refresh](pinned-behaviour.md#cbm-ii-dram-refresh).
- **The TED's line step and the 7501's port**: the datasheet's decode,
  about 3 cycles ahead of `xplus4`, and the trap tests `xplus4` fails.
  [TED beam and the 7501 port](pinned-behaviour.md#ted-beam-and-the-7501-port).
  Where the TED's fetches, picture and sound follow `xplus4` over the
  datasheet, such as a voice's 1023 - x period, the same doc says so
  under the TED's entries.
- **The 6809's timing** follows the MC6809E datasheet and the neetandev
  vectors, never `xpet`.
  [6809 dead cycles](pinned-behaviour.md#6809-dead-cycles).
- **The SuperPET's CPU select and write protect** through the system
  latch at `$EFF8`, after the 324037 schematic, Levak and Fachat
  (`PET::SuperPET::Board`). A program that uses them runs otherwise on
  `xpet`. With SW2 at PROG, badline starts the 6809 at power-on, as the
  latch's clear bit 0 picks it; `xpet` boots the 6502.
- **A CRTC PET's rows taller than eight lines** blank the lines past the
  eighth, after the schematics, where `xpet` repeats them
  (`PET::CRTCVideo`). Don't take `xpet` as a reference for tall rows.
- **A 6525's port C in mode 1** reads the CB, CA and IRQ pins in its top
  three bits, after the datasheet (`Chips::TPI`): `$A0` at a B series'
  READY, where `xcbm2` reads `$C0`.
- **The P500's sprite bytes in phi2** come from the video bus the FPLA
  describes (`Chips::VIC::Bank#peek_sprite`), not the KERNAL bytes
  `xcbm5x0` returns.
- **The PET's power-on RAM** is zeros. `crtc13`'s reference shows
  `xpet`'s own pattern, and no dump of a real PET's is known.
- **The VIC-I's sound**: its volume scales the output linearly, where
  `xvic`'s doesn't, and its loudness and output stage are fitted, not
  pinned. [VIC-I sound](pinned-behaviour.md#vic-i-sound).
