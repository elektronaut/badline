[![Version](https://img.shields.io/gem/v/badline.svg?style=flat)](https://rubygems.org/gems/badline)
[![Build](https://github.com/elektronaut/badline/actions/workflows/build.yml/badge.svg)](https://github.com/elektronaut/badline/actions/workflows/build.yml)

# Badline

Badline is a Commodore 64 emulator written in Ruby.

The 6510, the VIC-II and both CIAs are emulated one cycle at a time,
so the machine behaves like the real thing down to raster timing, bad
lines and sprite DMA. Programs load from PRG and P00 files, D64/D71/D81
disk images, CRT cartridges or a plain directory on your disk, and the
SDL2 front end gives you a window, a keyboard, joysticks, paddles and a
1351 mouse.

## Requirements

Badline needs Ruby 4.0 or newer and SDL2, which is available from most
package managers.

```sh
brew install sdl2           # macOS
apt install libsdl2-dev     # Debian/Ubuntu
```

## Installation

```sh
gem install badline
```

Or add it to your Gemfile and run `bundle install`.

```ruby
gem "badline"
```

## Usage

Run `badline` on its own to boot to the BASIC prompt, or hand it
something to load.

```sh
badline                     # READY.
badline game.prg            # Load and run a program
badline game.d64            # Mount a disk image as device 8
badline game.t64            # Mount a tape archive as device 8
badline game.crt            # Attach a cartridge
badline ~/c64               # Mount a directory as device 8
```

Programs and disk images start automatically. Pass `--no-autostart` to
boot to `READY.` with the media attached but nothing running, so you can
type the `LOAD` yourself.

```sh
badline --no-autostart game.d64
```

YJIT is enabled at startup, since the emulator needs all the speed it
can get. `--disable-jit` turns that off. `badline --help` lists
everything.

## Media

- **`.prg`, `.p00`** — loaded once the KERNAL has booted. Programs that
  load at the BASIC start address (`$0801`) are run, anything else is
  left in memory for you to `SYS`.
- **`.d64`, `.d71`, `.d81`** — mounted as device 8, read-only.
  Autostart types `LOAD"*",8,1` followed by `RUN`.
- **`.t64`** — tape archives, mounted as device 8, read-only. The files
  inside load by name like a disk; the tape itself is not emulated.
- **`.crt`** — standard, Ocean and Magic Desk cartridges. Other hardware
  types raise `Badline::Cartridge::UnsupportedTypeError`.
- **A directory** — mounted as device 8, read *and* write. Every file in
  it is a PRG, and `SAVE` writes a new one.

Disk access works by trapping the KERNAL's `LOAD` and `SAVE` routines
and its serial bus primitives rather than by emulating a 1541. Files
also open by name through `OPEN`/`CHRIN`, and the DOS command channel
answers `U1` block reads, `B-P` and `I`, so block-access loaders work.
There is no drive CPU, so fast loaders that upload their own 6502 code
to the drive (`M-W`, `M-E`) and copy protection that reads raw GCR
won't work.

## Input

The keyboard is mapped positionally where the two layouts agree. The
keys that don't line up:

| C64 | Host |
|-----|------|
| `RUN/STOP` | `Escape` |
| `CLR/HOME` | `Home` |
| `CTRL` | `Left Ctrl` |
| `C=` | `Left Alt` |
| `RESTORE` | Not mapped |
| `@` | `\` |
| `:` | `'` |
| `£` | `End` |
| `INST/DEL` | `Backspace` |

`Tab` steps through the input modes, which the window title names:

| Mode | What the host drives |
|------|----------------------|
| (none) | The keyboard, as above |
| `[JOY]` | Arrows + space are joystick 2, `WASD` + left shift joystick 1 |
| `[MOUSE]` | A 1351 mouse in control port 1 |
| `[PADDLE]` | A pair of paddles in control port 1 |

In the two pointer modes the mouse is grabbed: motion moves the mouse or
turns the paddle knobs, and the host buttons land where the hardware puts
them — left and right button on the 1351's fire and up lines, paddle A
and B's buttons on the left and right lines. `Tab` back to a keyboard
mode to release the pointer.

Control port 1's fire line also runs to the VIC's light pen pin, so
joystick 1's button and the 1351's left button latch `$D013`/`$D014` just
as they do on hardware.

A connected game controller drives the joysticks in every mode, so it
works without switching to `[JOY]`. The first controller is joystick 2,
the second joystick 1; the D-pad and left stick both steer, and the face
and shoulder buttons fire. Controllers can be plugged and unplugged while
the emulator runs.

## What's emulated

- **6510** — all 256 opcodes, documented and illegal alike, cycle-exact
  and verified against the
  [65x02 single step tests](https://github.com/SingleStepTests/65x02).
- **Memory** — full banking through the 6510 I/O port, including the
  cartridge lines and Ultimax mode.
- **VIC-II** — all five graphics modes, sprites with multicolour,
  expansion, priority and collision detection, raster interrupts, bad
  lines, sprite DMA, VIC banks and the border.
- **CIA 1 and 2** — timers, TOD clocks with alarms, interrupts, the
  keyboard matrix with its phantom keypresses, both joystick ports and
  the POTX/POTY mux.
- **Cartridges** — standard cartridges plus Ocean and Magic Desk bank
  switching.

Not there yet:

- The SID answers register reads and writes, including the pot lines,
  but makes no sound.
- No 1541 emulation, so nothing that drives the serial bus itself will
  run.
- No datasette and no REU.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/elektronaut/badline). See
[CONTRIBUTING.md](CONTRIBUTING.md) for how to run the tests and how
commits are formatted, and note that this project ships with a
[code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](MIT-LICENSE).
