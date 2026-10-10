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
writing or appending, `S` to scratch, `U2` and `B-W` block writes, and
`B-A` and `B-F`. It doesn't rename, copy, format or validate disks.
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
drive's red LED lights in the bottom right corner of the border.

A `.g64` holds the disk's raw GCR, half tracks and all, so copy
protection and fast loaders that read it work.

## The true 1581

With a true drive on device 8, a `.d81` goes in an emulated 1581 in
its place: the 3.5" drive's own DOS on its 6502, with its WD1772 reading
and writing the image's sectors and its 8520 on the serial bus. Another
disk image swaps the 1541 (or on the C128 the 1571) back in. On the
C128 in C128 mode the 1581 talks fast serial (burst), as the 1571 does.

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
the 1541's place.

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

## The light pen

Control port 1's fire line is also the VIC-II's light pen input, so
joystick 1's fire button and the 1351's left button in port 1 latch the
light pen registers.
