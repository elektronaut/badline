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

    LIGHTPEN_IRQ = 0x08 # $D019 latch bit

    # Columns carrying a per-cycle hook, so an ordinary column costs one
    # array read instead of the dispatch.
    HOOK_COLUMNS = Array.new(63) do |column|
      [14, 15, 54, 55, 57, 62].include?(column)
    end.freeze

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
      @lp_triggered = false
      @lp_low = false

      super()
    end

    def cycle!
      start_line! if @column.zero?

      @display_state.cycle(@rasterline, @column)

      # The g-access runs a phase ahead of the c-access, so the column
      # reads the cell the previous one fetched.
      draw!

      fetch_character_data! if dma_active?

      column_hooks if HOOK_COLUMNS[@column]

      @column += 1
      if @column == @columns_per_line
        finish_line!
        @column = 0
        @rasterline = @rasterline == @last_line ? 0 : @rasterline + 1
        check_raster_irq! unless @rasterline.zero?
      end
      nil
    end

    # The sprite and border hooks that fall on named cycles, in Bauer's
    # numbering (VIC column + 1). Guarded in #cycle! so an ordinary column
    # pays two compares rather than the dispatch.
    def column_hooks
      case @column
      when 14 then @sprites.advance_mcbase
      when 15 then @sprites.finish_mcbase
      when 54 then toggle_and_check_sprite_dma
      when 55 then check_sprite_dma
      when 57 then @sprites.check_display(@rasterline)
      when 62 then @sequencer.check_vertical_border(@rasterline)
      end
    end

    # The IRQ line is held asserted while any enabled latch bit is set in
    # $D019/$D01A, until the program acknowledges it by writing to $D019.
    def interrupted?
      @registers.irq_line?
    end

    def peek(addr)
      i = index(addr) % (2**6)
      case i
      when 0x11 then (@registers[0x11] & 0x7f) | ((rasterline & 0x100) >> 1)
      when 0x12 then rasterline & 0xff
      when 0x19 then irq_status # Latch + master IRQ bit, unused bits read 1
      else @registers.read(i)
      end
    end

    def poke(addr, value)
      reg = index(addr) % (2**6)
      log_register_change(reg, value)
      @registers.write(reg, value)
    end

    def position
      (@rasterline * @width) + (@column * 8)
    end

    def dma_active?
      @display_state.fetching?(@column)
    end

    def ba_low?
      return true if @sprite_ba[@column]

      @display_state.bad_line? && @column >= 13 && @column < 56
    end

    # Light pen input level (CIA1 PB4). A falling edge triggers the latch.
    def lightpen_level(high)
      @lp_low = !high
      trigger_lightpen if @lp_low
    end

    # The first trigger per frame latches the beam position into LPX/LPY and
    # raises the LP IRQ. The latch happens one cycle after the edge, with the
    # 6569's two extra half-pixels; a trigger on the last line is consumed
    # without latching unless it lands on the line's first cycle.
    def trigger_lightpen
      return if @lp_triggered

      @lp_triggered = true
      column = @column + 1
      line = @rasterline
      if column == @columns_per_line
        column = 0
        line = line == @last_line ? 0 : line + 1
      end
      return if line == @last_line && column.positive?

      vic_x = ((column * 8) - Sprite::X_OFFSET) % @width
      latch_lightpen((vic_x >> 1) + 2, line)
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

    # Mid-line writes to the color and sprite registers are logged against
    # the cycle after the write (the CPU runs after the VIC within a machine
    # cycle, so @column already points there); each register adds its own
    # pixel delay on top.
    def log_register_change(reg, value)
      old = @registers[reg]
      return if old == value

      if (0x20..0x24).cover?(reg)
        @sequencer.color_patches.log(reg, old, value, @column * 8) unless blanking?
      else
        @sprites.log_change(reg, old, value, @column * 8)
      end
    end

    def check_sprite_dma
      rebuild_sprite_ba if @sprites.check_dma(@rasterline)
    end

    def toggle_and_check_sprite_dma
      @sprites.toggle_expansion
      check_sprite_dma
    end

    # The trigger re-arms at the start of each frame; if the pen line is
    # still low, the latch retriggers immediately with a fixed LPX of $d1.
    def start_lightpen_frame
      @lp_triggered = false
      return unless @lp_low

      @lp_triggered = true
      latch_lightpen(0xd1, 0)
    end

    def latch_lightpen(lpx, line)
      @registers.write(0x13, lpx & 0xff)
      @registers.write(0x14, line & 0xff)
      @registers.latch_irq!(LIGHTPEN_IRQ)
    end

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

      vmli = @display_state.vmli
      @sequencer.emit(@character_buffer[vmli] || 0, @color_buffer[vmli] || 1,
                      col, @display_state.vc, @display_state.rc)
      @display_state.graphics_access if col >= 0 && col < DisplayState::COLUMNS_PER_ROW
    end

    def finish_line!
      return if vblank?

      @sequencer.apply_color_patches

      # Composite the active sprites over the finished background line
      # and copy the line into the frame display.
      if @sprites.active?
        @sequencer.snapshot_line
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

    def start_line!
      if @rasterline.zero?
        @display_state.new_frame
        start_lightpen_frame
        # The line 0 raster compare happens one cycle later than on all
        # other lines (Bauer 3.12).
        check_raster_irq!
      end
      @sequencer.new_line(@rasterline)
      @sprites.start_line
      rebuild_sprite_ba
      @display_state.new_line(@rasterline)
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

    # A c-access that falls between BA and AEC reads a bus the CPU still
    # drives, so the video matrix byte comes back as $ff.
    def fetch_character_data!
      vmli = @display_state.vmli
      vc = @display_state.vc
      @character_buffer[vmli] =
        @display_state.bus_taken?(@column) ? video_matrix(vc) : 0xff
      @color_buffer[vmli] = vic_bank.peek_color(vc)
    end
  end
end
