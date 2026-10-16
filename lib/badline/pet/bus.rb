# frozen_string_literal: true

require "badline/pet/bus/expansion"

module Badline
  class PET
    # The CPU's bus:
    #
    # $0000-$7FFF - RAM, 4K, 8K, 16K or 32K of it from $0000, then nothing
    # $8000-$8FFF - screen RAM, repeated (Model), then nothing
    # $9000-$AFFF - two empty ROM sockets
    # $B000-$DFFF - BASIC 4, or BASIC 1 or 2 from $C000
    # $E000-$E7FF - the screen editor ROM
    # $E800-$E8FF - I/O (IO)
    # $E900-$EFFF - nothing
    # $F000-$FFFF - the KERNAL ROM
    #
    # The data lines hold the last byte they carried, so a read from an
    # empty spot finds it, mostly the high byte of the address just
    # fetched, as PET/unconnected shows on a real 3016. Writes to ROM and
    # to empty spots go nowhere. An 8096 banks its 64K board over
    # $8000-$FFFF (Expansion).
    class Bus
      include Addressable

      # The last byte the CPU moved, which an empty spot reads back.
      class OpenBus
        def initialize(bus)
          @bus = bus
        end

        def peek(_addr) = @bus.data
        def poke(_addr, _value); end
      end

      # Screen RAM, repeated over the pages it answers in.
      class ScreenRAM
        attr_reader :cells

        def initialize(size)
          @cells = Array.new(size, 0)
          @mask = size - 1
        end

        def peek(addr) = @cells[addr & @mask]

        def poke(addr, value)
          @cells[addr & @mask] = value
        end
      end

      # $E800-$E8FF. Each chip answers on one address line, with its
      # registers repeated: A4 selects PIA 1, A5 PIA 2, A6 the VIA and A7
      # the CRTC, where there is one. Where more than one chip answers a
      # read, each pulls the lines it drives low, so the CPU reads the AND
      # of them, and a write reaches them all. Where none answers, as in
      # $E800-$E80F, the CPU reads the last byte on the bus.
      class IO
        def initialize(bus, pia1:, pia2:, via:, crtc:, crtc_fitted:)
          @bus = bus
          @pia1 = pia1
          @pia2 = pia2
          @via = via
          @crtc = crtc
          @lines = crtc_fitted ? 0xf0 : 0x70
        end

        def peek(addr)
          return @bus.data if addr.nobits?(@lines)

          value = 0xff
          value &= @pia1.peek(addr) if addr.anybits?(0x10)
          value &= @pia2.peek(addr) if addr.anybits?(0x20)
          value &= @via.peek(addr) if addr.anybits?(0x40)
          value &= @crtc.peek(addr) if addr.anybits?(@lines & 0x80)
          value
        end

        def poke(addr, value)
          @pia1.poke(addr, value) if addr.anybits?(0x10)
          @pia2.poke(addr, value) if addr.anybits?(0x20)
          @via.poke(addr, value) if addr.anybits?(0x40)
          @crtc.poke(addr, value) if addr.anybits?(@lines & 0x80)
        end
      end

      attr_reader :ram, :screen, :expansion

      # The last byte the CPU read or wrote.
      attr_reader :data

      # +model+ is a Model::Profile, +ram_kb+ the RAM below $8000 and
      # +editor+ the editor ROM's file. The CRTC answers only on a board
      # the model fits one on.
      def initialize(model:, ram_kb:, editor:, pia1:, pia2:, via:, crtc:)
        addressable_at(0, length: 2**16)
        @ram = Memory.new([], length: ram_kb * 1024, start: 0)
        @screen = ScreenRAM.new(model.screen_bytes)
        @screen_pages = model.screen_pages
        basic = ROM.read(model.basic)
        @basic_rom = ROM.new(basic, length: basic.length, start: 0xe000 - basic.length)
        @editor_rom = ROM.load(editor, 0xe000)
        @kernal_rom = ROM.load(model.kernal, 0xf000)
        @io = IO.new(self, pia1:, pia2:, via:, crtc:, crtc_fitted: model.crtc?)
        @open_bus = OpenBus.new(self)
        @data = 0
        @read_pages = Array.new(256, @open_bus)
        @write_pages = Array.new(256, @open_bus)
        @expansion = model.expansion ? Expansion.new(self) : nil
        map_pages
      end

      # The RES line reaches the 8096's control register.
      def reset!
        @expansion&.reset!
      end

      def power_on!
        @ram.clear!
        @screen.cells.fill(0)
        @expansion&.power_on!
      end

      def peek(addr)
        @data = @read_pages[addr >> 8].peek(addr)
      end

      def poke(addr, value)
        @data = value
        @write_pages[addr >> 8].poke(addr, value)
      end

      # Lays the pages out again, for the 8096's control register.
      def map_pages
        map(@open_bus, 0x00, 0x100)
        map(@ram, 0x00, @ram.length >> 8)
        map(@screen, 0x80, @screen_pages)
        @read_pages.fill(@basic_rom, @basic_rom.start >> 8, @basic_rom.length >> 8)
        @read_pages.fill(@editor_rom, 0xe0, 0x08)
        map(@io, 0xe8, 0x01)
        @read_pages.fill(@kernal_rom, 0xf0, 0x10)
        @expansion&.map(@read_pages, @write_pages)
      end

      private

      def map(chip, first, count)
        @read_pages.fill(chip, first, count)
        @write_pages.fill(chip, first, count)
      end
    end
  end
end
