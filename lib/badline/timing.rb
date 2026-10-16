# frozen_string_literal: true

module Badline
  # = Timing
  #
  # What a front end needs to run a machine's frames and show them: the CPU
  # clock, the raster's cycles per line and lines per frame, and the
  # [left, top, width, height] of the raster it shows, how many of the
  # window's square pixels wide each of its pixels shows, and how many of
  # its pixels share one window pixel, as an 80-column screen's dots do.
  # Each machine derives it from its region.
  Timing = Data.define(:clock_hz, :cycles_per_line, :lines_per_frame, :crop, :pixel_width, :dots)
end
