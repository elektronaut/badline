# frozen_string_literal: true

require "spec_helper"

describe Badline::Drive1541::GCR do
  it "encodes four bytes as five" do
    # $08 $00 $01 $12: 01010 01001 01010 01010 01010 01011 01011 10010
    expect(described_class.encode([0x08, 0x00, 0x01, 0x12])).to eq([0x52, 0x54, 0xa5, 0x2d, 0x72])
  end

  it "encodes $0F filler as alternating bits" do
    expect(described_class.encode([0x0f] * 4)).to eq([0x55] * 5)
  end

  it "decodes what it encodes, for every byte" do
    bytes = (0..255).to_a
    expect(described_class.decode(described_class.encode(bytes))).to eq(bytes)
  end

  it "has no code with more than two 0 bits in a row" do
    expect(described_class::CODES.map { |code| format("%05b", code) }).to all(satisfy { |bits| !bits.include?("000") })
  end

  it "decodes to nil when a code isn't GCR" do
    expect(described_class.decode([0xff] * 5)).to be_nil
  end
end
