# frozen_string_literal: true

module Badline
  class PET
    # What PIA 1's port B reads from outside the chip: the key matrix's
    # columns, for the row PA0-PA3 select through a 4-to-10 decoder. The
    # editor writes a row number to $E810 and reads the row's keys from
    # $E812, a 0 for each key down. A row number past 9 selects no row.
    #
    # The graphics keyboard (N) and the business keyboard (B) are wired
    # differently, and the editor ROM scans the one its model has. Each
    # matrix lists its rows in port B bit order, :none where no key sits,
    # as the editors' key tables place them. The graphics keyboard's
    # digits are on its keypad; the business keyboard has a row of them
    # and a keypad (kp0 to kp9 and kp_period).
    class KeyboardPorts
      GRAPHICS_MATRIX = [
        %i[! # % & ( left clr_home cursor_h],
        [:'"', :"$", :"'", :"\\", :")", :none, :cursor_v, :delete],
        %i[q e t u o up 7 9],
        %i[w r y i p none 8 /],
        %i[a d g j l none 4 6],
        %i[s f h k : none 5 *],
        %i[z c b m ; return 1 3],
        %i[x v n , ? none 2 +],
        [:lshift, :"@", :"]", :none, :>, :rshift, :"0", :-],
        [:rvs, :"[", :space, :<, :run_stop, :none, :".", :"="]
      ].freeze

      BUSINESS_MATRIX = [
        %i[2 5 8 - kp8 cursor_h none none],
        %i[1 4 7 0 kp7 up none kp9],
        [:escape, :s, :f, :h, :"]", :k, :";", :kp5],
        %i[a d g j return l @ kp6],
        %i[tab w r y \\ i p delete],
        [:q, :e, :t, :u, :cursor_v, :o, :"[", :kp4],
        %i[lshift c b . kp_period none rshift kp3],
        %i[z v n , kp0 none repeat kp2],
        %i[rvs x space m clr_home none / kp1],
        %i[left 3 6 9 run_stop : none none]
      ].freeze

      attr_reader :keyboard

      def initialize(keyboard)
        @keyboard = keyboard
        @pia = nil
        @ieee = nil
      end

      # The PIA these ports hang off, whose port A selects the row, and the
      # PET's IEEEPorts, which answer PA6.
      def connect(pia, ieee)
        @pia = pia
        @ieee = ieee
      end

      # Port A's other lines: PA6 reads the IEEE bus's EOI, and the
      # cassette sense switches and the diagnostic sense float high with
      # nothing on them.
      def read_a(_lines) = @ieee.eoi_input

      def read_b(lines)
        row = @pia.port_a_output & 0x0f
        return lines if row > 9

        @keyboard.scan(0x3ff & ~(1 << row), lines).last
      end
    end
  end
end
