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
    mouse.move(6, 0)
    expect(mouse.pot_x).to eq(6)
  end

  it "counts Y against the host's downward axis" do
    mouse.move(0, -6)
    expect(mouse.pot_y).to eq(6)
  end

  it "takes two host pixels to a count" do
    mouse.move(1, 0)
    expect(mouse.pot_x).to eq(0)
  end

  it "keeps the odd half count for the next move" do
    mouse.move(1, 0)
    mouse.pot_x
    mouse.move(1, 0)
    expect(mouse.pot_x).to eq(2)
  end

  it "keeps the odd half count moving backwards" do
    mouse.move(-1, 0)
    mouse.pot_x
    mouse.move(1, 0)
    expect(mouse.pot_x).to eq(0)
  end

  it "wraps the X counter at six bits" do
    [60, 60, 10].each do |pixels|
      mouse.move(pixels, 0)
      mouse.pot_x
    end
    expect(mouse.pot_x).to eq(2)
  end

  it "wraps the X counter below zero" do
    mouse.move(-2, 0)
    expect(mouse.pot_x).to eq(126)
  end

  it "keeps bit 7 clear at the top of the counter" do
    mouse.move(-1, 0)
    expect(mouse.pot_x).to eq(126)
  end

  it "presents travel a driver recovers as a signed delta" do
    mouse.move(-20, 0)
    expect(delta(0x00, mouse.pot_x)).to eq(-10)
  end

  describe "motion between reads" do
    it "adds up moves until the driver reads" do
      3.times { mouse.move(10, 0) }
      expect(delta(0x00, mouse.pot_x)).to eq(15)
    end

    it "clamps a fast flick to 31 counts" do
      mouse.move(500, 0)
      expect(delta(0x00, mouse.pot_x)).to eq(31)
    end

    it "clamps a fast flick backwards to 31 counts" do
      mouse.move(-500, 0)
      expect(delta(0x00, mouse.pot_x)).to eq(-31)
    end

    it "keeps a clamped flick's direction from an odd half count" do
      mouse.move(1, 0)
      previous = mouse.pot_x
      mouse.move(500, 0)
      expect(delta(previous, mouse.pot_x)).to eq(31)
    end

    it "clamps Y separately" do
      mouse.move(0, 500)
      expect(delta(0x00, mouse.pot_y)).to eq(-31)
    end

    it "starts afresh after a read" do
      mouse.move(500, 0)
      mouse.pot_x
      mouse.move(500, 0)
      expect(delta(62, mouse.pot_x)).to eq(31)
    end
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
