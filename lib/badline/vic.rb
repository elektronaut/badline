# frozen_string_literal: true

require "badline/vic/bank"
require "badline/vic/registers"
require "badline/vic/display_state"
require "badline/vic/sequencer"
require "badline/vic/sprites"

module Badline
  class VIC
    include Addressable
    include IntegerHelper

    # The 6569 of the breadbin C64, the HMOS 8565 of the C64C, and the
    # C128's VIC-IIe, the 8566 (PAL) and 8564 (NTSC). The VIC-IIe draws as
    # the 8565 and adds the $D02F and $D030 registers.
    MODELS = %i[mos6569 mos8565 mos8566 mos8564].freeze

    # The sixteen colours #display's palette indices stand for, as RGB.
    PALETTE = [
      0x000000, 0xffffff, 0x924a40, 0x84c5cc,
      0x9351b6, 0x72b14b, 0x483aaa, 0xd5df7c,
      0x675200, 0xc33d00, 0xc18178, 0x606060,
      0x8a8a8a, 0xb3ec91, 0x867ade, 0xb3b3b3
    ].freeze

    # The sixteen colours' luminances, out of 32, as Philip Timmermann
    # (Pepto) measured them on the 6569.
    LUMINANCES = [0, 32, 10, 20, 12, 16, 8, 24, 12, 8, 16, 10, 15, 24, 15, 20].freeze

    # The sixteen colours on a green monochrome monitor, which shows only
    # their luminance, as the PET 64's does.
    GREEN_PALETTE = LUMINANCES.map do |luminance|
      green = luminance * 255 / 32
      ((green / 4) << 16) | (green << 8) | (green / 4)
    end.freeze

    attr_reader :display, :width, :height, :vic_bank, :column,
                :rasterline, :dirty_lines, :model, :region

    # The RGB colours #display's palette indices stand for: PALETTE, or
    # GREEN_PALETTE on a monochrome monitor.
    attr_accessor :palette

    # The line of #display the beam draws, which is the raster line unless
    # the VIC-IIe's TEST bit has moved the raster counter on since the
    # last vertical sync (#test_step!).
    attr_reader :output_line

    # The parts a VICE snapshot reads and sets.
    attr_reader :registers, :display_state, :sequencer, :sprites, :character_buffer, :color_buffer,
                :fetch_d011

    # Returns the byte the CPU's halted read would see, for the c-accesses
    # that run before AEC. Without it they read colour RAM.
    attr_writer :open_bus

    LIGHTPEN_IRQ = 0x08 # $D019 latch bit
    COLOR_REGISTERS = 0x20..0x2e

    # What the 8565 shows on the pixel before a color register write takes
    # hold, where the 6569 shows the old color: the grey dot.
    GREY_DOT = 0x0f

    # A g-access reaches the pixel output this many columns after it runs.
    GRAPHICS_DELAY = 2

    # What a column's g-access passed to the sequencer.
    G_BLANK = 0
    G_IDLE = 1
    G_DISPLAY = 2

    # The idle g-access in the column a mid-row bad line opens display
    # state reads here on a 6569.
    DMA_DELAY_IDLE_ADDRESS = 0x38ff

    # The $d011 mode bits a g-access still sees for a cycle after they fall:
    # BMM always, and ECM too when the access it leaves read the character
    # ROM.
    FETCH_HOLD = 0x20
    FETCH_HOLD_ROM = 0x60

    # The hooks a column can carry, as bits: MCBASE, the left border
    # compare with the end of the sprite, the sprite DMA compare, the
    # expansion flip-flop, the sprite display compare, and the start of the
    # vertical border for the line after the last column.
    HOOK_MCBASE = 1
    HOOK_LEFT = 2
    HOOK_DMA = 4
    HOOK_EXPANSION = 8
    HOOK_DISPLAY = 16
    HOOK_LAST = 32

    # The vertical sync starts this many lines into the vertical blank,
    # and lasts VSYNC_LINES.
    VSYNC_DELAY = 3
    VSYNC_LINES = 3

    # On the 6569 the DMA compares fall in columns 53 and 54 and the
    # display compare in column 57. A region whose sprite fetches run later
    # moves them with the fetches (Region::Profile#sprite_cycle).
    DMA_COLUMN = 53
    EXPANSION_COLUMN = 54

    # BA falls three columns ahead of each sprite's pair of s-accesses, and
    # the five-column windows step two columns apart from sprite 0 at column
    # 54 on the 6569, a column later where the fetches are. From sprite 3 on
    # they reach past the end of the line, so each is split: the tail
    # columns fall on the line whose DMA compare started the fetch, the head
    # columns on the line after it.
    SPRITE_BA_FIRST = 54
    SPRITE_BA_LENGTH = 5

    def initialize(debug: false, model: :mos6569, region: Region::PAL)
      raise ArgumentError, "unknown VIC-II model #{model}" unless MODELS.include?(model)

      addressable_at(0xd000, length: 2**10)
      @model = model
      @iie = %i[mos8566 mos8564].include?(model)
      @core = model == :mos6569 ? :mos6569 : :mos8565
      @region = region
      @palette = PALETTE
      @lightpen_extra = @core == :mos8565 ? 1 : 2
      @grey_dots = @core == :mos8565
      @delayed_fetch = @core == :mos8565
      @dma_delay_idle = @core == :mos6569
      @bank_swaps = @core == :mos8565
      @vic_bank = VIC::Bank.new(self)
      @debug = debug

      @columns_per_line = region.cycles_per_line
      @sprite_cycle = region.sprite_cycle
      @sprite_shift = region.sprite_cycle - Region::PAL.sprite_cycle
      @width = @columns_per_line * 8
      @height = region.lines_per_frame
      @last_column = @columns_per_line - 1
      @last_line = @height - 1
      @vsync_line = region.vblank[0] + VSYNC_DELAY
      layout_columns
      @blank_columns = Array.new(@columns_per_line) { |column| Region.blanked?(column, region.hblank) }.freeze
      @blank_lines = Array.new(@height) { |line| Region.blanked?(line, region.vblank) }.freeze
      @display = Array.new(@width * @height, 0)
      @lines = Array.new(@height) { Array.new(@width, 0) }
      @dirty_lines = Array.new(@height, true)
      @render = true

      power_on!
    end

    # The VIC has no reset pin, so only a power cycle brings back the
    # registers, the raster position and the fetch and sprite state it
    # starts with. The display keeps its buffers, cleared to black.
    def power_on!
      @registers = VIC::Registers.new(iie: @iie)
      @register_bytes = @registers.bytes
      @display_state = VIC::DisplayState.new(@registers, @last_column)
      @sequencer = VIC::Sequencer.new(@width, @registers, @vic_bank, model: @core, region: @region)
      @sequencer.render = @render
      @sprites = VIC::Sprites.new(@registers, @vic_bank, @width, model: @core, region: @region)
      @display.fill(0)
      @lines.each { |line| line.fill(0) }
      @dirty_lines.fill(true)

      @column = 0
      @rasterline = 0
      @output_line = 0

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
      @test_wrap = false
    end

    # Everything the VIC holds between cycles: the beam, the fetch and
    # g-access pipeline, the light pen and raster latches, the finished
    # lines, on the VIC-IIe the display line and the TEST bit's wrap, the
    # registers and the display, sequencer and sprite logic.
    # Whether it renders is the host's, and every line comes back dirty so
    # a front end repaints.
    def save_state(out)
      out.marker("VIC")
      out.int(@column).int(@rasterline)
      out.int(@g_tick).ints(@g_kind).int(@g_kept_char).int(@g_kept_color).boolean(@g_display)
      out.int(@fetch_d011).boolean(@lp_triggered).boolean(@lp_low).boolean(@raster_match)
      out.int(@vic_bank.lines)
      out.blob(@character_buffer).blob(@color_buffer).booleans(@sprite_ba)
      @lines.each { |line| out.blob(line) }
      out.int(@output_line).boolean(@test_wrap) if @iie
      @registers.save_state(out)
      @display_state.save_state(out)
      @sequencer.save_state(out)
      @sprites.save_state(out)
    end

    def load_state(input)
      input.marker("VIC")
      load_beam(input)
      load_buffers(input)
      load_lines(input)
      load_test_state(input) if @iie
      @registers.load_state(input)
      @display_state.load_state(input)
      @sequencer.load_state(input)
      @sprites.load_state(input)
    end

    def cycle!
      start_line! if @column.zero?

      # The g-access runs in the first half of the cycle, ahead of the bad
      # line compare, and the c-access in the second half, after it.
      draw!
      dma_delay_idle_access if @display_state.cycle(@rasterline, @column)

      fetch_character_data! if dma_active?

      hooks = @hook_columns[@column]
      column_hooks(hooks) if hooks

      @column += 1
      if @column == @columns_per_line
        finish_line!
        @column = 0
        step_output_line
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
    # #cycle! so an ordinary column pays an array read rather than the
    # dispatch.
    def column_hooks(hooks)
      @sprites.advance_mcbase if hooks.anybits?(HOOK_MCBASE)
      if hooks.anybits?(HOOK_LEFT)
        @sequencer.left_compare_vertical_border
        finish_sprite_mcbase
      end
      check_sprite_dma if hooks.anybits?(HOOK_DMA)
      @sprites.toggle_expansion if hooks.anybits?(HOOK_EXPANSION)
      @sprites.check_display(@rasterline) if hooks.anybits?(HOOK_DISPLAY)
      @sequencer.start_vertical_border(@rasterline == @last_line ? 0 : @rasterline + 1) if hooks.anybits?(HOOK_LAST)
    end

    # The IRQ line is held asserted while any enabled latch bit is set in
    # $D019/$D01A, until the program acknowledges it by writing to $D019.
    def interrupted?
      @registers.irq_line?
    end

    # The VIC-IIe's $D02F lines K0-K2 and $D030 bits, for the machine to
    # read. The 6569 and 8565 give 7, false and false.
    def extra_keyboard_lines = @registers.extra_keyboard_lines
    def fast? = @registers.fast?
    def test? = @registers.test?

    # $D030's FAST and TEST bits as bits 0 and 1, which the C128 reads once
    # a cycle.
    def clock_bits = @registers.clock_bits

    # Whether the cycle just run was one of the five refresh cycles, Bauer's
    # 11-15, whose phi1 half the VIC keeps in the VIC-IIe's FAST mode.
    # @column has already advanced, so it is the Bauer cycle less one.
    def refresh_cycle? = @column.between?(10, 14)

    # In the VIC-IIe's FAST mode the 8502 drives the bus in both halves of
    # the cycle, and the VIC's accesses in the cycle just run latched what
    # it put there. The g-access, or the idle access, took the byte of
    # phi1. A c-access took the byte of phi2 as one made before AEC does
    # (#fetch_character_data!): $ff for the video matrix, unless the CPU
    # was reading or writing the VIC's own registers, and the byte's low
    # nibble for colour. AEC can't follow BA down while the CPU runs at
    # 2 MHz, so on a bad line it falls three cycles after FAST mode ends.
    def take_cpu_bus(phi1, phi2, register_access)
      slot = @g_tick
      @g_data[slot] = phi1 unless @g_kind[slot] == G_BLANK
      display_state = @display_state
      display_state.keep_bus(@column)
      return unless display_state.fetching?(@column.zero? ? @last_column : @column - 1)

      vmli = display_state.vmli
      @character_buffer[vmli] = register_access ? phi2 : 0xff
      @color_buffer[vmli] = phi2 & 0x0f
    end

    # The VIC-IIe's TEST bit clocks the raster counter in every cycle, and
    # the C128 calls this ahead of each cycle the bit is set in. The line's
    # last cycle, whose own step it falls in with, adds nothing more. The
    # counter takes two steps from the frame's last line to line 0, as line
    # 0 reads the last line for its first cycle.
    def test_step!
      return if @column == @last_column

      if @rasterline == @last_line
        @test_wrap = !@test_wrap
        return if @test_wrap

        @rasterline = 0
        @display_state.new_frame
      else
        @test_wrap = false
        @rasterline += 1
      end
      @display_state.raster_step(@rasterline)
      check_raster_irq!
    end

    def peek(addr)
      i = offset_of(addr) % (2**6)
      case i
      when 0x11 then (@registers[0x11] & 0x7f) | ((raster_counter & 0x100) >> 1)
      when 0x12 then raster_counter & 0xff
      when 0x19 then irq_status # Latch + master IRQ bit, unused bits read 1
      when 0x1e, 0x1f then read_collision(i)
      else @registers.read(i)
      end.tap { |value| @sprites.bus_data(@column, value) }
    end

    # The register file as stored, read without a bus access's side effects.
    def register_file = Array.new(0x40) { |reg| @registers[reg] }

    def poke(addr, value)
      reg = offset_of(addr) % (2**6)
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

    # Whether this is the first cycle of sprite 0's BA window on the line
    # whose raster matches its Y, where the sprite's DMA starts. An REU
    # that moved a byte on the cycle before doesn't see BA fall here. Pinned by
    # REU/bonzai/spritetiming.
    def reu_ba_late?
      @column == SPRITE_BA_FIRST + @sprite_shift && sprite_zero_starting?
    end

    # Whether BA passes straight from a bad line's window to sprite 0's on
    # this cycle, the first of sprite 0's. An REU sees the bad line's DMA
    # end here. Pinned by REU/reutiming2/e4-m2 and e6-m2.
    def reu_ba_handed_on?
      @column == DisplayState::DMA_LAST + 2 && @sprite_ba[@column] && @display_state.bad_line_condition?
    end

    # Light pen input level (CIA1 PB4). A falling edge triggers the latch.
    def lightpen_level(high)
      @lp_low = !high
      trigger_lightpen if @lp_low
    end

    # The first trigger per frame latches the beam position into LPX/LPY and
    # raises the LP IRQ. The latch happens one cycle after the edge, with
    # the model's extra half-pixels, two on the 6569 and one on the 8565; a
    # trigger on the last line is consumed without latching unless it lands
    # on the line's first cycle.
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

      vic_x = Sprite::Timing.xpos(column * 8, @width, @region.x_hold)
      latch_lightpen((vic_x >> 1) + @lightpen_extra, line)
    end

    # The byte the VIC fetched in the phi1 half of the cycle the CPU is
    # running, worked out from the VIC's state. The CPU cycle after column
    # c is Bauer cycle c + 2, and each Bauer cycle has a fixed access (VICE
    # `cycle_phi1_fetch`).
    def phi1_data
      vic_bank.peek(phi1_address)
    end

    def hblank? = @blank_columns[@column]
    def vblank? = @blank_lines[@rasterline]
    def blanking? = @blank_lines[@rasterline] || @blank_columns[@column]

    def render? = @render

    # Whether finished lines are painted into #display. A headless run that
    # only reads the machine's state can turn it off: the sprite
    # collisions, lightpen and every register still behave the same, but
    # #display keeps the last lines painted. Turned back on, it is whole
    # again from the start of the next frame.
    def render=(on)
      @render = on
      @sequencer.render = on
    end

    # Puts the beam at the start of `line`.
    def restore_line(line)
      @rasterline = @output_line = line
      @column = 0
    end

    # The latches a VICE snapshot holds: the raster match, the light pen's
    # line held low and its trigger, as bits 0, 1 and 2.
    def latch_bits = (@raster_match ? 1 : 0) | (@lp_low ? 2 : 0) | (@lp_triggered ? 4 : 0)

    # Sets the latches from latch_bits, and the $D011 the next g-access
    # holds.
    def restore_latches(bits, fetch_d011)
      @raster_match = bits.anybits?(1)
      @lp_low = bits.anybits?(2)
      @lp_triggered = bits.anybits?(4)
      @fetch_d011 = fetch_d011
    end

    # Marks the columns BA is low for the sprites whose DMA runs.
    def rebuild_sprite_ba
      @sprite_ba.fill(false)
      8.times do |n|
        next unless @sprites[n].displaying?

        @sprite_ba_tail[n].each { |c| @sprite_ba[c] = true }
        @sprite_ba_head[n].each { |c| @sprite_ba[c] = true }
      end
    end

    # Reset the dirty flags once the frontend has consumed them.
    def clear_dirty_lines!
      @dirty_lines.fill(false)
    end

    private

    def load_beam(input)
      @column = input.int
      @rasterline = @output_line = input.int
      if input.schema < 9
        input.int
        input.boolean?
      end
      @g_tick = input.int
      input.ints_into(@g_kind)
      @g_kept_char = input.int
      @g_kept_color = input.int
      @g_display = input.boolean?
      @fetch_d011 = input.int
      @lp_triggered = input.boolean?
      @lp_low = input.boolean?
      @raster_match = input.boolean?
      @vic_bank.lines = input.int
    end

    def load_buffers(input)
      input.blob_into(@character_buffer)
      input.blob_into(@color_buffer)
      input.booleans_into(@sprite_ba)
    end

    # The VIC-IIe's display line and TEST wrap, which only its TEST bit
    # moves off the raster line.
    def load_test_state(input)
      @output_line = input.int
      @test_wrap = input.boolean?
    end

    # The display is the finished lines one after another.
    def load_lines(input)
      @lines.each_with_index do |line, number|
        input.blob_into(line)
        @display[number * @width, @width] = line
      end
      @dirty_lines.fill(true)
    end

    # The raster counter as $D011/$D012 read it. Every line advances on the
    # CPU cycle paired with column 62 except line 0, which the counter
    # reaches a cycle later, together with the line 0 raster compare.
    def raster_counter
      @column.zero? && @rasterline.zero? ? @last_line : @rasterline
    end

    # Mid-line writes to the color and sprite registers are logged against
    # the cycle after the write (the CPU runs after the VIC within a machine
    # cycle, so @column already points there); each register adds its own
    # pixel delay on top. On the 8565 a color register write that leaves
    # the value as it was still shows its grey dot.
    def log_register_change(reg, value)
      old = @registers[reg]
      return if old == value && !grey_dot?(reg)

      if (0x20..0x24).cover?(reg)
        @sequencer.colors_changed! unless reg == 0x20
        @sequencer.color_patches.log(reg, old, value, @column * 8) if @render && !blanking?
      else
        log_sprite_change(reg, old, value)
      end
    end

    def grey_dot?(reg) = @grey_dots && COLOR_REGISTERS.cover?(reg)

    # A sprite color shows its grey dot as a write of light grey on the
    # pixel before the new color.
    def log_sprite_change(reg, old, value)
      beam_x = @column * 8
      @sprites.log_change(reg, old, GREY_DOT, beam_x - 1) if grey_dot?(reg)
      @sprites.log_change(reg, old, value, beam_x)
    end

    # On the 6569 Bauer cycles 1-10 and 58-63 are sprite p- and s-accesses,
    # 11-15 refresh, 16-55 g-accesses and 56-57 idle. Where the sprite
    # fetches start later, the idle cycles before them grow, and on the
    # 6567R8 cycle 10 idles too. @column has already advanced, so it is the
    # Bauer cycle less one.
    def phi1_address
      cycle = @column + 1
      slot = (cycle - @sprite_cycle) % @columns_per_line
      if slot < 16
        sprite_phi1_address(slot)
      elsif cycle.between?(11, 15)
        0x3f00 | ((0xff - (5 * @rasterline) - (cycle - 11)) & 0xff)
      elsif cycle.between?(16, 55)
        graphics_phi1_address
      else
        0x3fff
      end
    end

    # Each sprite takes two cycles from sprite 0's, the p-access and then
    # the middle s-access.
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

    # A $d011/$d012 write is compared in the next column. A write in the
    # line's second last column is left to its last, which compares the
    # next line.
    def compare_raster_writes(reg)
      return unless (0x11..0x12).cover?(reg)
      return if @column == @last_column

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

    def sprite_zero_starting?
      @registers[0x15].anybits?(0x01) && @registers[0x01] == (@rasterline & 0xff)
    end

    # Splits the sprite BA windows at the end of the line and marks the hook
    # columns, for a line of the region's length: 14, 15, 53, 54 and 57, and
    # the line's last column, which starts the vertical border for the line
    # after it. The marks let an ordinary column cost one array read instead
    # of the dispatch.
    def layout_columns
      last = @last_column
      windows = Array.new(8) do |n|
        first = SPRITE_BA_FIRST + @sprite_shift + (2 * n)
        first...(first + SPRITE_BA_LENGTH)
      end
      @sprite_ba_tail = windows.map { |w| w.select { |c| c <= last } }.freeze
      @sprite_ba_head = windows.map { |w| w.filter_map { |c| c - last - 1 if c > last } }.freeze
      @hook_columns = layout_hooks.map { |hooks| hooks unless hooks.zero? }.freeze
    end

    def layout_hooks
      hooks = Array.new(@columns_per_line, 0)
      hooks[14] |= HOOK_MCBASE
      hooks[15] |= HOOK_LEFT
      hooks[DMA_COLUMN + @sprite_shift] |= HOOK_DMA
      hooks[DMA_COLUMN + @sprite_shift + 1] |= HOOK_DMA
      hooks[EXPANSION_COLUMN] |= HOOK_EXPANSION
      hooks[@region.sprite_display_cycle - 1] |= HOOK_DISPLAY
      hooks[@last_column] |= HOOK_LAST
      hooks
    end

    # Runs this column's g-access and draws the one from GRAPHICS_DELAY
    # columns earlier. The access reads its byte now, through the mode,
    # $d018 and bank of this cycle. A column with no g-access, or one made
    # while the vertical border flip-flop is set, latches nothing: it passes
    # on zero data with the screen byte and colour the last g-access
    # latched, which an idle g-access clears.
    def draw!
      @vic_bank.sample_lines if @bank_swaps
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

    # On the 6569 a bad line that opens display state mid-row (DMA delay)
    # moves the idle g-access of the column that triggers it from $3fff (or
    # $39ff) to DMA_DELAY_IDLE_ADDRESS, unless YSCROLL is 0 (vsp-tester,
    # colorfetchbug/main).
    def dma_delay_idle_access
      slot = @g_tick
      return unless @dma_delay_idle && @g_kind[slot] == G_IDLE
      return if @registers.yscroll.zero?

      @g_data[slot] = vic_bank.peek(DMA_DELAY_IDLE_ADDRESS)
    end

    # The 6569's g-access sees a mode bit that falls a cycle late: it
    # addresses with $d011 as this column has it, OR-ed with the held bits
    # the column before had. When BMM changes and the access moves from RAM
    # onto the character ROM, the low address byte still comes from the old
    # mode. The 8565's addresses with $d011 as the column before had it
    # (VICE x64sc `vicii_fetch_graphics`).
    def fetch_graphics(vmli, counter)
      d011 = @register_bytes[0x11]
      last = @fetch_d011
      return vic_bank.peek(graphics_address(d011, vmli, counter)) if d011 == last
      return vic_bank.peek(graphics_address(last, vmli, counter)) if @delayed_fetch

      from = graphics_address(last, vmli, counter)
      from_rom = vic_bank.character_rom?(from)
      address = graphics_address(d011 | (last & (from_rom ? FETCH_HOLD_ROM : FETCH_HOLD)), vmli, counter)
      if (d011 ^ last).anybits?(0x20) && !from_rom
        to = graphics_address(d011, vmli, counter)
        address = (from & 0xff) | (to & 0x3f00) if vic_bank.character_rom?(to)
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
      return finish_blank_line if vblank? || !@render

      composite = @sprites.active?
      @sequencer.apply_color_patches
      @sequencer.snapshot_line if composite
      @sprites.finish_line(composite ? @sequencer.colors : nil, @sequencer.fg)
      @sequencer.apply_border if composite

      colors = @sequencer.colors
      output_line = @output_line
      line = @lines[output_line]
      return if line == colors

      line[0, @width] = colors
      @display[output_line * @width, @width] = colors
      @dirty_lines[output_line] = true
    end

    # A blanked line paints nothing, and is never shown unless the TEST
    # bit has moved the beam off the raster line, where it shows black.
    def finish_blank_line
      @sprites.finish_line(nil, @sequencer.fg)
      return if @output_line == @rasterline || !@render

      line = @output_line
      @lines[line].fill(0)
      @display.fill(0, line * @width, @width)
      @dirty_lines[line] = true
    end

    # The display line the beam draws next follows the one before it, and
    # a line that ends in the vertical sync puts it back on the raster
    # line. Only the VIC-IIe's TEST bit moves the raster counter on between
    # the two, so the lines it skips shift the picture up until the next
    # sync.
    def step_output_line
      @output_line = if @rasterline.between?(@vsync_line, @vsync_line + VSYNC_LINES - 1)
                       @rasterline + 1
                     else
                       @output_line == @last_line ? 0 : @output_line + 1
                     end
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
