# frozen_string_literal: true

require "spec_helper"

RSpec.describe Badline::VIC::Sequencer do
  subject(:sequencer) { described_class.new(504, registers, bank) }

  let(:registers) { Badline::VIC::Registers.new }
  let(:bank) { Badline::VIC::Bank.new }
  let(:col) { 10 }
  let(:x_pos) { (col + 16) * 8 }

  before do
    registers.write(0x20, 2)
    registers.write(0x21, 6)
  end

  def put_char(screencode, bits)
    bank.address_bus.ram.poke(screencode * 8, bits)
  end

  # Hands the sequencer one g-access through its ring, as the VIC does, in
  # the slot the column's position gives it.
  def emit_byte(data, screencode, color, column, display: true)
    slot = column & 3
    sequencer.ring_data[slot] = data
    sequencer.ring_char[slot] = screencode
    sequencer.ring_color[slot] = color
    sequencer.emit(slot, column, display)
  end

  def emit_at(screencode, column)
    emit_byte(bank.peek(screencode * 8), screencode, 1, column)
  end

  def warm_columns
    (0...(col - 1)).each { |c| emit_at(0, c) }
  end

  def render(bits, xscroll: 0, prev_bits: nil, line: 51)
    registers.write(0x16, 0xc8 | xscroll) # keep CSEL (40 cols), set XSCROLL
    sequencer.latch_xscroll
    put_char(0, 0)
    put_char(1, bits)
    put_char(2, prev_bits || 0)
    sequencer.new_line(line)
    warm_columns
    emit_at(prev_bits ? 2 : 0, col - 1)
    emit_at(1, col)
    sequencer.colors[x_pos, 8]
  end

  def render_fg(bits, **)
    render(bits, **)
    sequencer.fg[x_pos, 8]
  end

  describe "standard text decode" do
    it "draws set bits in the foreground colour" do
      expect(render(0b1000_0001)).to eq([1, 6, 6, 6, 6, 6, 6, 1])
    end

    it "draws clear bits in the background colour" do
      expect(render(0)).to eq([6, 6, 6, 6, 6, 6, 6, 6])
    end
  end

  describe "foreground-mask" do
    it "marks set bits as foreground" do
      expect(render_fg(0b1010_0000))
        .to(eq([true, false, true, false, false, false, false, false]))
    end

    it "marks background pixels as not foreground" do
      expect(render_fg(0)).to all(be(false))
    end

    it "marks idle-state pixels as not foreground" do
      put_char(1, 0xff)
      sequencer.new_line(51)
      emit_byte(0xff, 0, 0, col, display: false)
      expect(sequencer.fg[x_pos, 8]).to all(be(false))
    end

    describe "under the 38-column border" do
      before do
        registers.write(0x16, 0xc0) # CSEL=38, XSCROLL=0
        put_char(1, 0xff)
        sequencer.new_line(51)
        emit_at(1, 0) # column 0 -> x 128..135; x 128 is clipped
      end

      it "shows the border colour" do
        expect(sequencer.colors[128]).to eq(2)
      end

      it "keeps the graphics foreground-mask" do
        expect(sequencer.fg[128]).to be(true)
      end
    end
  end

  describe "border / window clip" do
    it "renders foreground inside the visible line" do
      expect(render(0xff)).to all(eq(1))
    end

    it "renders border for a line outside the display window" do
      expect(render(0xff, line: 10)).to all(eq(2))
    end

    it "renders border for columns outside the horizontal window" do
      registers.write(0x16, 0xc8) # CSEL=40, XSCROLL=0
      put_char(1, 0xff)
      sequencer.new_line(51)
      emit_at(1, -16) # column -16 maps to x 0 (border)
      expect(sequencer.colors[0, 8]).to all(eq(2))
    end
  end

  describe "fine horizontal scrolling (XSCROLL)" do
    context "with XSCROLL=0" do
      it "draws the cell unshifted" do
        expect(render(0b1000_0000)).to eq([1, 6, 6, 6, 6, 6, 6, 6])
      end
    end

    context "with XSCROLL=1" do
      it "shifts the cell one pixel to the right" do
        expect(render(0b1000_0000, xscroll: 1))
          .to eq([6, 1, 6, 6, 6, 6, 6, 6])
      end

      it "bleeds the previous cell into the vacated pixel" do
        # prev cell bit 0 set -> its rightmost pixel fills the leftmost slot
        expect(render(0, prev_bits: 0b0000_0001, xscroll: 1))
          .to eq([1, 6, 6, 6, 6, 6, 6, 6])
      end
    end

    context "with XSCROLL=7 (maximum)" do
      it "shifts the cell seven pixels to the right" do
        expect(render(0b1000_0000, xscroll: 7))
          .to eq([6, 6, 6, 6, 6, 6, 6, 1])
      end
    end

    context "when at the left edge of the display (column 0)" do
      let(:col) { 0 }

      # The group before column 0 is the zero-data group the sequencer shifts
      # out ahead of the first g-access, so its pixels bleed in like any
      # other.
      it "takes the shifted-in pixels from the group before it" do
        expect(render(0, prev_bits: 0b0000_0001, xscroll: 1).first).to eq(1)
      end
    end

    describe "#new_line" do
      it "repaints the whole line in the border colour" do
        sequencer.new_line(51)
        expect(sequencer.colors).to all(eq(2))
      end
    end
  end

  # Bauer §3.9 rules 2-5: the top compare resets the vertical flip-flop at
  # once, the bottom one arms it for the next line's first cycle or the left
  # window edge, so DEN and RSEL toggled mid-frame still open or close the
  # border. Pinned by dentest and border.
  describe "vertical border flip-flop" do
    # RSEL=1 puts the top compare on line 51; CSEL=40 puts the left one at
    # pixel 128, the first pixel of display column 0.
    def paint_line(line, den:, den_midline: false, left_compare_first: false)
      registers.write(0x16, 0xc8)
      registers.write(0x11, 0x08 | (den ? 0x10 : 0x00))
      put_char(0, 0)
      sequencer.new_line(line)
      sequencer.left_compare_vertical_border if left_compare_first
      registers.write(0x11, 0x18) if den_midline
      (-2..3).each { |c| emit_at(0, c) }
      sequencer.colors[128]
    end

    it "opens the window on the top compare line with DEN set" do
      expect(paint_line(51, den: true)).to eq(6) # background
    end

    it "keeps the border closed with DEN clear" do
      expect(paint_line(51, den: false)).to eq(2) # border
    end

    it "opens on a DEN set after the line has started" do
      expect(paint_line(51, den: false, den_midline: true)).to eq(6)
    end

    it "leaves the border closed on any other line" do
      expect(paint_line(52, den: true)).to eq(2)
    end

    # Pinned by vborder2-36: the 40-column left compare runs a column before
    # the column that draws its pixel.
    it "keeps the DEN the 40-column left compare saw a column earlier" do
      expect(paint_line(51, den: false, den_midline: true, left_compare_first: true)).to eq(2)
    end

    context "with the window open at the bottom compare line" do
      before do
        registers.write(0x11, 0x18) # DEN=1, RSEL=1: bottom compare on 251
        sequencer.start_vertical_border(51)
        sequencer.new_line(251)
        sequencer.compare_vertical_border(251)
      end

      it "only arms the flip-flop for the rest of the line" do
        expect(sequencer.vertical_closed?).to be(false)
      end

      it "closes it at the next line's first cycle" do
        sequencer.start_vertical_border(252)
        expect(sequencer.vertical_closed?).to be(true)
      end
    end
  end

  # Pinned by hvborder1/2, border-bm-ysh* and border-mcbm: with the side
  # border left open, the vertical border only withholds the graphics data,
  # and the zero data still shows in the colours the last g-access latched.
  describe "a column with no g-access" do
    def paint_blank(d011, d016: 0xc8)
      registers.write(0x11, d011)
      registers.write(0x16, d016)
      sequencer.new_line(260)
      sequencer.instance_variable_set(:@main_border, false)
      emit_byte(0, 0x35, 0x09, col - 1, display: false)
      emit_byte(0, 0x35, 0x09, col, display: false)
      sequencer.colors[x_pos]
    end

    it "paints the kept screen byte's low nibble in standard bitmap" do
      expect(paint_blank(0x3b)).to eq(5)
    end

    it "paints $d021 in multicolour bitmap" do
      expect(paint_blank(0x3b, d016: 0xd8)).to eq(6)
    end

    it "paints black in an invalid mode" do
      expect(paint_blank(0x7b)).to eq(0)
    end

    it "shows the vertical border only through the main flip-flop" do
      registers.write(0x11, 0x3b)
      sequencer.new_line(260)
      emit_byte(0, 0x35, 0x09, col, display: false)
      expect(sequencer.colors[x_pos]).to eq(2)
    end
  end

  # Pinned by modesplit and videomode: a mode written mid-line changes the
  # colours inside the group, at pixel 4 for a rising bit.
  describe "a mode change inside a group" do
    before do
      registers.write(0x22, 5)
      put_char(0x40, 0)
    end

    it "keeps the old mode for the first four pixels" do
      render(0) # warms the line in text mode
      registers.write(0x11, 0x5b) # ECM
      emit_at(0x40, col + 1)
      expect(sequencer.colors[x_pos + 8, 8]).to eq([6, 6, 6, 6, 5, 5, 5, 5])
    end
  end

  # Pinned by modesplit and vicii_reg_timing: the pixels XSCROLL keeps from
  # the previous byte show a background colour written since it was painted.
  describe "a background write under XSCROLL" do
    it "paints the kept pixels in the new colour" do
      render(0, xscroll: 3)
      registers.write(0x21, 9)
      sequencer.colors_changed!
      emit_at(0, col + 1)
      expect(sequencer.colors[x_pos + 8, 3]).to eq([9, 9, 9])
    end
  end

  describe "horizontal border flip-flop" do
    def paint_line(switch_at: nil, switch_to: nil)
      put_char(1, 0xff)
      sequencer.new_line(51)
      (-6..44).each do |c|
        registers.write(0x16, switch_to) if switch_at && c == switch_at
        emit_at(1, c)
      end
    end

    it "closes the right border at the 40-column compare on a normal line" do
      registers.write(0x16, 0xc8) # CSEL=40 throughout
      paint_line
      expect(sequencer.colors[450]).to eq(2) # x 450 is right border
    end

    it "leaves the right border open when the right compare is skipped" do
      registers.write(0x16, 0xc8) # start at CSEL=40
      paint_line(switch_at: 39, switch_to: 0xc0)
      expect(sequencer.colors[450]).to eq(1) # graphics, not border
    end
  end
end
