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
`--save-snapshot FILE` saves one to `FILE` after the last frame, and
`--vice` adds VICE's modules to it (see [VICE](#vice)). A snapshot that
fails to open leaves the machine running as it was.

## Which snapshots load

Snapshots from badline 0.14.0 on load in that version and every later
one. Each part of the machine is saved as named fields, so a later
badline skips a field it no longer needs, and a field an earlier one
didn't save starts as it does when the machine is switched on. What a
restore leaves out or changes is printed, such as a module missing from
the file. [snapshot-format.md](snapshot-format.md) lists every field.

Snapshots from badline 0.13 and earlier are refused, with a message
naming the version that saved them, which still opens them. No snapshot
loaded across releases before 0.14.0, and none converts.

## From Ruby

`computer.save_snapshot(path)` saves, `computer.restore_snapshot(path)`
takes a machine back to a snapshot, and `Badline::Snapshot.load(path)`
builds a new machine as the saved one was built and restores it.
`computer.snapshot` returns a `Badline::Snapshot::Image` in memory,
without a file, and `computer.restore(image)` takes the machine back to
it; `image.load` builds a new machine from it. A restore that fails
leaves the machine as it was. `computer.export_snapshot(path)` saves with
VICE's modules too.

Saving first runs the machine on to the next instruction boundary, and
to the end of an REU transfer under way, so it advances the machine by a
few cycles: usually under a hundred, and up to about 262,000 for an REU
swapping 64K. `computer.cycles` afterwards says where it was saved. A
save straight after another runs no cycles and writes the same file. In
the window this happens between frames, and the cycles fold into the
next frame. `computer.snapshot` in memory saves the same way.

## What a snapshot holds

A snapshot holds the machine as it was at the instruction boundary it
was saved at: the chips down to the pixel pipeline, the RAM and
any +60K or +256K expansion, the cartridge with its RAM and flash, a
GEO-RAM, a true 1541 with its RAM, its VIAs and the disk under the head,
a disk or directory mounted through the traps with its open channels,
and the tape with its place on it. A restored machine runs on exactly
as the saved one would have.

A tape, a `.t64` archive, a disk image mounted through the traps and a
true drive's disk come back with their contents from the snapshot, so
they need no file to restore. A true drive's disk holds its image as last
written to its file, with the tracks the drive has written since, and
writes back to that file while it is there. When the file is gone, the
disk comes back write-protected. A directory mounted as device 8 opens
again from its path. What the host holds stays the
host's: the keyboard, the joysticks, the mouse and paddles, sound, and
blocks given to `on_init` that hadn't run yet, which a restore reports.

Every model saves this way, PAL, NTSC, old NTSC and Drean alike, and so
does a machine with an REU, with its RAM and its registers. A snapshot
restores into a machine with the same chip models, region, RAM
expansion, REU, KERNAL, datasette and board. The second and third SIDs
the SID player fits for a stereo tune are saved too, each with its
address and model, and a restore fits them.

Text typed with `type_text` that the machine hasn't taken yet, such as
autostart's `RUN`, carries over, and so do the keys a C128 is typing on
its key matrix. The VIC-II's line in progress carries over to a badline
that draws lines the same way. A later badline that draws them another
way starts the rest of that line afresh, and says so.

## The VIC-20

`badline vic20` saves and restores the same way, with the same keys,
slots and pause menu page. A VIC-20 snapshot holds its RAM and colour
RAM, a cartridge's ROM, the VIC with its picture and sound, both VIAs,
the CPU, the tape with its place on it, the disk or directory device 8
serves through the traps and a true 1541 or 1581, and restores into a
VIC-20 with the same RAM expansion. Its file names its machine `VIC20`,
as xvic's do, and holds only badline's modules, so xvic doesn't open it,
and badline doesn't open xvic's. Restoring a
VIC-20 snapshot while a C64 runs, or a C64 one while a VIC-20 runs,
swaps the machine in the window.

## The C128

`badline c128` saves and restores the same way too. A C128 snapshot
holds its 128K of RAM, both colour RAM banks, the CPU port, the MMU's
registers and the page pointer writes it holds, the VIC-IIe, both CIAs,
the SID, the VDC with its RAM and registers, the 8502 and the Z80, a
cartridge, the tape, the disk device 8 serves through the traps and a
true 1541, 1571 or 1581, and restores into a C128 of the same model with
the same SID, built for the same mode. The VDC's picture is left out and
painted again while the window shows it, and the window shows the
VIC-IIe after a restore. Its file names its machine `C128`, as x128's
do, and holds only badline's modules, so x128 doesn't open it, and
badline doesn't open x128's. Restoring a C128 snapshot while another machine runs swaps the
machine in the window, as for the VIC-20.

## The Plus/4

