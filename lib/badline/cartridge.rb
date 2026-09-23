# frozen_string_literal: true

require "badline/cartridge/bank"
require "badline/cartridge/flash"
require "badline/cartridge/standard"
require "badline/cartridge/simons_basic"
require "badline/cartridge/ocean"
require "badline/cartridge/fun_play"
require "badline/cartridge/super_games"
require "badline/cartridge/epyx_fastload"
require "badline/cartridge/westermann"
require "badline/cartridge/rex_utility"
require "badline/cartridge/game_system"
require "badline/cartridge/dinamic"
require "badline/cartridge/zaxxon"
require "badline/cartridge/magic_desk"
require "badline/cartridge/comal80"
require "badline/cartridge/easy_flash"
require "badline/cartridge/mach5"
require "badline/cartridge/pagefox"
require "badline/cartridge/rgcd"
require "badline/cartridge/g_mod2"
require "badline/cartridge/freezer"
require "badline/cartridge/action_replay"
require "badline/cartridge/atomic_power"
require "badline/cartridge/final_cartridge3"
require "badline/cartridge/retro_replay"

module Badline
  class Cartridge
    class UnsupportedTypeError < StandardError; end

    ROMH_START = 0xa000
    BANK_SIZE = 0x2000

    HARDWARE_TYPES = {
      0 => :Standard, 1 => :ActionReplay, 3 => :FinalCartridge3,
      4 => :SimonsBasic, 5 => :Ocean, 7 => :FunPlay, 8 => :SuperGames,
      9 => :AtomicPower, 10 => :EpyxFastload, 11 => :Westermann,
      12 => :RexUtility, 15 => :GameSystem, 17 => :Dinamic, 18 => :Zaxxon,
      19 => :MagicDesk, 21 => :Comal80, 32 => :EasyFlash, 36 => :RetroReplay,
      51 => :Mach5, 53 => :Pagefox, 57 => :RGCD, 60 => :GMod2
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
      @on_nmi_change = nil
      @nmi = false
      @open_bus = nil
      @clock = nil
      install_chips(crt.chips)
    end

    def on_change(&block)
      @on_change = block
    end

    # Called with the level of the cartridge's pull on the NMI line when it
    # changes. The line is wired-OR with CIA 2's.
    def on_nmi_change(&block)
      @on_nmi_change = block
    end

    def nmi?
      @nmi
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

    # Whether the first half of the cycle, where the VIC does most of its
    # fetching, sees Ultimax mode. Some cartridges drive GAME and EXROM
    # differently in the two halves; #ultimax? is the second, the CPU's.
    def phi1_ultimax?
      ultimax?
    end

    # The I/O pages ($de, $df) whose reads the mapper drives. Reads of the
    # others are open bus.
    def readable_io_pages
      []
    end

    def poke(_addr, _value); end

    # A window taking writes to $E000-$FFFF while reads there see the C64's
    # memory, for a cartridge that asserts Ultimax on write cycles only.
    def romh_writes; end

    # The RES line on the expansion port.
    def reset; end

    # The freeze button, which cartridges without one ignore.
    def press_button; end

    def release_button; end

    private

    def nmi=(level)
      return if @nmi == level

      @nmi = level
      @on_nmi_change&.call(level)
    end

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
