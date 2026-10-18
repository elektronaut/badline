# frozen_string_literal: true

module Badline
  class CBM2
    # What TPI2's ports read from outside the chip: the key matrix and the
    # board's jumpers. The KERNAL drives the matrix's sixteen column lines
    # low one at a time from PB0-PB7 and PA0-PA7 and reads its six row
    # lines on PC0-PC5, a 0 for each key down. PC6 and PC7 read the
    # jumpers: PC7 high on a 700, whose editor then loads its own CRTC
    # table, and PC6 high on a 600 at 60 Hz.
    #
    # MATRIX lists the keys on each column line, PB0 first, in row order,
    # :none where no key sits, as the KERNAL's key table at $EA29 places
    # them, named as the B series' keyboard matrix sheet labels them.
    class KeyboardPorts
      MATRIX = [
        %i[f1 escape tab none shift control],
        %i[f2 1 q a z none],
        %i[f3 2 w s x c],
        %i[f4 3 e d f v],
        %i[f5 4 r t g b],
        %i[f6 5 6 y h n],
        %i[f7 7 u j m space],
        %i[f8 8 i k , .],
        %i[f9 9 o l ; /],
        [:f10, :"0", :-, :p, :"[", :"'"],
        [:cursor_down, :"=", :left_arrow, :"]", :return, :pi],
        %i[cursor_up cursor_left cursor_right delete cbm none],
        %i[clr_home kp_question kp7 kp4 kp1 kp0],
        %i[off_rvs ce kp8 kp5 kp2 kp_period],
        %i[norm_graph kp_multiply kp9 kp6 kp3 kp00],
        %i[run_stop kp_divide kp_minus kp_plus kp_enter none]
      ].freeze

      attr_reader :keyboard

      # +jumpers+ is PC6 and PC7 as the board's jumpers drive them.
      def initialize(keyboard, jumpers)
        @keyboard = keyboard
        @jumpers = jumpers
        @tpi = nil
      end

      # The TPI whose ports drive the column lines.
      def connect(tpi)
        @tpi = tpi
      end

      def read_a(lines) = lines

      def read_b(lines) = lines

      def read_c(lines)
        columns = (@tpi.port_a_output << 8) | @tpi.port_b_output
        rows = @keyboard.scan(columns, lines | 0x3f).last
        (rows & 0x3f) | (@jumpers & lines & 0xc0)
      end
    end
  end
end
