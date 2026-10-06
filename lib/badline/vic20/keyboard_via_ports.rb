# frozen_string_literal: true

module Badline
  class Vic20
    # What VIA 2's ports read from outside the chip: the key matrix, with
    # port B driving its columns and port A reading its rows. The KERNAL's
    # SCNKEY ($EB1E) writes a column pattern to $9120 and reads the rows
    # back from $9121, and its key table ($EC5E) puts each key at column
    # times 8 plus row.
    #
    # PB7 is also the joystick's right switch. A held switch pulls that
    # column line low before the matrix settles, so it reads as a key down
    # in every row whose key in column 7 is held too. PB3 doubles as the
    # cassette write line, which only the datasette listens to.
    class KeyboardVIAPorts
      # One row of keys per port A line, in port B column order. The keys
      # are the C64's, under the same names, wired to other lines.
      MATRIX = [
        %i[1 left control run_stop space cbm q 2],
        %i[3 w a lshift z s e 4],
        %i[5 r d x c f t 6],
        %i[7 y g v b h u 8],
        %i[9 i j n m k o 0],
        %i[+ p l , . : @ -],
        %i[£ * ; / rshift = up clr_home],
        %i[delete return cursor_h cursor_v f1 f3 f5 f7]
      ].freeze

      attr_reader :keyboard, :joystick

      def initialize(keyboard:, joystick:)
        @keyboard = keyboard
        @joystick = joystick
        @via = nil
      end

      # The VIA these ports hang off, whose other port's output the matrix
      # settles against.
      def connect(via)
        @via = via
      end

      def read_a(lines) = @keyboard.scan(lines, columns(@via.port_b_output)).first

      def read_b(lines) = @keyboard.scan(@via.port_a_output, columns(lines)).last

      private

      # The joystick's right switch is bit 3 of its port bits, and pulls PB7.
      def columns(lines) = lines & (0x7f | ((@joystick.port_bits & 0x08) << 4))
    end
  end
end
