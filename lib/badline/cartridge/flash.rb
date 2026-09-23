# frozen_string_literal: true

module Badline
  class Cartridge
    # An AMD 29F0x0 flash chip, driven through the JEDEC command set in the
    # AMD datasheets. Each command opens with two unlock cycles, $AA to the
    # first unlock address and $55 to the second, and a third write picks
    # the command:
    #
    #   $90 autoselect: offset 0 reads the manufacturer, 1 the device and 2
    #       the sector protection, until a reset
    #   $F0 reset to reading the array, which a lone $F0 also does
    #   $A0 byte program: the next write clears bits of the array, which
    #       only an erase sets again
    #   $80 erase, after two more unlock cycles: $10 to the first unlock
    #       address erases the chip, and $30 to a sector erases the sector.
    #       Further sectors can follow within the 50 us window.
    #
    # While a program or erase runs, a read returns status: DQ7 the
    # complement of the programmed bit (0 while erasing), DQ6 toggling on
    # every read, DQ5 set when a program failed and DQ3 set once an erase
    # has left its window. $B0 suspends a sector erase and $30 resumes it.
    #
    # The cartridge reads the array through windows, and the chip swaps
    # them for status windows while it is busy or in autoselect.
    class Flash
      Model = Data.define(:size, :sector_size, :unlock1, :unlock2, :unlock_mask, :manufacturer, :device)

      AM29F040 = Model.new(size: 0x80000, sector_size: 0x10000, unlock1: 0x5555, unlock2: 0x2aaa,
                           unlock_mask: 0x7fff, manufacturer: 0x01, device: 0xa4)
      AM29F040B = Model.new(size: 0x80000, sector_size: 0x10000, unlock1: 0x555, unlock2: 0x2aa,
                            unlock_mask: 0x7ff, manufacturer: 0x01, device: 0xa4)
      AM29F010 = Model.new(size: 0x20000, sector_size: 0x4000, unlock1: 0x5555, unlock2: 0x2aaa,
                           unlock_mask: 0x7fff, manufacturer: 0x01, device: 0x20)

      # The datasheet's typical times, in cycles at 1 MHz.
      PROGRAM_CYCLES = 7
      ERASE_WINDOW_CYCLES = 50
      SECTOR_ERASE_CYCLES = 1_000_000
      CHIP_ERASE_CYCLES = 8_000_000

      # The array, read directly while the chip reads it.
      class Window
        def initialize(flash, base)
          @flash = flash
          @data = flash.data
          @base = base
        end

        def peek(addr)
          @data[@base | (addr & 0x1fff)]
        end
        alias [] peek

        def poke(addr, value)
          @flash.write(@base | (addr & 0x1fff), value)
        end
        alias []= poke
      end

      # Reads through the chip, for its status and autoselect codes.
      class StatusWindow < Window
        def peek(addr)
          @flash.read(@base | (addr & 0x1fff))
        end
        alias [] peek
      end

      attr_reader :data, :state
      attr_writer :clock

      def initialize(data, model: AM29F040B, clock: -> { 0 })
        @model = model
        @data = data + ([0xff] * (model.size - data.length))
        @clock = clock
        @windows = {}
        @status_windows = {}
        @on_change = nil
        @state = :read
        @base_state = :read
        @cycle = 0
        @toggle = 0
      end

      # Called when the chip starts or stops answering reads from the array.
      def on_change(&block)
        @on_change = block
      end

      def window(base)
        if array_mode?
          @windows[base] ||= Window.new(self, base)
        else
          @status_windows[base] ||= StatusWindow.new(self, base)
        end
      end

      def array_mode?
        @state == :read || @state == :program_setup
      end

      def read(offset)
        settle
        case @state
        when :read then @data[offset]
        when :autoselect then autoselect_code(offset)
        when :suspended then suspended_read(offset)
        else status
        end
      end

      def write(offset, value)
        settle
        case @state
        when :program_setup then program(offset, value)
        when :erase_window then extend_erase(offset, value)
        when :erasing then suspend if value == 0xb0
        when :suspended then resume if value == 0x30
        when :program_error then enter(:read, base: :read) if value == 0xf0
        when :programming, :chip_erase then nil
        else command(offset, value)
        end
      end

      private

      def command(offset, value)
        if value == 0xf0
          @cycle = 0
          return enter(:read, base: :read)
        end

        address = offset & @model.unlock_mask
        @cycle = case @cycle
                 when 0, 3 then address == @model.unlock1 && value == 0xaa ? @cycle + 1 : 0
                 when 1, 4 then address == @model.unlock2 && value == 0x55 ? @cycle + 1 : 0
                 when 2 then command_cycle(address, value)
                 when 5 then erase_command(offset, address, value)
                 end
      end

      def command_cycle(address, value)
        return 0 unless address == @model.unlock1

        case value
        when 0x90 then enter(:autoselect, base: :autoselect)
        when 0xa0 then @state = :program_setup
        when 0x80 then return 3
        end
        0
      end

      def erase_command(offset, address, value)
        if value == 0x10 && address == @model.unlock1
          start_busy(:chip_erase, CHIP_ERASE_CYCLES)
        elsif value == 0x30
          @erasing_sectors = [sector(offset)]
          start_busy(:erase_window, ERASE_WINDOW_CYCLES)
        end
        0
      end

      def program(offset, value)
        @programmed = value
        @data[offset] &= value
        if @data[offset] == value
          start_busy(:programming, PROGRAM_CYCLES)
        else
          enter(:program_error)
        end
      end

      def extend_erase(offset, value)
        case value
        when 0x30
          @erasing_sectors |= [sector(offset)]
          @done_at = now + ERASE_WINDOW_CYCLES
        when 0xb0
          @remaining = @erasing_sectors.length * SECTOR_ERASE_CYCLES
          enter(:suspended)
        else
          @erasing_sectors = nil
          enter(@base_state)
        end
      end

      def suspend
        @remaining = @done_at - now
        enter(:suspended)
      end

      def resume
        start_busy(:erasing, @remaining)
      end

      # Moves a timed operation on once the clock has passed its end.
      def settle
        return unless @done_at && now >= @done_at

        case @state
        when :erase_window
          start_busy(:erasing, @done_at - now + (@erasing_sectors.length * SECTOR_ERASE_CYCLES))
          settle
        when :erasing
          @erasing_sectors.each { |s| @data.fill(0xff, s * @model.sector_size, @model.sector_size) }
          @erasing_sectors = nil
          finish
        when :chip_erase
          @data.fill(0xff)
          finish
        else
          finish
        end
      end

      def finish
        @done_at = nil
        enter(@base_state)
      end

      def start_busy(state, cycles)
        @done_at = now + cycles
        @programmed = 0xff unless state == :programming
        enter(state)
      end

      def enter(state, base: @base_state)
        was_array = array_mode?
        @state = state
        @base_state = base
        @done_at = nil unless %i[programming erase_window erasing chip_erase].include?(state)
        @on_change&.call if was_array != array_mode?
      end

      def status
        @toggle ^= 0x40
        value = (~@programmed & 0x80) | @toggle
        value |= 0x20 if @state == :program_error
        value |= 0x08 if @state == :erasing || @state == :chip_erase
        value
      end

      def suspended_read(offset)
        @erasing_sectors.include?(sector(offset)) ? 0x80 : @data[offset]
      end

      def autoselect_code(offset)
        case offset & 0x43
        when 0 then @model.manufacturer
        when 1 then @model.device
        when 2 then 0x00
        else @data[offset]
        end
      end

      def sector(offset)
        offset / @model.sector_size
      end

      def now
        @clock.call
      end
    end
  end
end
