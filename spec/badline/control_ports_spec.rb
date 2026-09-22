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

  describe "attached devices" do
    let(:device) { Badline::Input::Paddles.new }

    it "pulls port A low through a device on port 2" do
      ports.device2 = device
      device.press(:left)
      expect(ports.read_a(0xff, 0xff)).to eq(0b11111011)
    end

    it "pulls port B low through a device on port 1" do
      ports.device1 = device
      device.press(:right)
      expect(ports.read_b(0xff, 0xff)).to eq(0b11110111)
    end
  end

  describe "the light pen line (port 1 fire)" do
    it "reads high with nothing pressed" do
      expect(ports).to be_port_b4_high
    end

    it "reads low while joystick 1 fires" do
      joystick1.press(:fire)
      expect(ports).not_to be_port_b4_high
    end

    it "ignores joystick 2's fire button" do
      joystick2.press(:fire)
      expect(ports).to be_port_b4_high
    end

    it "reads low through a port 1 device's fire line" do
      ports.device1 = Badline::Input::Mouse1351.new
      ports.device1.press(:left)
      expect(ports).not_to be_port_b4_high
    end

    it "ignores a port 2 device's fire line" do
      ports.device2 = Badline::Input::Mouse1351.new
      ports.device2.press(:left)
      expect(ports).to be_port_b4_high
    end

    it "ignores the keyboard matrix" do
      keyboard.press(:a)
      expect(ports).to be_port_b4_high
    end
  end

  describe "pot mux" do
    let(:port1_device) { Struct.new(:pot_x, :pot_y, :port_bits).new(0x10, 0x20, 0xff) }
    let(:port2_device) { Struct.new(:pot_x, :pot_y, :port_bits).new(0x30, 0x08, 0xff) }

    before do
      ports.port_a_source = Struct.new(:port_a_lines).new(0xff)
      ports.device1 = port1_device
      ports.device2 = port2_device
    end

    it "floats POTX high with nothing selected" do
      ports.port_a_source.port_a_lines = 0x3f
      expect(ports.pot_x).to eq(0xff)
    end

    it "floats POTY high with no device in the selected port" do
      ports.device1 = nil
      ports.port_a_source.port_a_lines = 0x40
      expect(ports.pot_y).to eq(0xff)
    end

    it "reads POTX from port 1 on PA6" do
      ports.port_a_source.port_a_lines = 0x40
      expect(ports.pot_x).to eq(0x10)
    end

    it "reads POTY from port 2 on PA7" do
      ports.port_a_source.port_a_lines = 0x80
      expect(ports.pot_y).to eq(0x08)
    end

    it "reads the lower resistance with both ports selected" do
      expect(ports.pot_x).to eq(0x10)
    end

    it "reads the lower resistance on POTY too" do
      expect(ports.pot_y).to eq(0x08)
    end

    it "floats high with no select lines wired up" do
      ports.port_a_source = nil
      expect(ports.pot_x).to eq(0xff)
    end
  end
end
