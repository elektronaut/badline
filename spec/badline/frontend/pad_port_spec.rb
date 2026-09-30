# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::PadPort do
  subject(:port) { described_class.new(joystick) }

  let(:joystick) { Badline::Joystick.new }

  def buttons(*held)
    Array.new(described_class::BUTTON_COUNT) { |button| held.include?(button) ? 1 : 0 }
  end

  describe ".active" do
    it "is empty for an idle controller" do
      expect(described_class.active(buttons, 0, 0)).to eq([])
    end

    it "steers with the D-pad" do
      expect(described_class.active(buttons(11, 13), 0, 0)).to eq(%i[up left])
    end

    it "fires with every face and shoulder button" do
      [0, 1, 2, 3, 9, 10].each do |button|
        expect(described_class.active(buttons(button), 0, 0)).to eq([:fire])
      end
    end

    it "ignores the other buttons" do
      expect(described_class.active(buttons(4, 5, 6, 7, 8), 0, 0)).to eq([])
    end

    it "steers with the left stick past the deadzone" do
      expect(described_class.active(buttons, 8_001, -32_768)).to eq(%i[up right])
    end

    it "ignores the left stick inside the deadzone" do
      expect(described_class.active(buttons, -8_000, 8_000)).to eq([])
    end
  end

  describe "#update" do
    it "presses what the controller holds" do
      port.update(%i[up fire])
      expect(joystick.port_bits).to eq(0xff & ~0b10001)
    end

    it "releases what the controller let go of" do
      port.update(%i[up fire])
      port.update([:fire])
      expect(joystick.port_bits).to eq(0xff & ~0b10000)
    end

    it "leaves directions it didn't press alone" do
      joystick.press(:left)
      port.update([:up])
      port.update([])
      expect(joystick.port_bits).to eq(0xff & ~0b00100)
    end
  end

  describe "#release" do
    it "releases everything it pressed" do
      port.update(%i[down right])
      port.release
      expect([joystick.port_bits, port.pressed]).to eq([0xff, []])
    end
  end
end
