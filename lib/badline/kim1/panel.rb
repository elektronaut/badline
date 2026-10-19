# frozen_string_literal: true

module Badline
  class KIM1
    # The keypad and display on U2's ports (User Manual, figures 3.5 and
    # 3.6), and the TTY/KB jumper.
    #
    # PB1-PB4 feed a 74145 decoder, U24. Its outputs 0-2 select the
    # keypad's three rows, 3 the jumper, and 4-9 the six LED digits, left
    # to right. PA0-PA6 drive the selected digit's segments a-g, a high
    # line lighting one, and read the selected row's keys, a pressed key
    # pulling its line low: PA6 is the row's first key, PA0 its seventh.
    # Fitted, the jumper pulls PA0 low while output 3 is selected, which
    # the monitor reads as teletype mode, and PA7 takes the teletype's
    # line in (Teletype).
    #
    # Nothing holds the display lit. A program lights each digit in turn
    # (the monitor's SCANDS, $1F1F), so the panel times how long each
    # segment is lit from the writes to U2's ports: lit_cycles hands the
    # totals to a front end, and display reads back what the digits show.
    class Panel
      # The keys of the matrix, by the code the monitor's GETKEY ($1F6A)
      # gives them: the row times 7 plus the column.
      KEYS = %w[0 1 2 3 4 5 6 7 8 9 A B C D E F AD DA + GO PC].freeze

      # The monitor's segment patterns for 0-F, its table at $1FE7 without
      # bit 7, which PA7 doesn't drive.
      HEX_SEGMENTS = [0x3f, 0x06, 0x5b, 0x4f, 0x66, 0x6d, 0x7d, 0x07,
                      0x7f, 0x6f, 0x77, 0x7c, 0x39, 0x5e, 0x79, 0x71].freeze

      DIGITS = 6

      # The decoder output of the leftmost digit.
      FIRST_DIGIT = 4

      # A digit lit for less than this many cycles at a time doesn't count
      # as showing anything: the monitor passes its digits through that
      # quickly between patterns.
      SHOWN_CYCLES = 100

      # A digit not lit for this many cycles, some five of the monitor's
      # scans, reads as dark.
      DARK_CYCLES = 20_000

      # Whether the TTY/KB jumper is fitted.
      attr_accessor :tty

      # Whether the teletype's line in is high, its idle level. Low, it
      # pulls PA7 low while PB5 is low, which gates it through.
      attr_accessor :tty_in_high

      # +clock+ answers +cycles+, the cycle each write to the ports lands
      # on.
      def initialize(clock)
        @clock = clock
        @rriot = nil
        @tty = false
        @tty_in_high = true
        @held = -1
        @digit = -1
        @segments = 0
        @since = 0
        @lit = Array.new(DIGITS * 7, 0)
        @shown = Array.new(DIGITS, 0)
        @shown_at = Array.new(DIGITS, -DARK_CYCLES - 1)
      end

      # U2, whose port B selects the row the keys are read from.
      def connect(rriot)
        @rriot = rriot
      end

      # Holds down the key KEYS names `name`, and lets go of any other.
      def press(name)
        code = KEYS.index(name)
        raise ArgumentError, "no KIM-1 key named #{name}" if code.nil?

        @held = code
      end

      def release
        @held = -1
      end

      # The name of the key held down, or nil.
      def held = @held.negative? ? nil : KEYS[@held]

      def read_a(_lines)
        port_b = @rriot.port_b_output
        row = decoded(port_b)
        mask = @tty_in_high || port_b.anybits?(0x20) ? 0xff : 0x7f
        mask &= 0xfe if row == 3 && @tty
        held = @held
        mask &= ~(0x40 >> (held % 7)) & 0xff if held >= 0 && held / 7 == row
        mask
      end

      def read_b(_lines) = 0xff

      # The lines U2's ports drive after a write to them.
      def lines_written(port_a, port_b)
        digit = decoded(port_b) - FIRST_DIGIT
        digit = -1 unless digit >= 0 && digit < DIGITS
        segments = digit.negative? ? 0 : port_a & 0x7f
        return if digit == @digit && segments == @segments

        now = @clock.cycles
        end_lit(now)
        @digit = digit
        @segments = segments
        @since = now
      end

      # The cycles each segment has been lit since the last call, seven to
      # a digit from the left, a to g, and starts counting again.
      def lit_cycles
        now = @clock.cycles
        end_lit(now)
        @since = now
        totals = @lit.dup
        @lit.map! { 0 }
        totals
      end

      # The segments, a in bit 0 to g in bit 6, each digit shows: its
      # pattern the last time it was lit for SHOWN_CYCLES or more, or 0
      # once it has been dark for DARK_CYCLES.
      def display
        now = @clock.cycles
        Array.new(DIGITS) do |digit|
          if digit == @digit && @segments != 0 && now - @since >= SHOWN_CYCLES
            @segments
          elsif now - @shown_at[digit] <= DARK_CYCLES
            @shown[digit]
          else
            0
          end
        end
      end

      # The display as text, such as "0200 A9": a space for a dark digit
      # and ? for a pattern that isn't a hex digit, with a space between
      # the address and the data.
      def display_text
        chars = display.map do |segments|
          next " " if segments.zero?

          index = HEX_SEGMENTS.index(segments)
          index.nil? ? "?" : index.to_s(16).upcase
        end
        "#{chars[0, 4].join} #{chars[4, 2].join}"
      end

      private

      def decoded(port_b) = (port_b >> 1) & 0x0f

      def end_lit(now)
        digit = @digit
        return if digit.negative? || @segments.zero?

        lit = now - @since
        7.times { |segment| @lit[(digit * 7) + segment] += lit if @segments.anybits?(1 << segment) }
        return if lit < SHOWN_CYCLES

        @shown[digit] = @segments
        @shown_at[digit] = now
      end
    end
  end
end
