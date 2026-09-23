# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC trap on the KERNAL serial LOAD routine ($F4A5, the default ILOAD
    # vector target). Reads device 8 requests from the virtual drive's
    # channel 0, then hands over to the ROM's own tail so it prints
    # SEARCHING FOR and LOADING (or VERIFYING) in direct mode, reports
    # errors and returns with the routine's register/zeropage contract;
    # other devices fall through to the ROM. So does a load that reaches
    # below $0334, into the zero page, the stack or the KERNAL vectors: the
    # ROM's byte loop then loads it through the serial traps, and a loader
    # that overwrites ISTOP takes over mid-load as it does on a real drive.
    class Load < File
      ADDRESS = 0xf4a5

      # ROM entry points: the SEARCHING FOR and LOADING/VERIFYING messages,
      # the byte loop that retries a timed-out byte until RUN/STOP, the
      # successful return (CLC, LDX $AE, LDY $AF, RTS) and the
      # FILE NOT FOUND and MISSING FILE NAME error exits
      SEARCHING_MESSAGE = 0xf5af
      LOADING_MESSAGE = 0xf5d2
      BYTE_LOOP = 0xf4f3
      LOAD_DONE = 0xf5a9
      FILE_NOT_FOUND_EXIT = 0xf704
      MISSING_FILE_NAME_EXIT = 0xf710

      # ST bits at $90
      EOI = 0x40
      VERIFY_MISMATCH = 0x10
      READ_TIMEOUT = 0x02

      def initialize(cpu:, bus:, drive:)
        super(cpu:, bus:)
        @drive = drive
      end

      def call
        return unless active?

        @bus.poke(0x93, @cpu.a)
        @bus.poke(0x90, 0x00)
        name = filename
        return @cpu.program_counter = MISSING_FILE_NAME_EXIT if Storage.parse_name(name).first.empty?

        data, complete = receive(name)
        if low_memory?(data)
          @drive.close(0)
        else
          finish(data, complete)
        end
      end

      private

      # Reads the file the way the ROM's byte loop would, up to the byte
      # flagged EOI. A read error in the file's chain stops the bytes early,
      # with no EOI.
      def receive(name)
        @drive.open(0, name)
        data = []
        loop do
          byte, eoi = @drive.read(0)
          return [data, false] unless byte

          data << byte
          return [data, true] if eoi
        end
      end

      # No first byte means the file isn't there, or its first block didn't
      # read. A later read error leaves the ROM retrying the next byte
      # until RUN/STOP breaks the load, as on a real drive.
      def finish(data, complete)
        if data.empty?
          @bus.poke(0x90, EOI | READ_TIMEOUT)
          continue_with(SEARCHING_MESSAGE, FILE_NOT_FOUND_EXIT)
        else
          deliver(data)
          @bus.poke(0x90, @bus.peek(0x90) & ~EOI) unless complete
          continue_with(SEARCHING_MESSAGE, LOADING_MESSAGE, complete ? LOAD_DONE : BYTE_LOOP)
        end
      end

      def low_memory?(data)
        load? && data.length > 2 && load_address(data) < 0x0334
      end

      # A=0 is LOAD, A=1 is VERIFY, kept at $93 (VERCK)
      def load?
        @bus.peek(0x93).zero?
      end

      def deliver(data)
        addr = load_address(data)
        payload = data[2..] || []
        payload = payload[0, 0x10000 - addr] if addr + payload.length > 0x10000
        if load?
          @bus.ram.write(addr, payload)
          @bus.poke(0x90, EOI)
        else
          verify(addr, payload)
        end
        end_addr = (addr + payload.length) & 0xffff
        @bus.poke(0xae, low_byte(end_addr))
        @bus.poke(0xaf, high_byte(end_addr))
      end

      def verify(addr, payload)
        match = payload.each_with_index.all? { |byte, i| @bus.peek(addr + i) == byte }
        @bus.poke(0x90, match ? EOI : EOI | VERIFY_MISMATCH)
      end

      # Secondary address $B9 zero relocates to the caller-supplied address
      # stashed at $C3/$C4 (MEMUSS)
      def load_address(data)
        if @bus.peek(0xb9).zero?
          uint16(@bus.peek(0xc3), @bus.peek(0xc4))
        else
          uint16(data[0], data[1].to_i)
        end
      end
    end
  end
end
