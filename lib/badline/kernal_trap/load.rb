# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC trap on the KERNAL serial LOAD routine ($F4A5, the default ILOAD
    # vector target). Serves device 8 requests from a storage backend, then
    # hands over to the ROM's own tail so it prints SEARCHING FOR and
    # LOADING (or VERIFYING) in direct mode, reports errors and returns
    # with the routine's register/zeropage contract; other devices fall
    # through to the ROM.
    class Load < File
      ADDRESS = 0xf4a5

      # ROM entry points: the SEARCHING FOR and LOADING/VERIFYING messages,
      # the successful return (CLC, LDX $AE, LDY $AF, RTS) and the
      # FILE NOT FOUND and MISSING FILE NAME error exits
      SEARCHING_MESSAGE = 0xf5af
      LOADING_MESSAGE = 0xf5d2
      LOAD_DONE = 0xf5a9
      FILE_NOT_FOUND_EXIT = 0xf704
      MISSING_FILE_NAME_EXIT = 0xf710

      # ST bits at $90
      EOI = 0x40
      VERIFY_MISMATCH = 0x10
      READ_TIMEOUT = 0x02

      def call
        return unless active?

        @bus.poke(0x93, @cpu.a)
        @bus.poke(0x90, 0x00)
        name, type = Storage.parse_name(filename)
        return @cpu.program_counter = MISSING_FILE_NAME_EXIT if name.empty?

        if (data = @storage.read_file(name, type: type || :prg))
          deliver(data)
          continue_with(SEARCHING_MESSAGE, LOADING_MESSAGE, LOAD_DONE)
        else
          @bus.poke(0x90, EOI | READ_TIMEOUT)
          continue_with(SEARCHING_MESSAGE, FILE_NOT_FOUND_EXIT)
        end
      end

      private

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
          uint16(data[0], data[1])
        end
      end

      # Runs the ROM routines in order, each returning into the next, and
      # the last one to the trapped routine's caller
      def continue_with(first, *rest)
        rest.reverse_each { |address| push_address((address - 1) & 0xffff) }
        @cpu.program_counter = first
      end
    end
  end
end
