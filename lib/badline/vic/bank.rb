# frozen_string_literal: true

module Badline
  class VIC < Cycleable
    # The 16K window the VIC sees into RAM, selected by CIA2 $DD00. Character
    # ROM shadows $1000-$1FFF in banks 0 and 2.
    class Bank
      include Addressable

      # The CIA2 port A bank bits are inverted: %11 selects bank 0.
      BANK_STARTS = [0xc000, 0x8000, 0x4000, 0x0000].freeze

      attr_reader :address_bus

      # The byte the last phi1 fetch left on the data bus. Colour RAM drives
      # only the low four lines, so a CPU read there takes its upper nibble
      # from this.
      attr_reader :phi1_data

      def initialize(address_bus = nil)
        addressable_at(0x0000, length: 2**14)
        @address_bus = address_bus || AddressBus.new
        @phi1_data = 0
      end

      # A phi1 fetch: a g- or p-access. A sprite's three s-accesses are read
      # together through here as well, so its last byte stands in for the
      # middle one that really runs in phi1.
      def peek(offset)
        @phi1_data = peek_phi2(offset)
      end

      # A phi2 fetch, the c-access, which leaves the phi1 bus value alone.
      def peek_phi2(offset)
        return ultimax_peek(offset) if @address_bus.ultimax

        bits = bank_switch_register
        if bits.allbits?(0b01) && (offset & 0xf000) == 0x1000
          @address_bus.character_rom.peek(0xc000 + offset)
        else
          @address_bus.ram.peek(BANK_STARTS[bits] + offset)
        end
      end

      def peek_color(offset)
        address_bus.color_ram.nibble(0xd800 + offset)
      end

      def poke(_addr, _value)
        raise ReadOnlyMemoryError
      end

      def start
        BANK_STARTS[bank_switch_register]
      end

      private

      # In Ultimax mode the cartridge ROMH replaces the character ROM
      # shadow, visible at $3000-$3FFF of the window.
      def ultimax_peek(offset)
        romh = @address_bus.cartridge.romh
        if romh && offset.allbits?(0x3000)
          romh.peek(0xe000 + (offset & 0x1fff))
        else
          @address_bus.ram.peek(BANK_STARTS[bank_switch_register] + offset)
        end
      end

      def bank_switch_register
        @address_bus.cia2.port_a_lines & 0b11
      end

      def character_rom?
        bank_switch_register.allbits?(0b01)
      end
    end
  end
end
