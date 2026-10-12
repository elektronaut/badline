# frozen_string_literal: true

require "badline/plus4/acia/frames"

module Badline
  class Plus4
    # The Plus/4's 6551 ACIA at $FD00-$FD0F, its four registers repeated:
    #
    # $FD00 - read the receiver's data, write the transmitter's
    # $FD01 - read the status, write a programmed reset
    # $FD02 - the command register
    # $FD03 - the control register
    #
    # Status: bit 0 a parity error, 1 a framing error, 2 an overrun, 3 the
    # receiver full, 4 the transmitter empty, 5 DCD and 6 DSR as their pins
    # read (1 high, not asserted), 7 an interrupt. Reading it clears bit 7.
    #
    # Command: bit 0 DTR, which also enables the receiver and every
    # interrupt, bit 1 set disables the receiver's interrupt, bits 2-3 the
    # transmitter (00 off with RTS high, 01 on with its interrupt, 10 on
    # without, 11 sending a break), bit 4 echoes what is received, bits 5-7
    # the parity.
    #
    # Control: bits 0-3 the baud rate from the 1.8432 MHz crystal (0, the
    # 16x external clock, runs straight from the crystal, 115,200 baud),
    # bit 4 the receiver's clock (0 the RxC pin, which nothing drives on the
    # Plus/4, so the receiver hears nothing), bits 5-6 the word length (8
    # down to 5 bits) and bit 7 the stop bits (Frames).
    #
    # The transmitter runs in whole characters while it is on: at the end
    # of each it hands the character it shifted out to the line, moves a
    # waiting byte from the data register into the shift register and sets
    # the transmitter empty, and with its interrupt on interrupts while the
    # register is empty, every character until a byte comes. The first
    # character ends a character's time after the transmitter comes on.
    # The receiver takes a character's time for each byte the line sends,
    # and a byte that arrives while the last is unread is lost to an
    # overrun. The receiver full, and DCD or DSR changing, interrupt unless
    # bit 1 disables it.
    #
    # The user port carries no CTS, so the transmitter is always clear to
    # send; the KERNAL takes the user port's 6529 P1 as its handshake.
    #
    # What is on the other end of the user port (#plug): nothing, where
    # DCD and DSR read high and what is sent goes nowhere; a terminal,
    # which asserts DCD and DSR, sends what the host feeds it (#feed) while
    # DTR is asserted and keeps what it receives for the host to drain
    # (#drain); or a loopback plug, which returns TxD to RxD and DTR to DSR
    # and DCD.
    #
    # The machine runs the ACIA at the cycle it next has something to do
    # (#due) through #run!, and learns its IRQ line and that cycle from
    # `clock`'s #acia_changed, whose #cycles is the time.
    class ACIA
      include Frames

      PARITY_ERROR = 0x01
      FRAMING_ERROR = 0x02
      OVERRUN = 0x04
      RECEIVER_FULL = 0x08
      TRANSMITTER_EMPTY = 0x10
      DCD = 0x20
      DSR = 0x40
      IRQ = 0x80

      NOTHING = 0
      TERMINAL = 1
      LOOPBACK = 2

      # No shift in progress.
      IDLE = -1

      # Far enough ahead that it never comes.
      NEVER = 1 << 60

      attr_reader :command, :control, :device, :due

      def initialize(clock, clock_hz)
        @clock = clock
        @clock_hz = clock_hz
        @device = NOTHING
        @incoming = []
        @received = []
        reset!
      end

      # The RES line: every register cleared, the transmitter empty and
      # both shift registers stopped.
      def reset!
        @command = 0
        @control = 0
        @errors = 0
        @receiver_full = false
        @transmitter_empty = true
        @irq = false
        @receive_data = 0
        @transmit_data = 0
        @shifting = IDLE
        @transmit_at = NEVER
        @transmit_remainder = 0
        @receive_at = NEVER
        @receive_remainder = 0
        @clock_lost = false
        @lines = modem_lines
        changed
      end

      def irq? = @irq

      # DTR and RTS as asserted, low on the pins.
      def dtr? = @command.anybits?(0x01)

      def rts? = @command.anybits?(0x0c)

      # Whether the transmitter sends a break, holding TxD low.
      def break? = @command & 0x0c == 0x0c

      # Plugs NOTHING, a TERMINAL or a LOOPBACK plug into the user port.
      def plug(device)
        @device = device
        @incoming.clear
        lines_changed
        start_receiving
        changed
      end

      # Bytes the terminal sends, one a character's time while DTR is
      # asserted.
      def feed(bytes)
        return unless @device == TERMINAL

        @incoming.concat(bytes)
        start_receiving
        changed
      end

      # What the terminal has received since the last drain.
      def drain
        received = @received
        @received = []
        received
      end

      # Runs what falls due up to cycle `now`: the transmitter's character
      # ends, then the receiver's.
      def run!(now)
        end_character while @transmit_at <= now
        receive_character while @receive_at <= now
        changed
      end

      def peek(addr)
        case addr & 0x03
        when 0
          @receiver_full = false
          @receive_data
        when 1 then read_status
        when 2 then @command
        else @control
        end
      end

      def poke(addr, value)
        case addr & 0x03
        when 0 then write_data(value)
        when 1 then write_command(@command & 0xe0, clear_overrun: true)
        when 2 then write_command(value)
        else @control = value
        end
        changed
      end

      # The status as a read finds it, without clearing the interrupt.
      def status
        status = @errors | (@lines & (DCD | DSR))
        status |= RECEIVER_FULL if @receiver_full
        status |= TRANSMITTER_EMPTY if @transmitter_empty
        @irq ? status | IRQ : status
      end

      private

      def read_status
        value = status
        @irq = false
        changed
        value
      end

      def write_data(value)
        @transmit_data = value
        @transmitter_empty = false
      end

      def write_command(value, clear_overrun: false)
        was_on = transmitter_on?
        @command = value
        @errors &= ~OVERRUN if clear_overrun
        start_transmitting if transmitter_on? && !was_on
        stop_transmitting unless transmitter_on? || @shifting != IDLE
        lines_changed
        start_receiving
      end

      def transmitter_on?
        control = @command & 0x0c
        control != 0 && control != 0x0c
      end

      def interrupts? = @command.anybits?(0x01)

      def receiver_interrupts? = @command & 0x03 == 0x01

      def transmitter_interrupts? = @command & 0x0d == 0x05

      def receiving? = dtr? && @control.anybits?(0x10)

      def start_transmitting
        @transmit_remainder = 0
        @transmit_at = after(@clock.cycles, true)
      end

      def stop_transmitting
        @transmit_at = NEVER
      end

      # A character's end: the character shifted out goes to the line, and
      # the transmitter takes the next byte or interrupts while it has none.
      def end_character
        sent = @shifting
        @shifting = IDLE
        deliver(sent) unless sent == IDLE
        on = transmitter_on?
        if on && !@transmitter_empty
          @shifting = @transmit_data & word_mask
          @transmitter_empty = true
        end
        @irq = true if on && @transmitter_empty && transmitter_interrupts?
        if on || @shifting != IDLE
          @transmit_at = after(@transmit_at, true)
        else
          stop_transmitting
        end
      end

      def deliver(byte)
        case @device
        when TERMINAL then @received << byte
        when LOOPBACK then take(byte) if receiving?
        end
      end

      def start_receiving
        return unless @receive_at == NEVER && !@incoming.empty? && receiving?

        @receive_remainder = 0
        @receive_at = after(@clock.cycles, false)
      end

      def receive_character
        byte = @incoming[0]
        @incoming.delete_at(0)
        take(byte)
        @receive_at = !@incoming.empty? && receiving? ? after(@receive_at, false) : NEVER
      end

      # A whole character in from RxD: into the data register, or lost to
      # an overrun while the last is unread. In echo mode it goes back out
      # to the terminal.
      def take(byte)
        if @receiver_full
          @errors |= OVERRUN
        else
          @receive_data = byte & word_mask
          @receiver_full = true
          @errors = 0
        end
        @received << byte if @device == TERMINAL && @command & 0x1c == 0x10
        @irq = true if receiver_interrupts?
      end

      # DCD and DSR as the device drives them, interrupting on a change.
      def lines_changed
        lines = modem_lines
        return if lines == @lines

        @lines = lines
        @irq = true if receiver_interrupts?
      end

      def modem_lines
        case @device
        when TERMINAL then 0
        when LOOPBACK then dtr? ? 0 : DCD | DSR
        else DCD | DSR
        end
      end

      def changed
        @due = [@transmit_at, @receive_at].min
        @clock.acia_changed(@irq && interrupts?, @due)
      end
    end
  end
end
