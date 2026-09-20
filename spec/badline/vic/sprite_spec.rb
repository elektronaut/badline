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

  # The Y match at line 60 turns DMA on (cycles 55/56) and display on
  # (cycle 58). The first row renders on line 61.
  def start_display
    sprite.check_dma(60)
    sprite.check_display(60)
    sprite.start_line
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
      sprite.check_dma(59)
      expect(sprite).not_to be_displaying
    end

    it "starts displaying on the rasterline matching Y" do
      sprite.check_dma(60)
      expect(sprite).to be_displaying
    end

    it "shows no pixels on the matching line itself" do
      sprite.start_line
      sprite.check_dma(60)
      expect(sprite.line_pixels).to be_nil
    end

    it "displays for 21 rasterlines after the matching line" do
      start_display
      20.times { sprite.start_line }
      expect(sprite).to be_displaying
    end

    it "stops displaying after 21 rasterlines" do
      start_display
      21.times { sprite.start_line }
      expect(sprite).not_to be_displaying
    end

    it "keeps the rows invisible when Y no longer matches at cycle 58" do
      sprite.check_dma(60)
      sprite.check_display(61) # Y was moved between the compares
      sprite.start_line
      expect(sprite.line_pixels).to be_nil
    end

    it "does not start when disabled" do
      registers.write(0x15, 0)
      sprite.check_dma(60)
      expect(sprite).not_to be_displaying
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
      sprite.start_line
      expect([row0, sprite.pixel(204)]).to eq([sprite.color, sprite.color])
    end

    it "advances to source row 1 only on the third display line" do
      start_display
      sprite.start_line
      sprite.start_line
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
