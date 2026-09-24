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
- `window.rb` opens an SDL2 window and plays the machine in it. It builds
  with Spinel only; see [A window](#a-window) below.
- `sig/` holds RBS seeds for types Spinel can't infer on its own.
- `check.rb` backs the rake tasks below.

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

## A window

`window.rb` is a spike: it shows that a Spinel build can be played in a
window, without ruby-sdl2. It boots the machine, or attaches and
autostarts a media file, and runs it a PAL frame at a time: it polls SDL
events, clocks 19,656 cycles, repacks the lines the VIC changed into a
streaming texture, presents it and waits out the rest of the 20 ms.

It calls libSDL2 through Spinel's FFI (`ffi_func`, `ffi_buffer` and the
`ffi_read_*`/`ffi_write_*` accessors), so it needs SDL2 installed
(`brew install sdl2`) and doesn't run on CRuby. `rake spinel:build` leaves
it out for that reason. Build and run it by hand:

```sh
spinel -I lib --no-line-map --rbs spinel/sig spinel/window.rb -o tmp/spinel/window
tmp/spinel/window [media] [frames] [paced|unpaced] [screenshot.bmp]
tmp/spinel/window vendor/OneLoad64-Games-Collection-v5/IK+.crt
```

- The host keyboard maps by position (SDL scancodes, US layout) onto the
  C64 keys `GUI::KeyMap` gives the same keys by name. Esc is RUN/STOP.
- Tab switches the arrow keys and space over to joystick 2 and back, as
  the SDL front end's joystick mode does.
- `frames` quits after that many frames, and `unpaced` drops the 50 Hz
  pacing, so the frame rate shows how much headroom there is (the display
  refresh still caps it).
- A screenshot path saves the last frame as the renderer drew it, read
  back before it is presented.

Every 50 frames it prints the frame rate and the time per frame spent on
events, emulation, the texture upload, presenting and waiting.

Spinel hands an `Array` of Integers to C as 64-bit words, and a texture
wants 32-bit pixels, so the harness packs two neighbouring pixels into
each word of an `XRGB8888` texture, where the top byte of each pixel is
ignored.

It links against `-L/opt/homebrew/lib` and `-L/usr/local/lib`; elsewhere,
pass the library path through `--cc` (`--cc="cc -L/path/to/lib"`). There
is no sound, joystick port 1, gamepad or mouse yet.
