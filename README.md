[![Version](https://img.shields.io/gem/v/badline.svg?style=flat)](https://rubygems.org/gems/badline)
[![Build](https://github.com/elektronaut/badline/actions/workflows/build.yml/badge.svg)](https://github.com/elektronaut/badline/actions/workflows/build.yml)

# Badline

Badline is a Commodore 64 emulator written in Ruby.

The 6510, the VIC-II and both CIAs are emulated one cycle at a time,
so the machine behaves like the real thing down to raster timing, bad
lines and sprite DMA. Programs load from PRG and P00 files, D64/D71/D81
disk images, CRT cartridges or a plain directory on your disk, and the
SDL2 front end gives you a window, a keyboard and a joystick.

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
- **`.crt`** — standard, Ocean and Magic Desk cartridges. Other hardware
  types raise `Badline::Cartridge::UnsupportedTypeError`.
- **A directory** — mounted as device 8, read *and* write. Every file in
  it is a PRG, and `SAVE` writes a new one.

Disk access works by trapping the KERNAL's `LOAD` and `SAVE` routines
rather than by emulating a 1541. Loading is instant, but there is no
drive CPU, so fast loaders and copy protection that talk to the drive
directly won't work.

## Keyboard and joystick

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

`Tab` toggles joystick mode, where the arrow keys and space become
joystick port 2 and the window title gains a `[JOY]` marker. Toggle it
back off to type again.

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
  keyboard matrix and joystick port 2.
- **Cartridges** — standard cartridges plus Ocean and Magic Desk bank
  switching.

Not there yet:

- The SID answers register reads and writes, but makes no sound.
- No 1541 emulation, so nothing that drives the serial bus itself will
  run.
- No datasette, no REU, no joystick port 1.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/elektronaut/badline). See
[CONTRIBUTING.md](CONTRIBUTING.md) for how to run the tests and how
commits are formatted, and note that this project ships with a
[code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](MIT-LICENSE).
