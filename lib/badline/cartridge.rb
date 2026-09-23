# frozen_string_literal: true

require "badline/cartridge/bank"
require "badline/cartridge/standard"
require "badline/cartridge/ocean"
require "badline/cartridge/magic_desk"

module Badline
  class Cartridge
    class UnsupportedTypeError < StandardError; end

    ROMH_START = 0xa000
    BANK_SIZE = 0x2000

    HARDWARE_TYPES = {
      0 => :Standard, 5 => :Ocean, 19 => :MagicDesk
    }.freeze

    # The EXROM and GAME line levels of each memory configuration. The lines
    # are active low.
    MODES = {
      rom8k: [0, 1].freeze, rom16k: [0, 0].freeze,
      ultimax: [1, 0].freeze, off: [1, 1].freeze
    }.freeze

    attr_reader :name, :exrom, :game, :roml, :romh

    # A callable returning the current cycle, for mappers with timed state.
    attr_writer :clock

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
      @open_bus = nil
      @clock = nil
      install_chips(crt.chips)
    end

    def on_change(&block)
      @on_change = block
    end

    # The address bus hands over the C64's RAM, for mappers that write
    # through to it, and the open bus, for I/O reads the cartridge doesn't
    # drive.
    def connect(ram:, open_bus:)
      @ram = ram
      @open_bus = open_bus
    end

    def ultimax?
      @game.zero? && @exrom == 1
    end

    # The I/O pages ($de, $df) whose reads the mapper drives. Reads of the
    # others are open bus.
    def readable_io_pages
      []
    end

    def poke(_addr, _value); end

    private

    def changed!
      @on_change&.call
    end

    def mode=(mode)
      @exrom, @game = MODES.fetch(mode)
    end

    def open_bus(addr)
      @open_bus ? @open_bus.peek(addr) : 0xff
    end

    def install_chips(_chips)
      raise NotImplementedError
    end

    def rom_bank(data)
      Bank.new(data)
    end

    def bank(banks, number)
      banks[number] || EMPTY_BANK
    end

    # Sorts the CHIP packets into ROML and ROMH banks by load address. A 16K
    # chip at $8000 spans both.
    def banks_from(chips)
      roml = []
      romh = []
      chips.each do |chip|
        if chip.address >= ROMH_START
          romh[chip.bank] = rom_bank(chip.data)
        else
          roml[chip.bank] = rom_bank(chip.data[0, BANK_SIZE])
          romh[chip.bank] = rom_bank(chip.data[BANK_SIZE, BANK_SIZE]) if chip.data.length > BANK_SIZE
        end
      end
      [roml, romh]
    end
  end
end
