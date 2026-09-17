# frozen_string_literal: true

require "badline/cartridge/standard"
require "badline/cartridge/ocean"
require "badline/cartridge/magic_desk"

module Badline
  class Cartridge
    class UnsupportedTypeError < StandardError; end

    ROML_START = 0x8000
    ROMH_START = 0xa000
    ULTIMAX_ROMH_START = 0xe000
    BANK_SIZE = 0x2000

    HARDWARE_TYPES = { 0 => :Standard, 5 => :Ocean, 19 => :MagicDesk }.freeze

    attr_reader :name, :exrom, :game, :roml, :romh

    class << self
      def from_file(path)
        from_crt(Storage::CRTFile.new(path))
      end

      def from_crt(crt)
        type = HARDWARE_TYPES.fetch(crt.hardware_type) do
          raise UnsupportedTypeError,
                "Unsupported cartridge hardware type #{crt.hardware_type}"
        end
        const_get(type).new(crt)
      end
    end

    def initialize(crt)
      @name = crt.name
      @exrom = crt.exrom
      @game = crt.game
      @roml = @romh = nil
      @on_change = nil
      install_chips(crt.chips)
    end

    def on_change(&block)
      @on_change = block
    end

    def ultimax?
      @game.zero? && @exrom == 1
    end

    # IO1/IO2 reads are open bus unless a mapper says otherwise.
    def peek(_addr)
      0xff
    end

    def poke(_addr, _value); end

    private

    def changed!
      @on_change&.call
    end

    def install_chips(_chips)
      raise NotImplementedError
    end

    # Banked cartridges index their ROMs by the CHIP packet's bank number.
    # Built by mapping over the chips rather than assigning into an empty
    # array: an empty array literal gives Spinel nothing to infer the
    # element type from, and it settles on an integer array.
    def bank_roms(chips, start)
      chips.sort_by(&:bank).map { |chip| rom_bank(chip.data, start) }
    end

    # Chips smaller than 8K (e.g. 4K Ultimax ROMs) have unconnected upper
    # address lines and mirror across the full bank.
    def rom_bank(data, start)
      data *= BANK_SIZE / data.length if data.length < BANK_SIZE
      ROM.new(data, length: data.length, start:)
    end
  end
end
