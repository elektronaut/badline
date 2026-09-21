# frozen_string_literal: true

require "spec_helper"

describe Badline::ControlPorts do
  subject(:ports) do
    described_class.new(keyboard:, joystick2:)
  end

  let(:keyboard) { Badline::Keyboard.new }
  let(:joystick2) { Badline::Joystick.new }

  it "wires joystick 2 onto port A" do
    joystick2.press(:up)
    expect(ports.read_a(0xff, 0xff)).to eq(0b11111110)
  end

  it "ANDs the joystick with the keyboard on port A" do
    joystick2.press(:fire)
    expect(ports.read_a(0xfe, 0xff)).to eq(keyboard.read_a(0xfe, 0xff) & 0b11101111)
  end

  it "leaves port B as keyboard passthrough" do
    keyboard.press(:a)
    expect(ports.read_b(0xfd, 0xff)).to eq(keyboard.read_b(0xfd, 0xff))
  end

  it "selects a matrix row from a joystick 2 line" do
    keyboard.press(:a) # row 1, column 2
    joystick2.press(:down) # pulls row 1 low
    expect(ports.read_b(0xff, 0xff)).to eq(0b11111011)
  end
end
