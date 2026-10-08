# frozen_string_literal: true

require "badline/c128/vdc/memory"
require "badline/c128/vdc/window"
require "badline/c128/vdc/painter"
require "badline/c128/vdc/raster"

module Badline
  class C128
    # The 8563 or 8568 VDC: the address register at $D600 and the data
    # register at $D601, mirrored through $D6FF, in front of 37 internal
    # registers (38 on the 8568), the VDC's own RAM (Memory) and its 80
    # column RGBI display (Raster, Painter).
    #
    # A write to $D600 selects a register, and a read there gives the
    # status: bit 7 ready for the next access, bit 5 in the vertical blank
    # (outside the displayed rows), and bits 0-2 the version. $D601 reads
    # and writes the selected register. A register past the last reads $FF.
    # The light pen is left out.
    #
    # R18 and R19 hold the update address, high byte first, and a write to
    # either reads the RAM there into R31. A read of R31 gives that byte,
    # moves the address on and reads the next. A write of R31 stores the
    # byte, moves the address on and reads the next. A write of R30 then
    # repeats the last byte written over R30 more bytes (256 for 0), or with
    # R24 bit 7 copies that many from R32/R33 on, and leaves the update
    # address, and R32/R33 for a copy, after the last byte.
    #
    # The VDC runs on its own 16 MHz dot clock, a character clock every
    # character width of dots (R22, doubled by R25 bit 4). The status reads
    # not ready for ACCESS_CLOCKS character clocks after an access through
    # R31 or a write of R18 or R19, and for one clock per byte a block write
    # fills or two per byte it copies.
    class VDC
      include Addressable

      STATUS_READY = 0x80
      STATUS_VBLANK = 0x20
      UPDATE_HIGH = 18
      UPDATE_LOW = 19
      WORD_COUNT = 30
      DATA = 31
      SOURCE_HIGH = 32
      SOURCE_LOW = 33
      DOT_CLOCK_HZ = 16_000_000

      # Character clocks the status reads busy after an access through R31
      # or a write of R18 or R19, fitted to the timings a flat C128 gave
      # VDC/vdctiming (TimingResultsFlatC128.jpg).
      ACCESS_CLOCKS = 30

      # The version in the status bits: 1 for the 8563 R8 and R9, and 2 for
      # the 8568.
      VERSIONS = { mos8563: 1, mos8568: 2 }.freeze

      # The 16 RGBI colours, red, green, blue and intensity from bit 3 down,
      # as the Programmer's Reference Guide names them: 1100 is dark yellow.
      PALETTE = Array.new(16) do |rgbi|
        intensity = rgbi.anybits?(1) ? 0x55 : 0
        red = (rgbi.anybits?(8) ? 0xaa : 0) + intensity
        green = (rgbi.anybits?(4) ? 0xaa : 0) + intensity
        blue = (rgbi.anybits?(2) ? 0xaa : 0) + intensity
        (red << 16) | (green << 8) | blue
      end.freeze

      attr_reader :model, :registers

      # Whether lines paint into the display as the raster passes them.
      attr_reader :render

      # +ram_kb+ is 16 or 64, and +clock_hz+ the CPU's clock the VDC is
      # clocked against.
      def initialize(model: :mos8563, ram_kb: 16, clock_hz: Region::PAL.clock_hz)
        addressable_at(0xd600, length: 0x100)
        @model = model
        @version = VERSIONS.fetch(model)
        @clock_hz = clock_hz
        @registers = Array.new(model == :mos8568 ? 38 : 37, 0)
        @memory = Memory.new(ram_kb)
        @painter = Painter.new(@registers, @memory)
        @raster = Raster.new(@registers, @painter)
        @render = false
        power_on!
      end

      # The dots a character takes, R22 bits 4-7 plus one, or R22 bits 4-7
      # doubled in double-width mode.
      def self.char_dots(registers)
        width = registers[22] >> 4
        registers[25].anybits?(0x10) ? [width, 1].max * 2 : width + 1
      end

      # The registers clear, the RAM clears and the raster starts a frame.
      def power_on!
        @registers.fill(0)
        @memory.clear!
        @memory.mode64 = false
        @selected = 0
        @read_latch = 0
        @write_data = 0
        @busy_until = 0
        @phase = 0
        @raster.reset!
        @line_units = @raster.line_dots * @clock_hz
        @painter.clear!
      end

      def ram = @memory.ram

      def render=(on)
        @render = on
        @painter.clear!
      end

      # Everything the VDC holds but its display, which it paints again
      # while it renders: the registers, the RAM, the data port and the
      # raster. Whether it renders is the host's.
      def save_state(out)
        out.marker("VDC")
        out.ints(@registers).blob(@memory.ram)
        out.int(@selected).int(@read_latch).int(@write_data).int(@busy_until).int(@phase).int(@line_units)
        @raster.save_state(out)
        @painter.save_state(out)
      end

      def load_state(input)
        input.marker("VDC")
        input.ints_into(@registers)
        input.blob_into(@memory.ram)
        @memory.mode64 = @registers[28].anybits?(0x10)
        @selected = input.int
        @read_latch = input.int
        @write_data = input.int
        @busy_until = input.int
        @phase = input.int
        @line_units = input.int
        @raster.load_state(input)
        @painter.load_state(input)
      end

      # The frames the raster has finished, which the blinking counts.
      def frame = @raster.frame

      def display = @painter.display

      def width = @painter.width

      def height = @painter.height

      def dirty_lines = @painter.dirty_lines

      def clear_dirty_lines! = @painter.clear_dirty_lines!

      def palette = PALETTE

      # The [left, top, width, height] of the display a monitor shows.
      def crop = @painter.crop(@raster.line_dots, @raster.frame_lines, @raster.sync_lines)

      # The update address R18 and R19 hold.
      def update_address = (@registers[UPDATE_HIGH] << 8) | @registers[UPDATE_LOW]

      # Whether an access or a block operation is still under way.
      def busy? = @phase < @busy_until

      # One CPU cycle: the dot clock runs on, and a line ends once it has
      # run a line's dots. The line's phase counts dots times the CPU's
      # clock, DOT_CLOCK_HZ a cycle.
      def cycle!
        @phase += DOT_CLOCK_HZ
        end_line if @phase >= @line_units
      end

      def peek(addr)
        return status if offset_of(addr).even?
        return read_ram if @selected == DATA

        @selected < @registers.length ? @registers[@selected] : 0xff
      end

      def poke(addr, value)
        return @selected = value & 0x3f if offset_of(addr).even?
        return if @selected >= @registers.length

        write_register(@selected, value)
      end

      private

      def status
        value = @version
        value |= STATUS_READY unless busy?
        value |= STATUS_VBLANK if @raster.vertical_blank?
        value
      end

      def end_line
        @phase -= @line_units
        @busy_until -= @line_units
        @raster.end_line(@render)
        @line_units = @raster.line_dots * @clock_hz
      end

      def write_register(number, value)
        @registers[number] = value
        case number
        when DATA then write_ram(value)
        when WORD_COUNT then block(value.zero? ? 256 : value)
        when UPDATE_HIGH, UPDATE_LOW then read_ahead
        when 28 then @memory.mode64 = value.anybits?(0x10)
        end
      end

      def read_ram
        value = @read_latch
        advance(1)
        read_ahead
        value
      end

      def write_ram(value)
        @memory.store(update_address, value)
        @write_data = value
        advance(1)
        read_ahead
      end

      def read_ahead
        @read_latch = @memory.fetch(update_address)
        busy(ACCESS_CLOCKS)
      end

      def block(count)
        copy = @registers[24].anybits?(0x80)
        copy ? copy_block(count) : fill_block(count)
        @read_latch = @memory.fetch(update_address)
        busy(copy ? count * 2 : count)
      end

      def fill_block(count)
        address = update_address
        count.times { |i| @memory.store(address + i, @write_data) }
        advance(count)
      end

      def copy_block(count)
        destination = update_address
        source = (@registers[SOURCE_HIGH] << 8) | @registers[SOURCE_LOW]
        count.times { |i| @memory.store(destination + i, @memory.fetch(source + i)) }
        advance(count)
        source = (source + count) & 0xffff
        @registers[SOURCE_HIGH] = source >> 8
        @registers[SOURCE_LOW] = source & 0xff
      end

      def advance(count)
        address = (update_address + count) & 0xffff
        @registers[UPDATE_HIGH] = address >> 8
        @registers[UPDATE_LOW] = address & 0xff
      end

      # Holds the status busy for `clocks` character clocks after whatever
      # is already under way.
      def busy(clocks)
        @busy_until = [@busy_until, @phase].max + (clocks * VDC.char_dots(@registers) * @clock_hz)
      end
    end
  end
end
