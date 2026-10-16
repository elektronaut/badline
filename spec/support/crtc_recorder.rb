# frozen_string_literal: true

# A CRTC's output that keeps what the CRTC hands it: each displayed
# character's [MA, RA, characters since horizontal sync], and how many
# horizontal syncs, line ends, rows ends and frame starts there were.
class CRTCRecorder
  attr_reader :characters, :hsyncs, :line_ends, :rows_ends, :frame_starts

  def initialize
    clear
  end

  def clear
    @characters = []
    @hsyncs = 0
    @line_ends = 0
    @rows_ends = 0
    @frame_starts = 0
  end

  def character(address, raster, since_hsync)
    @characters << [address, raster, since_hsync]
  end

  def hsync = @hsyncs += 1

  def line_end = @line_ends += 1

  def rows_end = @rows_ends += 1

  def frame_start = @frame_starts += 1
end
