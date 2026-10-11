# frozen_string_literal: true

module Badline
  class Plus4
    # The keyboard: the 6529 at $FD30-$FD3F, whose eight outputs drive the
    # key matrix's lines, and the TED's K0-K7 inputs, which $FF08 latches
    # (Chips::TED#keyboard_port=). The KERNAL's scan ($DB11) writes each
    # line's mask to $FD30 and $FF08 and reads the keys back from $FF08,
    # and its key table at $E026 puts each key at line times 8 plus input
    # bit.
    #
    # The 6529 is a quasi-bidirectional latch: a read returns what was
    # written to it.
    class KeyboardPort
      # One row of keys per 6529 output, in K0-K7 order, after the
      # KERNAL's key table. HELP is the KERNAL's F7, and the two SHIFT keys
      # share one place.
      MATRIX = [
        %i[delete return £ help f1 f2 f3 @],
        %i[3 w a 4 z s e lshift],
        %i[5 r d 6 c f t x],
        %i[7 y g 8 b h u v],
        %i[9 i j 0 m k o n],
        %i[crsr_down p l crsr_up . : - ,],
        %i[crsr_left * ; crsr_right esc = + /],
        %i[1 clr_home control 2 space cbm q run_stop]
      ].freeze

      attr_reader :keyboard, :output

      def initialize(keyboard)
        @keyboard = keyboard
        @output = 0xff
      end

      def reset!
        @output = 0xff
      end

      def peek(_addr) = @output

      def poke(_addr, value)
        @output = value
      end

      # The K0-K7 inputs the TED latches on a write of +_value+ to $FF08:
      # high but where a held key joins a line the 6529 pulls low.
      def latch(_value) = @keyboard.scan(@output, 0xff).last
    end
  end
end
