# frozen_string_literal: true

module Badline
  class KIM1
    # A teletype on the KIM-1's 20 mA loop, full duplex, at `baud`
    # (User Manual, section 2.6 and figure 3.7).
    #
    # It sends what #type is given on its line to the board, a start bit,
    # eight data bits from the lowest and two stop bits a character, and
    # the board takes the line in on U2's PA7 while PB5 is low. It prints
    # what the board's printer line carries: PB0, which the monitor drives,
    # and, through the NAND U26, every bit coming in, so the hardware
    # echoes what is typed. It reads each character at its own baud,
    # sampling the middle of each bit from the start bit's edge, a start
    # bit high again by its middle a glitch, and keeps all it has printed
    # in #output, without bit 7.
    #
    # The monitor reads a character only while it waits for one, so the
    # teletype sends the next only once both lines have been quiet for
    # GAP_CHARACTERS characters' time. After a reset it sends RUBOUT, which
    # the monitor times to learn the baud.
    class Teletype
      RUBOUT = 0x7f
      GAP_CHARACTERS = 2

      # The cycles from a reset to the RUBOUT, by when the monitor waits
      # for its start bit.
      RUBOUT_DELAY = 2_000

      BAUDS = [110, 300, 1200, 2400, 4800, 9600].freeze

      attr_reader :baud, :output

      def initialize(panel, baud: 9600)
        @panel = panel
        @queue = []
        @output = +""
        @line_high = true
        @sending = []
        @send_at = 0
        @quiet_until = 0
        @receiving = false
        @received = 0
        @bits = 0
        @sample_at = 0.0
        @last_printer = true
        self.baud = baud
      end

      # Sets the rate both ways, which the monitor learns at the next reset.
      def baud=(baud)
        raise ArgumentError, "no teletype at #{baud} baud" unless BAUDS.include?(baud)

        @baud = baud
        @bit = 1_000_000.0 / baud
      end

      # Queues `text`'s bytes to send, its letters in capitals, as a Model
      # 33 types them.
      def type(text)
        text.upcase.bytes.each { |byte| @queue << byte }
      end

      # Whether characters are queued or on their way in or out.
      def busy? = !@queue.empty? || !@sending.empty? || @receiving

      # Whether the line to the board is high, its idle level.
      def line_high? = @line_high

      # Drops what was on its way in and sends RUBOUT once the monitor
      # is ready for it, at cycle `now`.
      def reset!(now)
        @queue.clear
        @sending.clear
        drive(true)
        @queue << RUBOUT
        @quiet_until = now + RUBOUT_DELAY
      end

      # Runs cycle `now`, with the printer line `printer_high`.
      def cycle!(now, printer_high)
        send_bits(now)
        receive(now, printer_high)
      end

      private

      def send_bits(now)
        if @sending.empty?
          start_character(now) if !@queue.empty? && !@receiving && now >= @quiet_until
        elsif now >= @send_at
          drive(@sending.shift)
          @send_at += @bit
          @quiet_until = now + (GAP_CHARACTERS * 11 * @bit) if @sending.empty?
        end
      end

      # The character's eleven bits, the start bit going out now.
      def start_character(now)
        byte = @queue.shift
        @sending = [false] + Array.new(8) { |bit| byte.anybits?(1 << bit) } + [true, true]
        @send_at = now.to_f
        send_bits(now)
      end

      def drive(high)
        return if high == @line_high

        @line_high = high
        @panel.tty_in_high = high
      end

      def receive(now, printer_high)
        if @receiving
          sample(now, printer_high) if now >= @sample_at
        elsif @last_printer && !printer_high
          @receiving = true
          @received = 0
          @bits = -1
          @sample_at = now + (0.5 * @bit)
        end
        @last_printer = printer_high
      end

      # The middle of the start bit, which has to be low still, each data
      # bit's, then the stop bit's.
      def sample(now, printer_high)
        if @bits.negative?
          @receiving = !printer_high
          @bits = 0
          @sample_at += @bit
        elsif @bits < 8
          @received |= 1 << @bits if printer_high
          @bits += 1
          @sample_at += @bit
        else
          @receiving = false
          @output << (@received & 0x7f).chr if printer_high
          @quiet_until = [@quiet_until, now + (GAP_CHARACTERS * 11 * @bit)].max
        end
      end
    end
  end
end
