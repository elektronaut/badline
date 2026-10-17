# frozen_string_literal: true

module Badline
  class PET
    class Bus
      # The 64K board of the 8096 and the 8296: four 16K banks, which a
      # write-only control register at $FFF0 lays over $8000-$FFFF, two at
      # a time:
      #
      #   bit 7  the board on; when clear, the rest ignored
      #   bit 6  I/O shows through at $E800-$EFFF
      #   bit 5  the screen shows through at $8000-$8FFF
      #   bit 3  bank 3 at $C000-$FFFF, else bank 1
      #   bit 2  bank 2 at $8000-$BFFF, else bank 0
      #   bit 1  writes to $C000-$FFFF go nowhere
      #   bit 0  writes to $8000-$BFFF go nowhere
      #
      # A write to $FFF0 lands where $FFF0 was before it, too. The RES line
      # clears the register, so the 8096 starts as an 8032.
      #
      # The 8296 decodes its memory in a PLA, after the logic equations
      # André Fachat read out of it (8296desc.txt on zimmers.net), with 32K
      # of RAM from $8000 (Bus#screen) besides the board:
      #
      # - With bit 7 clear, every write from $8000 up but to $E8xx goes to
      #   that RAM, under the ROMs too. Reads find the screen at $8000,
      #   the empty sockets at $9000 and $A000, BASIC, the editor at
      #   $E000-$E7FF and again at $E900-$EFFF, and the KERNAL, unless the
      #   lines /RAMSEL9, /RAMSELA and /RAMON put RAM there (#ram_lines).
      #   RAMSEL9 puts it at $9000, RAMSELA at $A000, RAMON at
      #   $8000-$DFFF, RAMON with either of the others at $E000-$EFFF but
      #   $E8xx, and RAMON with RAMSELA at $F000 as well.
      # - With bit 7 set, I/O showing through brings back the editor at
      #   $E900-$EFFF, which an 8096 leaves empty.
      #
      # Jumpers tie the lines: JU2 RAMSEL9 low and JU1 RAMSELA low
      # (:ram9, :rama), or JU4, JU3 and JU5 RAMSEL9, RAMSELA and RAMON to
      # the user port's PA1, PA0 and PA2 (:userport), each active low.
      # With none fitted, as on xpet's 8296, the lines stay high.
      class Expansion
        # A 16K bank of the board, seen from +start+.
        class Window
          attr_accessor :read_only

          def initialize(cells, offset, start)
            @cells = cells
            @offset = offset - start
            @read_only = false
          end

          def peek(addr) = @cells[addr + @offset]

          def poke(addr, value)
            @cells[addr + @offset] = value unless @read_only
          end
        end

        # Page $FF's writes, which pass to what the page holds and set the
        # control register at $FFF0.
        class ControlPort
          attr_accessor :under

          def initialize(expansion, under)
            @expansion = expansion
            @under = under
          end

          def poke(addr, value)
            @under.poke(addr, value)
            @expansion.control = value if addr == 0xfff0
          end
        end

        # The user port lines that RAMSELA, RAMSEL9 and RAMON follow.
        USER_PORT_LINES = 0x07

        attr_reader :cells, :control

        # The user port's PA0-PA2 as the board last saw them.
        attr_reader :lines

        # +jumpers+ are the 8296's (ROMSets::JUMPERS) when +board8296+ is.
        def initialize(bus, board8296: false, jumpers: [])
          @bus = bus
          @cells = Array.new(0x10000, 0)
          @banks = [0x8000, 0xc000, 0x8000, 0xc000].each_with_index.map do |start, bank|
            Window.new(@cells, bank * 0x4000, start)
          end
          @port = ControlPort.new(self, @banks[1])
          @control = 0
          @board8296 = board8296
          @ram9 = jumpers.include?("ram9")
          @rama = jumpers.include?("rama")
          @user_port = jumpers.include?("userport")
          @lines = USER_PORT_LINES
        end

        def board8296? = @board8296

        # Whether the board follows the user port's lines.
        def user_port? = @user_port

        def control=(value)
          @control = value
          @bus.map_pages
        end

        # Follows the user port's lines, +port_a+ as the VIA drives them.
        def lines=(port_a)
          lines = port_a & USER_PORT_LINES
          return if lines == @lines

          @lines = lines
          @bus.map_pages
        end

        def reset!
          self.control = 0
        end

        def power_on!
          @cells.fill(0)
        end

        # Whether the CPU reads the KERNAL at $F000-$FFFF.
        def kernal_mapped?
          return false if @control.anybits?(0x80)

          !(@board8296 && ram_on? && ram_a?)
        end

        # Lays the banks the register picks over the pages, and the
        # control register over page $FF's writes.
        def map(reads, writes)
          if @control.anybits?(0x80)
            map_banks(reads, writes)
          elsif @board8296
            map_ram8296(reads, writes)
          end
          @port.under = writes[0xff]
          writes[0xff] = @port
        end

        private

        def ram_on? = @user_port && @lines.nobits?(0x04)

        def ram9? = @ram9 || (@user_port && @lines.nobits?(0x02))

        def ram_a? = @rama || (@user_port && @lines.nobits?(0x01))

        def map_banks(reads, writes)
          low = @banks[@control.anybits?(0x04) ? 2 : 0]
          high = @banks[@control.anybits?(0x08) ? 3 : 1]
          low.read_only = @control.anybits?(0x01)
          high.read_only = @control.anybits?(0x02)
          first = @control.anybits?(0x20) ? 0x90 : 0x80
          reads.fill(low, first, 0xc0 - first)
          writes.fill(low, first, 0xc0 - first)
          [[0xc0, 0x28], [0xe8, 0x08], [0xf0, 0x10]].each do |page, count|
            next if page == 0xe8 && @control.anybits?(0x40)

            reads.fill(high, page, count)
            writes.fill(high, page, count)
          end
          map_editor_through(reads, writes) if @board8296
        end

        # I/O showing through on the 8296 leaves $E900-$EFFF to the editor,
        # and its writes to nothing.
        def map_editor_through(reads, writes)
          return unless @control.anybits?(0x40)

          reads.fill(@bus.editor_rom, 0xe9, 0x07)
          writes.fill(@bus.open_bus, 0xe9, 0x07)
        end

        def map_ram8296(reads, writes)
          ram = @bus.screen
          writes.fill(ram, 0x90, 0x58)
          writes.fill(ram, 0xe9, 0x17)
          reads.fill(@bus.editor_rom, 0xe9, 0x07)
          ram_on = ram_on?
          ram9 = ram9?
          ram_a = ram_a?
          reads.fill(ram, 0x90, 0x10) if ram9 || ram_on
          reads.fill(ram, 0xa0, 0x10) if ram_a || ram_on
          return unless ram_on

          reads.fill(ram, 0xb0, 0x30)
          return unless ram9 || ram_a

          reads.fill(ram, 0xe0, 0x08)
          reads.fill(ram, 0xe9, 0x07)
          reads.fill(ram, 0xf0, 0x10) if ram_a
        end
      end
    end
  end
end
