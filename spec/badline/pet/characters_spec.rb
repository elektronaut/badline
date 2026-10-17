# frozen_string_literal: true

require "spec_helper"

describe Badline::PET::Characters do
  subject(:characters) { described_class.new("pet/characters2.rom") }

  let(:rom) { Badline::ROM.read("pet/characters2.rom") }

  it "holds the graphics set's rows from 0" do
    expect(characters.rows[(1 << 3) | 2]).to eq(rom[(1 << 3) | 2])
  end

  it "holds the text set's from TEXT" do
    expect(characters.rows[described_class::TEXT | (1 << 3) | 2]).to eq(rom[0x400 | (1 << 3) | 2])
  end

  it "inverts the rows of the codes with bit 7 set" do
    expect(characters.rows[(0x81 << 3) | 2]).to eq(rom[(1 << 3) | 2] ^ 0xff)
  end

  context "with the 8296's 4K ROM" do
    subject(:characters) { described_class.new("pet/characters-din.rom") }

    it "holds its second half from HALF" do
      expect(characters.rows[described_class::HALF | 3]).to eq(rom[3])
    end
  end
end
