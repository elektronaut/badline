# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Controls do
  subject(:controls) { described_class.new(computer) }

  let(:computer) { Badline::Computer.new }
  let(:ports) { computer.control_ports }

  describe "#toggle_keys" do
    it "switches the keys between the keyboard and the joysticks" do
      states = Array.new(3) { controls.toggle_keys.then { controls.joystick_mode? } }
      expect(states).to eq([true, false, true])
    end

    it "leaves the pot device plugged in" do
      controls.plug(:mouse1)
      controls.toggle_keys
      expect(ports.device1.class).to eq(Badline::Input::Mouse1351)
    end
  end

  describe "#plug" do
    it "puts a 1351 mouse on port 1" do
      controls.plug(:mouse1)
      expect([ports.device1.class, ports.device2]).to eq([Badline::Input::Mouse1351, nil])
    end

    it "puts paddles on port 2" do
      controls.plug(:paddles2)
      expect([ports.device1, ports.device2.class]).to eq([nil, Badline::Input::Paddles])
    end

    it "takes the device away with :none" do
      controls.plug(:paddles2)
      controls.plug(:none)
      expect([ports.device1, ports.device2]).to eq([nil, nil])
    end
  end

  describe "#tag" do
    it "is empty for the keyboard" do
      expect(controls.tag).to eq("")
    end

    it "names the port the arrows drive in joystick mode" do
      controls.toggle_keys
      controls.swap_ports
      expect(controls.tag).to eq("JOY 1")
    end

    it "names the pot device and its port" do
      controls.plug(:paddles1)
      expect(controls.tag).to eq("PADDLE 1")
    end
  end

  describe "#tag with both" do
    it "names the joystick and the pot device" do
      controls.toggle_keys
      controls.plug(:mouse1)
      expect(controls.tag).to eq("JOY 2, MOUSE 1")
    end
  end

  describe "#pot_device?" do
    it "is false for the keyboard and the joysticks" do
      states = Array.new(2) { controls.pot_device?.tap { controls.toggle_keys } }
      expect(states).to eq([false, false])
    end

    it "is true for a mouse" do
      controls.plug(:mouse2)
      expect(controls.pot_device?).to be(true)
    end
  end

  describe "#mouse_motion" do
    it "moves the 1351's counters" do
      controls.plug(:mouse2)
      controls.mouse_motion(6, 4)
      expect([ports.device2.pot_x, ports.device2.pot_y]).to eq([6, 0x7c])
    end

    it "turns the paddles" do
      controls.plug(:paddles1)
      controls.mouse_motion(20, -10)
      expect([ports.device1.pot_x, ports.device1.pot_y]).to eq([0x8a, 0x7b])
    end

    it "does nothing without a pot device" do
      expect { controls.mouse_motion(10, 10) }.not_to raise_error
    end
  end

  describe "#mouse_button" do
    it "puts the 1351's left button on the fire line" do
      controls.plug(:mouse1)
      controls.mouse_button(1, true)
      expect(ports.device1.port_bits & 0x1f).to eq(0b01111)
    end

    it "puts the right button on paddle B's line" do
      controls.plug(:paddles2)
      controls.mouse_button(3, true)
      expect(ports.device2.port_bits & 0x1f).to eq(0b10111)
    end

    it "releases the button" do
      controls.plug(:mouse1)
      controls.mouse_button(1, true)
      controls.mouse_button(1, false)
      expect(ports.device1.port_bits & 0x1f).to eq(0x1f)
    end

    it "ignores the middle button" do
      controls.plug(:mouse1)
      controls.mouse_button(2, true)
      expect(ports.device1.port_bits & 0x1f).to eq(0x1f)
    end
  end

  describe "#key" do
    it "types on the keyboard in keyboard mode" do
      expect { controls.key(4, true) }.to(change { computer.keyboard.scan(0x00, 0xff) })
    end

    it "drives joystick 2 with the arrows in joystick mode" do
      controls.toggle_keys
      controls.key(82, true)
      expect(computer.joystick2.port_bits & 0x1f).to eq(0b11110)
    end

    it "types shifted cursor up with the up arrow in keyboard mode" do
      controls.key(82, true)
      expect(computer.keyboard.keys).to eq([:cursor_up])
    end

    it "presses RESTORE with Page Up with a pot device plugged in" do
      controls.plug(:mouse1)
      allow(computer).to receive(:press_restore)
      controls.key(75, true)
      expect(computer).to have_received(:press_restore)
    end
  end

  describe "with a VIC-20" do
    let(:computer) { Badline::Vic20.new }

    it "drives its one joystick with the arrows" do
      controls.toggle_keys
      controls.key(82, true)
      expect(computer.joystick1.port_bits & 0x1f).to eq(0b11110)
    end

    it "drives its one joystick with WASD too" do
      controls.toggle_keys
      controls.key(7, true)
      expect(computer.joystick1.port_bits & 0x1f).to eq(0b10111)
    end

    it "names the joystick without a port" do
      controls.toggle_keys
      expect(controls.tag).to eq("JOY")
    end

    it "lets go of RESTORE as the key comes up" do
      allow(computer).to receive(:release_restore)
      controls.key(75, false)
      expect(computer).to have_received(:release_restore)
    end

    it "plugs no pot device in" do
      controls.plug(:mouse1)
      expect([controls.pot, controls.pot_device?]).to eq([:none, false])
    end
  end

  describe "with a C128" do
    let(:computer) { Badline::C128.new }

    {
      "the keypad's 7" => [95, :keypad7], "the keypad's Enter" => [88, :keypad_enter], "Insert" => [73, :help],
      "the right Alt" => [230, :alt], "Scroll Lock" => [71, :no_scroll], "Esc" => [41, :run_stop],
      "Page Down" => [78, :run_stop], "the up arrow" => [82, :cursor_up]
    }.each do |name, (scancode, key)|
      it "presses #{key} for #{name}" do
        controls.key(scancode, true)
        expect(computer.keyboard.keys).to eq([key])
      end
    end

    it "locks CAPS LOCK down with Caps Lock, holding P6 low" do
      controls.key(57, true)
      expect(computer.address_bus.peek(0x01).anybits?(0x40)).to be(false)
    end

    it "lets CAPS LOCK up as Caps Lock comes up" do
      controls.key(57, true)
      controls.key(57, false)
      expect(computer.address_bus.caps_lock).to be(false)
    end

    it "locks 40/80 DISPLAY down with Pause" do
      controls.key(72, true)
      expect(computer.mmu.display_key).to be(true)
    end

    it "locks 40/80 DISPLAY down with F6" do
      controls.key(63, true)
      expect(computer.mmu.display_key).to be(true)
    end

    context "when in C128 mode" do
      let(:computer) { Badline::C128.new(mode: :c128) }

      it "presses ESC for Esc" do
        controls.key(41, true)
        expect(computer.keyboard.keys).to eq([:esc])
      end

      it "presses RUN/STOP for Page Down" do
        controls.key(78, true)
        expect(computer.keyboard.keys).to eq([:run_stop])
      end
    end
  end

  describe "#computer=" do
    let(:other) { Badline::Computer.new }

    it "puts the pot device in the other machine's port" do
      controls.plug(:paddles2)
      controls.computer = other
      expect(other.control_ports.device2.class).to eq(Badline::Input::Paddles)
    end

    it "takes the pot device out for a VIC-20" do
      controls.plug(:paddles2)
      controls.computer = Badline::Vic20.new
      expect(controls.pot).to eq(:none)
    end

    it "sends the keys to the other machine" do
      allow(other).to receive(:press_restore)
      controls.computer = other
      controls.key(75, true)
      expect(other).to have_received(:press_restore)
    end
  end
end
