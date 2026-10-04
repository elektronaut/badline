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
doesn't count, nothing is printed, and `F12` never picks an autosave. A
machine that can't be saved to a file, such as one with an REU, warns
once and stops autosaving.

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

A snapshot only restores in the badline version that wrote it, into a
machine with the same chip models, RAM expansion and REU.
`computer.snapshot` holds an REU's RAM, registers and transfer too, but
a machine with an REU doesn't save to a file yet, as badline doesn't
write VICE's REU module. Nor does an NTSC or Drean machine, as badline
doesn't write an NTSC or PAL-N VIC-II in VICE's terms yet.

## VICE

Snapshots use VICE's `.vsf` format. badline writes VICE's modules for
the CPU, RAM and CPU port, both CIAs, the SID and the VIC-II, plus the
ones x64sc needs to open the file, with nothing attached to the
cartridge, tape or user ports and no true drive. A `BADLINE` module,
which VICE skips, holds the whole machine, and badline restores its own
snapshots from it.

x64sc 3.10 opens badline's snapshots, taken at the end of the
instruction the CPU was in, as long as its VIC-II model matches
(`-model c64` for the default machine). It keeps its own drives and
leaves out the cartridge, the expansions and the tape.

Snapshots x64sc saves open in badline through the same modules: the CPU
at its instruction boundary, RAM, the CPU port, the CIAs' registers,
timers and clocks, the SID's registers and reSID voice state, and the
VIC-II's registers, beam position, counters and colour RAM. The VIC-II's
pixel pipeline starts empty. badline reads the modules x64sc 3.7 to 3.10
write, and VICE's development versions' `MAINC64CPU` and `VIC-IISC`. A
module version it doesn't know is left out, or fails the restore for the
CPU and RAM. It reports the modules it leaves out, such as the 1541
drives, the cartridge, the datasette and the keyboard, and carries on
without them. A snapshot of an NTSC machine fails, as badline reads only
VICE's PAL VIC-II. Restored into a running machine, a VICE snapshot
fails for a machine built another way, such as a C64C's snapshot in a
C64, and otherwise takes the cartridge out and switches the machine off
and on.
