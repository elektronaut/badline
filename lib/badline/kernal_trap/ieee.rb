# frozen_string_literal: true

module Badline
  module KernalTrap
    # The traps on a PET's IEEE-488 primitives (IEEELayout), which serve
    # device 8 from the virtual drive as Serial does on the serial bus
    # (Frames). Other devices fall through to the ROM, which finds nobody on
    # the bus. It is no Routine, so that Routine's layout stays a Layout.
    #
    # The PET's primitives differ from the serial KERNALs': TALK and LISTEN
    # address the device in FA, not in A, and BASIC 2's LOAD sends its
    # channel after TALK with SECOND, not TKSA, so SECOND takes a talker's
    # channel too. BASIC 1's UNTALK and UNLISTEN store their command in FA,
    # and its LOAD and SAVE address the device in FA after an UNLISTEN, so
    # they find no device, as on a real PET with those ROMs.
    # Each trap leaves A and the lines the ROM drives as the routine does.
    class IEEE
      include IntegerHelper
      include Steps
      include Frames

      # The command BASIC 1's UNTALK and UNLISTEN leave in FA.
      UNTALK_COMMAND = 0x5f
      UNLISTEN_COMMAND = 0x3f

      # The device the traps serve, or nil to serve none.
      attr_accessor :device

      def initialize(cpu:, bus:, layout:, dos:)
        @cpu = cpu
        @bus = bus
        @layout = layout
        @dos = dos
        @device = Routine::DEVICE
        @listening = false
        @talking = false
        @listen_channel = nil
        @talk_channel = nil
        @frame = OPEN
        @buffer = []
      end

      private

      def talk
        @talk_channel = nil
        @talking = addressed?
        address_device if @talking
      end

      def listen
        @listen_channel = nil
        @listening = addressed?
        address_device if @listening
      end

      # The device TALK or LISTEN addresses: the one in A or in FA, as the
      # layout says.
      def addressed? = (@layout.device_in_a ? @cpu.a : @bus.peek(zero_page.device)) == @device

      # TALK and LISTEN end with the command sent under ATN, which stays
      # low, and A holding $FF.
      def address_device
        @layout.attention(@bus)
        send_byte
        @cpu.a = 0xff
        set_flags
        return_to_caller
      end

      # A close needs no data, and the drive closes the channel as the
      # secondary address comes: BASIC 1's CLOSE sends no UNLISTEN after it.
      def second
        if @listening
          @frame = @cpu.a & 0xf0
          @listen_channel = @cpu.a & 0x0f
          @buffer = []
          close_channel if @frame == CLOSE
        elsif @talking
          @talk_channel = @cpu.a & 0x0f
        else
          return
        end
        send_byte
        release_attention
      end

      def tksa
        return unless @talking

        @talk_channel = @cpu.a & 0x0f
        send_byte
        @layout.listen_to_talker(@bus)
        release_attention
      end

      def untalk
        return unless @talking

        @talking = false
        @bus.poke(zero_page.device, UNTALK_COMMAND) if @layout.overwrites_device
        time_serial_byte(Routine::ISOUR_TIMEOUT)
        release_bus
      end

      def unlisten
        return unless @listening

        @listening = false
        @bus.poke(zero_page.device, UNLISTEN_COMMAND) if @layout.overwrites_device
        deliver_frame
        time_serial_byte(Routine::ISOUR_TIMEOUT)
        release_bus
      end

      # ACPTR leaves the byte in A, with the flags PLA gives it, and the PET
      # listening, NRFD and NDAC pulled low.
      def acptr
        return unless @talking

        @layout.listen_to_talker(@bus)
        byte, status = received
        time_serial_byte(Routine::ACPTR_TIMEOUT)
        @cpu.a = byte
        set_flags
        update_status(status)
        @cpu.status.carry = false
        return_to_caller
      end

      def close_channel
        @dos.close(@listen_channel)
        @listen_channel = nil
      end

      def send_byte
        time_serial_byte(Routine::ISOUR_TIMEOUT)
        @layout.byte_sent(@bus)
      end

      def release_attention
        @cpu.a = @layout.release_attention(@bus)
        set_flags
        return_to_caller
      end

      def set_flags
        @cpu.status.negative = @cpu.a.anybits?(0x80)
        @cpu.status.zero = @cpu.a.zero?
      end
    end
  end
end
