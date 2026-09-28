# frozen_string_literal: true

module Badline
  # = Region
  #
  # The timing and geometry a video standard gives the machine.
  module Region
    # The CPU clock, the VIC's raster, where the beam is blanked, the display
    # window's edges, the part of the raster a front end shows, and the
    # mains frequency that feeds the CIAs' TOD pins.
    #
    # Columns are the VIC's cycles within a line, counted from 0, and a
    # column draws 8 pixels, so the raster is `cycles_per_line * 8` pixels
    # wide. `hblank` and `vblank` are the [first, last] blanked column and
    # line, inclusive, and wrap past the end of the line or frame when first
    # is the larger. `display_x_bounds` holds the display window's
    # [left, right] pixels per CSEL state, 38 columns then 40, and `crop`
    # the [left, top, width, height] a front end shows.
    Profile = Data.define(:name, :clock_hz, :cycles_per_line, :lines_per_frame, :hblank, :vblank,
                          :display_x_bounds, :crop, :mains_hz)

    # The 6569 of a PAL C64: 63 cycles by 312 lines at 985,248 Hz, with
    # 50 Hz mains.
    PAL = Profile.new(
      name: :pal, clock_hz: 985_248, cycles_per_line: 63, lines_per_frame: 312,
      hblank: [61, 9].freeze, vblank: [300, 15].freeze,
      display_x_bounds: [[135, 438].freeze, [128, 447].freeze].freeze,
      crop: [96, 20, 384, 272].freeze, mains_hz: 50
    )

    # The 6567R8 of an NTSC C64: 65 cycles by 263 lines at 1,022,727 Hz,
    # with 60 Hz mains, and lines 13-40 blanked (Bauer). The machine does
    # not run it yet: the blanked columns and the display window are PAL's
    # stand-ins, and the crop leaves out lines 0-12, which show below the
    # last line.
    NTSC = Profile.new(
      name: :ntsc, clock_hz: 1_022_727, cycles_per_line: 65, lines_per_frame: 263,
      hblank: [61, 9].freeze, vblank: [13, 40].freeze,
      display_x_bounds: [[135, 438].freeze, [128, 447].freeze].freeze,
      crop: [96, 41, 384, 222].freeze, mains_hz: 60
    )

    # Whether a column or line lies in a [first, last] blanking span.
    def self.blanked?(position, span)
      first, last = span
      return position.between?(first, last) if first <= last

      position >= first || position <= last
    end
  end
end
