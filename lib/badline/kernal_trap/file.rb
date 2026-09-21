# frozen_string_literal: true

module Badline
  module KernalTrap
    class File < Routine
      MISSING_FILENAME = 0x08

      def initialize(cpu:, bus:, storage:)
        super(cpu:, bus:)
        @storage = storage
      end

      private

      def active?
        kernal? && @bus.peek(0xba) == DEVICE
      end

      # Filename pointer at $BB/$BC, length at $B7
      def filename
        pointer = uint16(@bus.peek(0xbb), @bus.peek(0xbc))
        bytes = Array.new(@bus.peek(0xb7)) do |i|
          @bus.peek((pointer + i) & 0xffff)
        end
        Storage.strip_drive_prefix(Storage.ascii(bytes))
      end

      def error(code)
        @cpu.a = code
        @cpu.status.carry = true
      end
    end
  end
end
