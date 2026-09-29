# The native badline

`badline` built with [Spinel](https://github.com/matz/spinel), which
compiles the emulator core ahead of time to C, fast enough to play games
in real time. It plays the machine in an SDL2 window, reaching libSDL2
through Spinel's FFI (`ffi_func`, `ffi_buffer` and the
`ffi_read_*`/`ffi_write_*` accessors) rather than ruby-sdl2, so it builds
with Spinel only and doesn't run on CRuby. `exe/badline-ruby` is the same
emulator on CRuby.

## Installing

With Homebrew:

```sh
brew install elektronaut/tap/badline
badline --version
```

The formula builds the release's pack (see [Packing](#packing)) with the
system's C compiler, so it needs no Spinel, and pulls in SDL2. It comes
from the [elektronaut/homebrew-tap](https://github.com/elektronaut/homebrew-tap)
tap, which each release updates.

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

### Packing

`rake native:pack` writes a tarball that builds the native badline with a
C compiler and make alone, from Spinel's `spin pack`: the generated C,
Spinel's runtime sources and a Makefile, plus the ROMs.

```sh
SPINEL=~/src/spinel/bin/spinel rake native:pack
```

The task stages a spin project in `tmp/native/pack/project`, whose
manifest names the load path as path dependencies, and packs it into
`tmp/native/pack/badline-VERSION`. The tarball is
`tmp/native/badline-VERSION-spinel-COMMIT.tar.gz`, and its `PACK-INFO`
names the badline version, the revision and the Spinel build. `SPIN`
names `spin` if it isn't beside `SPINEL`.

To build a pack by hand, point the linker at SDL2 and the binary at the
ROMs, which it otherwise looks for where the pack was made:

```sh
tar -xzf badline-0.4.0-spinel-15f037af.tar.gz && cd badline-0.4.0
LIBRARY_PATH="$(brew --prefix)/lib" make -j
BADLINE_ROM_PATH=roms ./badline --version
```

The Homebrew formula in `packaging/homebrew/badline.rb` does the same,
installing the ROMs under its share directory. When release-please cuts a
release, the Build workflow's `homebrew` job packs the tag, builds and
boots the pack, attaches it to the GitHub release and pushes the formula,
with the release's url and sha256, to the tap. The job stays off until the
repository has a `HOMEBREW_TAP_TOKEN` secret: a fine-grained token with
Contents read and write access to `elektronaut/homebrew-tap`.

## The source

- `native/badline.rb` is the entry point: it reads the options, builds
  the machine and runs the window.
- `native/lib/badline/native.rb` requires the emulator core from `lib/`
  file by file, since `lib/badline.rb` also loads the CRuby front end,
  and badline-ruby's player from `lib/badline/audio` but for its SDL
  sink and its io/console terminal, then the members in
  `native/lib/badline/native/`:
  - `sdl.rb` declares the SDL2 functions, structs and constants the
    others call, and `LibC`'s `malloc`, `free` and `poll`.
  - `app.rb` (`App`) opens the window and runs the frame loop.
  - `screen.rb` (`Screen`) repacks the VIC's display for the texture,
    and `drive_led.rb` (`DriveLed`) places and colours the true drive's
    LED over it.
  - `sound.rb` (`Sound`) feeds the SID's samples to SDL's audio queue.
  - `keys.rb` (`Keys`) maps SDL scancodes to C64 keys and joystick
    directions, and `controls.rb` (`Controls`) holds the input mode and
    routes keys and the mouse to the keyboard, the joysticks or a pot
    device.
  - `gamepads.rb` (`Gamepads`) opens and polls the game controllers, and
    `pad_port.rb` (`PadPort`) maps each one onto a joystick.
  - `options.rb` (`Options`) parses the command line, and `help.rb`
    holds its `--help`.
  - `headless.rb` (`Headless`) runs `--headless` and `--audio-out` with
    badline-ruby's `Audio::CLI`, handing it `audio_sink.rb`
    (`AudioSink`), SDL's audio queue for playback, and `console.rb`
    (`Console`), the terminal in raw mode through `stty`, waiting for
    keys with `poll(2)`.
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

It takes `exe/badline-ruby`'s options, parsed by
`Badline::Native::Options` inside Spinel's subset rather than with
OptionParser, with the same checks and messages. `badline --help` lists
them. The window's are below, and `--headless` and `--audio-out` play or
render a `.sid` tune without it, as described under
[Without the window](#without-the-window).

- `-s`, `--song N` picks a subtune of a `.sid` file, and `--sid 6581` or
  `--sid 8580` the SID to fit, which is otherwise a `.sid` tune's own, or
  the 6581.
- `--no-autostart` attaches the media and stops at `READY.`.
- `--read-only` mounts a disk image write-protected, leaving its file
  unchanged.
- `--true-drive` puts a true 1541 on device 8 in place of the KERNAL
  traps, as in `exe/badline-ruby`: a `.d64` or `.g64` goes into it and
  autostarts through its DOS, and its LED lights in the bottom right
  corner of the border. A `.g64` plugs one in without it.
- `--ntsc` runs an NTSC C64, with the 6567R8 VIC-II, instead of a PAL
  one. Its 235 lines sit in the middle of the window, which keeps PAL's
  272, between black bands.
- The SID plays through the host's audio device, and F10 mutes and
  unmutes it. `--no-sound` turns it off. Unlike `exe/badline-ruby`, which
  runs below real time and plays only with `--sound`, the native build
  plays unless told not to (`--sound` is accepted too).
- `--no-vsync` paces the machine's frames by the timer, or by the sound,
  instead of the display. See [Pacing](#pacing).
- `--verbose` prints the display, sound and game controller setup as the
  window opens, and the frame report below.
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
  C64 keys `GUI::KeyMap` gives the same keys by name. Esc is RUN/STOP
  and Page Up is RESTORE.
- Tab steps through `exe/badline-ruby`'s input modes, and shift-Tab
  steps back: keyboard, joystick, a 1351 mouse on port 1 or 2, and
  paddles on port 1 or 2. The title bar names the mode.
- In joystick mode, as in the SDL front end's, the arrow keys and space
  drive joystick 2 and WASD and left shift drive joystick 1. F9 swaps the
  two, for games that read port 1, and the title bar names the port the
  arrows drive.
- In the mouse and paddle modes the host mouse is held in relative mode.
  Its motion moves the 1351 or turns the paddles, and its left and right
  buttons go to the 1351's buttons or the two paddles' fire buttons.
- Game controllers drive the joysticks as in `exe/badline-ruby`: the
  first one found drives joystick 2 and a second one joystick 1. The
  D-pad and the left stick steer, and every face and shoulder button
  fires. Controllers are picked up when they are plugged in or out.

With `--verbose`, every 50 frames it prints the frame rate, the time per frame spent on
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

### Without the window

`--headless` plays a `.sid` tune on the host's audio device, and
`--audio-out FILE` renders it to a `.wav` or `.aiff` file, as
`badline-ruby --headless` and `--audio-out` do (see
[Playing and rendering SID tunes](../README.md#playing-and-rendering-sid-tunes)).
They take the same options: `--song`, `--sid`, `--seconds`,
`--songlengths`, `--rate`, `--filter-chunk`, `--quiet` and `--no-tui`.
The window's options, `--no-sound`, `--no-vsync`, `--true-drive`, `--ntsc`,
`--verbose` and the testing ones included, are refused with them.

It runs badline-ruby's own player from `lib/badline/audio`: the tune
runs on the bare rig or the whole machine as there, and a render is the
same file byte for byte. Two parts differ. The audio device is
`AudioSink`, which queues the samples through Spinel's FFI as
`Audio::SDLSink` does through ruby-sdl2, and without a display SDL's
dummy or disk audio drivers work (`SDL_AUDIODRIVER=dummy`). On a
terminal, `Console` puts it in raw mode with `stty raw -echo isig` and
restores it with `stty` afterwards, and waits for keys with `poll(2)`,
where badline-ruby uses io/console and io/wait. A signal handler turns
Ctrl-C into `Interrupt`, which stops the tune as in badline-ruby.

```sh
tmp/native/badline --headless tune.sid
tmp/native/badline --seconds 180 tune.sid --audio-out out.wav
```

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
  the refresh rate. After 10 frames, and at every report, that falls
  back to a timer, keeping the display-sized frames, and `--verbose`
  prints a notice.

`--no-vsync` runs the machine's own frames instead, paced by the sound
as below or, without it, by a timer: 19,656 cycles in 19.95 ms on PAL,
17,095 in 16.7 ms on NTSC.

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
