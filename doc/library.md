# Using badline from Ruby

The gem is also a library, which runs a `Badline::Computer` from Ruby
without a window.

```ruby
require "badline"

computer = Badline::Computer.new
Badline::Media.attach(computer, "game.d64")         # attaches and autostarts
computer.on_init { computer.type_text("print 6*7\r") } # once the machine has booted
3_500_000.times { computer.cycle! }
computer.address_bus.peek(0x0400)                   # screen RAM starts at $0400
```

[media.md](media.md) covers attaching and swapping media, and
[snapshots.md](snapshots.md) saving and restoring the machine.

## Building a machine

`Badline::Computer.new` builds the default machine: a PAL C64 with the
6569 VIC-II, 6526 CIAs and a 6581 SID. Its keywords build others:

- `vic_model: :mos8565` fits the C64C's 8565, with its grey dots on
  colour register writes and its own timing for mode splits, sprite
  multicolour splits and the light pen.
- `region: Badline::Region::NTSC` builds an NTSC machine: the 6567R8's
  65 cycles by 263 lines at 1,022,727 Hz, with its later sprite fetches
  and its X counter, and TOD clocks on 60 Hz mains.
  `Badline::Region::NTSC_OLD` is the first NTSC C64s' 6567R56A, 64 cycles
  by 262 lines. The stock KERNAL tells them from PAL by the raster, so
  every region boots the same ROMs.
- `cia_model: :mos6526a` fits the C64C's 6526As, whose interrupt
  register timing differs.
- `sid_model: :mos8580` fits the 8580.
- `ram_expansion: :plus60k` or `:plus256k` fits the +60K or +256K RAM
  expansion, banked through its register at `$D100`.
- `reu: 512` plugs in a RAM Expansion Unit of that many K.

## Cartridges

`Media.attach(computer, path, cartridge: { flash_jumper: true })` sets
the Retro Replay's flash jumper, which makes its flash take writes, and
`bank_jumper: true` runs it from the second 64K of a 128K image.
EasyFlash and GMod2 flash take writes through the chip's command set
(program, sector and chip erase, autoselect), so games and EAPI can save
to it. An EasyFlash image's EAPI is swapped for a bundled copy of the
Am29F040 EAPI on attach, as VICE does. Flash writes stay in memory and
are lost when the emulator quits: the `.crt` file is never overwritten.

A GEO-RAM takes the expansion port, so it can't sit alongside a
cartridge: `computer.attach_cartridge(Badline::Cartridge::GeoRAM.new(size: 512))`.
Its contents are lost when the emulator quits.

## ROMs

The KERNAL, BASIC and character ROMs come with the gem. To run other
images, such as a patched KERNAL, point `BADLINE_ROM_PATH` at a
directory that holds `kernal.rom`, `basic.rom` and `character.rom`, plus
`eapi/eapi-am29f040-14` if you attach EasyFlash cartridges.
`Badline.rom_path = dir` does the same before a `Badline::Computer` is
built, and `nil` restores the bundled set.
