# The native badline

`badline` built with [Spinel](https://github.com/matz/spinel), which
compiles the emulator core ahead of time to C, fast enough to play games
in real time. It plays the machine in an SDL2 window, reaching libSDL2
through Spinel's FFI (`ffi_func`, `ffi_buffer` and the
`ffi_read_*`/`ffi_write_*` accessors) rather than ruby-sdl2, so it builds
with Spinel only and doesn't run on CRuby. `exe/badline-ruby` is the same
emulator on CRuby.

## Building

Build Spinel from source (`make deps && make`) and install SDL2
(`brew install sdl2`, `apt install libsdl2-dev`), then:

```sh
SPINEL=~/src/spinel/bin/spinel rake native:build
tmp/native/badline --version
```

That compiles `native/badline.rb` into `tmp/native/badline`. `SPINEL`
names the compiler if it isn't on `PATH`, and `SPINEL_CC` the C compiler
command. The task finds libSDL2's directory with `pkg-config --libs sdl2`,
or `sdl2-config --libs` without pkg-config, and falls back to
`/opt/homebrew/lib` and `/usr/local/lib`. `SDL2_LDFLAGS` overrides that,
as in `SDL2_LDFLAGS=-L/opt/sdl2/lib`.

`--version` names the build: the badline version, the revision it was
built from (`git describe`) and the `spinel --version` of the compiler.
The task writes those into `tmp/native/lib/badline/native/build_info.rb`,
ahead of `native/lib` on the load path. A build by hand gets the empty
defaults in `native/lib/badline/native/build_info.rb`:

```sh
spinel -I native/lib -I lib --no-line-map --rbs spinel/sig native/badline.rb \
  -o tmp/native/badline --cc="cc $(pkg-config --libs-only-L sdl2)"
```

## The source

- `native/badline.rb` is the entry point: it reads the options, builds
  the machine and runs the window.
- `native/lib/badline/native.rb` requires the emulator core from `lib/`
  file by file, since `lib/badline.rb` also loads the CRuby front end,
  then the members in `native/lib/badline/native/`:
  - `sdl.rb` declares the SDL2 functions, structs and constants the
    others call, and `LibC`'s `malloc` and `free`.
  - `app.rb` (`App`) opens the window and runs the frame loop.
  - `screen.rb` (`Screen`) repacks the VIC's display for the texture.
  - `sound.rb` (`Sound`) feeds the SID's samples to SDL's audio queue.
  - `keys.rb` (`Keys`) maps SDL scancodes to C64 keys and joystick
    directions, and `controls.rb` (`Controls`) routes them to the
    keyboard or the joysticks.
  - `options.rb` (`Options`) parses the command line.
  - `pacer.rb` (`Pacer`) and `frame_rate.rb` (`FrameRate`) decide how many
    cycles a frame clocks and how long it waits.
  - `version.rb` and `build_info.rb` make the `--version` line.

The files under `native/` stay inside the subset of Ruby Spinel compiles,
which `spec/spinel_subset_spec.rb` enforces. The parts that don't touch
SDL, such as the options and the version line, also load on CRuby, where the specs cover
them.

## Running

```sh
tmp/native/badline [options] [media]
tmp/native/badline vendor/OneLoad64-Games-Collection-v5/IK+.crt
```

It takes `exe/badline-ruby`'s window options, parsed by
`Badline::Native::Options` inside Spinel's subset rather than with
OptionParser. `badline --help` lists them:

- `-s`, `--song N` picks a subtune of a `.sid` file, and `--sid 6581` or
  `--sid 8580` the SID to fit, which is otherwise a `.sid` tune's own, or
  the 6581.
- `--no-autostart` attaches the media and stops at `READY.`.
- The SID plays through the host's audio device, and F10 mutes and
  unmutes it. `--no-sound` turns it off. Unlike `exe/badline-ruby`, which
  runs below real time and plays only with `--sound`, the native build
  plays unless told not to (`--sound` is accepted too).
