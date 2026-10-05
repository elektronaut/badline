# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC traps on the KERNAL's serial bus primitives. Frames addressed to
    # device 8 go to a virtual drive instead of out over the IEC lines, so
    # OPEN/CHKIN/CHRIN reach a CBM DOS, and so do the block reads that
    # loaders make through them. Other devices fall through to the ROM.
    #
    # With +device+ nil the traps answer no device, and every frame goes
    # out over the bus, to a true drive if one is plugged in.
    class Serial < Routine
      attr_accessor :device

      ROUTINES = {
        0xed09 => :talk,
        0xed0c => :listen,
        0xedb9 => :second,
        0xedc7 => :tksa,
        0xeddd => :ciout,
        0xedef => :untalk,
        0xedfe => :unlisten,
        0xee13 => :acptr
      }.freeze

      # Frame type in the high nibble of the secondary address
      OPEN = 0xf0
      CLOSE = 0xe0

      # ST bits at $90
      DEVICE_NOT_PRESENT = 0x80
      EOI = 0x40
      READ_TIMEOUT = 0x02

      NO_DATA = [0x0d, EOI | READ_TIMEOUT].freeze

      def initialize(cpu:, bus:, drive:, device: DEVICE)
        super(cpu:, bus:)
        @drive = drive
        @device = device
        @listening = false
        @talking = false
        @listen_channel = nil
        @talk_channel = nil
        @frame = OPEN
        @buffer = []
      end

      # The frame under way, with the channels and the bytes it gathered.
      # The device it answers is the machine's to set.
      def save_state(out)
        out.boolean(@listening).boolean(@talking).optional_int(@listen_channel).optional_int(@talk_channel)
        out.int(@frame).blob(@buffer)
      end

      def load_state(input)
        @listening = input.boolean?
        @talking = input.boolean?
        @listen_channel = input.optional_int
        @talk_channel = input.optional_int
        @frame = input.int
        @buffer = input.blob
      end

      def install
        ROUTINES.each do |address, routine|
          @cpu.install_trap(address) { call_routine(routine) if kernal? }
        end
        self
      end

      private

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

      # Addressing the bus starts a new frame. The channel number arrives
      # in the secondary address that follows. Each byte sent under ATN,
      # and each byte of a frame, times its handshake with CIA 1's timer B
      # as ISOUR does.
      def talk
        @talk_channel = nil
        @talking = @cpu.a == @device
        sent_under_atn if @talking
      end

      def listen
        @listen_channel = nil
        @listening = @cpu.a == @device
        sent_under_atn if @listening
      end

      def sent_under_atn
        time_serial_byte(ISOUR_TIMEOUT)
        return_to_caller
      end

      def second
        return unless @listening

        @frame = @cpu.a & 0xf0
        @listen_channel = @cpu.a & 0x0f
        @buffer = []
        sent_under_atn
      end

      def tksa
        return unless @talking

        @talk_channel = @cpu.a & 0x0f
        sent_under_atn
      end

      # CIOUT holds each byte back until the next one, or the UNLISTEN,
      # comes, so the first byte of a frame sends nothing.
      def ciout
        return unless @listening

        time_serial_byte(ISOUR_TIMEOUT) if !@buffer.empty? && accepted?
        @buffer << @cpu.a
        update_status(DEVICE_NOT_PRESENT) unless accepted?
        @cpu.status.carry = false
        return_to_caller
      end

      # The drive acknowledges every byte of an open or close frame, but
      # takes data only on a channel it has open. Otherwise nothing holds
      # the data line when a byte starts, so the KERNAL finds no device.
      def accepted?
        [OPEN, CLOSE].include?(@frame) || @drive.listening?(@listen_channel)
      end

      def unlisten
        return unless @listening

        @listening = false
        deliver_frame
        time_serial_byte(ISOUR_TIMEOUT)
        release_bus
      end

      def untalk
        return unless @talking

        @talking = false
        time_serial_byte(ISOUR_TIMEOUT)
        release_bus
      end

      # UNLSN and UNTLK end by releasing ATN, the clock and the data line on
      # CIA 2's port A, and leave the port's last read in the accumulator.
      def release_bus
        @cpu.a = release_serial_lines
        @cpu.status.negative = @cpu.a.anybits?(0x80)
        @cpu.status.zero = @cpu.a.zero?
        return_to_caller
      end

      def acptr
        return unless @talking

        byte, status = received
        time_serial_byte(ACPTR_TIMEOUT)
        @cpu.a = byte
        update_status(status)
        @cpu.status.carry = false
        return_to_caller
      end

      def deliver_frame
        return unless @listen_channel

        case @frame
        when OPEN then @drive.open(@listen_channel, @buffer.pack("C*"))
        when CLOSE then @drive.close(@listen_channel)
        else @drive.write(@listen_channel, @buffer)
        end
        @buffer = []
      end

      def received
        byte, eoi = @drive.read(@talk_channel)
        return NO_DATA unless byte

        [byte, eoi ? EOI : 0]
      end

      def update_status(bits)
        return if bits.zero?

        @bus.poke(0x90, @bus.peek(0x90) | bits)
      end
    end
  end
end
