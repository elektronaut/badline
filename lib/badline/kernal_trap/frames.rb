# frozen_string_literal: true

module Badline
  module KernalTrap
    # The frames a drive takes and sends through the traps on a KERNAL's
    # eight bus primitives, shared by the serial bus's (Serial) and the
    # IEEE-488 bus's (IEEE): the traps going in and out, the bytes a
    # listener gathers into a frame for the DOS, the bytes a talker sends,
    # and the status they leave. The class that includes it, with Steps,
    # answers each primitive and keeps @dos, @listening, @talking,
    # @listen_channel, @talk_channel, @frame and @buffer.
    module Frames
      # Frame type in the high nibble of the secondary address
      OPEN = 0xf0
      CLOSE = 0xe0

      # ST bits
      DEVICE_NOT_PRESENT = 0x80
      EOI = 0x40
      READ_TIMEOUT = 0x02

      NO_DATA = [0x0d, EOI | READ_TIMEOUT].freeze

      def install
        routines.each do |address, routine|
          @cpu.install_trap(address) { call_routine(routine) if kernal_mapped? }
        end
        self
      end

      # Takes the traps out again, so the KERNAL's own routines run.
      def uninstall
        routines.each_key { |address| @cpu.remove_trap(address) }
      end

      private

      def routines
        {
          @layout.talk => :talk,
          @layout.listen => :listen,
          @layout.second => :second,
          @layout.tksa => :tksa,
          @layout.ciout => :ciout,
          @layout.untalk => :untalk,
          @layout.unlisten => :unlisten,
          @layout.acptr => :acptr
        }
      end

      def call_routine(routine)
        case routine
        when :talk then talk
        when :listen then listen
        when :second then second
        when :tksa then tksa
        when :ciout then ciout
        when :untalk then untalk
        when :unlisten then unlisten
        when :acptr then acptr
        end
      end

      # CIOUT holds each byte back until the next one, or the UNLISTEN,
      # comes, so the first byte of a frame sends nothing.
      def ciout
        return unless @listening

        time_serial_byte(Routine::ISOUR_TIMEOUT) if !@buffer.empty? && accepted?
        @buffer << @cpu.a
        update_status(DEVICE_NOT_PRESENT) unless accepted?
        @cpu.status.carry = false
        return_to_caller
      end

      # The drive acknowledges every byte of an open or close frame, but
      # takes data only on a channel it has open. Otherwise nothing holds
      # the data line when a byte starts, so the KERNAL finds no device.
      def accepted?
        [OPEN, CLOSE].include?(@frame) || @dos.listening?(@listen_channel)
      end

      # UNLSN and UNTLK end by releasing the bus, and leave the port's last
      # read in the accumulator.
      def release_bus
        @cpu.a = @layout.release_serial_lines(@bus)
        @cpu.status.negative = @cpu.a.anybits?(0x80)
        @cpu.status.zero = @cpu.a.zero?
        return_to_caller
      end

      def deliver_frame
        return unless @listen_channel

        case @frame
        when OPEN then @dos.open(@listen_channel, @buffer.pack("C*"))
        when CLOSE then @dos.close(@listen_channel)
        else @dos.write(@listen_channel, @buffer)
        end
        @buffer = []
      end

      def received
        byte, eoi = @dos.read(@talk_channel)
        return NO_DATA unless byte

        [byte, eoi ? EOI : 0]
      end

      def update_status(bits)
        return if bits.zero?

        @bus.poke(zero_page.status, @bus.peek(zero_page.status) | bits)
      end
    end
  end
end
