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

    # What a column's g-access passed to the sequencer.
    G_BLANK = 0
    G_IDLE = 1
    G_DISPLAY = 2

    # The $d011 mode bits a g-access still sees for a cycle after they fall.
    FETCH_HOLD = 0x20

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
      @register_bytes = @registers.bytes
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
      @g_kind = Array.new(4, G_BLANK)
      @g_kept_char = 0
      @g_kept_color = 0
      @g_data = @sequencer.ring_data
      @g_char = @sequencer.ring_char
      @g_color = @sequencer.ring_color
      @g_display = false
      @fetch_d011 = @register_bytes[0x11]
      @lp_triggered = false
      @lp_low = false
      @raster_match = false

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
        check_raster_irq!(@rasterline.zero? ? @last_line : @rasterline)
      end
      watch_collisions
      nil
    end

    # The sprite and border hooks that fall on named cycles, one column
    # ahead of Bauer's numbering — two for MCBASE, the DMA compares and the
    # expansion flip-flop, which the `spriteenable` and `spritecrunch`
    # references place a column earlier still. Guarded in
    # #cycle! so an ordinary column pays two compares rather than the
    # dispatch.
    def column_hooks
      case @column
      when 14 then @sprites.advance_mcbase
      when 15
        @sequencer.left_compare_vertical_border
        finish_sprite_mcbase
      when 53 then check_sprite_dma
      when 54 then check_dma_and_toggle_expansion
      when 57 then @sprites.check_display(@rasterline)
      when 62 then @sequencer.start_vertical_border(@rasterline == @last_line ? 0 : @rasterline + 1)
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
      when 0x11 then (@registers[0x11] & 0x7f) | ((raster_counter & 0x100) >> 1)
      when 0x12 then raster_counter & 0xff
      when 0x19 then irq_status # Latch + master IRQ bit, unused bits read 1
      when 0x1e, 0x1f then read_collision(i)
      else @registers.read(i)
      end.tap { |value| @sprites.bus_data(@column, value) }
    end

    def poke(addr, value)
      reg = index(addr) % (2**6)
      @sprites.bus_data(@column, value)
      log_register_change(reg, value)
      @registers.write(reg, value)
      compare_raster_writes(reg)
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

    # The byte the VIC fetched in the phi1 half of the cycle the CPU is
    # running, worked out from the VIC's state. The CPU cycle after column
    # c is Bauer cycle c + 2, and each Bauer cycle has a fixed access (VICE
    # `cycle_phi1_fetch`).
    def phi1_data
      vic_bank.peek(phi1_address)
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

    # The raster counter as $D011/$D012 read it. Every line advances on the
    # CPU cycle paired with column 62 except line 0, which the counter
    # reaches a cycle later, together with the line 0 raster compare.
    def raster_counter
      @column.zero? && @rasterline.zero? ? @last_line : @rasterline
    end

    # Mid-line writes to the color and sprite registers are logged against
    # the cycle after the write (the CPU runs after the VIC within a machine
    # cycle, so @column already points there); each register adds its own
    # pixel delay on top.
    def log_register_change(reg, value)
      old = @registers[reg]
      return if old == value

      if (0x20..0x24).cover?(reg)
        @sequencer.colors_changed! unless reg == 0x20
        @sequencer.color_patches.log(reg, old, value, @column * 8) unless blanking?
      else
        @sprites.log_change(reg, old, value, @column * 8)
      end
    end

    # Bauer cycles 1-10 and 58-63 are sprite p- and s-accesses, 11-15
    # refresh, 16-55 g-accesses and 56-57 idle. @column has already
    # advanced, so it is the Bauer cycle less one.
    def phi1_address
      cycle = @column + 1
      if cycle < 11 || cycle > 57
        sprite_phi1_address((cycle - 58) % 63)
      elsif cycle < 16
        0x3f00 | ((0xff - (5 * @rasterline) - (cycle - 11)) & 0xff)
      elsif cycle < 56
        graphics_phi1_address
      else
        0x3fff
      end
    end

    # Each sprite takes two cycles from Bauer 58, the p-access and then the
    # middle s-access.
    def sprite_phi1_address(slot)
      n = slot >> 1
      return @registers.screen_base + 0x3f8 + n if slot.even?

      @sprites[n].phi1_address || 0x3fff
    end

    # The g-access of the column just run. In display state it used the
    # VC and VMLI it then stepped past.
    def graphics_phi1_address
      return @registers.ecm.nonzero? ? 0x39ff : 0x3fff unless @g_display

      graphics_address(@registers[0x11], @display_state.vmli - 1, (@display_state.vc - 1) & 0x3ff)
    end

    # A $d011/$d012 write is compared in the next column. A write after
    # column 61 is left to column 62, which compares the next line.
    def compare_raster_writes(reg)
      return unless (0x11..0x12).cover?(reg)
      return if @column == @columns_per_line - 1

      check_raster_irq!
      @sequencer.compare_vertical_border(@rasterline) if reg == 0x11
    end

    def check_sprite_dma
      rebuild_sprite_ba if @sprites.check_dma(@rasterline, @column)
    end

    # A sprite whose DMA ends here fetches nothing at the end of this line,
    # so its BA tail goes too.
    def finish_sprite_mcbase
      @sprites.finish_mcbase
      rebuild_sprite_ba if @sprites.stopped_dma?
    end

    def check_dma_and_toggle_expansion
      check_sprite_dma
      @sprites.toggle_expansion
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
    # columns earlier. The access reads its byte now, through the mode,
    # $d018 and bank of this cycle. A column with no g-access, or one made
    # while the vertical border flip-flop is set, latches nothing: it passes
    # on zero data with the screen byte and colour the last g-access
    # latched, which an idle g-access clears.
    def draw!
      slot = @g_tick = (@g_tick + 1) & 3
      display_state = @display_state
      access = display_state.graphics_column?(@column) && !@sequencer.vertical_closed?
      if access
        latch_graphics(slot, display_state)
      else
        @g_kind[slot] = G_BLANK
        @g_data[slot] = 0
        @g_char[slot] = @g_kept_char
        @g_color[slot] = @g_kept_color
      end
      @g_display = display_state.display?
      display_state.graphics_access(@column) if @g_display
      emit_graphics((slot - GRAPHICS_DELAY) & 3, @column - 16) unless blanking?
      @sequencer.latch_xscroll(@register_bytes[0x16] & 0b111) if access
      @fetch_d011 = @register_bytes[0x11]
    end

    def latch_graphics(slot, display_state)
      unless display_state.display?
        @g_kind[slot] = G_IDLE
        @g_data[slot] = vic_bank.peek(@registers.ecm.zero? ? 0x3fff : 0x39ff)
        @g_char[slot] = @g_color[slot] = @g_kept_char = @g_kept_color = 0
        return
      end

      vmli = display_state.vmli
      @g_kind[slot] = G_DISPLAY
      @g_data[slot] = fetch_graphics(vmli, display_state.vc)
      @g_char[slot] = @g_kept_char = @character_buffer[vmli] || 0
      @g_color[slot] = @g_kept_color = @color_buffer[vmli] || 1
    end

    # The g-access sees a mode bit that falls a cycle late: it addresses
    # with $d011 as this column has it, OR-ed with the bits the column
    # before had. When BMM changes and the access moves from RAM onto the
    # character ROM, the low address byte still comes from the old mode
    # (VICE x64sc `vicii_fetch_graphics`).
    def fetch_graphics(vmli, counter)
      d011 = @register_bytes[0x11]
      last = @fetch_d011
      return vic_bank.peek(graphics_address(d011, vmli, counter)) if d011 == last

      address = graphics_address(d011 | (last & FETCH_HOLD), vmli, counter)
      if (d011 ^ last).anybits?(0x20)
        from = graphics_address(last, vmli, counter)
        to = graphics_address(d011, vmli, counter)
        address = (from & 0xff) | (to & 0x3f00) if !vic_bank.character_rom?(from) && vic_bank.character_rom?(to)
      end
      vic_bank.peek(address)
    end

    def graphics_address(d011, vmli, counter)
      rc = @display_state.rc
      case d011 & 0x60
      when 0x00 then @registers.char_base | ((@character_buffer[vmli] || 0) << 3) | rc
      when 0x20 then @registers.bitmap_base | (counter << 3) | rc
      when 0x40 then (@registers.char_base | ((@character_buffer[vmli] || 0) << 3) | rc) & 0x39ff
      else (@registers.bitmap_base | (counter << 3) | rc) & 0x39ff
      end
    end

    def emit_graphics(slot, col)
      @sequencer.emit(slot, col, @g_kind[slot] == G_DISPLAY)
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

    # The raster compare latches the flag only as the line and the target
    # come to match, so a target moved along with the raster line holds the
    # match without latching again (VICE x64sc). It runs at each line step
    # and after each $d011/$d012 write. The line asserts via #interrupted?
    # when the mask bit in $D01A is set.
    def check_raster_irq!(line = @rasterline)
      match = line == @registers.raster_target
      @registers.latch_raster_irq! if match && !@raster_match
      @raster_match = match
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

    # A collision raises its $D019 bit as the beam crosses the pixel rather
    # than when the line is folded at its end, so while an enabled
    # collision IRQ is still unlatched the fold keeps up with the beam.
    def watch_collisions
      return if (@registers[0x1a] & ~@registers[0x19]).nobits?(0x06)

      @sprites.collide_upto(@column * 8, @sequencer.fg)
    end

    def irq_status
      @sprites.collide_upto(@column * 8, @sequencer.fg)
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
