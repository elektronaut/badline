# frozen_string_literal: true

module Badline
  module KernalTrap
    # PC trap on the KERNAL serial LOAD routine ($F4A5, the default ILOAD
    # vector target). Serves device 8 requests from a storage backend and
    # returns to the caller with the routine's register/zeropage contract;
    # other devices fall through to the ROM.
    class Load < File
      ADDRESS = 0xf4a5

      FILE_NOT_FOUND = 0x04

      def call
        return unless active?

        name, type = Storage.parse_name(filename)
        if name.empty?
          error(MISSING_FILENAME)
        elsif (data = @storage.read_file(name, type: type || :prg))
          deliver(data)
        else
          error(FILE_NOT_FOUND)
        end
        return_to_caller
      end

      private

      # A=0 is LOAD, A=1 is VERIFY
      def load?
        @cpu.a.zero?
      end

      def deliver(data)
        addr = load_address(data)
        payload = data[2..] || []
        payload = payload[0, 0x10000 - addr] if addr + payload.length > 0x10000
        @bus.ram.write(addr, payload) if load?
        finish((addr + payload.length) & 0xffff)
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

      def finish(end_addr)
        @bus.poke(0x90, 0x40)
        @bus.poke(0xae, low_byte(end_addr))
        @bus.poke(0xaf, high_byte(end_addr))
        @cpu.x = low_byte(end_addr)
        @cpu.y = high_byte(end_addr)
        @cpu.status.carry = false
      end
    end
  end
end
