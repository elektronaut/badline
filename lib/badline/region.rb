# frozen_string_literal: true

module Badline
  # = Region
  #
  # The timing and geometry a video standard gives the machine.
  module Region
    # The CPU clock, the VIC's raster, where the beam is blanked, the display
    # window's edges, the part of the raster a front end shows, the mains
    # frequency that feeds the CIAs' TOD pins, and where the VIC's sprite
    # fetches and X counter sit in the line.
    #
    # Columns are the VIC's cycles within a line, counted from 0, and a
    # column draws 8 pixels, so the raster is `cycles_per_line * 8` pixels
    # wide. `hblank` and `vblank` are the [first, last] blanked column and
    # line, inclusive, and wrap past the end of the line or frame when first
    # is the larger. `display_x_bounds` holds the display window's
    # [left, right] pixels per CSEL state, 38 columns then 40, and `crop`
    # the [left, top, width, height] a front end shows.
    #
    # `sprite_cycle` is Bauer's cycle for sprite 0's p-access, and each
    # sprite after it takes two more. `sprite_display_cycle` is the cycle
    # that turns a sprite's display on or off. `x_hold` is how many pixels
    # the X counter spends past its run, repeating $184-$187, and a raster
    # of more than 512 pixels needs them.
    Profile = Data.define(:name, :clock_hz, :cycles_per_line, :lines_per_frame, :hblank, :vblank,
                          :display_x_bounds, :crop, :mains_hz, :sprite_cycle, :sprite_display_cycle,
                          :x_hold)

    # The 6569 of a PAL C64: 63 cycles by 312 lines at 985,248 Hz, with
    # 50 Hz mains.
    PAL = Profile.new(
      name: :pal, clock_hz: 985_248, cycles_per_line: 63, lines_per_frame: 312,
      hblank: [61, 9].freeze, vblank: [300, 15].freeze,
      display_x_bounds: [[135, 438].freeze, [128, 447].freeze].freeze,
      crop: [96, 20, 384, 272].freeze, mains_hz: 50,
      sprite_cycle: 58, sprite_display_cycle: 58, x_hold: 0
    )

    # The 6567R8 of an NTSC C64: 65 cycles by 263 lines at 1,022,727 Hz,
    # with 60 Hz mains. The sprite fetches and the compares ahead of them
    # run a cycle later than on the 6569 (the spritesteal, spritex and
    # phi1timing testprogs), and the X counter pauses near $184, as Bauer's
    # 6567R8 diagram shows, reading $184-$187 for 8 pixels more. The
    # blanked lines are the ones VICE's NTSC view leaves out, 12-27. It shows lines 0-11 below
    # line 262, and the crop leaves those out.
    NTSC = Profile.new(
      name: :ntsc, clock_hz: 1_022_727, cycles_per_line: 65, lines_per_frame: 263,
      hblank: [63, 9].freeze, vblank: [12, 27].freeze,
      display_x_bounds: [[135, 438].freeze, [128, 447].freeze].freeze,
      crop: [96, 28, 384, 235].freeze, mains_hz: 60,
      sprite_cycle: 59, sprite_display_cycle: 59, x_hold: 8
    )

    # The 6567R56A of the first NTSC C64s: 64 cycles by 262 lines at
    # 1,022,727 Hz. Its sprite fetches run a cycle later than the 6569's,
    # as on the 6567R8, but it turns the display on in the same cycle as
    # the 6569, and its X counter runs straight through 512 pixels, one
    # coordinate for each.
    NTSC_OLD = Profile.new(
      name: :ntscold, clock_hz: 1_022_727, cycles_per_line: 64, lines_per_frame: 262,
      hblank: [62, 9].freeze, vblank: [13, 27].freeze,
      display_x_bounds: [[135, 438].freeze, [128, 447].freeze].freeze,
      crop: [96, 28, 384, 234].freeze, mains_hz: 60,
      sprite_cycle: 59, sprite_display_cycle: 58, x_hold: 0
    )

    # The 6572 of the Drean C64, sold in Argentina on PAL-N: 65 cycles by
    # 312 lines at 1,023,440 Hz, with 50 Hz mains. It lays out the line
    # as the 6567R8 does, sprite fetches and X counter hold included
    # (spritescan_drean), and blanks and crops lines as PAL does.
    DREAN = Profile.new(
      name: :drean, clock_hz: 1_023_440, cycles_per_line: 65, lines_per_frame: 312,
      hblank: [63, 9].freeze, vblank: [300, 15].freeze,
      display_x_bounds: [[135, 438].freeze, [128, 447].freeze].freeze,
      crop: [96, 20, 384, 272].freeze, mains_hz: 50,
      sprite_cycle: 59, sprite_display_cycle: 59, x_hold: 8
    )

    # Whether a column or line lies in a [first, last] blanking span.
    def self.blanked?(position, span)
      first, last = span
      return position.between?(first, last) if first <= last

      position >= first || position <= last
    end
  end
end
