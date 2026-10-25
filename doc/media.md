# Media

The [README](../README.md#media) lists the formats badline takes. This
page covers how device 8 and the true 1541 work, and how to attach media
from Ruby.

## Device 8 without a drive

Apart from a `.g64`, which only a true drive can read, there is no 1541
unless `--true-drive` asks for one. Device 8 works by trapping the
KERNAL's `LOAD` and `SAVE` routines and its serial bus primitives, so
files open by name through `OPEN` and `CHRIN` as well. `LOAD"$",8` lists
the directory of any medium mounted there, as a 1541 does.

The command channel answers `I`, `B-P` and `U1` block reads, which
covers loaders that read blocks directly. On a writable disk image it
also takes `SAVE` (with `@0:` to replace a file), files opened for
writing or appending, `S` to scratch, `U2` and `B-W` block writes,
`B-A` and `B-F`, `N` to format the disk (or, without an ID, clear it),
`R` to rename a file and `C` to copy or join files, with the reports a
2031 or 8050 gives. It acts as a single drive, so it doesn't duplicate
or copy whole disks (`D`, `C1=0`), and it doesn't validate disks.
Loaders that upload their own code to the drive with `M-W` and `M-E`,
and copy protection that reads raw GCR, won't work there, but do on a
true drive.

A directory mounted as device 8 serves the `.prg` and `.p00` files in it
and the contents of any `.t64`, and `SAVE` writes a new `.prg`.

## The true 1541

`--true-drive` puts an emulated 1541 on device 8 instead, running its
own DOS ROM on its own 6502 and talking to the machine over the serial
bus. It reads `.d64` and `.g64` images, which it autostarts with the
same `LOAD"*",8,1` and `RUN`, but not `.d71`, `.d81` or `.t64` images
or directories. Loading runs at the speed of a real 1541, and the
drive's red activity LED and green power LED light in the bottom right
corner of the border. A 1581 flashes its power LED after an error.

On the Plus/4 and the C16, `--true-drive` puts an emulated 1551 there
instead, on TCBM, the parallel cable to its interface in the expansion
port, and `--drive-type 1541` a 1541 on the serial bus.

On the PET, `--true-drive` puts an emulated 2031 there, the 1541's board
with an IEEE-488 interface, running DOS 2.6 and answering the bus's
handshake line by line. It reads `.d64` and `.g64` images, which BASIC 2
and 4 autostart with `LOAD"*",8` and `RUN`; a `.d80` or `.d82` needs the
traps. BASIC 1's LOAD never finishes on the drive, since its UNLISTEN
leaves its command in the device number the LOAD then talks to, but its
OPEN, INPUT# and PRINT# work, and the error channel with them. `--basic
2`, the upgrade Commodore sold, loads.

A `.g64` holds the disk's raw GCR, half tracks and all, so copy
protection and fast loaders that read it work.

## The true 1581

With a true drive on device 8, a `.d81` goes in an emulated 1581 in
its place: the 3.5" drive's own DOS on its 6502, with its WD1772 reading
and writing the image's sectors and its 8520 on the serial bus. Another
disk image swaps the 1541 (or on the C128 the 1571) back in. On the
C128 in C128 mode the 1581 talks fast serial (burst), as the 1571 does.

## C128 boot disks

At power-on the C128 KERNAL reads track 1, sector 0 of the disk in
device 8, and when the block starts with `CBM` it loads and runs it.
CP/M's system disks and boot games boot that way. A 1581 first loads and
runs a `USR` file named `COPYRIGHT CBM 86` when the disk has one, which
is how CP/M's 1581 disks hand the KERNAL their boot block.

On a C128 in C128 mode, a `.d64`, `.d71` or `.d81` that boots, with that
block or that file, goes in a true drive as device 8, a 1581 for a
`.d81` and the C128D's 1571 otherwise, and nothing is typed, so the
KERNAL boots it. `badline c128 cpm3.d81` comes up at CP/M's `A>`
prompt. Other disks keep the traps and `LOAD"*",8,1`, `--true-drive`
puts any disk in a true drive, and on the C64, the VIC-20 and a C128 in
C64 mode nothing changes. A boot disk inserted while the machine runs
boots at the next reset.

## Write protection

Disks given on the command line, inserted from the pause menu or by an
`--at` insert go in write-protected, so the drive reports
`26,WRITE PROTECT ON` for any write and the image file stays as it was.
`--writable`, or WRITABLE on the pause menu's Drive page, lets writes go
straight back to the image file. An image the host can't write, and a
`.t64`, stay write-protected.

## From Ruby

`Badline::Media.attach(computer, path)` attaches any medium the
command line takes, and autostarts it unless given `autostart: false`.
`Badline::Media.insert_disk(computer, path)` swaps the disk image or
directory in device 8 while the machine runs, for software that asks for
another disk. Both write to disk images unless told otherwise:
`insert_disk` takes `read_only: true`, and `attach` takes
`disk: { read_only: true }`, as the test harnesses under `bin/` do. A
`.g64` goes in the true 1541, and takes out a disk mounted through the
traps, so `LOAD` and `SAVE` reach the 1541 too. With the 1541 in device
8, a `.d64` goes in its drive as well, and a `.d81` in a 1581 that takes
the 1541's place. On a C128 in C128 mode, `attach` puts a boot disk in a
true drive and types nothing (`Badline::Media::BootDisk`).

`Badline::Media::DiskSet.around(path)` lists the disks of the set a disk
image belongs to, which the pause menu's PREVIOUS DISK and NEXT DISK step
through. An `.m3u` or `.vfl` list in the disk's folder that names it
gives the set. Without one, the set is found by name in the folder.
Given a list, it returns the disks the list names.

A list names one disk image a line, as a path relative to the list or an
absolute one. Blank lines and lines starting with `#` are skipped, and
entries that aren't there are left out. In a VICE `.vfl` flip list, only
the entries after a `UNIT 8` line, or before any `UNIT` line, count.
`Media.attach` and the command line take a list as media and attach its
first disk.

## Recording to tape

From Ruby, a blank tape made with
`Badline::Storage::TAP.create(path, platform:)` (0 for the C64, 1 for
the VIC-20, 2 for the Plus/4 and the C16) goes in the datasette with
`computer.datasette.insert`, `record!` presses RECORD and PLAY, and
`stop!` lets them up and writes the tape to its file. The C64 and the
VIC-20 record version 1 TAPs, and the Plus/4 and the C16 version 2 TAPs
of half waves.

A program SAVEd that way on the C64 loads and runs in VICE's x64sc, on
the VIC-20 in xvic, and on the Plus/4 or the C16 in xplus4 as a Plus/4.
xplus4's C16 model loads no tape, its own included (#704).
Checked with VICE 3.10.

## The light pen

Control port 1's fire line is also the VIC-II's light pen input, so
joystick 1's fire button and the 1351's left button in port 1 latch the
light pen registers. On the VIC-20 the joystick's fire line is the
VIC-I's light pen input, and the fire button latches `$9006` and `$9007`.
