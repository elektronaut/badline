# frozen_string_literal: true

require "spec_helper"
require "badline/gui"

describe Badline::GUI::Event do
  let(:sdl) { Badline::SDL }

  # SDL_Event's leading type, timestamp and window id, then the rest.
  def raw_event(type, rest = "")
    [type, 0, 1].pack("L3").concat(rest.b).ljust(56, "\0")
  end

  def push(*events)
    events.each { |event| sdl.SDL_PushEvent(event) }
  end

  # state, repeat, two bytes of padding, then the keysym: scancode, sym, mod.
  def key_event(type, sym, mod, repeat: 0) = raw_event(type, [1, repeat, 0, 0, 0, sym, mod].pack("C4l2S"))

  before { Badline::GUI::SDLError.check(sdl.SDL_InitSubSystem(sdl::INIT_EVENTS)) }

  after do
    nil while described_class.poll
    sdl.SDL_QuitSubSystem(sdl::INIT_EVENTS)
  end

  describe ".poll" do
    it "returns nil once the queue is empty" do
      expect(described_class.poll).to be_nil
    end

    it "reads a quit" do
      push(raw_event(0x100))
      expect(described_class.poll).to eq(described_class::Quit.new)
    end

    it "reads a key going down with its modifiers" do
      push(key_event(0x300, sdl::KEY_TAB, sdl::KMOD_SHIFT))
      expect(described_class.poll).to eq(described_class::KeyDown.new(sym: sdl::KEY_TAB, mod: sdl::KMOD_SHIFT))
    end

    it "flags a key repeat" do
      push(key_event(0x300, sdl::KEY_TAB, 0, repeat: 1))
      expect(described_class.poll.repeat).to be(true)
    end

    it "reads a key going up" do
      push(key_event(0x301, sdl::KEY_F10, 0))
      expect(described_class.poll).to eq(described_class::KeyUp.new(sym: sdl::KEY_F10, mod: 0))
    end

    it "reads the mouse's relative motion" do
      # which, state, x, y, then xrel and yrel.
      push(raw_event(0x400, [0, 0, 10, 20, -3, 5].pack("L2l4")))
      expect(described_class.poll).to eq(described_class::MouseMotion.new(xrel: -3, yrel: 5))
    end

    it "reads a mouse button going down" do
      # which, then button and state.
      push(raw_event(0x401, [0, 3, 1].pack("LC2")))
      expect(described_class.poll).to eq(described_class::MouseButton.new(button: 3, pressed: true))
    end

    it "reads a mouse button going up" do
      push(raw_event(0x402, [0, 1, 0].pack("LC2")))
      expect(described_class.poll).to eq(described_class::MouseButton.new(button: 1, pressed: false))
    end

    it "reads a controller arriving" do
      push(raw_event(0x653))
      expect(described_class.poll).to eq(described_class::ControllerDevice.new)
    end

    it "skips the events the front end doesn't handle" do
      push(raw_event(0x8000), raw_event(0x100))
      expect(described_class.poll).to eq(described_class::Quit.new)
    end
  end

  describe ".key_name" do
    it "names a key the way SDL does" do
      expect(described_class.key_name(sdl::KEY_F10)).to eq("F10")
    end
  end
end
