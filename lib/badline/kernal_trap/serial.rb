# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC traps on the KERNAL's serial bus primitives. Frames addressed to
    # device 8 go to a virtual drive instead of out over the IEC lines, so
    # OPEN/CHKIN/CHRIN reach a CBM DOS, and so do the block reads that
    # loaders make through them. Other devices fall through to the ROM.
    class Serial < Routine
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
      EOI = 0x40
      READ_TIMEOUT = 0x02

      NO_DATA = [0x0d, EOI | READ_TIMEOUT].freeze

      def initialize(cpu:, bus:, drive:)
        super(cpu:, bus:)
        @drive = drive
        @listening = false
        @talking = false
        @listen_channel = nil
        @talk_channel = nil
        @frame = OPEN
        @buffer = []
      end

      def install
        ROUTINES.each do |address, routine|
          @cpu.install_trap(address) { send(routine) if kernal? }
        end
        self
      end

      private

      # Addressing the bus starts a new frame. The channel number arrives
      # in the secondary address that follows.
      def talk
        @talk_channel = nil
        @talking = @cpu.a == DEVICE
        return_to_caller if @talking
      end

      def listen
        @listen_channel = nil
        @listening = @cpu.a == DEVICE
        return_to_caller if @listening
      end

      def second
        return unless @listening

        @frame = @cpu.a & 0xf0
        @listen_channel = @cpu.a & 0x0f
        @buffer = []
        return_to_caller
      end

      def tksa
        return unless @talking

        @talk_channel = @cpu.a & 0x0f
        return_to_caller
      end

      def ciout
        return unless @listening

        @buffer << @cpu.a
        @cpu.status.carry = false
        return_to_caller
      end

      def unlisten
        return unless @listening

        @listening = false
        deliver_frame
        return_to_caller
      end

      def untalk
        return unless @talking

        @talking = false
        return_to_caller
      end

      def acptr
        return unless @talking

        byte, status = received
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