- `--no-vsync` paces PAL frames by the timer, or by the sound, instead of
  the display. See [Pacing](#pacing).
- `--version` names the build.

Values can also come as `--song=2`, and `--` ends the options. Three more
options are for testing:

- `--frames N` quits after that many frames.
- `--unpaced` drops vsync and the pacing, so the frame rate shows how
  much headroom there is.
- `--screenshot FILE` saves the last frame as a BMP, as the renderer drew
  it, read back before it is presented.

It boots the machine, or attaches and autostarts a media file, and runs
it a frame at a time: it polls SDL events, clocks the frame's cycles,
queues the SID's samples when sound is on, repacks the lines the VIC
changed into a streaming texture, presents it and waits.

- The host keyboard maps by position (SDL scancodes, US layout) onto the
  C64 keys `GUI::KeyMap` gives the same keys by name. Esc is RUN/STOP.
- Tab switches to joystick mode and back. As in the SDL front end's
  joystick mode, the arrow keys and space drive joystick 2 and WASD and
  left shift drive joystick 1. F9 swaps the two, for games that read
  port 1, and the title bar names the port the arrows drive.

Every 50 frames it prints the frame rate, the time per frame spent on
events, emulation, audio, the texture upload, presenting and waiting, and
the slowest frame's work. With sound on it adds the samples queued per
second, the queue's range, and the underruns and dropped samples so far.

To run it without a display, as CI does, use SDL's dummy drivers. The
dummy video driver has no accelerated renderer, so name the software one
for a screenshot:

```sh
SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software SDL_AUDIODRIVER=dummy \
  tmp/native/badline --frames 150 --unpaced --screenshot tmp/native/ready.bmp
```

There is no gamepad, mouse or paddle support yet.

### Pacing

By default the renderer waits for the display's vertical sync, as
`exe/badline-ruby` does when it paces, and a frame lasts one refresh: it
clocks as many cycles as the machine runs in that time, 16,420 at 60 Hz
and 6,842 at 144 Hz, so the machine runs at its own speed on any display.
`Pacer` and `FrameRate` hold the rules.

- The display reports its refresh rate as a whole number. From the first
  report on, the frames are sized to the rate the display actually
  presents at, measured over the whole run, when that is within 10% of
  the reported rate.
- With the sound playing, the display paces the frames and the audio
  device consumes the samples, and the two clocks drift apart. Each frame
  is trimmed to steer the audio queue towards 80 ms: by up to 2% in
  proportion to the queue's error, plus a trim that builds up while the
  error lasts, up to 5%. A frame that would take the queue past 160 ms waits for it, so no
  samples are dropped.
- If presenting doesn't wait, as with vsync off in the display's driver
  or under SDL's dummy video driver, the frames come faster than 1.5 times
  the refresh rate. After 10 frames, and at every report, that prints a
  notice and falls back to a timer, keeping the display-sized frames.

`--no-vsync` runs PAL frames of 19,656 cycles instead, paced by the sound
as below or, without it, by a 20 ms timer.

### Sound

The SID records at the rate the audio device opens with, 44.1 kHz unless
the device prefers another, and each frame's samples go onto SDL's audio
queue (`SDL_QueueAudio`). Without vsync, the pacing follows
`exe/badline-ruby --sound`'s:

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
  frames go back to the timer.

Each frame's samples go onto the queue through an `IO::Buffer` of signed
16-bit values (`set_value(:s16, ...)`), which Spinel's FFI hands to
`SDL_QueueAudio` as a `:buffer_in` pointer.

### The texture

Spinel hands an `Array` of Integers to C as 64-bit words, and a texture
wants 32-bit pixels, so `Screen` packs two neighbouring pixels into each
word of an `XRGB8888` texture, where the top byte of each pixel is
ignored. The frames stay an `Array`, because writing them into an
`IO::Buffer` with `set_value` was slower than the `Array` stores.
