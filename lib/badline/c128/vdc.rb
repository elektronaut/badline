# frozen_string_literal: true

module Badline
  class C128
    # The 8563 or 8568 VDC's CPU side, without a display: the address
    # register at $D600 and the data register at $D601, mirrored through
    # $D6FF, in front of 37 internal registers (38 on the 8568) and the
    # VDC's own RAM.
    #
    # A write to $D600 selects a register, and a read there gives the
    # status: bit 7 is always set, ready for the next access, and bits 0-2
    # hold the version. $D601 reads and writes the selected register.
    # R18 and R19 hold the update address, high byte first, and R31 reads
    # or writes the RAM there and moves the address on by one. A register
    # past the last reads $FF.
    class VDC
      include Addressable

      STATUS_READY = 0x80
      UPDATE_HIGH = 18
      UPDATE_LOW = 19
      DATA = 31

      # The version in the status bits: 1 for the 8563 R8 and R9, and 2 for
      # the 8568.
      VERSIONS = { mos8563: 1, mos8568: 2 }.freeze

      attr_reader :model, :ram, :registers

      # +ram_kb+ is 16 or 64.
      def initialize(model: :mos8563, ram_kb: 16)
        addressable_at(0xd600, length: 0x100)
        @model = model
        @version = VERSIONS.fetch(model)
        @registers = Array.new(model == :mos8568 ? 38 : 37, 0)
        @ram = Array.new(ram_kb * 1024, 0)
        @ram_mask = @ram.length - 1
        @selected = 0
      end

      # The update address R18 and R19 hold.
      def update_address = ((@registers[UPDATE_HIGH] << 8) | @registers[UPDATE_LOW]) & @ram_mask

      def peek(addr)
        return STATUS_READY | @version if offset_of(addr).even?
        return read_ram if @selected == DATA

        @selected < @registers.length ? @registers[@selected] : 0xff
      end

      def poke(addr, value)
        return @selected = value & 0x3f if offset_of(addr).even?
        return write_ram(value) if @selected == DATA

        @registers[@selected] = value if @selected < @registers.length
      end

      private

      def read_ram
        value = @ram[update_address]
        advance
        value
      end

      def write_ram(value)
        @ram[update_address] = value
        advance
      end

      def advance
        address = (update_address + 1) & @ram_mask
        @registers[UPDATE_HIGH] = address >> 8
        @registers[UPDATE_LOW] = address & 0xff
      end
    end
  end
end
