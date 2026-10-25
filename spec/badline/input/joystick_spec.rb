# frozen_string_literal: true

require "spec_helper"

describe Badline::Input::Joystick do
  subject(:joystick) { described_class.new }

  it "reads all bits high when idle" do
    expect(joystick.port_bits).to eq(0xff)
  end

  it "pulls bit 0 low for up" do
    joystick.press(:up)
    expect(joystick.port_bits).to eq(0b11111110)
  end

  it "pulls bit 4 low for fire" do
    joystick.press(:fire)
    expect(joystick.port_bits).to eq(0b11101111)
  end

  it "combines simultaneous presses" do
    joystick.press(:left)
    joystick.press(:fire)
    expect(joystick.port_bits).to eq(0b11101011)
  end

  it "restores a bit on release" do
    joystick.press(:down)
    joystick.release(:down)
    expect(joystick.port_bits).to eq(0xff)
  end

  it "ignores unknown directions" do
    joystick.press(:wiggle)
    expect(joystick.port_bits).to eq(0xff)
  end

  it "tells its change handler a switch moved" do
    moves = []
    joystick.on_change { moves << joystick.port_bits }
    joystick.press(:fire)
    joystick.release(:fire)
    expect(moves).to eq([0xef, 0xff])
  end
end
