# frozen_string_literal: true

require "badline/vic20/vic/painter"
require "badline/vic20/vic/text_window"

module Badline
  class Vic20
    # The VIC-I, the 6561 on PAL machines: its sixteen registers, the
    # raster, the text window's fetches over the V-bus and the picture. The
    # writes to the sound's registers, $900A-$900E, go on to the Sound
    # attached as #sound.
    #
    # The registers repeat through $9000-$90FF. $9003 bit 7 and $9004 read
    # the raster line, its bit 0 and bits 8-1. $9006 and $9007 read the
    # light pen, which nothing triggers yet, and $9008 and $9009 the two
    # pots, which read $FF with nothing plugged in. The other registers
    # read back what was written to them.
    #
    # The text window opens on the line where the raster's bits 8-1 match
    # $9001, and closes after the number of text rows in $9003, each 8 lines
    # of a character, or 16 with $9003 bit 0 set. On each of its lines the
    # VIC fetches two bytes a character, $9002's count of them: the
    # character code from the video matrix, with the colour nibble beside it
    # on the colour bus, then the character's pattern byte for the line.
    # The first code is fetched four cycles after the column in $9000, so
    # the window starts 16 cycles into the line with the KERNAL's origin of
    # 12, and none is fetched past the end of the line. The fetches go to a
    # 14-bit address, the VIC's own (see Bus#video_fetch), and the byte each
    # one reads is the V-bus's last byte. Outside the window the 6561E
    # fetches nothing and the V-bus keeps the CPU's last byte there.
    #
    # The video matrix counter steps once a character. It starts each line
    # of a text row where the row started, and the next row starts where
    # the last line of the row left it. It starts the frame at zero.
    #
    # The picture is 4 pixels a cycle, so 284 a line. A character's 8
    # pixels come out in the two cycles after its pattern fetch. The
    # display's lines start 6 cycles after the raster count moves, as
    # xvic's view of the frame does, so the character fetched 16 cycles
    # into the line lands 48 pixels in. Lines 0-27 are blanked.
    class VIC
      include TextWindow

      # What a VIC-I sets for the machine: the clock, the raster's cycles
      # per line and lines per frame, and how many lines at the top of the
      # frame it blanks. The 6560 of NTSC machines, with its half lines and
      # the interlace of $9000 bit 7, would be another.
      Profile = Data.define(:clock_hz, :cycles_per_line, :lines_per_frame, :blanked_lines)

      # The 6561: 71 cycles by 312 lines, lines 0-27 blanked (Marko
      # Mäkelä's VIC-I.txt).
      PAL = Profile.new(clock_hz: 1_108_405, cycles_per_line: 71, lines_per_frame: 312, blanked_lines: 28)

      PIXELS_PER_CYCLE = 4

      # The column whose pixels start a line of the display.
      FIRST_PIXEL_COLUMN = 6

      # How many cycles after the column in $9000 the first code is fetched.
      FETCH_DELAY = 4

      # The colours, as RGB, each from its luma and chroma: luma in five
      # levels from black to white, and chroma at one strength in a phase
      # that steps by 22.5 degrees from blue's. The levels and phases are
      # the VIC-I's table on Wikipedia's "MOS Technology VIC" (Y, Pb, Pr),
      # turned into RGB with the BT.601 matrix and the chroma scaled by 0.2.
      PALETTE = [
        0x000000, 0xffffff, 0x82251d, 0x7ddae2, 0xb259bf, 0x4da640, 0x402e9a, 0xbfd165,
        0xb27240, 0xf2b27f, 0xc2655d, 0xbdffff, 0xf299ff, 0x8de57f, 0x806eda, 0xffffa5
      ].freeze

      attr_reader :rasterline, :column, :profile
      attr_accessor :sound

      def initialize(profile = PAL)
        @profile = profile
        @cycles_per_line = profile.cycles_per_line
        @lines_per_frame = profile.lines_per_frame
        @painter = Painter.new(@lines_per_frame, @cycles_per_line * PIXELS_PER_CYCLE, profile.blanked_lines)
        @patterns = @painter.patterns
        @colors = @painter.colors
        @counts = @painter.counts
        @starts = @painter.starts
        @stale = @painter.stale
        @bus = nil
        @sound = nil
        @color_cells = Array.new(0x400, 0)
        power_on!
      end

      # The bus the VIC fetches from, the machine's, and the colour RAM
      # whose cells come in on the colour bus beside each code.
      def connect(bus)
        @bus = bus
        @color_cells = bus.color_ram.cells
      end

      # The power-on state: the registers cleared and the raster at the top
      # of the frame. The VIC has no RES pin, so only power reaches it.
      def power_on!
        @registers = Array.new(16, 0)
        @rasterline = 0
        @column = 0
        @origin_x = @origin_y = @columns = @rows = 0
        @char_shift = 3
        @screen_base = @char_base = 0
        new_frame
        @fetch_from = @fetch_to = 0
        @fetched = @slot = 0
        @code = 0
        @painter.power_on!(@lines_per_frame - 1)
        schedule
      end

      def cycle!
        column = @column + 1
        @column = column
        return unless column == @next_event

        if column > FIRST_PIXEL_COLUMN && column < @fetch_to && column >= @fetch_from
          access(column)
          column += 1
          @next_event = column < @fetch_to ? column : @cycles_per_line
        else
          event(column)
        end
      end

      # The sixteen registers as written.
      def register_file = @registers.dup

      # The display, a palette index a pixel, 284 to a line and every line
      # of the frame.
      def display = @painter.display

      def width = @painter.width

      def height = @lines_per_frame

      # Whether each line of the display has changed since the front end
      # last cleared them.
      def dirty_lines = @painter.dirty_lines

      def clear_dirty_lines! = @painter.clear_dirty_lines!

      def palette = PALETTE

      # Whether the VIC paints its display. It fetches either way.
      def render = @painter.render

      def render=(value)
        @painter.render = value
      end

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
        when 0x00, 0x02 then window_written
        when 0x01 then @origin_y = value
        when 0x03 then rows_written(value)
        when 0x05 then bases_written
        when 0x0a, 0x0b, 0x0c, 0x0d then @sound&.write(register, value)
        when 0x0e
          @painter.aux_written(pixel_position, value >> 4)
          @sound&.write(register, value)
        when 0x0f then @painter.colors_written(pixel_position, value)
        end
      end

      private

      def event(column)
        if column == @cycles_per_line
          column = @column = 0
          start_line
        end
        @painter.finish_line(@rasterline) if column == FIRST_PIXEL_COLUMN
        access(column) if column >= @fetch_from && column < @fetch_to
        schedule
      end

      # The next column with something to do: the end of the line, the
      # start of a display line, or a fetch.
      def schedule
        column = @column
        upcoming = column < FIRST_PIXEL_COLUMN ? FIRST_PIXEL_COLUMN : @cycles_per_line
        fetch = column < @fetch_from ? @fetch_from : column + 1
        upcoming = fetch if fetch < @fetch_to && fetch < upcoming
        @next_event = upcoming
      end

      def start_line
        line = @rasterline + 1
        if line == @lines_per_frame
          line = 0
          new_frame
        end
        @rasterline = line
        next_text_line if @window_open
        open_window if !@window_open && !@window_done && (line >> 1) == @origin_y && @rows.positive?
        place_fetches
      end

      def place_fetches
        line = @rasterline
        @slot = line * Painter::SLOTS
        @fetched = @counts[line] = 0
        @starts[line] = @origin_x * PIXELS_PER_CYCLE
        unless @window_open
          @fetch_from = @fetch_to = 0
          return
        end

        @fetch_from = @origin_x + FETCH_DELAY
        fetches_end
      end

      def fetches_end
        last = @fetch_from + (2 * @columns)
        @fetch_to = [last, @cycles_per_line].min
      end

      def access(column)
        slot = @slot + @fetched
        if (column - @fetch_from).even?
          address = (@screen_base + @matrix) & 0x3fff
          @code = @bus.video_fetch(address)
          color = @color_cells[address & 0x3ff]
          return if @colors[slot] == color

          @colors[slot] = color
        else
          pattern = @bus.video_fetch((@char_base + (@code << @char_shift) + @char_line) & 0x3fff)
          @matrix += 1
          @fetched += 1
          @counts[@rasterline] = @fetched
          return if @patterns[slot] == pattern

          @patterns[slot] = pattern
        end
        @stale[@rasterline] = true
      end

      # The pixel of the display line a register write in this cycle takes
      # hold from: the second of the cycle's four.
      def pixel_position
        column = @column - FIRST_PIXEL_COLUMN
        column += @cycles_per_line if column.negative?
        (column * PIXELS_PER_CYCLE) + 1
      end
    end
  end
end
