# What 1.0 promises

From 1.0 on, the things this page names stay as they are through 1.x,
and change only with a major version. Everything it doesn't name is
internal: it can move, be renamed or go away in a minor release. Ruby
can't hide a class, so this page is the contract.

## The command line

Both executables, `badline` (native) and `badline-ruby` (CRuby), with
their subcommands `c64`, `vic20`, `c128` and `sid`, every option
`--help` lists, the `--at` and `--script` event grammar, and what
`--headless` and `--audio-out` print.

Each exits with `0` when the run ends as asked, and `1` when the
options can't be parsed, the window can't be opened or a tune couldn't
be played.

The pause menu is UI, not API. Its pages, rows and keys can change in a
minor release, as can the window's key bindings and the on-screen hints.

## The library

What [library.md](library.md), [media.md](media.md) and
[snapshots.md](snapshots.md) document, and nothing else:

- Building a machine: `Badline::Machine.build(family, model:, sid_model:,
  reu:, ram:)`, and `Badline::C64.new`, `Badline::Vic20.new` and
  `Badline::C128.new` with the keywords those pages name.
  `Badline::Model`, `Badline::C128::Model` and `Badline::Region` and
  their constants.
- The machine contract, as `lib/badline/machine.rb` describes it:
  identity, clocking, lifecycle, video, sound, input, media, snapshots
  and tests, with the parts of it that page says each family answers,
  and the C128's own additions it names.
- Memory through the machine: `peek(addr)`, `poke(addr, value)` and
  `ram`. The bus a machine runs on is reachable through `address_bus`
  but not promised, so it can be reshaped without breaking callers.
- Media: `Badline::Media.attach`, `Badline::Media.insert_disk` and
  `Badline::Media::DiskSet.around`, with the keywords media.md names.
- Snapshots: `Badline::Snapshot.load(path)`, and on a machine
  `snapshot`, `restore`, `save_snapshot` and `restore_snapshot`.
- Paths: `Badline.rom_path=` and `Badline.data_path=`.
- Driving a machine headlessly: `on_init`, `type_text`, `capture_output`
  and `install_debug_register`, which the runners under `bin/` and
  headless scripts depend on.
- The errors a caller rescues, which keep their names and their
  ancestors: `Badline::Machine::Unsupported`, `Badline::Media::NotDisk`,
  `Badline::Media::DiskList::Error`, `Badline::Media::TrueDrive::Error`,
  `Badline::Drives::Datasette::Missing`, `Badline::Storage::WriteError`
  with its DOS error `code`, the `FormatError` of `Badline::Storage::T64`,
  `Tap`, `CRTFile` and `G64Image`, `Badline::SIDTune::File::FormatError`,
  `Badline::Snapshot::FormatError`,
  `Badline::C64::Cartridge::UnsupportedTypeError` and
  `Badline::Options::Error`.

Not promised: the chips (`Badline::Chips`, their readers and their
registers), the buses, the cartridge mappers' constructors,
`Badline::KernalTrap`, `Badline::Drives` beyond the datasette's error,
`Badline::Storage` beyond its errors, `Badline::Support`,
`Badline::Options`, `Badline::Frontend` and `Badline::Audio`. The specs
and the runners use them; a program built on the gem shouldn't.

## The snapshot format

A `.vsf` file: VICE's modules for the chips x64sc reads, and a
`BADLINE` module holding the whole machine, as snapshots.md describes.
Until 1.0 a snapshot restores only in the badline version that wrote
it. 1.0 settles the `BADLINE` module's layout per chip, and from then
on a 1.x reads any snapshot a 1.x wrote: a field added later takes a
default when it's missing, and a field dropped later is ignored.

## The data folder

The data folder's location, `BADLINE_DATA_PATH`, its `quicksaves`,
`autosaves` and `saves` subfolders, the slot names `quicksave-1.vsf` to
`quicksave-5.vsf` and `autosave-1.vsf` to `autosave-3.vsf`, and `.vsf`
as the file type.
