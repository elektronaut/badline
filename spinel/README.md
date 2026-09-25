# Spinel harness

[Spinel](https://github.com/matz/spinel) compiles a subset of Ruby ahead of
time to C. `lib/badline/` stays inside that subset, which
`spec/spinel_subset_spec.rb` enforces, so the emulator core builds with
Spinel unchanged. The programs here drive that build and check it against
CRuby.

- `boot.rb` boots the machine headless and types `print 6*7`, or attaches
  and autostarts a media file. It prints a `Badline::Checkpoint` every
  million cycles, then the screen, the cycle and instruction counts and
  the registers.
- `cpu_tests.rb` runs SingleStepTests cases against the CPU and checks
  registers, cycle counts, the bus trace and RAM.
- `convert.rb` samples the SingleStepTests JSON into the line format
  `cpu_tests.rb` reads, since the Spinel build has no JSON library. It runs
  on CRuby only.
- `lorenz.rb` runs the Wolfgang Lorenz chain with the same driver as
  `bin/lorenz` (`test/lorenz_chain.rb`) and prints what the run recorded,
  for CRuby to turn into baseline rows. See
  [The Lorenz chain](#the-lorenz-chain) below.
- `sidtests.rb` runs a list of SID testprogs with the same code as
  `bin/sidtests` (`test/sidtests_machine.rb`) and prints a baseline row per
  test. See [The SID testprogs](#the-sid-testprogs) below.
- `testbench.rb` runs VICE testbench tests with the same code as
  `bin/testbench` (`test/testbench_machine.rb`) and prints what each test
  left behind, for `bin/testbench` to score. See
  [The testbench](#the-testbench) below.
- `window.rb` opens an SDL2 window and plays the machine in it. It builds
  with Spinel only; see [A window](#a-window) below.
- `sig/` holds RBS seeds for types Spinel can't infer on its own.
- `check.rb` and `sidtests_check.rb` back the rake tasks below.

## Building

Build Spinel from source (`make deps && make`), then point `SPINEL` at the
compiler if it isn't on `PATH`:

```sh
SPINEL=~/src/spinel/bin/spinel rake spinel:build
```

That compiles `boot` and `cpu_tests` into `tmp/spinel/`. `SPINEL_CC`
passes a C compiler command through `--cc`. For instance
`SPINEL_CC="cc -DSP_RBS_CHECK"` checks the RBS seeds at runtime.

To build one harness by hand:

```sh
spinel -I lib --no-line-map --rbs spinel/sig spinel/boot.rb -o tmp/spinel/boot
tmp/spinel/boot [cycles] [timed_from] [media]
```

## Checking against CRuby

```sh
rake spinel:check
rake "spinel:check[vendor/OneLoad64-Games-Collection-v5/IK+.crt]"
rake "spinel:check[path/to/game.crt,40000000]"
```

`spinel:check` builds both harnesses, then runs each compiled binary and
the same harness on CRuby. It fails unless the outputs match: every
checkpoint, the screen, the counts and the registers for the boot, and
every SingleStepTests verdict. Without media it boots for 6M cycles. With
media it runs 23M cycles unless given a count. The first run converts 100
SingleStepTests cases per opcode into `tmp/spinel/cases.txt`, so it needs
`vendor/65x02` (`rake vendor:65x02`).

The checkpoint lines are the ones `bin/machine_diff` prints, so it can
name the first component that differs. Save the compiled build's
lines and run the same scenario against them on CRuby:

```sh
tmp/spinel/boot | grep " cpu=" > tmp/spinel/boot.txt
bin/machine_diff type --cycles 6000000 --against tmp/spinel/boot.txt
tmp/spinel/boot 23000000 3000000 game.crt | grep " cpu=" > tmp/spinel/game.txt
bin/machine_diff game.crt --cycles 23000000 --against tmp/spinel/game.txt
```

Both harnesses print timings. They show where the time goes but aren't a
benchmark, so use `bin/benchmark` and `bin/profile` for CRuby speed.

## The Lorenz chain

```sh
rake spinel:lorenz
rake "spinel:lorenz[whole]"
```

`spinel:lorenz` builds `lorenz` and runs the chain on it, checked row by
row against `test/baselines/lorenz.txt` as `rake regression:lorenz` checks
`bin/lorenz`. By default it runs the chain's four stretches, the ones
`rake regression:lorenz-1` to `lorenz-4` run, side by side, one process
each. `[whole]` runs the whole chain in one process instead. It fails on
any row that differs from the baseline, and on a stretch that ends short
or reports a different set of rows.

The compiled binary only emulates. It drives the chain with
`Lorenz::Chain` and `Lorenz::Disk` from `test/lorenz_chain.rb`, the same
code `bin/lorenz` drives it with: the LOAD log, the swap to `Disk4.d64`,
the space typed when a test halts for a key, and the checks for the end
of the chain. What it records goes to stdout, which the task keeps in
`tmp/spinel/lorenz-N.out`:

```
load OFFSET NAME        one per program the suite loaded
key OFFSET              one per key typed
result RESULT CYCLES
transcript LENGTH
...the transcript
```

`Lorenz::Run` in `test/lorenz_run.rb` turns that into rows on CRuby, where
the digests and the regexps are, and writes them beside the output as
`lorenz-N.txt`. `Lorenz.run_chain` does the work between the arguments and
that text, so it can be compiled as an extension later.

To run a stretch by hand:

```sh
spinel -I lib --no-line-map --rbs spinel/sig spinel/lorenz.rb -o tmp/spinel/lorenz
tmp/spinel/lorenz vendor/VICE-testprogs/general/Lorenz-2.15/Lorenz.d81 --resume rola --stop-after cmpix
```

## The SID testprogs

```sh
rake spinel:sidtests
rake "spinel:sidtests[8580]"
```

`spinel:sidtests` builds `sidtests` and runs the SID testprogs for a chip
on it, 6581 unless given 8580, and compares the rows against
`test/baselines/sid.txt` or `sid-8580.txt` as `rake regression:sid` and
`regression:sid-8580` compare `bin/sidtests`' rows. It splits the tests
into `SHARDS` lists (4 by default) of about the same total cycle budget
and runs one process per list side by side. It fails if a process fails
or leaves a test without a row.

CRuby reads the testlist, picks the tests for the chip and writes each
list to `tmp/spinel/spinel-sid-N.list` (`spinel-sid-8580-N.list` for the
8580):

```
sid 6581|8580       the chip every machine is built with
root PATH           the directory the test names are under
test CYCLES NAME    one per test, in the order to run them
```

The compiled binary only emulates. For each test it builds a fresh
machine, attaches the program and runs it until it reports through
`$D7FF` or runs out of its budget, with `SIDTests.exit_code` from
`test/sidtests_machine.rb`, the code `bin/sidtests` scores a test with. It
prints each test's row in the baseline format, which the task keeps in
`tmp/spinel/spinel-sid-N.out` and gathers into `spinel-sid.txt` in test
order. `bin/sidtests` boots once and forks each test from the booted
machine. The Spinel build can't fork, so it boots each test itself.
Attaching at power-on loads the program at the same cycle as attaching to
the booted machine, so the rows come out the same. `SIDTests.run_list`
does the work between the list and the rows, so it can be compiled as an
extension later.

`sidtests.rb` requires `debug_register.rb`, which reopens
`Badline::Computer`, `AddressBus` and `DebugRegister` to hand the debug
register's handler on as a value. Spinel refuses a block that reads a
local when it is passed on with an anonymous `&` into a constructor, as
`Computer#install_debug_register` passes it, and the handler
`SIDTests.exit_code` installs reads one.

To run a list by hand:

```sh
spinel -I lib --no-line-map --rbs spinel/sig spinel/sidtests.rb -o tmp/spinel/sidtests
tmp/spinel/sidtests tmp/spinel/spinel-sid-1.list
```

## The testbench

```sh
rake spinel:testbench
rake "spinel:testbench[testbench-cia]"
rake "spinel:testbench[all]"
```

`spinel:testbench` builds `testbench` and runs a `bin/testbench` suite on
it, `testbench` (`VICII/`) unless given another, and compares the rows
against the suite's baseline in `test/baselines/` as
`rake regression:<suite>` does. `[all]` runs `testbench`,
`testbench-cia`, `testbench-interrupts`, `testbench-irqdma`,
`testbench-cpu`, `testbench-carts` and `testbench-cia-new` in turn, and fails at the end if any
of them changed. `SHARDS` and `RESUME=1` work as they do for
`rake regression:<suite>`, and the rows land in `tmp/spinel/<suite>.txt`.

The task runs `bin/testbench --engine tmp/spinel/testbench`, so CRuby
keeps everything but the emulation: the testlist and its filters, the
shards, `--resume` and the progress file, and the scoring, down to
decoding the reference PNGs and writing the failure artifacts. It writes
each shard's tests to `<results>.engine-N` and starts one build process
per shard, which reads them one per line, as tab-separated fields:

```
KEY TYPE BUDGET CARTRIDGE PROGRAM DIRECTORY CIA    CARTRIDGE or PROGRAM empty if the test has none
```

The compiled binary only emulates. For each test it builds a fresh
machine with the CIAs the test asks for (`mos6526` or `mos6526a`), booted to the cycle where a program loads unless the test starts
from a cartridge, and runs the test with `Testbench::Execution` from
`test/testbench_machine.rb`, the code `bin/testbench` runs a test with in
process. It prints what the test left behind, which `Testbench::Engine`
(`test/testbench_engine.rb`) reads and hands to the same scoring:

```
test KEY
exit CODE|none
cycles CYCLES
text            then the 25 lines of the text screen, for an exitcode test
screen          or 272 lines of 384 hex palette indices, for a screenshot test
done
```

`bin/testbench` forks each test from a machine it booted once. The build
can't fork, so it boots each test itself. A test that outlives its
deadline is killed with its build process, and one the build dies on gets
a crashed row, as in process. The shard's other tests carry on in a new
process. `Testbench.run_test` does the work between a test's line and its
record, so it can be compiled as an extension later.

`--engine` takes `bin/testbench`'s filters like any other run:

```sh
spinel -I lib --no-line-map --rbs spinel/sig spinel/testbench.rb -o tmp/spinel/testbench
ruby --yjit bin/testbench --engine tmp/spinel/testbench VICII/spritegap/spritegap3.prg
```

## A window

`window.rb` is a spike: it shows that a Spinel build can be played in a
window, without ruby-sdl2. It boots the machine, or attaches and
autostarts a media file, and runs it a PAL frame at a time: it polls SDL
events, clocks 19,656 cycles, queues the SID's samples when sound is on,
repacks the lines the VIC changed into a streaming texture, presents it and
waits.

It calls libSDL2 through Spinel's FFI (`ffi_func`, `ffi_buffer` and the
`ffi_read_*`/`ffi_write_*` accessors), so it needs SDL2 installed
(`brew install sdl2`) and doesn't run on CRuby. `rake spinel:build` leaves
it out for that reason. Build and run it by hand:

```sh
spinel -I lib --no-line-map --rbs spinel/sig spinel/window.rb -o tmp/spinel/window
tmp/spinel/window [media] [frames] [paced|unpaced] [sound] [screenshot.bmp]
tmp/spinel/window vendor/OneLoad64-Games-Collection-v5/IK+.crt sound
```

The arguments can come in any order: a number is the frame count, a
`.bmp` path the screenshot, and anything else the media.

- The host keyboard maps by position (SDL scancodes, US layout) onto the
  C64 keys `GUI::KeyMap` gives the same keys by name. Esc is RUN/STOP.
- Tab switches to joystick mode and back. As in the SDL front end's
  joystick mode, the arrow keys and space drive joystick 2 and WASD and
  left shift drive joystick 1. F9 swaps the two, for games that read
  port 1, and the title bar names the port the arrows drive.
- `sound` plays the SID, and F10 mutes and unmutes it. Sound is off
  unless asked for, as in `exe/badline`.
- `frames` quits after that many frames, and `unpaced` drops the 50 Hz
  pacing, so the frame rate shows how much headroom there is (the display
  refresh still caps it).
- A screenshot path saves the last frame as the renderer drew it, read
  back before it is presented.

Every 50 frames it prints the frame rate, the time per frame spent on
events, emulation, audio, the texture upload, presenting and waiting, and
the slowest frame's work. With sound on it adds the samples queued per
second, the queue's range, and the underruns and dropped samples so far.

### Sound

The SID records at the rate the audio device opens with, 44.1 kHz unless
the device prefers another, and each frame's samples go onto SDL's audio
queue (`SDL_QueueAudio`). The pacing follows `exe/badline --sound`:

- The device starts once the queue holds 80 ms.
- Once the device plays, it is the clock. Each frame waits until the queue
  is down to 80 ms instead of waiting out 20 ms, so the machine runs at
  the device's pace and the queue can't drift. That is a PAL frame rate of
  about 50.1 Hz rather than 50.
- Below real time the queue runs dry. The device then stops until the
  queue holds 80 ms again, so the sound stutters in silent gaps rather
  than slowing down or changing pitch, and the first underrun prints a
  notice.
- Unpaced, a frame whose samples would take the queue past 250 ms is
  dropped whole.
- Muted, or when the device won't open, the samples are dropped and the
  frames go back to the 20 ms timer.

Spinel hands the queue an `Array` of Integers as 64-bit words, so each word
packs four signed 16-bit samples, and a frame's last one to three samples
wait for the next frame.

Spinel hands an `Array` of Integers to C as 64-bit words, and a texture
wants 32-bit pixels, so the harness packs two neighbouring pixels into
each word of an `XRGB8888` texture, where the top byte of each pixel is
ignored.

It links against `-L/opt/homebrew/lib` and `-L/usr/local/lib`; elsewhere,
pass the library path through `--cc` (`--cc="cc -L/path/to/lib"`). There
is no gamepad, mouse or paddle support yet.
