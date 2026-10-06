# frozen_string_literal: true

require "badline/vic20/region"
require "badline/vic20/vic/fetches"
require "badline/vic20/vic/pixels"
require "badline/vic20/vic/color_writes"
require "badline/vic20/vic/video_bus"

module Badline
  class Vic20
    # The VIC-I, the 6561 on PAL machines: its sixteen registers, its raster
    # and its picture, without the sound.
    #
    # The registers repeat through $9000-$90FF. $9003 bit 7 and $9004 read
    # the raster line, its bit 0 and bits 8-1. $9006 and $9007 read the
    # light pen, which nothing triggers yet, and $9008 and $9009 the two
    # pots, which read $FF with nothing plugged in. The other registers
    # read back what was written to them.
    #
    # == The picture
    #
    # Each cycle the VIC draws four pixels. Inside the text window it
    # spends two cycles on a character, both in the half of the cycle the
    # CPU leaves alone: one fetch from the video matrix, which brings the
    # colour nibble from colour RAM alongside, then one from the character
    # generator. Outside the window it fetches nothing and draws the
    # border. Fetches has the window and the fetches, and Pixels the
    # pixels. #display holds a palette index for each pixel, #width to a
    # line, and #dirty_lines marks the lines that changed.
    #
    # VideoBus has its side of the bus.
    class VIC
      include Fetches
      include Pixels
      include ColorWrites
      include VideoBus

      # The sixteen colours #display's indices stand for, as RGB. Built from
      # the 6561's colour signals as Wikipedia's "MOS Technology VIC" table
      # gives them: four luma levels above black (Y of 0.25, 0.5, 0.75 and
      # 1), and chroma at unit amplitude on angles that are multiples of
      # 22.5 degrees. The chroma is scaled by 0.2 and each colour converted
      # with the ITU-R BT.601 YPbPr equations, clamped to 0-255.
      PALETTE = [
        0x000000, 0xffffff, 0x82251d, 0x7ddae2,
        0xb259bf, 0x4da640, 0x402e9a, 0xbfd165,
        0xb27240, 0xf2b27f, 0xc2655d, 0xbdffff,
        0xf299ff, 0x8de57f, 0x806eda, 0xffffa5
      ].freeze

      # The cycles from the one that draws a pixel group to the start of
      # the display line it belongs to.
      PIXEL_DELAY = 8

      # The cycles from a character generator fetch to its first pixels.
      LOAD_DELAY = 3

      # The cycles from the horizontal origin's match to the first fetch.
      FETCH_DELAY = 4

      # Where the vertical half of the window stands in the frame.
      V_IDLE = 0
      V_DONE = 1
      V_PENDING = 2
      V_DISPLAY = 3

      # What the fetches on the current line are doing.
      H_IDLE = 0
      H_START = 1
      H_MATRIX = 2
      H_CHARACTER = 3
      H_DONE = 4

      # What sits at each 256-byte page of the VIC's address space.
      PAGE_RAM = 0
      PAGE_ROM = 1
      PAGE_COLOR = 2
      PAGE_EMPTY = 3

      attr_reader :rasterline, :column, :display, :width, :height, :dirty_lines, :region

      # Whether the VIC paints its display. A run that never looks at it can
      # leave it off, and the fetches still happen.
      attr_accessor :render

      def initialize(region = Region::PAL)
        @region = region
        @cycles_per_line = region.cycles_per_line
        @lines_per_frame = region.lines_per_frame
        @max_columns = region.max_columns
        @width = @cycles_per_line * 4
        @height = @lines_per_frame
        @display = Array.new(@width * @height, 0)
        @dirty_lines = Array.new(@height, true)
        @line = Array.new(@width, 0)
        @pages = Array.new(64) { |page| page_kind(page) }.freeze
        @ram = nil
        @character_rom = nil
        @color_ram = nil
        @bus = nil
        @render = true
        power_on!
      end

      # Hooks the VIC to the machine's bus: its RAM, character ROM and
      # colour RAM for the fetches, and the V-bus's data lines they leave
      # their bytes on.
      def connect(bus)
        @bus = bus
        @ram = bus.ram
        @character_rom = bus.character_rom
        @color_ram = bus.color_ram
      end

      # The power-on state: the registers cleared, the raster at the top
      # of the frame and the window shut. The VIC has no RES pin, so only
      # power reaches it.
      def power_on!
        @registers = Array.new(16, 0)
        @rasterline = 0
        @column = 0
        @tick = 0
        @v_state = V_IDLE
        @h_state = H_IDLE
        @countdown = 0
        @rows = 0
        @row_count = 0
        @columns = 0
        @pending_columns = 0
        @char_height = 8
        @ycounter = 0
        @memptr = 0
        @memptr_step = 0
        @index = 0
        @code = 0
        @code_color = 0
        @blank_line = true
        @blank_last_line = true
        @load_pattern = Array.new(4, 0)
        @load_color = Array.new(4, -1)
        @pattern = 0
        @pattern_color = 0
        @second_half = false
        @border_from = -1
        @background = @border = @auxiliary = @reverse = 0
        @old_background = @old_border = @old_auxiliary = @old_reverse = 0
        @colors_changed = false
        @display.fill(0)
        @line.fill(0)
        @dirty_lines.fill(true)
      end

      def cycle!
        open_vertical if @v_state == V_IDLE && @registers[1] == (@rasterline >> 1)
        column = advance
        check_window(column) if @v_state >= V_PENDING
        latch(column) if column < 3
        fetch if @h_state != H_IDLE
        draw(column) if @render
        sync_colors if @colors_changed
        @tick += 1
      end

      # The sixteen registers as written.
      def register_file = @registers.dup

      # Reset the dirty flags once the front end has consumed them.
      def clear_dirty_lines!
        @dirty_lines.fill(false)
      end

      def palette = PALETTE

      def peek(addr)
        register = addr & 0x0f
        case register
        when 0x03 then ((@rasterline & 0x01) << 7) | (@registers[3] & 0x7f)
        when 0x04 then @rasterline >> 1
        when 0x06, 0x07 then 0
        when 0x08, 0x09 then 0xff
        else @registers[register]
        end
      end

      def poke(addr, value)
        register = addr & 0x0f
        @registers[register] = value
        case register
        when 0x03 then @char_height = value.anybits?(0x01) ? 16 : 8
        when 0x0e then set_colors(@background, @border, value >> 4, @reverse)
        when 0x0f then set_colors(value >> 4, value & 0x07, @auxiliary, value.anybits?(0x08) ? 0 : 1)
        end
      end
    end
  end
end
