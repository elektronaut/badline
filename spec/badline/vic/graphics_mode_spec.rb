# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::GraphicsMode do
  let(:registers) { Badline::VIC::Registers.new }
  let(:bank) { Badline::VIC::Bank.new }
  let(:sequencer) { Badline::VIC::Sequencer.new(504, registers, bank) }

  describe Badline::VIC::GraphicsMode::Text do
    subject(:mode) { described_class.new }

    before { registers.write(0x21, 6) } # background

    it "draws set bits in the cell colour and clear bits in the background" do
      mode.paint(0b1000_0001, 1, 4, sequencer)
      expect(sequencer.cur_colors).to eq([4, 6, 6, 6, 6, 6, 6, 4])
    end

    it "marks set bits as foreground" do
      mode.paint(0b1000_0001, 1, 4, sequencer)
      expect(sequencer.cur_fg)
        .to(eq([true, false, false, false, false, false, false, true]))
    end
  end

  describe Badline::VIC::GraphicsMode::MulticolorText do
    subject(:mode) { described_class.new }

    before do
      registers.write(0x21, 6) # background 0
      registers.write(0x22, 5) # background 1
      registers.write(0x23, 4) # background 2
    end

    context "with a single-colour cell (colour bit 3 clear)" do
      it "decodes as hi-res using the low three colour bits" do
        mode.paint(0b1000_0000, 1, 0x07, sequencer)
        expect(sequencer.cur_colors).to eq([7, 6, 6, 6, 6, 6, 6, 6])
      end

      it "marks the set bit as foreground" do
        mode.paint(0b1000_0000, 1, 0x07, sequencer)
        expect(sequencer.cur_fg.first).to be(true)
      end
    end

    context "with a multicolour cell (colour bit 3 set)" do
      # pairs map 00->bg0(6) 01->bg1(5) 10->bg2(4) 11->colour&7, double-wide.
      it "decodes 2-bit pairs into double-wide pixels" do
        mode.paint(0b00_01_10_11, 1, 0x08 | 0x02, sequencer) # colour low bits = 2
        expect(sequencer.cur_colors).to eq([6, 6, 5, 5, 4, 4, 2, 2])
      end

      it "marks only the high-bit (10/11) pairs as foreground" do
        mode.paint(0b00_01_10_11, 1, 0x08, sequencer)
        expect(sequencer.cur_fg).to eq([false, false, false, false,
                                        true, true, true, true])
      end
    end
  end

  describe Badline::VIC::GraphicsMode::ExtendedBackgroundText do
    subject(:mode) { described_class.new }

    before do
      registers.write(0x21, 6) # background 0
      registers.write(0x22, 5) # background 1
      registers.write(0x23, 4) # background 2
      registers.write(0x24, 3) # background 3
    end

    it "draws set bits in the cell colour" do
      mode.paint(0b1000_0000, 1, 7, sequencer)
      expect(sequencer.cur_colors).to eq([7, 6, 6, 6, 6, 6, 6, 6])
    end

    it "selects the background from the top two screencode bits" do
      mode.paint(0, 0b1000_0001, 7, sequencer) # bg index 0b10 = 2
      expect(sequencer.cur_colors).to all(eq(4))
    end

    it "marks set bits as foreground" do
      mode.paint(0b1000_0000, 1, 7, sequencer)
      expect(sequencer.cur_fg.first).to be(true)
    end
  end

  describe Badline::VIC::GraphicsMode::Bitmap do
    subject(:mode) { described_class.new }

    it "draws set bits in the screencode high nibble, clear bits in the low" do
      mode.paint(0b1000_0001, 0x4a, 0, sequencer) # fg = 4, bg = 10
      expect(sequencer.cur_colors).to eq([4, 10, 10, 10, 10, 10, 10, 4])
    end

    it "marks set bits as foreground" do
      mode.paint(0b1000_0001, 0x4a, 0, sequencer)
      expect(sequencer.cur_fg)
        .to(eq([true, false, false, false, false, false, false, true]))
    end
  end

  describe Badline::VIC::GraphicsMode::MulticolorBitmap do
    subject(:mode) { described_class.new }

    before { registers.write(0x21, 6) } # background 0

    # pairs: 00->bg0(6) 01->screencode high nibble 10->low nibble 11->colour RAM
    it "decodes 2-bit pairs into double-wide pixels" do
      mode.paint(0b00_01_10_11, 0x35, 9, sequencer) # high=3 low=5 colour RAM=9
      expect(sequencer.cur_colors).to eq([6, 6, 3, 3, 5, 5, 9, 9])
    end

    it "marks only the high-bit (10/11) pairs as foreground" do
      mode.paint(0b00_01_10_11, 0x35, 9, sequencer)
      expect(sequencer.cur_fg).to eq([false, false, false, false,
                                      true, true, true, true])
    end
  end

  describe Badline::VIC::GraphicsMode::Null do
    subject(:mode) { described_class.new }

    it "renders black" do
      sequencer.cur_colors.fill(9)
      mode.paint(0xff, 1, 1, sequencer)
      expect(sequencer.cur_colors).to all(eq(0))
    end

    it "marks nothing as foreground" do
      sequencer.cur_fg = Array.new(8, true)
      mode.paint(0xff, 1, 1, sequencer)
      expect(sequencer.cur_fg).to all(be(false))
    end
  end

  describe "#fg" do
    let(:inputs) { [0x00, 0x5a, 0xa5, 0xff].product([0x00, 0xc3], [0x02, 0x0a]) }

    def painted_masks(mode)
      inputs.map do |data, screencode, color|
        mode.paint(data, screencode, color, sequencer)
        sequencer.cur_fg
      end
    end

    described_class::MODES.uniq.each do |mode|
      it "gives the mask #{mode.class.name.split('::').last}#paint leaves" do
        expect(inputs.map { |args| mode.fg(*args) }).to eq(painted_masks(mode))
      end
    end
  end
end
