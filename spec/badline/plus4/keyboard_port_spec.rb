# frozen_string_literal: true

require "spec_helper"
require "badline/plus4"

describe Badline::Plus4::KeyboardPort do
  subject(:port) { described_class.new(keyboard, joystick1, joystick2) }

  let(:keyboard) { Badline::Input::Keyboard.new(matrix: described_class::MATRIX) }
  let(:joystick1) { Badline::Input::Joystick.new }
  let(:joystick2) { Badline::Input::Joystick.new }

  it "reads back the line mask written to it" do
    port.poke(0xfd30, 0x7f)
    expect(port.peek(0xfd30)).to eq(0x7f)
  end

  it "pulls a held key's input low on its line" do
    keyboard.press(:esc)
    port.poke(0xfd30, 0xbf)
    expect(port.latch(0xff)).to eq(0xef)
  end

  it "leaves a held key's input high off its line" do
    keyboard.press(:esc)
    port.poke(0xfd30, 0x7f)
    expect(port.latch(0xff)).to eq(0xff)
  end

  it "puts joystick 1 on K0-K3 and K6 when bit 2 is low" do
    %i[up right fire].each { |direction| joystick1.press(direction) }
    expect(port.latch(0xfa)).to eq(0xb6)
  end

  it "puts joystick 2's fire button on K7 when bit 1 is low" do
    %i[down fire].each { |direction| joystick2.press(direction) }
    expect(port.latch(0xfd)).to eq(0x7d)
  end

  it "leaves a joystick off K0-K7 unless selected" do
    joystick1.press(:left)
    expect(port.latch(0xfd)).to eq(0xff)
  end

  it "ghosts a joystick switch onto another key's input through a line" do
    keyboard.press(:"3")
    keyboard.press(:w)
    joystick1.press(:up)
    port.poke(0xfd30, 0xff)
    expect(port.latch(0xfb)).to eq(0xfc)
  end
end
