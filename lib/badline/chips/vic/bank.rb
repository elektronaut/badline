# frozen_string_literal: true

module Badline
  module Chips
    class VIC
      # The 16K window the VIC sees into RAM, selected by CIA2 $DD00, in the
      # bank a +256K picks for it. Character
      # ROM shadows $1000-$1FFF in banks 0 and 2.
      #
      # The machine's bus pushes in what the VIC sees through #connect,
      # #map_character_rom and #map whenever it changes. Until then the bank
      # has a CIA 2, RAM, colour RAM and character ROM of its own.
      #
      # The P500 wires the VIC another way (#map_video_bus): its phi1
      # reads go to the character ROM while VICDOTSEL is high, and its phi2
      # reads to the 1K static video matrix while STATVID is high, VA12
      # high picking the matrix and VA12 low reading 0. Otherwise both go to
      # the DRAM's 16K bank that VA14 and VA15 pick (#video_bus_lines). The
      # colour nibbles come from the colour RAM in every phi2 read.
      class Bank
        include Addressable

        # The CIA2 port A bank bits are inverted: %11 selects bank 0.
        BANK_STARTS = [0xc000, 0x8000, 0x4000, 0x0000].freeze

        attr_reader :ram, :color_ram

        # The bank lines as #sample_lines last saw them.
        attr_accessor :lines

        def initialize(vic)
          addressable_at(0x0000, length: 2**14)
          connect(cia2: CIA.new(start: 0xdd00), color_ram: C64::ColorMemory.new(vic))
          map_character_rom(ROM.load("character.rom", 0xd000))
          @base = 0
          @starts = BANK_STARTS
          map(Memory.new([], length: 2**16, start: 0))
          @lines = 0b11
          @swapped = false
          @video_bus = false
          @matrix = @ram
          @statvid = false
          @dotsel = false
          @video_base = 0
        end

        # CIA 2, whose port A picks the bank, and the colour RAM, read from
        # the address +color_base+ gives offset 0.
        def connect(cia2:, color_ram:, color_base: 0xd800)
          @cia2 = cia2
          @color_ram = color_ram
          @color_base = color_base
        end

        # The character ROM, read from the address +base+ gives offset 0. It
        # shows in the banks whose low line is high, unless +shadow+ is false.
        def map_character_rom(rom, base: 0xc000, shadow: true)
          @character_rom = rom
          @character_base = base
          @shadow_mask = shadow ? 0b01 : 0b00
        end

        # The RAM the VIC's 64K starts at +base+ in, and the cartridge's
        # Ultimax lines in each half of the cycle with the ROMH bank they
        # show.
        def map(ram, base: 0, phi1_ultimax: false, ultimax: false, romh: nil)
          @ram = ram
          unless base == @base
            @base = base
            @starts = BANK_STARTS.map { |start| base + start }.freeze
          end
          @romh = romh
          @phi1_other = phi1_ultimax
          @phi2_other = ultimax
        end

        # The P500's video bus: +dram+ is segment 0's 64K, +matrix+ the
        # static video matrix, read from its start address on, and
        # +color_ram+ the colour RAM, read from +color_base+ on. The
        # character ROM is the one #map_character_rom gives, read from
        # +base+ on.
        def map_video_bus(dram, matrix, color_ram, color_base)
          @ram = dram
          @matrix = matrix
          @color_ram = color_ram
          @color_base = color_base
          @video_bus = true
          @phi1_other = true
          @phi2_other = true
        end

        # STATVID, VICDOTSEL and VA14-VA15, as the P500's TPIs drive them.
        def video_bus_lines(statvid, dotsel, bank)
          @statvid = statvid
          @dotsel = dotsel
          @video_base = bank << 14
        end

        # On the 8565, a port A write that swaps the two bank lines, driving
        # one high as the other goes low, shows the VIC both lines low for the
        # cycle after it: every access in that cycle reads bank 3. A swap that
        # the DDR makes, releasing a line to float high, shows nothing.
        # Called once a cycle, ahead of the cycle's accesses.
        def sample_lines
          lines = @cia2.port_a_lines & 0b11
          @swapped = swap?(@lines, lines) && @cia2.port_registers[2].allbits?(0b11)
          @lines = lines
        end

        def peek(offset)
          return phi1_other(offset) if @phi1_other

          bits = bank_switch_register
          if (bits & @shadow_mask) == 0b01 && (offset & 0xf000) == 0x1000
            @character_rom.peek(@character_base + offset)
          else
            @ram.peek(@starts[bits] + offset)
          end
        end

        # A fetch in the second half of the cycle, the c-access, sees the
        # memory configuration the CPU does in that half. No cartridge drives
        # Ultimax mode in the first half alone, so otherwise it reads as #peek.
        def peek_phi2(offset)
          @phi2_other ? phi2_other(offset) : peek(offset)
        end

        # A sprite's s-access in phi2: on the P500's video bus as the other
        # phi2 reads, and otherwise as #peek.
        def peek_sprite(offset)
          @video_bus ? phi2_other(offset) : peek(offset)
        end

        def peek_color(offset)
          @color_ram.nibble(@color_base + offset)
        end

        def poke(_addr, _value)
          raise ReadOnlyMemoryError
        end

        # True if the VIC reads the character ROM at this offset.
        def character_rom?(offset)
          !@phi1_other && (bank_switch_register & @shadow_mask) == 0b01 && (offset & 0xf000) == 0x1000
        end

        def start
          BANK_STARTS[bank_switch_register]
        end

        private

        def phi1_other(offset)
          return ultimax_peek(offset) unless @video_bus
          return @character_rom.peek(@character_base + (offset & 0x0fff)) if @dotsel

          @ram.peek(@video_base + offset)
        end

        def phi2_other(offset)
          return ultimax_peek(offset) unless @video_bus
          return @ram.peek(@video_base + offset) unless @statvid
          return 0 if offset.nobits?(0x1000)

          @matrix.peek(@matrix.start + (offset & 0x03ff))
        end

        # In Ultimax mode the cartridge ROMH replaces the character ROM
        # shadow, visible at $3000-$3FFF of the window. The MAX is in
        # Ultimax mode with no cartridge too.
        def ultimax_peek(offset)
          romh = @romh
          if romh && offset.allbits?(0x3000)
            romh.peek(0xe000 + (offset & 0x1fff))
          else
            @ram.peek(@starts[bank_switch_register] + offset)
          end
        end

        def swap?(from, to) = (from ^ to) == 0b11 && from.anybits?(0b11) && to.anybits?(0b11)

        def bank_switch_register
          return 0 if @swapped

          @cia2.port_a_lines & 0b11
        end
      end
    end
  end
end
