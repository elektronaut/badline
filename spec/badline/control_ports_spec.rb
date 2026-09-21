# frozen_string_literal: true

require "spec_helper"

describe Badline::ControlPorts do
  subject(:ports) do
    described_class.new(keyboard:, joystick1:, joystick2:)
  end

  let(:keyboard) { Badline::Keyboard.new }
  let(:joystick1) { Badline::Joystick.new }
  let(:joystick2) { Badline::Joystick.new }

  it "wires joystick 2 onto port A" do
    joystick2.press(:up)
    expect(ports.read_a(0xff, 0xff)).to eq(0b11111110)
  end

  it "wires joystick 1 onto port B" do
    joystick1.press(:up)
    expect(ports.read_b(0xff, 0xff)).to eq(0b11111110)
  end

  it "ANDs the joystick with the keyboard on port A" do
    joystick2.press(:fire)
    expect(ports.read_a(0xfe, 0xff)).to eq(keyboard.read_a(0xfe, 0xff) & 0b11101111)
  end

  it "leaves port B as keyboard passthrough" do
    keyboard.press(:a)
    expect(ports.read_b(0xfd, 0xff)).to eq(keyboard.read_b(0xfd, 0xff))
  end

  describe "phantom keypresses" do
    it "selects a matrix row from a joystick 2 line" do
      keyboard.press(:a) # row 1, column 2
      joystick2.press(:down) # pulls row 1 low
      expect(ports.read_b(0xff, 0xff)).to eq(0b11111011)
    end

    it "selects a matrix column from a joystick 1 line" do
      keyboard.press(:a) # row 1, column 2
      joystick1.press(:left) # pulls column 2 low
      expect(ports.read_a(0xff, 0xff)).to eq(0b11111101)
    end

    it "keeps the stick itself visible through the phantom key" do
      keyboard.press(:a)
      joystick1.press(:left)
      expect(ports.read_b(0xff, 0xff)).to eq(0b11111011)
    end
  end
end
