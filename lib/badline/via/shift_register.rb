# frozen_string_literal: true

module Badline
  class VIA
    # The 6522's shift register, with the CB1 clock and CB2 data lines it
    # takes over in every mode but the first.
    #
    # ACR bits 4-2 pick the mode. Modes 1 to 3 shift in, left, with the new
    # bit taken from CB2 into bit 0 on each rising CB1 edge. Modes 4 to 7
    # shift out: each falling CB1 edge puts bit 7 on CB2 and rotates it back
    # round into bit 0, so after eight bits the byte is back where it
    # started. Modes 1, 4 and 5 clock off timer 2, modes 2 and 6 off φ2, and
    # modes 3 and 7 off whatever drives CB1 from outside.
    #
    # Under its own clock the register drives CB1, idling high. Reading or
    # writing the data register starts a byte, but only while the register
    # is idle and enabled: an access in mode 0, or one before the eighth bit
    # is in, leaves the count alone. CB1 falls on the first clock tick of
    # the byte and rises on the second, and so on, so a byte is eight pulses
    # over sixteen ticks. The interrupt flag is set on the tick that raises
    # CB1 over the eighth bit, and CB1 then stays high until the next
    # access.
    #
    # In modes 2 and 6 a tick is a φ2 cycle, from the second cycle after
    # the access on, which makes a byte sixteen cycles. In modes 1, 4 and 5
    # it comes two cycles after each timer 2 low byte underflow, on the
    # cycle after the low byte reloads, which makes a byte sixteen
    # underflows. Mode 4 never stops and never interrupts: its counter is
    # disabled, and the byte goes round and round.
    #
    # Under an external clock the register shifts on every CB1 edge, access
    # or not. The access only arms the counter: the flag is set on the eighth
    # rising edge after it, and the counter then waits for the next access.
    class ShiftRegister
      DISABLED = 0
      IN_T2 = 1
      IN_PHI2 = 2
      IN_EXTERNAL = 3
      OUT_FREE_RUNNING = 4
      OUT_T2 = 5
      OUT_PHI2 = 6
      OUT_EXTERNAL = 7

      attr_reader :mode, :data
      attr_accessor :cb2_input

      def initialize
        @mode = DISABLED
        @data = 0x00
        # Bits still to count before the flag, zero when the counter is idle.
        @bits = 0
        # The clock's last two cycles, newest in bit 0: timer 2 low byte
        # underflows in modes 1, 4 and 5, and whether the byte has started
        # in modes 2 and 6.
        @delay = 0
        @clock = true
        @cb2 = true
        # Nothing drives CB2 from outside, so it floats high.
        @cb2_input = true
      end

      def mode=(value)
        @mode = value & 0x07
      end

      def data=(value)
        @data = value & 0xff
      end

      # A read or write of the data register, which starts a byte if the
      # register is idle and enabled.
      def access!
        return if @mode == DISABLED || @bits.nonzero?

        @bits = 8
        @delay = 0 if @mode == IN_PHI2 || @mode == OUT_PHI2
      end

      # Whether the register is counting bits off its own clock, which
      # changes it from cycle to cycle.
      def clocking? = @bits.nonzero? && internal_clock?

      def save_state(out)
        out.int(@mode).int(@data).int(@bits).int(@delay).boolean(@clock).boolean(@cb2).boolean(@cb2_input)
      end

      def load_state(input)
        @mode = input.int
        @data = input.int
        @bits = input.int
        @delay = input.schema > 4 ? input.int : 0
        @clock = input.boolean?
        @cb2 = input.boolean?
        @cb2_input = input.boolean?
      end

      # Everything the register holds, for comparing it at two points.
      def state = [@mode, @data, @bits, @delay, @clock, @cb2, @cb2_input]

      # The CB1 level the register drives, or nil when CB1 is an input.
      def cb1_output
        internal_clock? ? @clock : nil
      end

      # The CB2 level the register drives, or nil when it doesn't.
      def cb2_output
        @mode >= OUT_FREE_RUNNING ? @cb2 : nil
      end

      # Clocked once per φ2 cycle, with whether timer 2's low byte underflowed
      # on it. Returns true on the cycle that sets the interrupt flag.
      def cycle!(t2_low_underflow)
        case @mode
        when IN_PHI2, OUT_PHI2 then @bits.nonzero? && phi2_tick
        when IN_T2, OUT_T2, OUT_FREE_RUNNING then t2_tick(t2_low_underflow)
        else false
        end
      end

      # A level change on CB1 from outside. Only the external clock modes
      # listen: shifting in samples CB2 as CB1 rises, and shifting out puts
      # the next bit on CB2 as it falls. Returns true when the edge sets the
      # interrupt flag.
      def cb1_edge!(rising)
        return false unless @mode == IN_EXTERNAL || @mode == OUT_EXTERNAL

        shift_in if rising && @mode == IN_EXTERNAL
        shift_out if !rising && @mode == OUT_EXTERNAL
        rising && eighth_bit?
      end

      private

      def internal_clock?
        @mode != DISABLED && @mode != IN_EXTERNAL && @mode != OUT_EXTERNAL
      end

      # A φ2 cycle of a byte: every one but the first ticks.
      def phi2_tick
        started = @delay.nonzero?
        @delay = 1
        started && tick
      end

      # Ticks on the underflow from two cycles back, while a byte is under
      # way.
      def t2_tick(underflow)
        due = @delay.anybits?(2)
        @delay = ((@delay << 1) & 2) | (underflow ? 1 : 0)
        due && @bits.nonzero? && tick
      end

      # One half period of the register's own clock: a falling edge puts a
      # bit out, and a rising one takes a bit in and counts it.
      def tick
        @clock = !@clock
        shift_out if !@clock && @mode >= OUT_FREE_RUNNING
        shift_in if @clock && @mode < IN_EXTERNAL
        @clock && @mode != OUT_FREE_RUNNING && eighth_bit?
      end

      # Counts a bit, and says whether it was the eighth since the access.
      def eighth_bit?
        return false if @bits.zero?

        @bits -= 1
        @bits.zero?
      end

      def shift_in
        @data = ((@data << 1) | (@cb2_input ? 1 : 0)) & 0xff
      end

      def shift_out
        @cb2 = @data.anybits?(0x80)
        @data = ((@data << 1) | (@cb2 ? 1 : 0)) & 0xff
      end
    end
  end
end
