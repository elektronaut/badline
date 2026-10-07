# frozen_string_literal: true

require "spec_helper"
require "badline/vic20"

describe Badline::Vic20::UserVIAPorts do
  subject(:via) { Badline::VIA.new(start: 0x9110, peripheral: described_class.new(joystick:, serial_bus:, datasette:)) }

  let(:joystick) { Badline::Joystick.new }
  let(:serial_bus) { Badline::IECBus.new }
  let(:datasette) { Badline::Datasette.new }

  it "reads port A high with the joystick at rest" do
    expect(via.peek(0x9111)).to eq(0xff)
  end

  { up: 0b1111_1011, down: 0b1111_0111, left: 0b1110_1111, fire: 0b1101_1111, right: 0xff }.each do |switch, lines|
    it "reads #{switch} on port A as $#{lines.to_s(16)}" do
      joystick.press(switch)
      expect(via.peek(0x9111)).to eq(lines)
    end
  end

  it "reads a diagonal on two lines" do
    joystick.press(:up)
    joystick.press(:left)
    expect(via.peek(0x9111)).to eq(0b1110_1011)
  end

  it "pulls a switch's line low while port A drives it high" do
    via.poke(0x9113, 0xff)
    via.poke(0x9111, 0xff)
    joystick.press(:fire)
    expect(via.peek(0x9111)).to eq(0b1101_1111)
  end

  it "leaves the user port on port B floating high" do
    joystick.press(:fire)
    expect(via.peek(0x9110)).to eq(0xff)
  end

  it "reads CLK low on PA0 while the serial bus's clock is pulled" do
    serial_bus.host_lines = Badline::IECBus::HOST_CLK_OUT
    expect(via.peek(0x9111)).to eq(0b1111_1110)
  end

  it "reads DATA low on PA1 while the serial bus's data line is pulled" do
    serial_bus.host_lines = Badline::IECBus::HOST_DATA_OUT
    expect(via.peek(0x9111)).to eq(0b1111_1101)
  end

  it "reads the cassette sense switch low on PA6 while a key is down" do
    datasette.play!
    expect(via.peek(0x9111)).to eq(0b1011_1111)
  end
end
