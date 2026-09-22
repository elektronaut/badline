[![Version](https://img.shields.io/gem/v/badline.svg?style=flat)](https://rubygems.org/gems/badline)
[![Build](https://github.com/elektronaut/badline/actions/workflows/build.yml/badge.svg)](https://github.com/elektronaut/badline/actions/workflows/build.yml)

# Badline

Badline is a Commodore 64 emulator written in Ruby. It emulates a PAL
machine one clock cycle at a time, stepping the 6510, the VIC-II, both
CIAs and the SID together, so raster timing, bad lines and sprite DMA
are modelled at the cycle level.

It runs programs, disk and tape images, cartridges and SID tunes, and
the SDL2 front end supports the keyboard, joysticks, game controllers,
paddles and a 1351 mouse. There is no live sound yet, and emulation runs
slower than a real C64. See [What's emulated](#whats-emulated) for the
details.

## Requirements

Ruby 4.0 or newer, and SDL2:

```sh
brew install sdl2           # macOS
apt install libsdl2-dev     # Debian/Ubuntu
```

## Installation

```sh
gem install badline
```

Or add `gem "badline"` to your Gemfile and run `bundle install`.

## Usage

Run `badline` with no arguments to boot to the BASIC prompt, or give it
something to load:

```sh
badline                     # READY.
badline game.prg            # Load and run a program
badline game.d64            # Mount a disk image as device 8 and load it
badline game.tap            # Insert a tape and load it
badline game.crt            # Attach a cartridge
badline tune.sid            # Play a SID tune
badline ~/c64               # Mount a directory as device 8
```

Programs, disk and tape images and SID tunes start automatically, and
a cartridge starts itself. A mounted directory waits for you to `LOAD`
from it. `--no-autostart` attaches the media and stops at `READY.`, so
you can type the `LOAD` yourself. `--song N` picks a subtune of a
`.sid` file, `--sid 8580` fits the newer SID, and `--disable-jit` runs
without YJIT, which is otherwise switched on at startup.
`badline --help` lists the options.

## Media

| Format | Handling |
|--------|----------|
| `.prg`, `.p00` | Loaded into memory after boot. A program at the BASIC start (`$0801`) is `RUN`, anything else is left for you to `SYS` |
| `.d64`, `.d71`, `.d81` | Mounted read-only as device 8, then `LOAD"*",8,1` and `RUN` |
| `.t64` | Mounted read-only as device 8 and loaded like a disk image. The files load by name, and no tape is involved |
| `.tap` | Inserted in the datasette with PLAY pressed, then `LOAD` and `RUN`. It loads at the speed of a real tape |
| `.crt` | Standard 8K, 16K and Ultimax cartridges, Ocean and Magic Desk. Other hardware types are rejected |
| `.sid` | PSID and RSID tunes, started through a small driver after boot |
| A directory | Mounted read-write as device 8. It serves the `.prg` and `.p00` files in it and the contents of any `.t64`, and `SAVE` writes a new `.prg` |

There is no 1541. Device 8 works by trapping the KERNAL's `LOAD` and
`SAVE` routines and its serial bus primitives, so files open by name
through `OPEN` and `CHRIN` as well. The command channel answers `I`,
`B-P` and `U1` block reads, which covers loaders that read blocks
directly. Loaders that upload their own code to the drive with `M-W` and
`M-E`, and copy protection that reads raw GCR, won't work.

## Rendering SID tunes

`badline-render` renders a `.sid` tune to a 16-bit PCM file. The output
extension picks the format, `.wav` or `.aiff`, and the default is the
tune's name with `.wav`.

```sh
badline-render tune.sid                        # tune.wav, length from HVSC
badline-render --seconds 180 tune.sid out.aiff
badline-render --song 3 --rate 48000 tune.sid
badline-render --sid 8580 tune.sid
badline-render --filter-chunk 1 tune.sid       # exact filter, slower
```

A `.sid` file doesn't store its length, so `badline-render` looks the
tune up by MD5 in HVSC's `Songlengths.md5`. It finds the database
through `--songlengths`, in a `DOCUMENTS` directory in any of the
tune's parent directories (the layout of an HVSC collection), or under
`$HVSC_BASE/DOCUMENTS`. Without a database or `--seconds` it renders
60 seconds.

PSID tunes render on a CPU and RAM with only the SID clocked, which is
faster than real time. RSID tunes set up their own interrupts, so they
boot a full C64 first and render at about half real time. The filter
steps four cycles at a time; `--filter-chunk 1` steps it every cycle,
which is exact and takes about twice as long. `badline-render --help`
lists the options.

## Input

Keys map by their unshifted symbol, and Shift gives the C64's shifted
character, not the host's: Shift-2 types `"`. These keys have no
same-named host key:

| C64 | Host |
|-----|------|
| `RUN/STOP` | `Escape` |
| `CLR/HOME` | `Home` |
| `INST/DEL` | `Backspace` |
| `CRSR ⇔` / `CRSR ⇕` | `Right` / `Down` (add Shift for left and up) |
| `←` / `↑` | `Left` / `Up` |
| `CTRL` | `Left Ctrl` |
| `C=` | `Left Alt` |
| `@` | `\` |
| `:` | `'` |
| `£` | `End` |
| `+` / `*` | Keypad `+` / Keypad `*` |
| `RESTORE` | Not mapped |

`Tab` steps through the input modes and `Shift-Tab` steps back. The
window title shows the current mode:

| Mode | What the host drives |
|------|----------------------|
| (none) | The keyboard |
| `[JOY]` | Arrows and Space are joystick 2, `WASD` and Left Shift joystick 1 |
| `[MOUSE 1]` / `[MOUSE 2]` | A 1351 mouse in control port 1 or 2 |
| `[PADDLE 1]` / `[PADDLE 2]` | A pair of paddles in control port 1 or 2 |

The mouse and paddle modes capture the host mouse until you `Tab` out of
them. Moving it moves the 1351 or turns the two paddle knobs, and the
left and right buttons are the 1351's buttons, or the fire buttons of
paddles A and B. Games differ in which port they read, which is why each
device has a mode per port.

Game controllers work in every mode. The first one is joystick 2 and
the second is joystick 1. The D-pad and left stick steer, the face and
shoulder buttons fire, and controllers can be connected or removed while
the emulator runs.

Control port 1's fire line is also the VIC-II's light pen input, so
joystick 1's fire button and the 1351's left button in port 1 latch the
light pen registers.

## What's emulated

- **6510**: every opcode, documented and undocumented, with per-cycle
  bus behaviour checked against the
  [65x02 single step tests](https://github.com/SingleStepTests/65x02).
  `JAM` opcodes halt the CPU until reset.
- **Memory**: banking through the 6510 port, including the cartridge
  `EXROM`/`GAME` lines and Ultimax mode.
- **VIC-II** (PAL 6569): the five standard graphics modes and the
  invalid ones, sprites with multicolour, expansion, priority and
  pixel-level collisions, raster interrupts, bad lines, sprite DMA, the
  border, VIC banks and the light pen.
- **CIA 1 and 2**: timers, time-of-day clocks with alarms, the serial
  shift register, interrupts, the keyboard matrix with its ghost keys,
  the control ports and the paddle multiplexer.
- **SID**: the 6581 and the 8580, with oscillators, ring modulation and
  sync, the envelope generator including the ADSR delay bug, the filter,
  and the RC network on the board that removes the DC offset from the
  output. The machine has a 6581 unless a `.sid` tune asks for an 8580
  in its header, and `--sid 6581` or `--sid 8580` overrides either.
- **Datasette**: `.tap` playback into CIA 1's FLAG line, with the motor
  and sense lines on the 6510 port.
- **Cartridges**: standard, Ocean and Magic Desk.

Known gaps:

- No live audio. The SID is emulated, but emulation runs below real
  time, so nothing plays it back yet. `badline-render` is the way to
  hear a tune.
- No drive emulation, so fast loaders and anything else that runs code
  on the drive won't work (see [Media](#media)). Disk images are
  read-only.
- No NTSC machine, no REU, and no `RESTORE` key.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/elektronaut/badline).
[CONTRIBUTING.md](CONTRIBUTING.md) covers running the tests and the
commit format, and the project has a
[code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](MIT-LICENSE).
