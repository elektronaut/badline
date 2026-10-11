# frozen_string_literal: true

module Badline
  class Plus4
    # The keyboard and the joysticks: the 6529 at $FD30-$FD3F, whose eight
    # outputs drive the key matrix's lines, and the TED's K0-K7 inputs,
    # which $FF08 latches (Chips::TED#keyboard_port=). The KERNAL's scan
    # ($DB11) writes each line's mask to $FD30 and $FF08 and reads the keys
    # back from $FF08, and its key table at $E026 puts each key at line
    # times 8 plus input bit.
    #
    # The joysticks share K0-K7. The byte written to $FF08 selects them,
    # bit 2 low joystick 1 and bit 1 low joystick 2, as BASIC's JOY does
    # ($FA and $FD). A selected joystick pulls up, down, left and right
    # onto K0-K3 and its fire button onto K6 (joystick 1) or K7
    # (joystick 2), and those lines settle against the matrix with the
    # keys'.
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

      def initialize(keyboard, joystick1, joystick2)
        @keyboard = keyboard
        @joystick1 = joystick1
        @joystick2 = joystick2
        @output = 0xff
      end

      def reset!
        @output = 0xff
      end

      def peek(_addr) = @output

      def poke(_addr, value)
        @output = value
      end

      # The K0-K7 inputs the TED latches on a write of +value+ to $FF08:
      # high but where a held key joins a line the 6529 pulls low, or a
      # joystick +value+ selects holds a switch closed.
      def latch(value) = @keyboard.scan(@output, joystick_lines(value)).last

      private

      def joystick_lines(value)
        lines = 0xff
        lines &= joystick_inputs(@joystick1.port_bits, 0x40) if value.nobits?(0x04)
        lines &= joystick_inputs(@joystick2.port_bits, 0x80) if value.nobits?(0x02)
        lines
      end

      # A joystick's switches, Input::Joystick's bits 0-4, on K0-K7: the
      # directions on K0-K3 and the fire button on +fire+.
      def joystick_inputs(bits, fire)
        bits.anybits?(0x10) ? bits | 0xf0 : (bits | 0xf0) & ~fire & 0xff
      end
    end
  end
end
