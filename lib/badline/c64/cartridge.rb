# frozen_string_literal: true

require "badline/c64/cartridge/bank"
require "badline/c64/cartridge/flash"
require "badline/c64/cartridge/standard"
require "badline/c64/cartridge/simons_basic"
require "badline/c64/cartridge/ocean"
require "badline/c64/cartridge/fun_play"
require "badline/c64/cartridge/super_games"
require "badline/c64/cartridge/epyx_fastload"
require "badline/c64/cartridge/westermann"
require "badline/c64/cartridge/rex_utility"
require "badline/c64/cartridge/game_system"
require "badline/c64/cartridge/dinamic"
require "badline/c64/cartridge/zaxxon"
require "badline/c64/cartridge/magic_desk"
require "badline/c64/cartridge/comal80"
require "badline/c64/cartridge/easy_flash"
require "badline/c64/cartridge/mach5"
require "badline/c64/cartridge/pagefox"
require "badline/c64/cartridge/rgcd"
require "badline/c64/cartridge/g_mod2"
require "badline/c64/cartridge/freezer"
require "badline/c64/cartridge/action_replay"
require "badline/c64/cartridge/atomic_power"
require "badline/c64/cartridge/final_cartridge3"
require "badline/c64/cartridge/retro_replay"
require "badline/c64/cartridge/kcs_power"
require "badline/c64/cartridge/geo_ram"

module Badline
  class C64
    class Cartridge
      class UnsupportedTypeError < StandardError; end
      ROMH_START = 0xa000
      BANK_SIZE = 0x2000

      HARDWARE_TYPES = {
        0 => Standard, 1 => ActionReplay, 2 => KCSPower, 3 => FinalCartridge3,
        4 => SimonsBasic, 5 => Ocean, 7 => FunPlay, 8 => SuperGames,
        9 => AtomicPower, 10 => EpyxFastload, 11 => Westermann,
        12 => RexUtility, 15 => GameSystem, 17 => Dinamic, 18 => Zaxxon,
        19 => MagicDesk, 21 => Comal80, 32 => EasyFlash, 36 => RetroReplay,
        51 => Mach5, 53 => Pagefox, 57 => RGCD, 60 => GMod2
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
        # Options set the cartridge's jumpers, for the mappers that have them.
        def from_file(path, **)
          from_crt(Storage::CRTFile.new(path), **)
        end

        def from_crt(crt, **)
          mapper_for(crt).new(crt, **)
        end

        def mapper_for(crt)
          HARDWARE_TYPES.fetch(crt.hardware_type) do
            raise UnsupportedTypeError,
                  "Unsupported cartridge hardware type #{crt.hardware_type}"
          end
        end
      end

      # Keeps the image it was built from, so a snapshot's machine can build
      # the same cartridge before the snapshot's state goes into it.
      def initialize(crt)
        @crt = crt
        @name = crt.name
        @exrom = crt.exrom
        @game = crt.game
        @roml = @romh = nil
        @banks = nil
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

      # A window at $A000-$BFFF in Ultimax mode, where the C64 maps nothing.
      def ultimax_a000; end

      # The RES line on the expansion port.
      def reset; end

      # Whether the cartridge has a freeze button.
      def freezer? = false

      # The freeze button, which cartridges without one ignore.
      def press_button; end

      def release_button; end

      private

      # The banks and views ROML and ROMH can point at, which a 0.14.0
      # snapshot names them by: the mapper's banks, or nothing for a mapper
      # whose windows stay where install_chips put them.
      def windows
        [*@banks, EMPTY_BANK] if @banks
      end

      def window_index(window, windows)
        return -1 if window.nil?

        windows.index { |candidate| candidate.equal?(window) } ||
          raise(ArgumentError, "#{self.class.name}: a window that isn't among its banks")
      end

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

      # Sets the lines and tells the machine to map the cartridge again.
      def select_mode(mode)
        self.mode = mode
        changed!
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

      # A bank the image leaves out reads as erased ROM.
      def bank(banks, number)
        banks[number] || EMPTY_BANK
      end

      # The bank register bits a ROM decodes. The ROM holds the highest bank
      # in the image, and has address lines for the power of two that covers
      # it; the register bits above those lines are ignored.
      def bank_mask(banks)
        (1 << (banks.length - 1).bit_length) - 1
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
end
require "badline/c64/cartridge/keyed_state"
