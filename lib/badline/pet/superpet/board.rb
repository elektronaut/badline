# frozen_string_literal: true

module Badline
  class PET
    class SuperPET < PET
      # The Waterloo board, after Levak's PET-Interfaces.txt, André
      # Fachat's SuperPET page and Commodore's 324037 schematic: 64K of
      # RAM in 16 banks of 4K, one at a time at $9000-$9FFF, and the I/O
      # page at $EF00 (IOPage), which both CPUs reach.
      #
      # The bank latch at $EFFC-$EFFD picks the bank with bits 0-3, and its
      # bit 7 lets writes reach the system latch at $EFF8-$EFFB:
      #
      #   bit 0  the CPU while SW2 is at PROG: 1 the 6502, 0 the 6809
      #   bit 1  the bank RAM while SW1 is at PROG: 1 read/write, 0 read only
      #   bit 3  pulls the user port's diagnostic sense, PIA 1's PA7, low
      #
      # Bit 0 of $EFFE-$EFFF puts the board's own ROM socket at $9000 in
      # place of the RAM, which badline leaves empty. All three are
      # write-only, and the RES line clears them, so the board starts at
      # bank 0.
      #
      # SW1 is READ, R/W or PROG, the bank RAM's write protect, and SW2
      # PROG, 6502 or 6809, the CPU. A write to the bank RAM while it is
      # protected goes nowhere.
      class Board
        CPU_SWITCH = %w[6502 6809 prog].freeze

        RAM_SWITCH = %w[rw read prog].freeze

        # $EF00-$EFFF: the 6702 at $EFE0-$EFE3, the ACIA at $EFF0-$EFF3
        # and the latches above. A read of a latch finds the last byte on
        # the bus, and below $EFF0, where neither chip answers, $FF.
        class IOPage
          def initialize(board, bus, dongle, acia)
            @board = board
            @bus = bus
            @dongle = dongle
            @acia = acia
          end

          def peek(addr)
            low = addr & 0xff
            return @bus.data if low >= 0xf4
            return @acia.peek(addr) if low >= 0xf0
            return @dongle.peek(addr) if low >= 0xe0 && low < 0xe4

            0xff
          end

          def poke(addr, value)
            low = addr & 0xff
            if low >= 0xfe
              @board.socket = value
            elsif low >= 0xfc
              @board.bank_latch = value
            elsif low >= 0xf8
              @board.system_latch = value
            elsif low >= 0xf0
              @acia.poke(addr, value) if low < 0xf4
            elsif low >= 0xe0
              @dongle.poke(addr, value) if low < 0xe4
            end
          end
        end

        attr_reader :cells, :bank_latch, :system_latch, :cpu_switch, :ram_switch

        # Bit 0 of $EFFE: 1 for the ROM socket at $9000.
        attr_reader :socket

        # +bus+ is the PET's, whose pages the board maps, and
        # +keyboard_ports+ PIA 1's, whose PA7 the diagnostic sense is.
        # +cpu_switch+ and +ram_switch+ are SW2's and SW1's positions, one
        # of CPU_SWITCH's and RAM_SWITCH's.
        def initialize(bus, dongle:, acia:, keyboard_ports:, cpu_switch: "6502", ram_switch: "rw")
          raise ArgumentError, "the CPU switch has no position #{cpu_switch}" unless CPU_SWITCH.include?(cpu_switch)
          raise ArgumentError, "the RAM switch has no position #{ram_switch}" unless RAM_SWITCH.include?(ram_switch)

          @bus = bus
          @dongle = dongle
          @keyboard_ports = keyboard_ports
          @cpu_switch = cpu_switch
          @ram_switch = ram_switch
          @cells = Array.new(0x10000, 0)
          @banks = Array.new(16) { |bank| Bus::Expansion::Window.new(@cells, bank << 12, 0x9000) }
          @io = IOPage.new(self, bus, dongle, acia)
          @bank_latch = 0
          @system_latch = 0
          @socket = 0
        end

        def bank = @bank_latch & 0x0f

        def bank_latch=(value)
          @bank_latch = value
          @bus.map_pages
        end

        def system_latch=(value)
          return if @bank_latch.nobits?(0x80)

          @system_latch = value
          @keyboard_ports.diagnostic_low = value.anybits?(0x08)
          @bus.map_pages
        end

        def socket=(value)
          @socket = value & 0x01
          @bus.map_pages
        end

        # Whether writes to the bank RAM go nowhere.
        def write_protected?
          case @ram_switch
          when "read" then true
          when "rw" then false
          else @system_latch.nobits?(0x02)
          end
        end

        # Whether the CPU switch, or the system latch with it at PROG,
        # picks the 6809.
        def m6809_selected?
          case @cpu_switch
          when "6502" then false
          when "6809" then true
          else @system_latch.nobits?(0x01)
          end
        end

        # The RES line clears the latches, and the 6702.
        def reset!
          @bank_latch = 0
          @system_latch = 0
          @socket = 0
          @keyboard_ports.diagnostic_low = false
          @dongle.reset!
          @bus.map_pages
        end

        def power_on!
          @cells.fill(0)
        end

        # Lays the bank, or the empty socket, over $9000-$9FFF and the I/O
        # page over $EF00.
        def map(reads, writes)
          if @socket.zero?
            window = @banks[bank]
            window.read_only = write_protected?
            reads.fill(window, 0x90, 0x10)
            writes.fill(window, 0x90, 0x10)
          else
            reads.fill(@bus.open_bus, 0x90, 0x10)
            writes.fill(@bus.open_bus, 0x90, 0x10)
          end
          reads[0xef] = @io
          writes[0xef] = @io
        end
      end
    end
  end
end
