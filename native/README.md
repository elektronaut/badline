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

- `native/badline.rb` is the entry point: it reads the arguments, builds
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
  - `version.rb` and `build_info.rb` make the `--version` line.

The files under `native/` stay inside the subset of Ruby Spinel compiles,
which `spec/spinel_subset_spec.rb` enforces. The parts that don't touch
SDL, such as the version line, also load on CRuby, where the specs cover
them.

## Running

```sh
tmp/native/badline [media] [frames] [paced|unpaced] [sound] [screenshot.bmp]
tmp/native/badline vendor/OneLoad64-Games-Collection-v5/IK+.crt sound
```

It boots the machine, or attaches and autostarts a media file, and runs
it a PAL frame at a time: it polls SDL events, clocks 19,656 cycles,
queues the SID's samples when sound is on, repacks the lines the VIC
changed into a streaming texture, presents it and waits. The arguments
can come in any order: a number is the frame count, a `.bmp` path the
screenshot, and anything else the media.

- The host keyboard maps by position (SDL scancodes, US layout) onto the
  C64 keys `GUI::KeyMap` gives the same keys by name. Esc is RUN/STOP.
- Tab switches to joystick mode and back. As in the SDL front end's
  joystick mode, the arrow keys and space drive joystick 2 and WASD and
  left shift drive joystick 1. F9 swaps the two, for games that read
  port 1, and the title bar names the port the arrows drive.
- `sound` plays the SID, and F10 mutes and unmutes it. Sound is off
  unless asked for, as in `exe/badline-ruby`.
- `frames` quits after that many frames, and `unpaced` drops the 50 Hz
  pacing, so the frame rate shows how much headroom there is (the display
  refresh still caps it).
- A screenshot path saves the last frame as the renderer drew it, read
  back before it is presented.

Every 50 frames it prints the frame rate, the time per frame spent on
events, emulation, audio, the texture upload, presenting and waiting, and
the slowest frame's work. With sound on it adds the samples queued per
second, the queue's range, and the underruns and dropped samples so far.

To run it without a display, as CI does, use SDL's dummy drivers. The
dummy video driver has no accelerated renderer, so name the software one
for a screenshot:

```sh
SDL_VIDEODRIVER=dummy SDL_RENDER_DRIVER=software SDL_AUDIODRIVER=dummy \
  tmp/native/badline 150 unpaced tmp/native/ready.bmp
```

There is no gamepad, mouse or paddle support yet.

### Sound

The SID records at the rate the audio device opens with, 44.1 kHz unless
the device prefers another, and each frame's samples go onto SDL's audio
queue (`SDL_QueueAudio`). The pacing follows `exe/badline-ruby --sound`:

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

### The texture

Spinel hands an `Array` of Integers to C as 64-bit words, and a texture
wants 32-bit pixels, so `Screen` packs two neighbouring pixels into each
word of an `XRGB8888` texture, where the top byte of each pixel is
ignored.
