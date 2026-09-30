# frozen_string_literal: true

require "spec_helper"
require_relative "../../../native/lib/badline/native/keys"
require_relative "../../../native/lib/badline/native/controls"

describe Badline::Native::Controls do
  subject(:controls) { described_class.new(computer) }

  let(:computer) { Badline::Computer.new }
  let(:ports) { computer.control_ports }

  def cycle_to(mode)
    controls.cycle_mode(1) until controls.mode == mode
  end

  describe "#cycle_mode" do
    it "steps through badline-ruby's modes and back round" do
      modes = Array.new(7) { controls.cycle_mode(1).then { controls.mode } }
      expect(modes).to eq(%i[joystick mouse1 mouse2 paddles1 paddles2 keyboard joystick])
    end

    it "steps back with a negative step" do
      controls.cycle_mode(-1)
      expect(controls.mode).to eq(:paddles2)
    end

    it "puts a 1351 mouse on port 1 in mouse1" do
      cycle_to(:mouse1)
      expect([ports.device1.class, ports.device2]).to eq([Badline::Input::Mouse1351, nil])
    end

    it "puts paddles on port 2 in paddles2" do
      cycle_to(:paddles2)
      expect([ports.device1, ports.device2.class]).to eq([nil, Badline::Input::Paddles])
    end

    it "takes the device away in keyboard mode" do
      cycle_to(:paddles2)
      controls.cycle_mode(1)
      expect([ports.device1, ports.device2]).to eq([nil, nil])
    end
  end

  describe "#tag" do
    it "is empty for the keyboard" do
      expect(controls.tag).to eq("")
    end

    it "names the port the arrows drive in joystick mode" do
      cycle_to(:joystick)
      controls.swap_ports
      expect(controls.tag).to eq("JOY 1")
    end

    it "names the pot device and its port" do
      cycle_to(:paddles1)
      expect(controls.tag).to eq("PADDLE 1")
    end
  end

  describe "#pot_device?" do
    it "is false for the keyboard and the joysticks" do
      states = Array.new(2) { controls.pot_device?.tap { controls.cycle_mode(1) } }
      expect(states).to eq([false, false])
    end

    it "is true for a mouse" do
      cycle_to(:mouse2)
      expect(controls.pot_device?).to be(true)
    end
  end

  describe "#mouse_motion" do
    it "moves the 1351's counters" do
      cycle_to(:mouse2)
      controls.mouse_motion(6, 4)
      expect([ports.device2.pot_x, ports.device2.pot_y]).to eq([6, 0x7c])
    end

    it "turns the paddles" do
      cycle_to(:paddles1)
      controls.mouse_motion(20, -10)
      expect([ports.device1.pot_x, ports.device1.pot_y]).to eq([0x8a, 0x7b])
    end

    it "does nothing without a pot device" do
      expect { controls.mouse_motion(10, 10) }.not_to raise_error
    end
  end

  describe "#mouse_button" do
    it "puts the 1351's left button on the fire line" do
      cycle_to(:mouse1)
      controls.mouse_button(1, true)
      expect(ports.device1.port_bits & 0x1f).to eq(0b01111)
    end

    it "puts the right button on paddle B's line" do
      cycle_to(:paddles2)
      controls.mouse_button(3, true)
      expect(ports.device2.port_bits & 0x1f).to eq(0b10111)
    end

    it "releases the button" do
      cycle_to(:mouse1)
      controls.mouse_button(1, true)
      controls.mouse_button(1, false)
      expect(ports.device1.port_bits & 0x1f).to eq(0x1f)
    end

    it "ignores the middle button" do
      cycle_to(:mouse1)
      controls.mouse_button(2, true)
      expect(ports.device1.port_bits & 0x1f).to eq(0x1f)
    end
  end

  describe "#key" do
    it "types on the keyboard in keyboard mode" do
      expect { controls.key(4, true) }.to(change { computer.keyboard.scan(0x00, 0xff) })
    end

    it "drives joystick 2 with the arrows in joystick mode" do
      cycle_to(:joystick)
      controls.key(82, true)
      expect(computer.joystick2.port_bits & 0x1f).to eq(0b11110)
    end

    it "types shifted cursor up with the up arrow in keyboard mode" do
      controls.key(82, true)
      expect(computer.keyboard.keys).to eq([:cursor_up])
    end

    it "presses RESTORE with Page Up in a pot device mode" do
      cycle_to(:mouse1)
      allow(computer).to receive(:press_restore)
      controls.key(75, true)
      expect(computer).to have_received(:press_restore)
    end
  end

  describe "#computer=" do
    let(:other) { Badline::Computer.new }

    it "puts the mode's device in the other machine's port" do
      cycle_to(:paddles2)
      controls.computer = other
      expect(other.control_ports.device2.class).to eq(Badline::Input::Paddles)
    end

    it "sends the keys to the other machine" do
      allow(other).to receive(:press_restore)
      controls.computer = other
      controls.key(75, true)
      expect(other).to have_received(:press_restore)
    end
  end
end
