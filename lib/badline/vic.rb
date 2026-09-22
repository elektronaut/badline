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

    # Returns the byte the CPU's halted read would see, for the c-accesses
    # that run before AEC. Without it they read colour RAM.
    attr_writer :open_bus

    LIGHTPEN_IRQ = 0x08 # $D019 latch bit

    # A g-access reaches the pixel output this many columns after it runs.
    GRAPHICS_DELAY = 2

    # Columns carrying a per-cycle hook, so an ordinary column costs one
    # array read instead of the dispatch.
    HOOK_COLUMNS = Array.new(63) do |column|
      [14, 15, 53, 54, 57, 62].include?(column)
    end.freeze

    # BA falls three columns ahead of each sprite's pair of s-accesses, and
    # the five-column windows step two columns apart from sprite 0 at column
    # 54. From sprite 3 on they reach past the end of the line, so each is
    # split: the tail columns fall on the line whose cycle 55/56 compare
    # started the fetch, the head columns on the line after it.
    SPRITE_BA_WINDOWS = Array.new(8) { |n| (54 + (2 * n))..(58 + (2 * n)) }.freeze
    SPRITE_BA_TAIL = SPRITE_BA_WINDOWS.map { |w| w.select { |c| c < 63 } }.freeze
    SPRITE_BA_HEAD = SPRITE_BA_WINDOWS.map { |w| w.filter_map { |c| c - 63 if c >= 63 } }.freeze

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
      @g_tick = 0
      @g_display = Array.new(4, false)
      @g_char = Array.new(4, 0)
      @g_color = Array.new(4, 1)
      @g_vc = Array.new(4, 0)
      @g_rc = Array.new(4, 0)
      @lp_triggered = false
      @lp_low = false

      super()
    end

    def cycle!
      start_line! if @column.zero?

      # The g-access runs in the first half of the cycle, ahead of the bad
      # line compare, and the c-access in the second half, after it.
      draw!
      @display_state.cycle(@rasterline, @column)

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

    # The sprite and border hooks that fall on named cycles, one column
    # ahead of Bauer's numbering — two for the DMA compares, which the
    # `spriteenable` references place a column earlier still. Guarded in
    # #cycle! so an ordinary column pays two compares rather than the
    # dispatch.
    def column_hooks
      case @column
      when 14 then @sprites.advance_mcbase
      when 15 then @sprites.finish_mcbase
      when 53 then toggle_and_check_sprite_dma
      when 54 then check_sprite_dma
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
      when 0x1e, 0x1f then read_collision(i)
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

    # Asked once the VIC has advanced, so @column is one ahead of the cycle
    # the CPU is about to run. A bad line holds BA on the condition as it
    # stands rather than the latched match.
    def ba_low?
      return true if @sprite_ba[@column]

      @display_state.bad_line_condition? &&
        @column > DisplayState::DMA_FIRST && @column <= DisplayState::DMA_LAST + 1
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
      rebuild_sprite_ba if @sprites.check_dma(@rasterline, @column)
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
      8.times do |n|
        next unless @sprites[n].displaying?

        SPRITE_BA_TAIL[n].each { |c| @sprite_ba[c] = true }
        SPRITE_BA_HEAD[n].each { |c| @sprite_ba[c] = true }
      end
    end

    # Runs this column's g-access and draws the one from GRAPHICS_DELAY
    # columns earlier.
    def draw!
      slot = @g_tick = (@g_tick + 1) & 3
      display_state = @display_state
      if (@g_display[slot] = display_state.display?)
        vmli = display_state.vmli
        @g_char[slot] = @character_buffer[vmli] || 0
        @g_color[slot] = @color_buffer[vmli] || 1
        @g_vc[slot] = display_state.vc
        @g_rc[slot] = display_state.rc
        display_state.graphics_access(@column)
      end
      return if blanking?

      slot = (slot - GRAPHICS_DELAY) & 3
      col = @column - 16
      if @g_display[slot]
        @sequencer.emit(@g_char[slot], @g_color[slot], col, @g_vc[slot], @g_rc[slot])
      else
        @sequencer.emit_idle(col)
      end
    end

    # Fold the rest of the line's sprite collisions in — they latch whether
    # or not there is a line to draw — then composite the active sprites
    # over the finished background and copy the line into the frame display.
    def finish_line!
      render = !vblank? && @sprites.active?
      @sequencer.apply_color_patches unless vblank?
      @sequencer.snapshot_line if render
      @sprites.finish_line(render ? @sequencer.colors : nil, @sequencer.fg)
      @sequencer.apply_border if render
      return if vblank?

      base = @rasterline * @width
      colors = @sequencer.colors
      return if @display[base, @width] == colors

      @display[base, @width] = colors
      @dirty_lines[@rasterline] = true
    end

    def video_matrix(index)
      vic_bank.peek_phi2(@registers.screen_base + index)
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

    # A collision register carries the pixels drawn up to the cycle before
    # the read — the VIC runs ahead of the CPU within a machine cycle, so
    # the column the read lands on has not latched yet — and the reset the
    # read asserts outlives it, swallowing the pixels drawn under it.
    def read_collision(reg)
      beam_x = @column * 8
      @sprites.collide_upto(beam_x, @sequencer.fg)
      @registers.read(reg).tap { @sprites.clear_collision(reg, beam_x) }
    end

    def irq_status
      (@registers[0x19] & 0x0f) | 0x70 | (interrupted? ? 0x80 : 0)
    end

    # A c-access that falls between BA and AEC reads a bus the CPU still
    # drives: the video matrix byte comes back as $ff, and the colour
    # nibble is the low nibble of the byte at the halted CPU's PC.
    def fetch_character_data!
      vmli = @display_state.vmli
      vc = @display_state.vc
      if @display_state.bus_taken?(@column)
        @character_buffer[vmli] = video_matrix(vc)
        @color_buffer[vmli] = vic_bank.peek_color(vc)
      else
        @character_buffer[vmli] = 0xff
        @color_buffer[vmli] = @open_bus ? @open_bus.call & 0x0f : vic_bank.peek_color(vc)
      end
    end
  end
end
