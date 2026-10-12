# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"
require_relative "../../support/keyed_oracle"

describe Badline::Chips::TIA do
  include KeyedOracle

  subject(:tia) { described_class.new }

  it "reads back what an output pin drives" do
    tia.poke(0x04, 0xfc)
    tia.poke(0x01, 0xfc)
    expect(tia.peek(0x01)).to eq(0xfc)
  end

  it "reads an input pin from the other side" do
    tia.inputs[2] = 0x81
    tia.poke(0x02, 0x3f)
    expect(tia.peek(0x02)).to eq(0x81)
  end

  it "reads its direction registers back" do
    tia.poke(0x03, 0xff)
    expect(tia.peek(0x0b)).to eq(0xff)
  end

  it "repeats its registers every 8 bytes" do
    tia.poke(0x08, 0x12)
    expect(tia.ports[0]).to eq(0x12)
  end

  it "reads registers 6 and 7 as $FF" do
    expect([tia.peek(0x06), tia.peek(0x07)]).to eq([0xff, 0xff])
  end

  it "loads its ports, their directions and what the other side drives from a keyed snapshot module" do
    tia.poke(0x03, 0xf0)
    tia.poke(0x02, 0x81)
    tia.inputs[1] = 0x5a
    target = described_class.new.tap { |fresh| keyed_round_trip(tia, fresh) }
    expect([target.ports, target.directions, target.inputs]).to eq([tia.ports, tia.directions, tia.inputs])
  end
end
