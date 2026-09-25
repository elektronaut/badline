[![Version](https://img.shields.io/gem/v/badline.svg?style=flat)](https://rubygems.org/gems/badline)
[![Build](https://github.com/elektronaut/badline/actions/workflows/build.yml/badge.svg)](https://github.com/elektronaut/badline/actions/workflows/build.yml)

# Badline

Badline is a Commodore 64 emulator written in Ruby. It emulates a PAL
machine one clock cycle at a time, stepping the 6510, the VIC-II, both
CIAs and the SID together, so raster timing, bad lines and sprite DMA
are modelled at the cycle level.

It runs programs, disk and tape images, cartridges and SID tunes, and
the SDL2 front end supports the keyboard, joysticks, game controllers,
paddles and a 1351 mouse. Emulation runs slower than a real C64, so
live sound, which is off by default, stutters. See
[What's emulated](#whats-emulated) for the details.

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

The KERNAL, BASIC and character ROMs come with the gem. To run other
images, such as a patched KERNAL, point `BADLINE_ROM_PATH` at a
directory that holds `kernal.rom`, `basic.rom` and `character.rom`,
plus `eapi/eapi-am29f040-14` if you attach EasyFlash cartridges. From
Ruby, `Badline.rom_path = dir` does the same before a
`Badline::Computer` is built, and `nil` restores the bundled set.

`--sound` plays the SID through the host's audio device, and `F10`
mutes and unmutes it. Sound is off by default. While it plays, the
audio device sets the pace instead of the display, so the machine never
runs ahead of the sound or drifts behind it. The whole machine runs
below real time, though, so the sound stutters: it plays in bursts with
silent gaps between them, at the right pitch, and never slows the
emulation down.

## Media

| Format | Handling |
|--------|----------|
| `.prg`, `.p00` | Loaded into memory after boot. A program at the BASIC start (`$0801`) is `RUN`, anything else is left for you to `SYS` |
| `.d64`, `.d71`, `.d81` | Mounted read-only as device 8, then `LOAD"*",8,1` and `RUN` |
| `.t64` | Mounted read-only as device 8 and loaded like a disk image. The files load by name, and no tape is involved |
| `.tap` | Inserted in the datasette with PLAY pressed, then `LOAD` and `RUN`. It loads at the speed of a real tape |
| `.crt` | The hardware types listed under [Cartridges](#whats-emulated). Other types are rejected |
| `.sid` | PSID and RSID tunes, started through a small driver after boot |
| A directory | Mounted read-write as device 8. It serves the `.prg` and `.p00` files in it and the contents of any `.t64`, and `SAVE` writes a new `.prg` |

There is no 1541. Device 8 works by trapping the KERNAL's `LOAD` and
`SAVE` routines and its serial bus primitives, so files open by name
through `OPEN` and `CHRIN` as well. The command channel answers `I`,
`B-P` and `U1` block reads, which covers loaders that read blocks
directly. Loaders that upload their own code to the drive with `M-W` and
`M-E`, and copy protection that reads raw GCR, won't work.

## Playing and rendering SID tunes

`badline-sid` plays a `.sid` tune on the host's audio device, or with
`--output` (or `-o`) renders it to a 16-bit PCM file instead. The
output extension picks the format, `.wav` or `.aiff`.

```sh
badline-sid tune.sid                           # play, length from HVSC
badline-sid -s 3 tune.sid                      # play the third subtune
badline-sid --seconds 180 tune.sid -o out.aiff
badline-sid -s 3 --rate 48000 tune.sid -o out.wav
badline-sid --sid 8580 tune.sid
badline-sid --filter-chunk 1 tune.sid -o out.wav   # exact filter, slower
```

Both modes take the same options. `--song` (or `-s`) picks the subtune,
counting from 1 as HVSC does, and defaults to the tune's own start
song. Playback asks the device for 44.1 kHz and takes whatever rate it
offers, unless `--rate` says otherwise. Ctrl-C stops it.

Played on a terminal, `badline-sid` shows the tune's name, author and
release, the song number and the time played against the song's
length. `n` or → skips to the next song, `p` or ← goes back one, space
pauses and `q` quits. `--no-tui`, or output that isn't a terminal,
gives plain progress output instead.

A `.sid` file doesn't store its length, so `badline-sid` looks the
tune up by MD5 in HVSC's `Songlengths.md5`. It finds the database
through `--songlengths`, in a `DOCUMENTS` directory in any of the
tune's parent directories (the layout of an HVSC collection), or under
`$HVSC_BASE/DOCUMENTS`. Without a database or `--seconds` it runs for
60 seconds.

PSID tunes run on a CPU and RAM with only the SID clocked, at about
twice real time, so they play smoothly. RSID tunes set up their own
interrupts, so they boot a full C64 first and run at about half real
time. They render fine but stutter when played, and `badline-sid` says
so when it falls behind. The filter steps four cycles at a time;
`--filter-chunk 1` steps it every cycle, which is exact and takes about
twice as long. `badline-sid --help` lists the options.

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

With `--sound`, `F10` mutes and unmutes the sound, and the window
title shows `[MUTED]` while it's off.

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
  the control ports and the paddle multiplexer. The machine has the
  original 6526s; `Badline::Computer.new(cia_model: :mos6526a)` fits the
  C64C's 6526As instead, whose interrupt register timing differs.
- **SID**: the 6581 and the 8580, with oscillators, ring modulation and
  sync, the envelope generator including the ADSR delay bug, the filter,
  and the RC network on the board that removes the DC offset from the
  output. The machine has a 6581 unless a `.sid` tune asks for an 8580
  in its header, and `--sid 6581` or `--sid 8580` overrides either.
- **Datasette**: `.tap` playback into CIA 1's FLAG line, with the motor
  and sense lines on the 6510 port.
- **Cartridges**: standard 8K, 16K and Ultimax, Simons' BASIC, Ocean,
  Fun Play / Power Play, Super Games, Epyx FastLoad, Westermann Learning,
  Rex Utility, C64 Game System / System 3, Dinamic, Zaxxon / Super Zaxxon,
  Magic Desk, Comal-80, EasyFlash, Mach 5, Pagefox, RGCD and GMod2, and
  the freezers Action Replay (v4.2 to v6), Atomic Power / Nordic Power,
  Retro Replay / Nordic Replay, Final Cartridge III / III+ and the KCS
  Power Cartridge.
  EasyFlash and GMod2 flash takes writes through the chip's command set
  (program, sector and chip erase, autoselect), so games and EAPI can
  save to it. An EasyFlash image's EAPI is swapped for a bundled copy of
  the Am29F040 EAPI on attach, as VICE does. The writes stay in memory
  and are lost when the emulator quits: the `.crt` file is never
  overwritten. The Retro Replay's flash
  works the same way in flash mode, which the flash jumper enables:
  `Media.attach(computer, path, cartridge: { flash_jumper: true })`, with
  `bank_jumper: true` to run from the second 64K of a 128K image. The
  GMod2 EEPROM and the Retro Replay clock port aren't there.

Known gaps:

- Live audio in the emulator window stutters, because the whole machine
  runs below real time. `badline-sid` plays PSID tunes smoothly on
  their own.
- No drive emulation, so fast loaders and anything else that runs code
  on the drive won't work (see [Media](#media)). Disk images are
  read-only.
- No NTSC machine, no REU, and no `RESTORE` key.
- The emulator window has no freeze button yet, so a freezer cartridge
  runs its menu but can't freeze a program.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/elektronaut/badline).
[CONTRIBUTING.md](CONTRIBUTING.md) covers running the tests and the
commit format, and the project has a
[code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](MIT-LICENSE).

Badline bundles one piece of third-party software:
`lib/badline/roms/eapi/eapi-am29f040-14`, the EasyFlash flash driver
(EAPI) for the Am29F040, © 2009–2010 Thomas 'skoe' Giesel, assembled
unaltered from [its upstream source](https://gitlab.com/easyflash/eapi).
It isn't part of badline and is distributed under the zlib licence; see
[its README](lib/badline/roms/eapi/README) and
[LICENSE.md](lib/badline/roms/eapi/LICENSE.md).
