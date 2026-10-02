[![Version](https://img.shields.io/gem/v/badline.svg?style=flat)](https://rubygems.org/gems/badline)
[![CI](https://github.com/elektronaut/badline/actions/workflows/ci.yml/badge.svg)](https://github.com/elektronaut/badline/actions/workflows/ci.yml)

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
badline game.vsf       # Restore a snapshot, from badline or VICE
badline ~/c64          # Mount a directory as device 8
```

Programs, disk and tape images and SID tunes start automatically, and
a cartridge starts itself. A mounted directory waits for you to `LOAD`
from it.

`badline-ruby` takes the same media and the same options, with the
differences noted in the table. `--help` lists the options for either.

### Options

| Option | Effect |
| --- | --- |
| `--no-autostart` | Attach the media and stop at `READY.`, so you can type the `LOAD` yourself |
| `--read-only` | Mount a disk image write-protected. The drive reports `26,WRITE PROTECT ON` for any write and the image file stays as it was |
| `--true-drive` | Put an emulated 1541 on device 8 instead of the KERNAL traps. See [Media](#media) |
| `-s`, `--subtune N` | Pick a subtune of a `.sid` file, counting from 1 |
| `--sid 6581`, `--sid 8580` | Fit the older or newer SID. `--sid auto`, the default, takes a `.sid` tune's own |
| `--reu SIZE` | Plug in a RAM Expansion Unit of `SIZE` K: 128, 256, 512 (a 1750) or up to 16384 |
| `--ntsc` | Run an NTSC C64, with the 6567R8 VIC-II, instead of a PAL one |
| `--no-sound` | Don't play the SID (`badline` only, where sound is on by default) |
| `--sound` | Play the SID (`badline-ruby`, where sound is off by default) |
| `--no-vsync` | Pace the window by a timer, or by the sound while it plays, instead of the display's vsync |
| `--verbose` | Print the display's refresh rate, the sound's sample rate and the game controllers found as the window opens, then the frame rate and the time each frame takes, once a second |
| `--disable-jit` | Run without YJIT, otherwise switched on at startup (`badline-ruby` only) |
| `--version` | Show the version and what built it (`badline` only) |
| `-h`, `--help` | List the options |

Both run the same window. `badline` plays the SID through the host's
audio device, and `F10` mutes and unmutes it. In `badline-ruby` the
machine runs below real time, so the sound stutters: it plays in bursts
with silent gaps between them, at the right pitch, and never slows the
emulation down.

### Scripted runs

| Option | Effect |
| --- | --- |
| `--frames N` | Quit after N frames |
| `--unpaced` | Run as fast as it can, without vsync or pacing |
| `--at FRAME:EVENT` | Press keys, type, swap media or take a screenshot once `FRAME` frames have run |
| `--script FILE` | Run the events in `FILE`, one `FRAME:EVENT` a line |
| `--screenshot FILE` | Save the last frame as a `.bmp` |
| `--save-snapshot FILE` | Save the machine as a `.vsf` snapshot after the last frame |

```sh
badline --unpaced --frames 12000 --true-drive disk1.d64 \
  --at 3500:key=space --at 5600:insert=disk2.d64 \
  --at 250,500,6000:screenshot=shot%05d.bmp
```

`--help` lists the events, and [native/README.md](native/README.md#running)
describes them.

### ROMs

The KERNAL, BASIC and character ROMs come with the gem. To run other
images, such as a patched KERNAL, point `BADLINE_ROM_PATH` at a
directory that holds `kernal.rom`, `basic.rom` and `character.rom`,
plus `eapi/eapi-am29f040-14` if you attach EasyFlash cartridges. From
Ruby, `Badline.rom_path = dir` does the same before a
`Badline::Computer` is built, and `nil` restores the bundled set.

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
| `.vsf` | A snapshot of a running machine, badline's own or one VICE's x64sc saved. See [Snapshots](#snapshots) |
| A directory | Mounted read-write as device 8. It serves the `.prg` and `.p00` files in it and the contents of any `.t64`, and `SAVE` writes a new `.prg` |

Apart from a `.g64`, which only a true drive can read, there is no 1541
unless `--true-drive` asks for one. Device 8 works by trapping the
KERNAL's `LOAD` and `SAVE` routines and its serial bus primitives, so
files open by name through `OPEN` and `CHRIN` as well. `LOAD"$",8` lists
the directory of any medium mounted there, as a 1541 does. The command
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

## Snapshots

In the window, `F11` saves the whole machine to a new
`badline-<date>-<time>.vsf` in the working directory, and `F12` goes
back to the snapshot last saved or opened, in a new machine built as the
saved one was. Both executables do this, and both open a `.vsf` given as
the media. A snapshot that fails to open leaves the machine running as
it was. From Ruby, `computer.save_snapshot(path)` saves,
`computer.restore_snapshot(path)` takes a machine back to a snapshot,
and `Badline::Snapshot.load(path)` builds a new machine as the saved one
was built and restores it. `computer.snapshot` and
`computer.restore(state)` do the same in memory, without a file. A
restore that fails leaves the machine as it was.

A snapshot holds the machine as it was on the cycle it was saved: the
chips down to the instruction step and the pixel pipeline, the RAM and
any +60K or +256K expansion, the cartridge with its RAM and flash, a
GEO-RAM, a true 1541 with its RAM, its VIAs and the disk under the head,
a disk or directory mounted through the traps with its open channels,
and the tape with its place on it. A restored machine runs on exactly
as the saved one would have. A directory, a tape and a true drive's
disk image open again from their paths when the snapshot is restored,
the disk with its tracks as the drive last saw them. A disk image mounted through the traps comes back
with its contents from the snapshot. What the host holds stays the host's: the keyboard, the
joysticks, the mouse and paddles, sound, and blocks given to `on_init`
that hadn't run yet, which a restore reports. A snapshot only restores
in the badline version that wrote it, into a machine with the same
chip models, RAM expansion and REU. `computer.snapshot` holds an REU's
RAM, registers and transfer too, but a machine with an REU doesn't save
to a file yet, as badline doesn't write VICE's REU module.

Snapshots use VICE's `.vsf` format. badline writes VICE's modules for
the CPU, RAM and CPU port, both CIAs, the SID and the VIC-II, plus the
ones x64sc needs to open the file, with nothing attached to the
cartridge, tape or user ports and no true drive. A `BADLINE` module,
which VICE skips, holds the whole machine, and badline restores its own
snapshots from it.

x64sc 3.10 opens badline's snapshots, taken at the end of the
instruction the CPU was in, as long as its VIC-II model matches
(`-model c64` for the default machine). It keeps its own drives and
leaves out the cartridge, the expansions and the tape. Snapshots x64sc
saves open in badline through the same modules: the CPU at its
instruction boundary, RAM, the CPU port, the CIAs' registers, timers and
clocks, the SID's registers and reSID voice state, and the VIC-II's
registers, beam position, counters and colour RAM. The VIC-II's pixel
pipeline starts empty. badline reads the modules x64sc 3.7 to 3.10
write, and VICE's development versions' `MAINC64CPU` and `VIC-IISC`. A module version
it doesn't know is left out, or fails the restore for the CPU and RAM.
It reports the modules it leaves out, such as the 1541 drives, the
cartridge, the datasette and the keyboard, and carries on without them.
An NTSC snapshot fails, as badline runs PAL only. Restored into a
running machine, a VICE snapshot fails for a machine built another way,
such as a C64C's snapshot in a C64, and otherwise takes the cartridge
out and switches the machine off and on.

## Playing and rendering SID tunes

`badline-ruby --headless` plays a `.sid` tune on the host's audio
device without opening the window, and `--audio-out` renders it to a
16-bit PCM file instead. The file's extension picks the format, `.wav`
or `.aiff`. The native `badline` has both modes too.

```sh
badline sid ~/C64Music/MUSICIANS/H/Hubbard_Rob               # play every tune below a directory
badline sid tune.sid other.sid                               # play a queue of tunes
badline-ruby --headless tune.sid                             # play, length from HVSC
badline-ruby --headless -s 3 tune.sid                        # play the third subtune
badline-ruby --headless --all-subtunes tune.sid                 # play on through every subtune
badline-ruby --seconds 180 tune.sid --audio-out out.aiff
badline-ruby -s 3 --rate 48000 tune.sid --audio-out out.wav
badline-ruby --headless --sid 8580 tune.sid
badline-ruby --filter-chunk 1 tune.sid --audio-out out.wav   # exact filter, slower
```

`badline sid FILE|DIR...` plays a queue of tunes in the terminal, in
the order given, and a directory adds every `.sid` tune below it in path
order. `badline sid` on its own prints its usage. It takes the options
below except `--headless` and `--audio-out`, and `--subtune` picks the
first tune's subtune. `--sid auto`, the default, fits each tune the SID
its header names. A tune written for 2 or 3 SIDs plays on the one SID
badline emulates, with a notice saying so, and a file that isn't a
tune is skipped. `badline tune.sid` still plays the tune in the window.

Both modes take the same options. The window's own, `--no-autostart`,
`--read-only`, `--sound`, `--true-drive`, `--reu`, `--ntsc` and
`--verbose`, don't apply to them. `--subtune` (or `-s`) picks the subtune, counting from 1 as HVSC
does, and defaults to the tune's own start subtune. Playback asks the
device for 44.1 kHz and takes whatever rate it offers, unless `--rate`
says otherwise. Ctrl-C stops it.

Played on a terminal, `--headless` and `sid` show each tune's name,
author and release as it starts, then the tune's place in the queue,
the subtune number and the time played against the subtune's length. `--headless`
queues just the one tune. Each tune plays its own subtune: `--subtune`, or
the tune's start subtune. When that subtune ends the player goes on to the next
tune, and it stops after the last. `a`, or `--all-subtunes`, turns on
playing all subtunes, so that a subtune that ends goes on to the tune's next
subtune, and a tune stepped to starts on its first subtune.

→ and ← step to the tune's next and previous subtune, stopping at its
first and last. `n` and `p` step to the next and previous tune. `s`
turns shuffle on and off, which plays the queue's tunes in a random
order, and `l` turns looping on and off, so that the end of the queue
goes on to its start. Space pauses and `q` quits. The status line
shows which modes are on, and they last until the player quits.

`--no-tui`, or output that isn't a terminal, gives plain progress
output instead and plays through the queue without the keys, while
`--audio-out` renders just the one subtune.

A `.sid` file doesn't store its length, so `badline-ruby` looks the
tune up by MD5 in HVSC's `Songlengths.md5`. It finds the database
through `--songlengths`, in a `DOCUMENTS` directory in any of the
tune's parent directories (the layout of an HVSC collection), or under
`$HVSC_BASE/DOCUMENTS`. Without a database or `--seconds` it runs for
60 seconds, but a subtune that falls silent for 5 seconds before then
ends there, when played and when rendered alike. Silent means the
output holds within 16 steps of one level, since a 6581 idles at a DC
offset rather than at zero. A subtune with a known length plays to its
length whatever it sounds like.

A tune in an HVSC collection also gets its entry in HVSC's `STIL.txt`,
found the same way: comments, covers, and subtune names and composers.
The tune's own fields follow its header, and each subtune's print as it
starts.

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

Keys map by their position on a US keyboard, whatever the host's layout,
and Shift gives the C64's shifted character, not the host's: Shift-2
types `"`. These keys have no same-named host key:

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
| `[JOY 2]` / `[JOY 1]` | Arrows and Space (or Right Ctrl) are the joystick named, `WASD` and Left Shift the other. `F9` swaps them |
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
- **REU**: the 1700, 1764 and 1750 RAM Expansion Units, and the bigger
  units up to 16M built on the same REC chip, with DMA timed against the
  VIC's bad lines and sprites. `--reu SIZE` plugs one in, and
  `Badline::Computer.new(reu: 512)` does the same from Ruby. An
  REU beside a cartridge loses I/O 2 to the cartridge.
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
  doesn't rename, copy, format or validate disks.
- No PAL-N (Drean) machine.
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
