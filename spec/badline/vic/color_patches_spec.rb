# frozen_string_literal: true

require "spec_helper"

# A color register written mid-line takes hold one pixel into the column the
# VIC emits next, but that emit paints the whole column. ColorPatches puts
# the boundary pixel back. Pinned by greydot, which is a single pixel wide.
RSpec.describe Badline::VIC::ColorPatches do
  subject(:patches) { sequencer.color_patches }

  let(:registers) { Badline::VIC::Registers.new }
  let(:bank) { Badline::VIC::Bank.new }
  let(:sequencer) { Badline::VIC::Sequencer.new(504, registers, bank) }
  let(:boundary) { (20 + 16) * 8 } # the first pixel of display column 20

  before do
    registers.write(0x20, 2) # border
    registers.write(0x21, 6) # background
    registers.write(0x16, 0xc8) # CSEL=40
    bank.address_bus.ram.poke(0, 0) # character 0, all background bits
    sequencer.new_line(51)
  end

  def paint(columns)
    columns.each { |col| sequencer.emit(0, 1, col, col, 0) }
  end

  describe "a background write inside the display window" do
    before do
      paint(0...20)
      registers.write(0x21, 9)
      patches.log(0x21, 6, 9, boundary)
      paint(20...40)
    end

    it "paints the whole column with the new color" do
      expect(sequencer.colors[boundary, 2]).to eq([9, 9])
    end

    it "hands the boundary pixel back to the old color" do
      sequencer.apply_color_patches
      expect(sequencer.colors[boundary, 2]).to eq([6, 9])
    end
  end

  describe "a border write" do
    before do
      paint(0...40)
      registers.write(0x20, 3)
      patches.log(0x20, 2, 3, 8)
      sequencer.colors[8] = 3
    end

    it "hands the boundary pixel back to the old border color" do
      sequencer.apply_color_patches
      expect(sequencer.colors[7, 3]).to all(eq(2))
    end
  end

  describe "a background write over a foreground pixel" do
    before do
      bank.address_bus.ram.poke(0, 0xff) # character 0, all foreground bits
      paint(0...20)
      registers.write(0x21, 9)
      patches.log(0x21, 6, 9, boundary)
      paint(20...40)
    end

    it "leaves it alone" do
      sequencer.apply_color_patches
      expect(sequencer.colors[boundary]).to eq(1)
    end
  end
end
