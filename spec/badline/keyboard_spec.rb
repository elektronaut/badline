# frozen_string_literal: true

require "spec_helper"

describe Badline::Keyboard do
  subject(:keyboard) { described_class.new }

  # :a sits at row 1, column 2 -- the reference key for most of these.
  let(:row1) { 0b11111101 }
  let(:col2) { 0b11111011 }

  it "ignores keys outside the matrix" do
    keyboard.press(:nonesuch)
    expect(keyboard.keys).to be_empty
  end

  it "covers all eight keys of every row" do
    expect(keyboard.matrix.map(&:length)).to all(eq(8))
  end

  describe "#read_b" do
    it "reads every column high with no keys pressed" do
      expect(keyboard.read_b(0x00, 0xff)).to eq(0xff)
    end

    it "pulls the column of a key in the selected row low" do
      keyboard.press(:a)
      expect(keyboard.read_b(row1, 0xff)).to eq(col2)
    end

    it "leaves the column high while another row is selected" do
      keyboard.press(:a)
      expect(keyboard.read_b(0b11111110, 0xff)).to eq(0xff)
    end

    it "merges several keys in the selected row" do
      keyboard.press(:a) # column 2
      keyboard.press(:z) # column 4
      expect(keyboard.read_b(row1, 0xff)).to eq(0b11101011)
    end

    it "forgets released keys" do
      keyboard.press(:a)
      keyboard.release(:a)
      expect(keyboard.read_b(row1, 0xff)).to eq(0xff)
    end
  end

  describe "#read_a" do
    it "reads every row high with no keys pressed" do
      expect(keyboard.read_a(0xff, 0x00)).to eq(0xff)
    end

    it "pulls the row of a key in the driven column low" do
      keyboard.press(:a)
      expect(keyboard.read_a(0xff, col2)).to eq(row1)
    end

    it "leaves rows high while another column is driven" do
      keyboard.press(:a)
      expect(keyboard.read_a(0xff, 0b11111110)).to eq(0xff)
    end

    it "reports every row of a key pressed in more than one" do
      keyboard.press(:a) # row 1
      keyboard.press(:d) # row 2, same column
      expect(keyboard.read_a(0xff, col2)).to eq(0b11111001)
    end
  end

  describe "ghosting" do
    before do
      keyboard.press(:a) # row 1, column 2
      keyboard.press(:z) # row 1, column 4
      keyboard.press(:d) # row 2, column 2
    end

    it "reports the fourth corner of the rectangle as pressed" do
      expect(keyboard.read_b(0b11111011, 0xff)).to eq(0b11101011)
    end

    it "drags the shorted row low along with it" do
      expect(keyboard.read_a(0b11111011, 0xff)).to eq(0b11111001)
    end
  end

  describe "combination keys" do
    # :cursor_v sits at row 0, column 7 and :lshift at row 1, column 7.
    it "holds shift and cursor down for cursor up" do
      keyboard.press(:cursor_up)
      expect(keyboard.read_a(0xff, 0b01111111)).to eq(0b11111100)
    end

    it "lets go of both keys on release" do
      keyboard.press(:cursor_up)
      keyboard.release(:cursor_up)
      expect(keyboard.read_a(0xff, 0b01111111)).to eq(0xff)
    end

    it "keeps a shift held on its own down" do
      keyboard.press(:lshift)
      keyboard.press(:cursor_left)
      keyboard.release(:cursor_left)
      expect(keyboard.read_b(row1, 0xff)).to eq(0b01111111)
    end
  end

  describe "a matrix passed in" do
    subject(:keyboard) { described_class.new(matrix: [%i[q w], %i[e a]]) }

    it "scans the keys where that matrix wires them" do
      keyboard.press(:a)
      expect(keyboard.read_b(0b11111101, 0xff)).to eq(0b11111101)
    end

    it "ignores keys only the C64 matrix has" do
      keyboard.press(:z)
      expect(keyboard.keys).to be_empty
    end
  end

  describe "a matrix with rows beyond the eighth" do
    subject(:keyboard) { described_class.new(matrix: Array.new(8) { [] } + [%i[extra0], %i[extra1], %i[extra2]]) }

    it "pulls the column of a key in a selected tenth row low" do
      keyboard.press(:extra1)
      expect(keyboard.scan(0b101_1111_1111, 0xff).last).to eq(0b11111110)
    end

    it "pulls a tenth row line low from a driven column" do
      keyboard.press(:extra1)
      expect(keyboard.scan(0x7ff, 0b11111110).first).to eq(0b101_1111_1111)
    end
  end

  it "wires the C64 matrix by default" do
    expect(keyboard.matrix).to eq(described_class::C64_MATRIX)
  end
end