The Plus/4, the C16 and the C116 save and restore the same way. A
snapshot of one holds its RAM with the ROM bank latch and whether ROM or
RAM is selected, the cartridges' ROMs in each slot, the CPU with its
port, the TED with its timers, its counters and its picture, the TED's
sound, the keyboard's 6529, the Plus/4's user port 6529 and ACIA, a TCBM
interface's TIAs, the tape with its place on it, the disk or directory
device 8 serves through the traps and a true 1541 or 1581. It restores
into a machine of the same model with the same RAM, and the BASIC,
KERNAL and function ROMs come with the model. Its file names its machine
`PLUS4`, as xplus4's do, and holds only badline's modules, so xplus4
doesn't open it, and badline doesn't open xplus4's. `--vice` and
`computer.export_snapshot(path)` refuse a Plus/4.

## The PET

Every PET and CBM model saves and restores the same way. A snapshot of
one holds its RAM, the screen RAM, or on an 8296 all 32K from `$8000`,
an 8096's or 8296's 64K board with its control register and the user
port lines the 8296's RAM follows, both PIAs, the VIA, the CPU, the
CRTC on the boards that have one, the picture with where the video is
in its frame, the tapes in both datasettes with their places on them,
and the disk or directory device 8 serves through the IEEE-488 traps.
It restores into a machine of the same model with the same RAM, the
same editor frame rate, the same ROMs, which come with the model, and
an 8296's same jumpers. Its file names its machine `PET`, as xpet's do,
and holds only badline's modules, so xpet doesn't open it unless it is
saved with `--vice` (see [xpet](#xpet)).

### xpet

A PET snapshot saved with `--vice`, or `computer.export_snapshot(path)`,
also holds xpet's modules for the CPU, the RAM with the screen RAM, or
an 8296's 32K from `$8000`, an 8096's or 8296's board and its control
register, the CRTC, both PIAs and the VIA, a true 2031's CPU, RAM, VIAs
and head, or a true 8050's or 8250's interface processor with its RAM
and 6532s and the heads' tracks, and the ones xpet 3.10 needs to open
the file, with nothing open on the file system drive and nothing on the
user port. The CRTC module carries the discrete boards' video too, in
xpet's terms. The file says it is in VICE's snapshot format 1.0, the
only one xpet reads.

xpet 3.10 opens those snapshots as long as its model and editor match:
`-model 2001`, `3032`, `3032B`, `4032`, `8032`, `8096` or `8296`, and
for a badline editor other than xpet's own, `-editor` naming badline's
ROM. xpet's 8296 runs the 8032's editor, 901474-04 dated 0283, so an
8296 saved for it has to run that editor (`--editor 4-80-b-50hz-0283`),
and xpet takes the 8296's jumpers from its own settings. It keeps its
own datasettes and leaves out badline's tapes and disks. A true drive
needs `-drive8type 2031`, `8050` or `8250` with `-drive8truedrive` and
the disk attached as `-8`. Its snapshot is settled with the 2031's CPU
between instructions too, and one saved while the 2031 talks on the bus
can stall there in xpet, as xpet's own snapshots saved while it searches
for a file do. xpet runs an 8050's floppy controller at a high level, so
a snapshot for it is settled until badline's controller sits in its idle
loop with both processors between instructions, and xpet's controller
starts from idle there, taking up any job the interface processor has
left it. A unit that doesn't reach its idle loop within about 262,000
cycles, such as one still starting up, is left out of xpet's modules,
and badline's own modules keep it. Its CRTC loses a few lines on
opening any snapshot, its own too, so a program it runs on from one
finds the vertical sync a few hundred cycles later than one it ran
without stopping.

Snapshots xpet saves open in badline through the same modules: the CPU
at its instruction boundary, the RAM, the screen RAM, an 8096's or
8296's board, the CRTC's registers and beam, both PIAs' registers and
flags, the VIA's registers, timers and shift register, a true 2031's
CPU, RAM, VIAs and head, which go on the bus with the disk badline's
2031 had in it, and a true 8050's or 8250's interface processor, its RAM
and both 6532s, which go on the bus with the disks badline's unit of the
same model had in it. Its floppy controller comes back as a unit
switched on has it, in its idle loop with the heads on track 1: its next
job steps them out to the track, and a job xpet's controller had under
way starts again from there. A program
badline runs on from xpet's snapshot finds the vertical sync on the
cycle xpet does, so the two run on alike, cycle for cycle. The picture
starts again with the next frame. xpet doesn't save its ROMs, which
keyboard it has or an 8296's jumpers, so the board, the RAM and the
CRTC's frame build the machine: a 2001, a 3032 for any other discrete
board, a 4032, an 8032, an 8096 or an 8296 with none of its jumpers
fitted, at 50 or 60 Hz, and an 8032, 8096 or 8296 whose CRTC lines are
64 cycles long runs xpet's own 50 Hz editor, 901474-04 dated 0283. A
SuperPET's snapshot fails. It reports the modules it leaves out, such
as the drives past device 8, the datasettes and the keyboard, and
carries on without them, and a snapshot without a true drive takes
badline's, a 2031, an 8050 or an 8250, off the bus and says so.
Restored into a running PET, an xpet snapshot fails for a PET built
another way, such as a 3032B, and otherwise switches the machine off
and on, keeping its tapes and the disk device 8 serves.

## The CBM-II

The B series, the 610, 620, 710 and 720, saves and restores the same
way. A snapshot of one holds segment 15's RAM, the screen RAM, the RAM
board's segments, both segment registers, a cartridge's ROMs, the CPU,
the CRTC with the picture, the SID, the CIA, the ACIA, both TPIs with
their priority stacks, the mains' place in its period, and the disk or
directory device 8 serves through the IEEE-488 traps. It restores into
a machine of the same model with the same KERNAL and mains. Its file
names its machine `CBM-II`, as xcbm2's do, and holds only badline's
modules, so xcbm2 doesn't open it unless it is saved with `--vice` (see
[xcbm2](#xcbm2)).

### xcbm2

A CBM-II snapshot saved with `--vice`, or `computer.export_snapshot(path)`, also holds
xcbm2's modules for the CPU, the RAM with both segment registers, the
CRTC, the CIA, both TPIs, the ACIA and the SID, and the ones xcbm2 3.10
needs to open the file, with no cartridge, nothing open on the file
system drive and nothing on the user port. The file says it is in
VICE's snapshot format 1.0, the only one xcbm2 reads.

xcbm2 3.10 opens those snapshots as long as its model matches: `-model
610`, `620`, `710` or `720`. It takes a 600's 60 Hz from the snapshot,
keeps its own drives and leaves out badline's cartridge and disk. It
runs on from badline's snapshot just as it runs on from one it saved
itself, cycle for cycle. Opening any snapshot, its own too, costs it a
couple of hundred cycles of its CRTC, so the mains ticks that much later
than in a run that didn't stop.

xcbm2 saves no mains. It ticks the mains once a frame of its CRTC, as
vertical sync ends, whatever its mains is set to, so its ticks come a
frame apart: 40,064 cycles on a 600 at 50 Hz, where badline's come
40,000 apart, and its 700 has no 60 Hz. A snapshot saved for xcbm2 ticks
where xcbm2's CRTC says, not where badline's mains had it. Neither
does xcbm2 save a TPI's priority stack, so the interrupts in service are
lost both ways. Its cursor blinks 32 fields on and 32 off, where the
6845 blinks 16 and 16, so it comes back showing or hidden as it was,
with its place in the blink scaled.

Snapshots xcbm2 saves open in badline through the same modules: the CPU
at its instruction boundary, the RAM and both segment registers, the
CRTC's registers and beam, the CIA's registers, timers and clock, both
TPIs' registers, latches, mask, AIR, CA and CB, the ACIA's registers and
the byte it waits to send, and the SID's registers and reSID voice
state. The mains' next falling edge comes where xcbm2 would tick it, and
the ones after at badline's 50 or 60 Hz, so the two part from the
second tick on. Until then a program badline runs on from xcbm2's
snapshot reads the mains, the CIA and the rest as xcbm2 does, cycle for
cycle. The picture starts again with the next frame. xcbm2 doesn't
save its ROMs, so the RAM board and the model line build the machine:
a 610, 620, 710 or 720 with xcbm2's KERNAL, 901244-04a, at 60 Hz for a
600 whose model line says so and at 50 Hz otherwise. A board of 512K or
more, or RAM mapped into segment 15, fails. It reports the modules it
leaves out, such as the drives, the datasette and the keyboard, and
carries on without them. A snapshot saved while xcbm2's drive was
sending on the IEEE-488 bus, part way into a `LOAD`, stalls there.
Restored into a running CBM-II, an xcbm2 snapshot fails for a CBM-II
built another way, and otherwise switches the machine off and on,
keeping the disk device 8 serves.

## VICE

Snapshots use VICE's `.vsf` format, and badline's own modules are named
`BL-` and something, which VICE skips. A C64 snapshot saved with
`--vice`, or `computer.export_snapshot(path)`, also holds VICE's
modules for the CPU, RAM and CPU port, both CIAs, the SID and the
VIC-II, and an REU's `REU1764`, plus the ones x64sc needs to open the
file, with nothing else attached to the cartridge port, nothing on the
tape or user ports and no true drive. The VIC-II module names the chip
as VICE does: the 6569 or 8565 on PAL, the 6567R8 or 8562 on NTSC, the
6567R56A on old NTSC and the 6572 on PAL-N. badline restores such a
snapshot from its own modules, and leaves VICE's alone.

x64sc 3.10 opens those snapshots, which are saved between
instructions with no REU transfer under way, as long as its VIC-II
model matches: `-model c64`, `c64c`, `ntsc`, `newntsc`,
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
