# frozen_string_literal: true

require "spec_helper"
require "badline/gui"
require_relative "../../support/fake_sink"

describe Badline::GUI::Application do
  let(:computer) { Badline::Computer.new }
  let(:window) do
    instance_double(
      Badline::GUI::Window,
      refresh_rate: Badline::GUI::Application::PAL_CLOCK_HZ, draw: nil, "title=": nil
    )
  end
  let(:gamepads) { instance_double(Badline::GUI::Gamepads, names: [], poll: nil, close: nil) }
  let(:ports) { computer.control_ports }

  before do
    allow(Badline::Computer).to receive(:new).and_return(computer)
    allow(Badline::GUI::Window).to receive(:new).and_return(window)
    allow(Badline::GUI::Gamepads).to receive(:new).and_return(gamepads)
    allow(SDL2::Mouse).to receive(:relative_mode=)
    allow($stdout).to receive(:puts)
  end

  def tab
    SDL2::Event::KeyDown.new.tap do |event|
      event.sym = SDL2::Key::TAB
      event.mod = 0
    end
  end

  def mouse_down(button) = SDL2::Event::MouseButtonDown.new.tap { |event| event.button = button }

  # Tab steps keyboard, joystick, mouse 1, mouse 2, paddles 1, paddles 2.
  def run_with(tabs:, button:)
    events = Array.new(tabs) { tab } + [mouse_down(button), SDL2::Event::Quit.new]
    allow(SDL2::Event).to receive(:poll) { events.shift }
    described_class.new.run
  end

  describe "the SID model" do
    it "fits the machine with the one asked for" do
      described_class.new(sid_model: :mos8580)
      expect(Badline::Computer).to have_received(:new).with(sid_model: :mos8580)
    end

    it "fits a 6581 by default" do
      described_class.new
      expect(Badline::Computer).to have_received(:new).with(sid_model: :mos6581)
    end
  end

  describe "a mouse button in paddle mode" do
    it "fires paddle A on port 1 with the left button" do
      run_with(tabs: 4, button: 1)
      expect(ports.read_b(0xff, 0xff)).to eq(0b11111011)
    end

    it "fires paddle B on port 1 with the right button" do
      run_with(tabs: 4, button: 3)
      expect(ports.read_b(0xff, 0xff)).to eq(0b11110111)
    end

    it "fires paddle A on port 2 with the left button" do
      run_with(tabs: 5, button: 1)
      expect(ports.read_a(0xff, 0xff)).to eq(0b11111011)
    end

    it "fires paddle B on port 2 with the right button" do
      run_with(tabs: 5, button: 3)
      expect(ports.read_a(0xff, 0xff)).to eq(0b11110111)
    end
  end

  describe "sound" do
    let(:sink) { FakeSink.new(rate: 44_100) }

    before do
      allow(Badline::Audio::SDLSink).to receive(:new).and_return(sink)
      allow(window).to receive(:refresh_rate).and_return(50)
    end

    def key_down(sym) = SDL2::Event::KeyDown.new.tap { |event| event.sym = sym }

    # One frame per event, and one more for the quit.
    def run_sound(*events, sound: true)
      events += [SDL2::Event::Quit.new]
      allow(SDL2::Event).to receive(:poll) { events.shift }
      described_class.new(sound:).tap(&:run)
    end

    it "opens no audio device by default" do
      run_sound(sound: false)
      expect(Badline::Audio::SDLSink).not_to have_received(:new)
    end

    it "leaves the SID unsynthesized by default" do
      run_sound(sound: false)
      expect(computer.sid.synthesizing?).to be(false)
    end

    it "queues a frame of the SID's output" do
      run_sound
      expect(sink.queued).to be_within(1).of(44_100 / 50)
    end

    it "closes the device on quit" do
      run_sound
      expect(sink.closed?).to be(true)
    end

    it "mutes with F10" do
      run_sound(key_down(SDL2::Key::F10))
      expect(sink.queued).to eq(0)
    end

    it "shows the mute in the title" do
      run_sound(key_down(SDL2::Key::F10))
      expect(window).to have_received(:title=).with("Badline [MUTED]")
    end

    context "when the device won't open" do
      before do
        allow(Badline::Audio::SDLSink).to receive(:new).and_raise(Badline::Audio::SDLSink::Error, "no device")
        allow(Warning).to receive(:warn)
      end

      it "says so" do
        run_sound
        expect(Warning).to have_received(:warn).with(/can't open the audio device: no device/, anything)
      end

      it "runs without sound" do
        run_sound
        expect(computer.sid.synthesizing?).to be(false)
      end
    end
  end

  describe "a mouse button in 1351 mode" do
    it "puts the left button on the fire line" do
      run_with(tabs: 2, button: 1)
      expect(ports.read_b(0xff, 0xff)).to eq(0b11101111)
    end
  end
end
