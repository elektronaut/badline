# frozen_string_literal: true

require "spec_helper"
require "badline/sdl"

describe Badline::SDL do
  # SDL_Event's leading type, timestamp and window id, then the rest.
  def raw_event(type, rest = "")
    [type, 0, 1].pack("L3").concat(rest.b).ljust(described_class::EVENT_SIZE, "\0")
  end

  def push(*events)
    events.each { |event| described_class::PushEvent.call(event) }
  end

  # state, repeat, two bytes of padding, then the keysym: scancode, sym, mod.
  def key_event(type, sym, mod, repeat: 0) = raw_event(type, [1, repeat, 0, 0, 0, sym, mod].pack("C4l2S"))

  before { described_class.check(described_class::InitSubSystem.call(described_class::INIT_EVENTS)) }

  after do
    nil while described_class.poll_event
    described_class::QuitSubSystem.call(described_class::INIT_EVENTS)
  end

  describe ".poll_event" do
    it "returns nil once the queue is empty" do
      expect(described_class.poll_event).to be_nil
    end

    it "reads a quit" do
      push(raw_event(0x100))
      expect(described_class.poll_event).to eq(described_class::Quit.new)
    end

    it "reads a key going down with its modifiers" do
      push(key_event(0x300, described_class::KEY_TAB, described_class::KMOD_SHIFT))
      expect(described_class.poll_event)
        .to eq(described_class::KeyDown.new(sym: described_class::KEY_TAB, mod: described_class::KMOD_SHIFT))
    end

    it "flags a key repeat" do
      push(key_event(0x300, described_class::KEY_TAB, 0, repeat: 1))
      expect(described_class.poll_event.repeat).to be(true)
    end

    it "reads a key going up" do
      push(key_event(0x301, described_class::KEY_F10, 0))
      expect(described_class.poll_event).to eq(described_class::KeyUp.new(sym: described_class::KEY_F10, mod: 0))
    end

    it "reads the mouse's relative motion" do
      # which, state, x, y, then xrel and yrel.
      push(raw_event(0x400, [0, 0, 10, 20, -3, 5].pack("L2l4")))
      expect(described_class.poll_event).to eq(described_class::MouseMotion.new(xrel: -3, yrel: 5))
    end

    it "reads a mouse button going down" do
      # which, then button and state.
      push(raw_event(0x401, [0, 3, 1].pack("LC2")))
      expect(described_class.poll_event).to eq(described_class::MouseButton.new(button: 3, pressed: true))
    end

    it "reads a mouse button going up" do
      push(raw_event(0x402, [0, 1, 0].pack("LC2")))
      expect(described_class.poll_event).to eq(described_class::MouseButton.new(button: 1, pressed: false))
    end

    it "reads a controller arriving" do
      push(raw_event(0x653))
      expect(described_class.poll_event).to eq(described_class::ControllerDevice.new)
    end

    it "skips the events the front end doesn't handle" do
      push(raw_event(0x8000), raw_event(0x100))
      expect(described_class.poll_event).to eq(described_class::Quit.new)
    end
  end

  describe ".key_name" do
    it "names a key the way SDL does" do
      expect(described_class.key_name(described_class::KEY_F10)).to eq("F10")
    end
  end

  describe ".check" do
    it "passes a non-negative result through" do
      expect(described_class.check(3)).to eq(3)
    end

    it "raises SDL's reason for a negative one" do
      described_class::SetRelativeMouseMode.call(1) # no video, so this fails and sets the error
      expect { described_class.check(-1) }.to raise_error(described_class::Error, /\S/)
    end
  end

  describe ".check_pointer" do
    it "raises for a null handle" do
      expect { described_class.check_pointer(Fiddle::Pointer.new(0)) }.to raise_error(described_class::Error)
    end
  end
end
