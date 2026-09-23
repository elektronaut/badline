# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::Sprite do
  subject(:sprite) { described_class.new(0, registers, bank, 504) }

  let(:registers) { Badline::VIC::Registers.new }
  let(:bank) { Badline::VIC::Bank.new }
  let(:ram) { bank.address_bus.ram }

  # $D018 default screen base is $0000, so sprite pointers live at $03f8.
  def point_sprite(index, ptr)
    ram.poke(0x03f8 + index, ptr)
  end

  def put_row(ptr, row, *bytes)
    bytes.each_with_index { |b, i| ram.poke((ptr * 64) + (row * 3) + i, b) }
  end

  before do
    registers.write(0x15, 0x01) # enable sprite 0
    registers.write(0x00, 100)  # X = 100
    registers.write(0x01, 60)   # Y = 60
    point_sprite(0, 0x20)       # data at $0800
  end

  # One rasterline of VIC hooks, in cycle order.
  def raster_line(line)
    sprite.start_line          # cycle 1: last line's fetch renders
    sprite.sequence
    sprite.advance_mcbase      # cycle 16: MCBASE takes MC
    sprite.finish_mcbase       # the end-of-sprite compare
    sprite.check_dma(line, 53) # cycles 55/56, on the first compare
    sprite.toggle_expansion    # cycle 56
    sprite.check_display(line) # cycle 58
  end

  def render?(line)
    raster_line(line)
    sprite.rendering?
  end

  # The Y match at line 60 turns DMA on (cycles 55/56) and display on
  # (cycle 58). The first row renders on line 61.
  def start_display
    raster_line(60)
    raster_line(61)
  end

  # The comparator is eight bits wide, so the PAL lines above 255 match the
  # Y coordinates 0-55 a second time. Pinned by the testbench's `spritey`,
  # whose reference collides on every line of the frame.
  describe "the eight-bit Y compare" do
    it "starts the DMA on the line the coordinate names" do
      raster_line(60)
      expect(render?(61)).to be(true)
    end

    it "starts it again 256 lines on" do
      raster_line(60 + 256)
      expect(render?(60 + 257)).to be(true)
    end

    it "leaves it alone on a line that only matches in nine bits" do
      raster_line(60 + 128)
      expect(render?(60 + 129)).to be(false)
    end
  end

  describe "#x with the 9th bit" do
    it "reads the low byte from $D000" do
      expect(sprite.x).to eq(100)
    end

    it "adds 256 when the MSB in $D010 is set" do
      registers.write(0x10, 0x01)
      expect(sprite.x).to eq(356)
    end
  end

  describe "display state machine" do
    it "is not displaying before the Y coordinate" do
      sprite.check_dma(59, 53)
      expect(sprite).not_to be_displaying
    end

    it "starts displaying on the rasterline matching Y" do
      sprite.check_dma(60, 53)
      expect(sprite).to be_displaying
    end

    it "shows no pixels on the matching line itself" do
      put_row(0x20, 0, 0x80, 0, 0)
      raster_line(60)
      sprite.sequence
      expect(sprite.pixel(204)).to be_nil
    end

    it "renders the 21 rasterlines following the match" do
      raster_line(60)
      expect((61..90).select { |line| render?(line) }).to eq((61..81).to_a)
    end

    it "stops the DMA once MCBASE reaches 63" do
      raster_line(60)
      (61..81).each { |line| raster_line(line) }
      expect(sprite).not_to be_displaying
    end

    # Pinned by spriterestart: only the DMA stops at cycle 16, so a Y match
    # at cycle 55 of the last row's line restarts it under a display that is
    # still on, and cycle 58 has no match to see.
    context "when Y matches only at the compare on the last row's line" do
      before do
        (60..80).each { |line| raster_line(line) }
        sprite.start_line
        sprite.advance_mcbase
        sprite.finish_mcbase
        registers.write(0x01, 81)
        sprite.check_dma(81, 53)
        registers.write(0x01, 60)
        sprite.check_display(81)
        sprite.start_line
      end

      it { is_expected.to be_rendering }
    end

    it "keeps the rows invisible when Y no longer matches at cycle 58" do
      sprite.check_dma(60, 53)
      sprite.check_display(61) # Y was moved between the compares
      raster_line(61)
      expect(sprite).not_to be_rendering
    end

    it "does not start when disabled" do
      registers.write(0x15, 0)
      sprite.check_dma(60, 53)
      expect(sprite).not_to be_displaying
    end

    it "keeps the rows invisible when MxE goes before cycle 58" do
      sprite.check_dma(60, 53)
      registers.write(0x15, 0) # disabled between the compares and cycle 58
      sprite.check_display(60)
      raster_line(61)
      expect(sprite).not_to be_rendering
    end
  end

  describe "the first s-access of a new DMA" do
    # Sprite 0's accesses follow the compares immediately, so a DMA started
    # on the second compare pulls BA a column short of AEC and that access
    # reads back the $ff the CPU is still driving.
    before { put_row(0x20, 0, 0x00, 0x00, 0x00) }

    def first_row(compare_column)
      sprite.check_dma(60, compare_column)
      sprite.check_display(60)
      raster_line(61)
    end

    it "reads $ff when the DMA started on the second compare" do
      first_row(54)
      expect(sprite.pixel(204)).to eq(sprite.color)
    end

    it "reads memory when the DMA started on the first compare" do
      first_row(53)
      expect(sprite.pixel(204)).to be_nil
    end

    it "leaves the two s-accesses behind it alone" do
      first_row(54)
      expect(sprite.pixel(204 + 8)).to be_nil
    end
  end

  # Pinned by the spritecrunch rows and sequencer-bug: MxYE cleared in
  # cycle 15 while the flip-flop is reset steps MCBASE to
  # (0x2a & (MCBASE & MC)) | (0x15 & (MCBASE | MC)), with MC three past
  # MCBASE after the s-accesses. The expected rows are the spritecrunch
  # readme's table.
  describe "sprite crunch" do
    # One line of the sprite, crunched or stepped normally, with $d017 set
    # ahead of cycle 56 when the next line crunches.
    def sprite_line(line, step, next_step)
      sprite.start_line
      sprite.clear_y_expansion(true) if step == :crunch
      registers.write(0x17, 0x00)
      sprite.advance_mcbase
      sprite.finish_mcbase
      registers.write(0x17, next_step == :crunch ? 0x01 : 0x00)
      sprite.check_dma(line, 53)
      sprite.toggle_expansion
      sprite.check_display(line)
    end

    def run_steps(steps)
      registers.write(0x17, steps.first == :crunch ? 0x01 : 0x00)
      raster_line(60)
      steps.each_with_index { |step, i| sprite_line(61 + i, step, steps[i + 1]) }
      sprite.start_line
      sprite.sequence
    end

    {
      [:crunch] => [0x00, 0x01],
      %i[crunch crunch] => [0x01, 0x05],
      %i[normal crunch] => [0x03, 0x07],
      %i[crunch normal crunch] => [0x04, 0x05],
      %i[normal normal crunch] => [0x06, 0x05]
    }.each do |steps, (from, to)|
      it format("steps MCBASE $%<from>02x to $%<to>02x", from:, to:) do
        ram.poke((0x20 * 64) + to, 0x80)
        run_steps(steps)
        expect(sprite.pixel(204)).to eq(sprite.color)
      end
    end

    it "keeps the DMA running when MCBASE steps over 63" do
      run_steps(Array.new(30, :crunch))
      expect(sprite).to be_displaying
    end

    context "when MxYE clears outside cycle 15" do
      before do
        ram.poke((0x20 * 64) + 0x03, 0x80)
        registers.write(0x17, 0x01)
        raster_line(60)
        sprite.clear_y_expansion(false)
        registers.write(0x17, 0x00)
      end

      it "steps MCBASE normally" do
        (61..62).each { |line| raster_line(line) }
        sprite.sequence
        expect(sprite.pixel(204)).to eq(sprite.color)
      end
    end
  end

  describe "mid-line writes" do
    let(:log) { Badline::VIC::RegisterLog.new(registers) }

    before do
      put_row(0x20, 0, 0x55, 0x55, 0x55)
      start_display
    end

    # The multicolor flip-flop idles while $d01c is clear, so the first
    # multicolor pixel shows what the hi-res path last latched — a clear bit
    # here, so transparent — and the pairs only start on the pixel after it.
    # A re-decoded row would put a %01 pair on all three.
    it "holds the hi-res latch over the first multicolor pixel" do
      log.log(204 + 21, 0x1c, 0x00, 0x01)
      log.prepare
      sprite.sequence(log)
      expect(sprite.codes[21, 3]).to eq([0, 1, 1])
    end

    # A sprite whose comparator has already fired keeps its position; one
    # still waiting picks up the new X and starts there instead.
    it "starts at an X written before the comparator reaches it" do
      log.log(150, 0x00, 100, 160)
      log.prepare
      sprite.sequence(log)
      expect(sprite.leftmost).to eq(160 + 104)
    end
  end

  describe "X comparator" do
    before { put_row(0x20, 0, 0b1000_0000, 0, 0) }

    it "matches an X coordinate inside the counter's range" do
      registers.write(0x00, 0xf7)
      registers.write(0x10, 0x01) # X = $1f7, the last value the counter takes
      start_display
      expect(sprite.span).to be_positive
    end

    # The VIC's X counter only runs to $1f7, so the eight coordinates above
    # it never match and the sprite stays dark.
    it "never matches an X coordinate past the counter's range" do
      registers.write(0x00, 0xf8)
      registers.write(0x10, 0x01) # X = $1f8
      start_display
      expect(sprite.span).to be_zero
    end
  end

  # Sprite 0's s-accesses reload its shift register at raster pixel 459.
  # Pinned by the spritescan dump, and by spritegap for the row it brings.
  describe "the reload" do
    before do
      put_row(0x20, 0, 0xff, 0xff, 0xff)
      put_row(0x20, 1, 0x80, 0, 0)
      registers.write(0x10, 0x01)
    end

    def sequence_at(x_pos)
      registers.write(0x00, x_pos - 0x100)
      start_display
      sprite.sequence
    end

    it "cuts a row short there, holding the last pixel for one more" do
      sequence_at(346) # first pixel at 450
      expect(sprite.span).to eq(10)
    end

    it "ignores a match in the twelve pixels from it" do
      sequence_at(361) # first pixel at 465
      expect([sprite.span, sprite.reload_span]).to eq([0, 0])
    end

    it "shows the next line's row from a match after them" do
      put_row(0x20, 0, 0, 0, 0)
      sequence_at(376) # first pixel at 480, on the line showing row 0
      expect(sprite.pixel(480)).to eq(sprite.color)
    end
  end

  describe "#pixel (hi-res)" do
    before do
      put_row(0x20, 0, 0b1000_0001, 0, 0)
      start_display
    end

    # X 100 -> raster X 204; leftmost pixel set, bit 7 (pixel 23) set.
    it "returns the sprite colour for a set bit" do
      expect(sprite.pixel(204)).to eq(sprite.color)
    end

    it "returns nil for a clear bit" do
      expect(sprite.pixel(205)).to be_nil
    end

    it "returns the sprite colour for bit 0 of byte 0 (pixel 7)" do
      expect(sprite.pixel(204 + 7)).to eq(sprite.color)
    end

    it "returns nil to the left of the sprite" do
      expect(sprite.pixel(203)).to be_nil
    end

    it "returns nil past the 24-pixel width" do
      expect(sprite.pixel(204 + 24)).to be_nil
    end
  end

  describe "#pixel (X-expanded)" do
    before do
      registers.write(0x1d, 0x01) # expand sprite 0 horizontally
      put_row(0x20, 0, 0b1000_0000, 0, 0)
      start_display
    end

    it "doubles each pixel, covering 48 raster pixels" do
      aggregate_failures do
        expect(sprite.pixel(204)).to eq(sprite.color)
        expect(sprite.pixel(205)).to eq(sprite.color)
        expect(sprite.pixel(206)).to be_nil
      end
    end
  end

  describe "#pixel (Y-expanded)" do
    before do
      registers.write(0x17, 0x01) # expand sprite 0 vertically
      put_row(0x20, 0, 0b1000_0000, 0, 0)
      put_row(0x20, 1, 0b0100_0000, 0, 0)
    end

    it "shows source row 0 on the first two display lines" do
      start_display
      row0 = sprite.pixel(204)
      raster_line(62)
      expect([row0, sprite.pixel(204)]).to eq([sprite.color, sprite.color])
    end

    it "advances to source row 1 only on the third display line" do
      start_display
      [62, 63].each { |line| raster_line(line) }
      expect(sprite.pixel(205)).to eq(sprite.color)
    end
  end

  describe "#pixel (multicolour)" do
    before do
      registers.write(0x1c, 0x01) # sprite 0 multicolour
      registers.write(0x25, 5)    # multicolour 0
      registers.write(0x26, 7)    # multicolour 1
      registers.write(0x27, 1)    # sprite 0 colour
      put_row(0x20, 0, 0b00_01_10_11, 0, 0)
      start_display
    end

    # Each pair is two raster pixels wide.
    it "maps 00 to transparent" do
      expect(sprite.pixel(204)).to be_nil
    end

    it "maps 01 to multicolour 0" do
      expect(sprite.pixel(206)).to eq(5)
    end

    it "maps 10 to the sprite colour" do
      expect(sprite.pixel(208)).to eq(1)
    end

    it "maps 11 to multicolour 1" do
      expect(sprite.pixel(210)).to eq(7)
    end
  end
end
