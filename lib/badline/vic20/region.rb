# frozen_string_literal: true

module Badline
  class Vic20
    # = Vic20::Region
    #
    # The timing and geometry a video standard gives the VIC-20: the CPU
    # clock, the VIC-I's raster, the most text columns it fetches, and the
    # [left, top, width, height] of the raster a front end shows.
    #
    # The raster is four pixels a cycle, so `cycles_per_line * 4` wide, and
    # its pixel 0 is where a screen origin ($9000) of 0 puts the first
    # character. The crop is VICE's view of the frame, which xvic's
    # screenshots show and the testbench's references were taken from.
    module Region
      Profile = Data.define(:name, :clock_hz, :cycles_per_line, :lines_per_frame, :max_columns, :crop)

      # The 6561 of a PAL VIC-20: 71 cycles by 312 lines at 1,108,405 Hz.
      PAL = Profile.new(
        name: :pal, clock_hz: 1_108_405, cycles_per_line: 71, lines_per_frame: 312,
        max_columns: 32, crop: [0, 28, 284, 284].freeze
      )
    end
  end
end
