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

      # The bits of a character: the start bit, eight data bits and two
      # stop bits.
      FRAME_BITS = 11

      attr_reader :baud, :output

      def initialize(panel, baud: 9600)
        @panel = panel
        @queue = []
        @output = +""
        @line_high = true
        @sending = 0
        @sent = FRAME_BITS
        @send_start = 0
        @quiet_until = 0
        @receiving = false
        @received = 0
        @bits = 0
        @edge = 0
        @sample_at = 0
        @last_printer = true
        self.baud = baud
      end

      # Sets the rate both ways, which the monitor learns at the next reset.
      def baud=(baud)
        raise ArgumentError, "no teletype at #{baud} baud" unless BAUDS.include?(baud)

        @baud = baud
      end

      # Queues `text`'s bytes to send, its letters in capitals, as a Model
      # 33 types them.
      def type(text)
        text.upcase.bytes.each { |byte| @queue << byte }
      end

      # Whether characters are queued or on their way in or out.
      def busy? = !@queue.empty? || @sent < FRAME_BITS || @receiving

      # Whether the line to the board is high, its idle level.
      def line_high? = @line_high

      # Drops what was on its way in and sends RUBOUT once the monitor
      # is ready for it, at cycle `now`.
      def reset!(now)
        @queue.clear
        @sent = FRAME_BITS
        drive(true)
        @queue << RUBOUT
        @quiet_until = now + RUBOUT_DELAY
      end

      # Runs cycle `now`, with the printer line `printer_high`.
      def cycle!(now, printer_high)
        send_bits(now)
        receive(now, printer_high)
      end

      # The teletype's fields in a keyed snapshot module (BL-TTY): the
      # baud, what is queued, the character going out and the one coming
      # in, by the cycles they started at, and all it has printed.
      def save_fields(out)
        out.int("baud", @baud).ints("queue", @queue).bytes("output", @output)
        out.bool("line_high", @line_high).int("send.byte", @sending).int("send.bits", @sent)
        out.int("send.start", @send_start).int("quiet_until", @quiet_until)
        out.bool("receive.busy", @receiving).int("receive.byte", @received).int("receive.bits", @bits)
        out.int("receive.edge", @edge).int("receive.sample_at", @sample_at).bool("printer_high", @last_printer)
      end

      def load_fields(input)
        baud = input.int("baud", @baud)
        @baud = BAUDS.include?(baud) ? baud : @baud
        @queue = input.ints("queue", []).map { |byte| byte & 0xff }
        @output = input.bytes("output", "".b).dup
        @line_high = input.bool("line_high", true)
        @sending = input.int("send.byte", 0) & 0xff
        @sent = input.int("send.bits", FRAME_BITS).clamp(0, FRAME_BITS)
        @send_start = input.int("send.start", 0)
        @quiet_until = input.int("quiet_until", 0)
        @receiving = input.bool("receive.busy", false)
        @received = input.int("receive.byte", 0) & 0xff
        @bits = input.int("receive.bits", 0).clamp(-1, 8)
        @edge = input.int("receive.edge", 0)
        @sample_at = input.int("receive.sample_at", 0)
        @last_printer = input.bool("printer_high", true)
        @panel.tty_in_high = @line_high
      end

      private

      # The cycles `halves` half bits take, rounded up.
      def half_bits(halves) = ((halves * 500_000) + @baud - 1) / @baud

      # Each bit goes out once its time from the start bit has passed.
      def send_bits(now)
        if @sent >= FRAME_BITS
          start_character(now) if !@queue.empty? && !@receiving && now >= @quiet_until
        elsif now >= @send_start + half_bits(2 * @sent)
          drive(bit_high?(@sent))
          @sent += 1
          @quiet_until = now + half_bits(2 * GAP_CHARACTERS * FRAME_BITS) if @sent == FRAME_BITS
        end
      end

      # The character's eleven bits, the start bit going out now.
      def start_character(now)
        @sending = @queue.shift
        @sent = 0
        @send_start = now
        send_bits(now)
      end

      # The start bit low, the data bits from the lowest, the stop bits
      # high.
      def bit_high?(index)
        return false if index.zero?
        return true if index > 8

        @sending.anybits?(1 << (index - 1))
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
          @edge = now
          @sample_at = now + half_bits(1)
        end
        @last_printer = printer_high
      end

      # The middle of the start bit, which has to be low still, each data
      # bit's, then the stop bit's.
      def sample(now, printer_high)
        if @bits.negative?
          @receiving = !printer_high
          @bits = 0
        elsif @bits < 8
          @received |= 1 << @bits if printer_high
          @bits += 1
        else
          @receiving = false
          @output << (@received & 0x7f).chr if printer_high
          @quiet_until = [@quiet_until, now + half_bits(2 * GAP_CHARACTERS * FRAME_BITS)].max
          return
        end
        @sample_at = @edge + half_bits((2 * @bits) + 3)
      end
    end
  end
end
