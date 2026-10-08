# Snapshots

In the window, `F11` quicksaves the whole machine to one of five slots,
`quicksave-1.vsf` to `quicksave-5.vsf` in the `quicksaves` folder of
badline's data folder. It fills the empty slots first, then replaces the
one saved longest ago. `F12` restores the newest quicksave, or a named
save in the data folder's `saves` folder if one is newer, in a new
machine built as the saved one was. Quicksaves stay after badline quits,
so `F12` finds them the next time it starts. What's printed on a save or
a restore names the slot and the file.

A run without `--frames` also autosaves every 6,000 frames the machine
has run, two minutes on PAL, to `autosave-1.vsf` to `autosave-3.vsf` in
the `autosaves` folder, replacing the oldest. Time in the pause menu
doesn't count, nothing is printed, and `F12` never picks an autosave. An
autosave that fails warns once and stops autosaving.

The pause menu's Snapshots page quicksaves, saves under a name in the
`saves` folder and loads a named save. The name starts as the game's,
from its cartridge, disk or tape, or BASIC, with the next free number,
and saving over a name already taken asks first. Below those, the
newest quicksaves and autosaves, with the time each was saved, load
with a press.

The data folder is `~/Library/Application Support/badline` on macOS,
and `$XDG_DATA_HOME/badline` or `~/.local/share/badline` elsewhere.
`BADLINE_DATA_PATH` puts it somewhere else.

Both executables do this, and both open a `.vsf` given as the media,
in a machine built as the saved one was, whatever `--model` says.
`--save-snapshot FILE` saves one to `FILE` after the last frame. A
snapshot that fails to open leaves the machine running as it was.

## From Ruby

`computer.save_snapshot(path)` saves, `computer.restore_snapshot(path)`
takes a machine back to a snapshot, and `Badline::Snapshot.load(path)`
builds a new machine as the saved one was built and restores it.
`computer.snapshot` and `computer.restore(state)` do the same in memory,
without a file. A restore that fails leaves the machine as it was.

## What a snapshot holds

A snapshot holds the machine as it was on the cycle it was saved: the
chips down to the instruction step and the pixel pipeline, the RAM and
any +60K or +256K expansion, the cartridge with its RAM and flash, a
GEO-RAM, a true 1541 with its RAM, its VIAs and the disk under the head,
a disk or directory mounted through the traps with its open channels,
and the tape with its place on it. A restored machine runs on exactly
as the saved one would have.

A tape, a `.t64` archive and a disk image mounted through the traps come
back with their contents from the snapshot, so they need no file to
restore. A true drive's disk opens again from its image's path, with its
tracks as the drive last saw them. When that file is gone, the disk
comes back from the tracks alone, write-protected. A directory mounted
as device 8 opens again from its path. What the host holds stays the
host's: the keyboard, the joysticks, the mouse and paddles, sound, and
blocks given to `on_init` that hadn't run yet, which a restore reports.

Every model saves this way, PAL, NTSC, old NTSC and Drean alike, and so
does a machine with an REU, with its RAM, its registers and a transfer
part way through. A snapshot only restores in the badline version that
wrote it, into a machine with the same chip models, region, RAM
expansion, REU, KERNAL, datasette and board. One saved before badline
recorded the KERNAL and the datasette restores as a machine with the
C64's KERNAL and a datasette, and one saved before it recorded the board
restores on a C64's.

## The VIC-20

`badline vic20` saves and restores the same way, with the same keys,
slots and pause menu page. A VIC-20 snapshot holds its RAM and colour
RAM, a cartridge's ROM, the VIC with its picture and sound, both VIAs,
the CPU, the tape with its place on it, the disk or directory device 8
serves through the traps and a true 1541, and restores into a VIC-20
with the same RAM expansion. Its file names its machine `VIC20`, as
xvic's do, and holds only the `BADLINE` module, so xvic doesn't open
it, and badline doesn't open xvic's. Restoring a
VIC-20 snapshot while a C64 runs, or a C64 one while a VIC-20 runs,
swaps the machine in the window.

## The C128

`badline c128` saves and restores the same way too. A C128 snapshot
holds its 128K of RAM, colour RAM, the CPU port, the MMU's registers,
the VIC-IIe, both CIAs, the SID, the VDC with its RAM and registers, the
CPU, a cartridge, the tape, the disk device 8 serves through the traps
and a true 1541, and restores into a C128 of the same model with the
same SID. The VDC's picture is left out and painted again while the
window shows it, and the window shows the VIC-IIe after a restore. Its
file names its machine `C128`, as x128's do, and holds only the
`BADLINE` module, so x128 doesn't open it, and badline doesn't open
x128's. Restoring a C128 snapshot while another machine runs swaps the
machine in the window, as for the VIC-20.

## VICE

Snapshots use VICE's `.vsf` format. badline writes VICE's modules for
the CPU, RAM and CPU port, both CIAs, the SID and the VIC-II, and an
REU's `REU1764`, plus the ones x64sc needs to open the file, with
nothing else attached to the cartridge port, nothing on the tape or user
ports and no true drive. The VIC-II module names the chip as VICE does:
the 6569 or 8565 on PAL, the 6567R8 or 8562 on NTSC, the 6567R56A on old
NTSC and the 6572 on PAL-N. A `BADLINE` module, which VICE skips, holds
the whole machine, and badline restores its own snapshots from it.

x64sc 3.10 opens badline's snapshots, taken at the end of the
instruction the CPU was in, and of an REU transfer under way, as long
as its VIC-II model matches: `-model c64`, `c64c`, `ntsc`, `newntsc`,
`oldntsc` or `drean`, as `--model` names the machine. It takes the REU
from the snapshot, keeps its own drives and leaves out the cartridge,
the other expansions and the tape. A program x64sc runs on from badline's
snapshot reads the raster as badline does, cycle for cycle.

Snapshots x64sc saves open in badline through the same modules: the CPU
at its instruction boundary, RAM, the CPU port, the CIAs' registers,
timers and clocks, the SID's registers and reSID voice state, the
VIC-II's registers, beam position, counters and colour RAM, and an
REU's size, registers and RAM. The VIC-II's model builds the machine's
region, and the 6569R1 runs as the 6569. The VIC-II's pixel pipeline
starts empty. badline reads the modules x64sc 3.7 to 3.10 write, and
VICE's development versions' `MAINC64CPU` and `VIC-IISC`. A module
version it doesn't know is left out, or fails the restore for the CPU
and RAM. It reports the modules it leaves out, such as the 1541 drives,
the cartridge port, the datasette and the keyboard, and carries on
without them. Restored into a running machine, a VICE snapshot
fails for a machine built another way, such as a C64C's snapshot in a
C64, and otherwise takes the cartridge out and switches the machine off
and on.
