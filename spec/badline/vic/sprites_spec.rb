# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::Sprites do
  subject(:sprites) { described_class.new(registers, bank, 504) }

  let(:registers) { Badline::VIC::Registers.new }
  let(:bank) { Badline::VIC::Bank.new }
  let(:ram) { bank.address_bus.ram }
  let(:colors) { Array.new(504, 6) } # background
  let(:fg) { Array.new(504, false) }

  # Place sprite `index` at X 100 (raster X 204), Y 60, with its leftmost pixel
  # set, pointing at data block `ptr`.
  def setup_sprite(index, ptr:, color:, x_pos: 100, priority: false)
    registers.write(0x15, registers[0x15] | (1 << index)) # enable
    registers.write(0x1b, registers[0x1b] | (priority ? (1 << index) : 0))
    registers.write(index * 2, x_pos)
    registers.write((index * 2) + 1, 60)
    registers.write(0x27 + index, color)
    ram.poke(0x03f8 + index, ptr)
    ram.poke(ptr * 64, 0b1000_0000)
  end

  # The Y match at line 60 turns DMA on (cycles 55/56) and display on
  # (cycle 58). The first row renders on line 61.
  def start_display
    sprites.check_dma(60, 53)
    sprites.check_display(60)
    sprites.start_line
  end

  describe "#finish_line" do
    before { setup_sprite(0, ptr: 0x20, color: 5) }

    it "draws the sprite pixel over the background" do
      start_display
      sprites.finish_line(colors, fg)
      expect(colors[204]).to eq(5)
    end

    it "leaves background untouched where the sprite is transparent" do
      start_display
      sprites.finish_line(colors, fg)
      expect(colors[205]).to eq(6)
    end

    it "does nothing when no sprite is displaying" do
      sprites.start_line # before any Y compare has matched
      expect(sprites).not_to be_active
    end
  end

  # Each sprite signal reaches the output on its own path, so a mid-line
  # write shows up a fixed number of pixels later. Pinned by the spritesplit
  # staircases: ss-hires-color/ss-mc-color* fix the color delay, ss-pri* the
  # priority one, and ss-hires-mc/ss-mc-hires/ss-*exp* the sequencer one.
  describe "mid-line write delays" do
    before do
      setup_sprite(0, ptr: 0x20, color: 5)
      registers.write(0x26, 2) # the shared color a %11 pair reads
      3.times { |byte| ram.poke((0x20 * 64) + byte, 0xff) } # a solid row
      start_display
    end

    # The sprite runs from pixel 204 to 227; every write here lands with the
    # beam at 200.
    def write(reg, old, value)
      registers.write(reg, value)
      sprites.log_change(reg, old, value, 200)
      sprites.finish_line(colors, fg)
    end

    it "shows a new sprite color nine pixels on" do
      write(0x27, 5, 9)
      expect(colors[208..209]).to eq([5, 9])
    end

    it "swaps the priority mux fourteen pixels on" do
      fg.fill(true)
      write(0x1b, 0x00, 0x01)
      expect(colors[213..214]).to eq([5, 6])
    end

    # The multicolor flip-flop idles while $d01c is clear, so the pixel the
    # write reaches repeats the last hi-res latch and the pairs start after it.
    it "reaches the sequencer fifteen pixels on" do
      write(0x1c, 0x00, 0x01)
      expect(colors[214..216]).to eq([5, 5, 2])
    end
  end

  describe "X-coordinate wrap" do
    # X 420 -> raster (420 + 104) % 504 = 20, so the sprite shows at the far
    # left of the line rather than running off the right edge.
    it "wraps a high X coordinate around to the left edge" do
      setup_sprite(0, ptr: 0x20, color: 5, x_pos: 420)
      start_display
      sprites.finish_line(colors, fg)
      expect(colors[20]).to eq(5)
    end
  end

  describe "collision across the border region" do
    # Two sprites overlapping at raster X 20 (X coordinate 420), well outside
    # the visible display window, still register a collision.
    it "detects a sprite-sprite collision outside the display window" do
      setup_sprite(0, ptr: 0x20, color: 5, x_pos: 420)
      setup_sprite(1, ptr: 0x21, color: 7, x_pos: 420)
      start_display
      sprites.finish_line(colors, fg)
      expect(registers.read(0x1e)).to eq(0b11)
    end
  end

  describe "sprite/sprite priority" do
    before do
      setup_sprite(0, ptr: 0x20, color: 5)
      setup_sprite(1, ptr: 0x21, color: 7)
      start_display
    end

    it "shows the lower-numbered sprite on top" do
      sprites.finish_line(colors, fg)
      expect(colors[204]).to eq(5)
    end
  end

  describe "sprite/foreground priority ($D01B)" do
    before { fg[204] = true } # background pixel is foreground graphics

    it "draws the sprite over foreground when priority is clear" do
      setup_sprite(0, ptr: 0x20, color: 5, priority: false)
      start_display
      sprites.finish_line(colors, fg)
      expect(colors[204]).to eq(5)
    end

    it "hides the sprite behind foreground when priority is set" do
      setup_sprite(0, ptr: 0x20, color: 5, priority: true)
      start_display
      sprites.finish_line(colors, fg)
      expect(colors[204]).to eq(6)
    end
  end

  describe "sprite/sprite collision ($D01E)" do
    before do
      setup_sprite(0, ptr: 0x20, color: 5)
      setup_sprite(1, ptr: 0x21, color: 7)
      start_display
      sprites.finish_line(colors, fg)
    end

    it "sets a bit per colliding sprite" do
      expect(registers.read(0x1e)).to eq(0b11)
    end

    it "latches the sprite-sprite collision IRQ flag" do
      expect(registers[0x19] & 0x04).to eq(0x04)
    end

    it "clears the register on read" do
      registers.read(0x1e)
      expect(registers.read(0x1e)).to eq(0)
    end

    it "does not collide when only one sprite overlaps a pixel" do
      registers.read(0x1e)       # clear the two-sprite collision above
      registers.write(0x02, 200) # move sprite 1 clear of sprite 0
      start_display
      sprites.finish_line(Array.new(504, 6), fg)
      expect(registers.read(0x1e)).to eq(0)
    end
  end

  # Collisions latch as the beam passes each sprite pixel, so a read of
  # $d01e mid-line sees the pixels drawn before the reading cycle and none
  # of the ones after it. The sprites' only pixel sits at raster X 204.
  # Pinned by the testbench's `sprite-sprite-collision-cycle`.
  describe "#collide_upto" do
    before do
      setup_sprite(0, ptr: 0x20, color: 5)
      setup_sprite(1, ptr: 0x21, color: 7)
      start_display
    end

    it "latches a collision the beam has passed" do
      sprites.collide_upto(205, fg)
      expect(registers.read(0x1e)).to eq(0b11)
    end

    it "leaves a collision the beam has not reached" do
      sprites.collide_upto(204, fg)
      expect(registers.read(0x1e)).to eq(0)
    end

    # A read holds the reset asserted for 12 more pixels, and the pixels
    # drawn under it never reach the register. Pinned by `spritevssprite`,
    # where the 32 pixels between two reads report as 20.
    it "drops the pixels a read's reset still covers" do
      sprites.clear_collision(0x1e, 193) # reset runs through pixel 204
      sprites.finish_line(colors, fg)
      expect(registers.read(0x1e)).to eq(0)
    end

    it "keeps the first pixel past a read's reset" do
      sprites.clear_collision(0x1e, 192) # reset stops one pixel short
      sprites.finish_line(colors, fg)
      expect(registers.read(0x1e)).to eq(0b11)
    end

    # The vertical blank has no line to paint the sprites over, but the
    # comparator still runs. Pinned by `spritey`.
    it "collides on a line with no background to paint over" do
      sprites.finish_line(nil, fg)
      expect(registers.read(0x1e)).to eq(0b11)
    end
  end

  describe "sprite/foreground collision ($D01F)" do
    before do
      setup_sprite(0, ptr: 0x20, color: 5)
      start_display
    end

    it "sets the sprite bit when its pixel overlaps foreground graphics" do
      fg[204] = true
      sprites.finish_line(colors, fg)
      expect(registers.read(0x1f)).to eq(0b1)
    end

    it "does not collide over background pixels" do
      sprites.finish_line(colors, fg)
      expect(registers.read(0x1f)).to eq(0)
    end

    it "latches the sprite-data collision IRQ flag" do
      fg[204] = true
      sprites.finish_line(colors, fg)
      expect(registers[0x19] & 0x02).to eq(0x02)
    end
  end
end
