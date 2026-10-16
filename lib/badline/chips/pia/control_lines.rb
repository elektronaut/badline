# frozen_string_literal: true

module Badline
  module Chips
    class PIA
      # One side's control register, CRA or CRB, its two control lines, CA1
      # and CA2 or CB1 and CB2, and their interrupt flags.
      #
      #   bit 0    C1 interrupt enable
      #   bit 1    C1 active edge, rising when set
      #   bit 2    the port (1) or its direction register (0) at the same address
      #   bits 5-3 C2:
      #            0e0  input, e the interrupt enable, falling edge
      #            1e0  input, rising edge
      #            100  handshake output
      #            101  pulse output
      #            110  low output
      #            111  high output
      #   bit 6    C2 flag, read only, held clear while C2 is an output
      #   bit 7    C1 flag, read only
      #
      # A flag is set by its line's active edge whether or not its interrupt
      # is enabled, and both are cleared by a read of the port. In handshake
      # mode C2 goes low on the strobing access and back high on the next
      # active C1 edge; in pulse mode it goes low for the cycle after it.
      # Side A strobes on a read of the port, side B on a write.
      class ControlLines
        attr_reader :c1_high, :c2_high

        # The level driven on C2, high while it is an input.
        attr_reader :c2_output

        def initialize(strobe_on_read:)
          @strobe_on_read = strobe_on_read
          @c1_high = @c2_high = true
          reset!
        end

        # Every bit clear: C2 an input, both interrupts off and the
        # direction register selected. The input levels carry over.
        def reset!
          @control = 0
          @c1_flag = @c2_flag = false
          @handshake_low = false
          @pulse = 0
          drive
        end

        # The control register as read, the flags in bits 7 and 6.
        def register
          value = @control
          value |= 0x80 if @c1_flag
          value |= 0x40 if @c2_flag
          value
        end

        # Writes bits 0-5; the flags can't be written. A new C2 mode starts
        # with any handshake or pulse over.
        def register=(value)
          mode = c2_mode
          @control = value & 0x3f
          @c2_flag = false if c2_output?
          unless c2_mode == mode
            @handshake_low = false
            @pulse = 0
          end
          drive
        end

        def port_selected? = @control.anybits?(0x04)

        def irq? = (@c1_flag && @control.anybits?(0x01)) || (@c2_flag && @control & 0x28 == 0x08)

        # Only the pulse output needs the clock.
        def pulsing? = @pulse.positive?

        def cycle!
          @pulse -= 1
          drive if @pulse.zero?
        end

        # A new C1 level. An active edge sets the flag and ends a handshake.
        def c1=(high)
          return if high == @c1_high

          @c1_high = high
          return unless high == @control.anybits?(0x02)

          @c1_flag = true
          @handshake_low = false
          drive
        end

        # A new C2 level. An active edge sets the flag while C2 is an input.
        def c2=(high)
          return if high == @c2_high

          @c2_high = high
          @c2_flag = true if !c2_output? && high == @control.anybits?(0x10)
        end

        # A read of the port, which clears both flags.
        def port_read!
          @c1_flag = @c2_flag = false
          strobe if @strobe_on_read
        end

        def port_written!
          strobe unless @strobe_on_read
        end

        private

        def c2_output? = @control.anybits?(0x20)

        def c2_mode = c2_output? ? @control & 0x38 : 0

        def strobe
          case @control & 0x38
          when 0x20 then @handshake_low = true
          when 0x28 then @pulse = 2
          else return
          end
          drive
        end

        def drive
          @c2_output = case @control & 0x38
                       when 0x20 then !@handshake_low
                       when 0x28 then @pulse.zero?
                       when 0x30 then false
                       else true
                       end
        end
      end
    end
  end
end
