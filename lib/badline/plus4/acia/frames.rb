# frozen_string_literal: true

module Badline
  class Plus4
    class ACIA
      # A character's frame and how long it takes. A start bit, 5 to 8
      # data bits, a parity bit where the command enables one, and the stop
      # bits: one, or with control bit 7 two, but one and a half for 5 bits
      # without parity and one for 8 bits with it (6551 datasheet). Each bit
      # takes 16 periods of the baud rate generator's 16x clock, the 1.8432
      # MHz crystal divided by the rate's divisor, which the machine's
      # cycles are counted against, carrying what is left of a cycle from
      # one character to the next.
      module Frames
        CRYSTAL_HZ = 1_843_200

        # The crystal's divisor for each baud rate the control register
        # selects: the external clock, then 50, 75, 109.92, 134.58, 150,
        # 300, 600, 1200, 1800, 2400, 3600, 4800, 7200, 9600 and 19,200.
        DIVISORS = [1, 2304, 1536, 1048, 856, 768, 384, 192, 96, 64, 48, 32, 24, 16, 12, 6].freeze

        def word_length = 8 - ((@control >> 5) & 0x03)

        def word_mask = (1 << word_length) - 1

        # The frame's length in half bits.
        def frame_halves
          length = word_length
          parity = @command.anybits?(0x20)
          stops = if @control < 0x80 || (length == 8 && parity) then 2
                  elsif length == 5 && !parity then 3
                  else 4
                  end
          ((1 + length + (parity ? 1 : 0)) * 2) + stops
        end

        private

        # The cycle a character the transmitter, or else the receiver,
        # starts at `time` ends at.
        def after(time, transmitter)
          units = frame_halves * 8 * DIVISORS[@control & 0x0f] * @clock_hz
          if transmitter
            units += @transmit_remainder
            @transmit_remainder = units % CRYSTAL_HZ
          else
            units += @receive_remainder
            @receive_remainder = units % CRYSTAL_HZ
          end
          time + (units / CRYSTAL_HZ)
        end
      end
    end
  end
end
