# frozen_string_literal: true

require "badline/vic/bank"
require "badline/vic/registers"
require "badline/vic/display_state"
require "badline/vic/sequencer"
require "badline/vic/sprites"

module Badline
  class VIC < Cycleable
    include Addressable
    include IntegerHelper

    attr_reader :address_bus, :display, :width, :height, :vic_bank, :column,
                :rasterline, :dirty_lines

    SPRITE_BA_RANGES = [
      55..59, 57..61, 59..62,
      0..2, 0..4, 2..6, 4..8, 6..10
    ].freeze

    def initialize(address_bus = nil, debug: false)
      addressable_at(0xd000, length: 2**10)
      @address_bus = address_bus || AddressBus.new
      @vic_bank = VIC::Bank.new(@address_bus)
      @debug = debug

      @width = 504
      @height = 312

      @registers = VIC::Registers.new
      @display_state = VIC::DisplayState.new(@registers)
      @sequencer = VIC::Sequencer.new(@width, @registers, @vic_bank)
      @sprites = VIC::Sprites.new(@registers, @vic_bank, @width)
      @display = Array.new(@width * @height, 0)
      @dirty_lines = Array.new(@height, true)

      @column = 0
      @rasterline = 0
      @columns_per_line = @width / 8
      @last_line = @height - 1

      @character_buffer = Array.new(40, 0)
      @color_buffer = Array.new(40, 0)
      @sprite_ba = Array.new(@width / 8, false)

      super()
    end

    def cycle!
      if @column.zero?
        @display_state.new_frame if @rasterline.zero?
        check_raster_irq!
        @sequencer.new_line(@rasterline)
        @sprites.start_line(@rasterline)
        rebuild_sprite_ba
        @display_state.new_line
      end

      @display_state.cycle(@rasterline, @column)

      fetch_character_data! if dma_active?

      draw!

      @column += 1
      if @column == @columns_per_line
        finish_line!
        @column = 0
        @rasterline = @rasterline == @last_line ? 0 : @rasterline + 1
      end
      nil
    end

    # The IRQ line is held asserted while any enabled latch bit is set in
    # $D019/$D01A, until the program acknowledges it by writing to $D019.
    def interrupted?
      @registers.irq_line?
    end

    def peek(addr)
      i = offset_of(addr) % (2**6)
      case i
      when 0x11 then (@registers[0x11] & 0x7f) | ((rasterline & 0x100) >> 1)
      when 0x12 then rasterline & 0xff
      when 0x19 then irq_status # Latch + master IRQ bit, unused bits read 1
      else @registers.read(i)
      end
    end

    def poke(addr, value)
      @registers.write(offset_of(addr) % (2**6), value)
    end

    def position
      (@rasterline * @width) + (@column * 8)
    end

    def dma_active?
      @display_state.bad_line? && @column >= 15 && @column < 55
    end

    def ba_low?
      return true if @sprite_ba[@column]

      @display_state.bad_line? && @column >= 13 && @column < 56
    end

    def hblank?
      @column < 10 || @column > 60
    end

    def vblank?
      @rasterline < 16 || @rasterline > 299
    end

    def blanking?
      @rasterline < 16 || @rasterline > 299 || @column < 10 || @column > 60
    end

    # Reset the dirty flags once the frontend has consumed them.
    def clear_dirty_lines!
      @dirty_lines.fill(false)
    end

    private

    def rebuild_sprite_ba
      @sprite_ba.fill(false)
      SPRITE_BA_RANGES.each_with_index do |range, n|
        next unless @sprites[n].displaying?

        range.each { |c| @sprite_ba[c] = true }
      end
    end

    def draw!
      return if blanking?

      col = @column - 16
      unless @display_state.display?
        @sequencer.emit_idle(col)
        return
      end

      cell = (@display_state.vc_base + col) & 0x3ff
      screencode = @character_buffer[col] || 0
      @sequencer.emit(screencode, @color_buffer[col] || 1, col,
                      cell, @display_state.rc)
    end

    def finish_line!
      return if vblank?

      # Composite the active sprites over the finished background line
      # and copy the line into the frame display.
      if @sprites.active?
        @sprites.composite(@sequencer.colors, @sequencer.fg)
        @sequencer.apply_border
      end
      base = @rasterline * @width
      colors = @sequencer.colors
      return if @display[base, @width] == colors

      @display[base, @width] = colors
      @dirty_lines[@rasterline] = true
    end

    def video_matrix(index)
      vic_bank.peek(@registers.screen_base + index)
    end

    def check_raster_irq!
      return unless @rasterline == @registers.raster_target

      # Latch the raster IRQ flag. The line asserts via #interrupted? when the
      # matching mask bit in $D01A is set.
      @registers.latch_raster_irq!
    end

    def irq_status
      (@registers[0x19] & 0x0f) | 0x70 | (interrupted? ? 0x80 : 0)
    end

    def fetch_character_data!
      vmli = @column - 15
      vc = (@display_state.vc_base + vmli) & 0x3ff
      @character_buffer[vmli] = video_matrix(vc)
      @color_buffer[vmli] = vic_bank.peek_color(vc)
    end
  end
end
