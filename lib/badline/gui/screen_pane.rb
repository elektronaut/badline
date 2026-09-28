# frozen_string_literal: true

module Badline
  module GUI
    # The part of the VIC's raster the machine's region crops out.
    class ScreenPane < Pane
      def initialize(computer, left: 0, top: 0, palette: Palette.new)
        @col_offset, @row_offset, crop_width, crop_height = computer.region.crop
        super(width: crop_width, height: crop_height, left:, top:)
        @computer = computer
        @row_bytes = width * 4
        @palette = palette.dwords
        @buffer = ("\x00" * (height * @row_bytes)).b
      end

      def render(renderer)
        blit(renderer, framebuffer)
      end

      private

      # Repack only the scanlines the VIC has touched since the last frame.
      def framebuffer
        vic = @computer.vic
        display = vic.display
        vic_width = vic.width
        dirty = vic.dirty_lines

        height.times do |row|
          next unless dirty[row + @row_offset]

          @buffer[row * @row_bytes, @row_bytes] =
            pack_row(display, vic_width, row)
        end
        vic.clear_dirty_lines!
        @buffer
      end

      def pack_row(display, vic_width, row)
        line = display[((row + @row_offset) * vic_width) + @col_offset, width]
        line.map! { |c| @palette[c] }
        line.pack("V*")
      end
    end
  end
end
