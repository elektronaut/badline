# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC traps on the KERNAL's serial bus primitives. Frames addressed to
    # device 8 go to a virtual drive instead of out over the IEC lines, so
    # OPEN/CHKIN/CHRIN reach a CBM DOS, and so do the block reads that
    # loaders make through them (Frames). Other devices fall through to the
    # ROM.
    #
    # With +device+ nil the traps answer no device, and every frame goes
    # out over the bus, to a true drive if one is plugged in.
    class Serial < Routine
      include Frames

      attr_accessor :device

      def initialize(cpu:, bus:, layout:, dos:, device: DEVICE)
        super(cpu:, bus:, layout:)
        @dos = dos
        @device = device
        @listening = false
        @talking = false
        @listen_channel = nil
        @talk_channel = nil
        @frame = OPEN
        @buffer = []
      end

      private

      # Addressing the bus starts a new frame. The channel number arrives
      # in the secondary address that follows. Each byte sent under ATN,
      # and each byte of a frame, times its handshake with the serial timer
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

      def acptr
        return unless @talking

        byte, status = received
        time_serial_byte(ACPTR_TIMEOUT)
        @cpu.a = byte
        update_status(status)
        @cpu.status.carry = false
        return_to_caller
      end
    end
  end
end
