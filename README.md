[![Version](https://img.shields.io/gem/v/badline.svg?style=flat)](https://rubygems.org/gems/badline)
[![Build](https://github.com/elektronaut/badline/actions/workflows/build.yml/badge.svg)](https://github.com/elektronaut/badline/actions/workflows/build.yml)

# Badline

Badline is a Commodore 64 emulator written in Ruby. It emulates a PAL
or NTSC machine one clock cycle at a time, stepping the 6510, the VIC-II, both
CIAs and the SID together, so raster timing, bad lines and sprite DMA
are modelled at the cycle level.

It runs programs, disk and tape images, cartridges and SID tunes, and
the SDL2 front end supports the keyboard, joysticks, game controllers,
paddles and a 1351 mouse. See [What's emulated](#whats-emulated) for the
details.

It comes in two builds of the same emulator:

- **`badline`**, compiled ahead of time with
  [Spinel](https://github.com/matz/spinel). It runs in real time with
  sound, so it's the one to play games with.
- **`badline-ruby`**, which comes with the Ruby gem and runs on CRuby. It
  runs slower than a real C64, so its sound is off by default. The gem is
  also a library, which runs a `Badline::Computer` from Ruby without a
  window.

## Installation

The native `badline`, with Homebrew:

```sh
brew install elektronaut/tap/badline
```

The formula builds it from the release's generated C, so it needs no
Spinel or Ruby. To build it from a checkout instead, see
[native/README.md](native/README.md).

The gem needs Ruby 4.0 or newer and the SDL2 library:

```sh
brew install sdl2           # macOS
apt install libsdl2-2.0-0   # Debian/Ubuntu
gem install badline
```

Or add `gem "badline"` to your Gemfile and run `bundle install`.

## Usage

Run `badline` with no arguments to boot to the BASIC prompt, or give it
something to load:

```sh
badline                # READY.
badline game.prg       # Load and run a program
badline game.d64       # Mount a disk image as device 8 and load it
badline game.tap       # Insert a tape and load it
badline game.crt       # Attach a cartridge
badline tune.sid       # Play a SID tune
badline ~/c64          # Mount a directory as device 8
```

`badline-ruby` takes the same media and the same options, with the
differences noted below.

Programs, disk and tape images and SID tunes start automatically, and
a cartridge starts itself. A mounted directory waits for you to `LOAD`
from it. `--no-autostart` attaches the media and stops at `READY.`, so
you can type the `LOAD` yourself. `--read-only` mounts a disk image
write-protected, so the drive reports `26,WRITE PROTECT ON` for any
write and the image file stays as it was. `--song N` picks a subtune of a
`.sid` file and `--sid 8580` fits the newer SID. `--ntsc` runs an NTSC
C64, with the 6567R8 VIC-II, instead of a PAL one. `badline-ruby` also
takes `--disable-jit`, which runs without YJIT, otherwise switched on at
startup. `--help` lists the options.

The KERNAL, BASIC and character ROMs come with the gem. To run other
images, such as a patched KERNAL, point `BADLINE_ROM_PATH` at a
directory that holds `kernal.rom`, `basic.rom` and `character.rom`,
plus `eapi/eapi-am29f040-14` if you attach EasyFlash cartridges. From
Ruby, `Badline.rom_path = dir` does the same before a
`Badline::Computer` is built, and `nil` restores the bundled set.

`badline` plays the SID through the host's audio device, and `F10`
mutes and unmutes it. `--no-sound` turns it off. The window is paced by
the display's vsync; `--no-vsync` paces it by a timer, or by the sound
while it plays.

`--verbose` prints the display's refresh rate, the sound's sample rate
and the game controllers found as the window opens. In `badline` it also
prints the frame rate and the time each frame takes, once a second.

In `badline-ruby` sound is off by default, and `--sound` turns it on.
The machine runs below real time there, so the sound stutters: it plays
in bursts with silent gaps between them, at the right pitch, and never
slows the emulation down.

## Media

| Format | Handling |
|--------|----------|
| `.prg`, `.p00` | Loaded into memory after boot. A program at the BASIC start (`$0801`) is `RUN`, anything else is left for you to `SYS` |
| `.d64`, `.d71`, `.d81` | Mounted read-write as device 8, then `LOAD"*",8,1` and `RUN`. Writes go straight back to the image file. With `--read-only`, or an image the host can't write, it acts as a write-protected disk |
| `.g64` | Put in a true 1541, which is plugged in as device 8 for it, then `LOAD"*",8,1` and `RUN`. The image holds the disk's raw GCR, half tracks and all, so copy protection and fast loaders that read it work. Tracks the drive writes go back to the image file. With `--read-only`, or an image the host can't write, it acts as a write-protected disk |
| `.t64` | Mounted read-only as device 8 and loaded like a disk image. The files load by name, and no tape is involved |
| `.tap` | Inserted in the datasette with PLAY pressed, then `LOAD` and `RUN`. It loads at the speed of a real tape |
| `.crt` | The hardware types listed under [Cartridges](#whats-emulated). Other types are rejected |
| `.sid` | PSID and RSID tunes, started through a small driver after boot |
| A directory | Mounted read-write as device 8. It serves the `.prg` and `.p00` files in it and the contents of any `.t64`, and `SAVE` writes a new `.prg` |

Apart from a `.g64`, which only a true drive can read, there is no 1541
unless `--true-drive` asks for one. Device 8 works by trapping the
KERNAL's `LOAD` and `SAVE` routines and its serial bus primitives, so
files open by name through `OPEN` and `CHRIN` as well. The command
channel answers `I`, `B-P` and `U1` block reads, which covers loaders
that read blocks directly. On a disk image it also takes `SAVE` (with
`@0:` to replace a file), files opened for writing or appending, `S` to
scratch, `U2` and `B-W` block writes, and `B-A` and `B-F`. Loaders that
upload their own code to the drive with `M-W` and `M-E`, and copy
protection that reads raw GCR, won't work there, but do on a true
drive.

`--true-drive` puts an emulated 1541 on device 8 instead, running its
own DOS ROM on its own 6502 and talking to the machine over the serial
bus. It reads `.d64` and `.g64` images, which it autostarts with the
same `LOAD"*",8,1` and `RUN`, but not `.d71`, `.d81` or `.t64` images
or directories. `--read-only` puts the disk in write-protected. Loading
runs at the speed of a real 1541, and the drive's red LED lights in the
bottom right corner of the border. Both executables take it.

`Badline::Media.insert_disk(computer, path)` swaps the disk image or
directory in device 8 while the machine runs, for software that asks for
another disk. It takes `read_only: true`, and `Badline::Media.attach`
takes `disk: { read_only: true }`, to mount a disk image write-protected,
as the test harnesses under `bin/` do. A `.g64` goes in the true 1541,
and takes out a disk mounted through the traps, so `LOAD` and `SAVE`
reach the 1541 too. With the 1541 in device 8, a `.d64` goes in its
drive as well.

## Playing and rendering SID tunes

`badline-ruby --headless` plays a `.sid` tune on the host's audio
device without opening the window, and `--audio-out` renders it to a
16-bit PCM file instead. The file's extension picks the format, `.wav`
or `.aiff`. The native `badline` has both modes too.

```sh
badline-ruby --headless tune.sid                             # play, length from HVSC
badline-ruby --headless -s 3 tune.sid                        # play the third subtune
badline-ruby --seconds 180 tune.sid --audio-out out.aiff
badline-ruby -s 3 --rate 48000 tune.sid --audio-out out.wav
badline-ruby --headless --sid 8580 tune.sid
badline-ruby --filter-chunk 1 tune.sid --audio-out out.wav   # exact filter, slower
```

Both modes take the same options. The window's own, `--no-autostart`,
`--read-only`, `--sound`, `--true-drive`, `--ntsc` and `--verbose`, don't apply
to them. `--song` (or `-s`) picks the subtune, counting from 1 as HVSC
does, and defaults to the tune's own start song. Playback asks the
device for 44.1 kHz and takes whatever rate it offers, unless `--rate`
says otherwise. Ctrl-C stops it.

Played on a terminal, `--headless` shows the tune's name, author and
release, the song number and the time played against the song's
length. `n` or → skips to the next song, `p` or ← goes back one, space
pauses and `q` quits. `--no-tui`, or output that isn't a terminal,
gives plain progress output instead.

A `.sid` file doesn't store its length, so `badline-ruby` looks the
tune up by MD5 in HVSC's `Songlengths.md5`. It finds the database
through `--songlengths`, in a `DOCUMENTS` directory in any of the
tune's parent directories (the layout of an HVSC collection), or under
`$HVSC_BASE/DOCUMENTS`. Without a database or `--seconds` it runs for
60 seconds.

PSID tunes run on a CPU and RAM with only the SID clocked, at about
twice real time, so they play smoothly. RSID tunes set up their own
interrupts, so they boot a full C64 first and run at about half real
time. They render fine but stutter when played, and `badline-ruby` says
so when it falls behind. The filter steps four cycles at a time;
`--filter-chunk 1` steps it every cycle, which is exact and takes about
twice as long. `badline-ruby --help` lists the options.

The native `badline` takes the same options and runs the same code, so
it renders the same file sample for sample, and it plays RSID tunes
without stuttering. See
[native/README.md](native/README.md#without-the-window).

## Input

Keys map by their unshifted symbol, and Shift gives the C64's shifted
character, not the host's: Shift-2 types `"`. These keys have no
same-named host key:

| C64 | Host |
|-----|------|
| `RUN/STOP` | `Escape` |
| `CLR/HOME` | `Home` |
| `INST/DEL` | `Backspace` |
| `CRSR ⇔` / `CRSR ⇕` | `Right` / `Down`, and `Left` / `Up` for the shifted directions |
| `←` / `↑` | `` ` `` / `]` |
| `CTRL` | `Left Ctrl` |
| `C=` | `Left Alt` |
| `@` | `\` |
| `:` | `'` |
| `£` | `End` |
| `+` / `*` | Keypad `+` / Keypad `*` |
| `RESTORE` | `Page Up` |

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

`F10` mutes and unmutes the sound, and the window title shows `[MUTED]`
while it's off.

## What's emulated

- **6510**: every opcode, documented and undocumented, with per-cycle
  bus behaviour checked against the
  [65x02 single step tests](https://github.com/SingleStepTests/65x02).
  `JAM` opcodes halt the CPU until reset.
- **Memory**: banking through the 6510 port, including the cartridge
  `EXROM`/`GAME` lines and Ultimax mode. The +60K and +256K RAM
  expansions fit with `Badline::Computer.new(ram_expansion: :plus60k)` or
  `:plus256k`, banked through their register at `$D100`.
- **VIC-II** (PAL 6569): the five standard graphics modes and the
  invalid ones, sprites with multicolour, expansion, priority and
  pixel-level collisions, raster interrupts, bad lines, sprite DMA, the
  border, VIC banks and the light pen.
  `Badline::Computer.new(vic_model: :mos8565)` fits the C64C's 8565
  instead, with its grey dots on colour register writes and its own
  timing for mode splits, sprite multicolour splits and the light pen.
  `Badline::Computer.new(region: Badline::Region::NTSC)` builds an NTSC
  machine instead: the 6567R8's 65 cycles by 263 lines at 1,022,727 Hz,
  with its later sprite fetches and its X counter, and TOD clocks on
  60 Hz mains. `Badline::Region::NTSC_OLD` is the first NTSC C64s'
  6567R56A, 64 cycles by 262 lines. The stock KERNAL tells them from PAL
  by the raster, so every region boots the same ROMs. `--ntsc` picks the
  6567R8.
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
- **GEO-RAM**: 64K to 4M of RAM seen through the `$DE00` page, with the
  `$DFFE`/`$DFFF` page and block registers. It takes the expansion port,
  so it can't sit alongside a cartridge:
  `computer.attach_cartridge(Badline::Cartridge::GeoRAM.new(size: 512))`.
  Its contents are lost when the emulator quits.

Known gaps:

- `badline-ruby` runs below real time, so its live audio stutters.
  `badline` plays smoothly, and so do PSID tunes under
  `badline-ruby --headless`.
- Without `--true-drive`, fast loaders and anything else that runs code
  on the drive won't work (see [Media](#media)). The command channel
  doesn't rename, copy, format or validate disks, and `LOAD"$",8`
  doesn't list a disk's directory yet.
- No REU, and no PAL-N (Drean) machine.
- The emulator window has no freeze button yet, so a freezer cartridge
  runs its menu but can't freeze a program.

## Contributing

Bug reports, feature requests, and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first. Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

[CONTRIBUTING.md](CONTRIBUTING.md) also covers running the tests and the
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
