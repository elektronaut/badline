# frozen_string_literal: true

require "spec_helper"

describe Badline::Input::MatrixTypist do
  subject(:typist) { described_class.new(keyboard) }

  let(:keyboard) { Badline::Input::Keyboard.new }
  let(:codes) { [0x44, 0xc9, 0x0d] }

  def type(cycles)
    cycles.times { typist.cycle!(codes) }
  end

  describe ".keys" do
    {
      0x44 => [:d], 0xc4 => %i[lshift d], 0x31 => [:"1"], 0x21 => %i[lshift 1], 0x2a => [:*],
      0x3f => %i[lshift /], 0x0d => [:return], 0x20 => [:space], 0x1b => []
    }.each do |code, keys|
      it "types $#{code.to_s(16)} with #{keys.inspect}" do
        expect(described_class.keys(code)).to eq(keys)
      end
    end
  end

  it "presses the first code's keys" do
    type(1)
    expect(keyboard.keys).to eq([:d])
  end

  it "holds them for HOLD cycles" do
    type(described_class::HOLD)
    expect(keyboard.keys).to eq([:d])
  end

  it "lets them go after HOLD cycles" do
    type(described_class::HOLD + 1)
    expect(keyboard.keys).to be_empty
  end

  it "presses the next code's keys after the gap" do
    type(described_class::HOLD + described_class::GAP + 1)
    expect(keyboard.keys).to eq(%i[lshift i])
  end

  it "takes each code as its keys go down" do
    type(described_class::HOLD + described_class::GAP + 1)
    expect(codes).to eq([0x0d])
  end

  it "is typing until the last gap has passed" do
    type(3 * (described_class::HOLD + described_class::GAP))
    expect(typist.typing?).to be(true)
  end

  it "is done once the last gap has passed" do
    type((3 * (described_class::HOLD + described_class::GAP)) + 1)
    expect(typist.typing?).to be(false)
  end
end
