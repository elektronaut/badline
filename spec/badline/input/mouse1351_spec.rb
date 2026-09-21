# frozen_string_literal: true

require "spec_helper"

describe Badline::Input::Mouse1351 do
  subject(:mouse) { described_class.new }

  # The driver's own arithmetic: difference of two readings, sign extended
  # from bit 6, halved back into counter units.
  def delta(previous, current)
    diff = (current - previous) & 0x7f
    diff -= 0x80 if diff >= 0x40
    diff / 2
  end

  it "starts POTX at zero" do
    expect(mouse.pot_x).to eq(0x00)
  end

  it "presents the X counter shifted up one bit" do
    mouse.move(3, 0)
    expect(mouse.pot_x).to eq(6)
  end

  it "counts Y against the host's downward axis" do
    mouse.move(0, -3)
    expect(mouse.pot_y).to eq(6)
  end

  it "wraps the X counter at six bits" do
    mouse.move(65, 0)
    expect(mouse.pot_x).to eq(2)
  end

  it "wraps the X counter below zero" do
    mouse.move(-1, 0)
    expect(mouse.pot_x).to eq(126)
  end

  it "keeps bit 7 clear at the top of the counter" do
    mouse.move(63, 0)
    expect(mouse.pot_x).to eq(126)
  end

  it "presents travel a driver recovers as a signed delta" do
    mouse.move(-10, 0)
    expect(delta(0x00, mouse.pot_x)).to eq(-10)
  end

  describe "buttons" do
    it "leaves the port lines high when idle" do
      expect(mouse.port_bits).to eq(0xff)
    end

    it "puts the left button on the fire line" do
      mouse.press(:left)
      expect(mouse.port_bits).to eq(0b11101111)
    end

    it "puts the right button on the up line" do
      mouse.press(:right)
      expect(mouse.port_bits).to eq(0b11111110)
    end

    it "releases a button" do
      mouse.press(:left)
      mouse.release(:left)
      expect(mouse.port_bits).to eq(0xff)
    end
  end
end
