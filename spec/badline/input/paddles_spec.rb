# frozen_string_literal: true

require "spec_helper"

describe Badline::Input::Paddles do
  subject(:paddles) { described_class.new }

  it "centres paddle A" do
    expect(paddles.pot_x).to eq(0x80)
  end

  it "centres paddle B" do
    expect(paddles.pot_y).to eq(0x80)
  end

  it "turns paddle A onto POTX" do
    paddles.move(0x20, 0)
    expect(paddles.pot_x).to eq(0x90)
  end

  it "turns paddle B onto POTY" do
    paddles.move(0, -0x20)
    expect(paddles.pot_y).to eq(0x70)
  end

  it "takes two host pixels to a count" do
    paddles.move(1, 0)
    expect(paddles.pot_x).to eq(0x80)
  end

  it "keeps the odd half count for the next turn" do
    2.times { paddles.move(1, 0) }
    expect(paddles.pot_x).to eq(0x81)
  end

  it "stops at the low end of the knob" do
    paddles.move(-0x200, 0)
    expect(paddles.pot_x).to eq(0x00)
  end

  it "stops at the high end of the knob" do
    paddles.move(0x200, 0)
    expect(paddles.pot_x).to eq(0xff)
  end

  it "turns straight back from the high end" do
    paddles.move(0x200, 0)
    paddles.move(-2, 0)
    expect(paddles.pot_x).to eq(0xfe)
  end

  describe "buttons" do
    it "leaves the port lines high when idle" do
      expect(paddles.port_bits).to eq(0xff)
    end

    it "puts paddle A's button on the left line" do
      paddles.press(:left)
      expect(paddles.port_bits).to eq(0b11111011)
    end

    it "puts paddle B's button on the right line" do
      paddles.press(:right)
      expect(paddles.port_bits).to eq(0b11110111)
    end

    it "releases a button" do
      paddles.press(:left)
      paddles.release(:left)
      expect(paddles.port_bits).to eq(0xff)
    end

    it "ignores a button it has no line for" do
      paddles.press(:middle)
      expect(paddles.port_bits).to eq(0xff)
    end
  end
end
