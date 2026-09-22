# frozen_string_literal: true

require "spec_helper"
require "badline/gui"

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
      expect(Badline::Computer).to have_received(:new).with(debug: false, sid_model: :mos8580)
    end

    it "fits a 6581 by default" do
      described_class.new
      expect(Badline::Computer).to have_received(:new).with(debug: false, sid_model: :mos6581)
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

  describe "a mouse button in 1351 mode" do
    it "puts the left button on the fire line" do
      run_with(tabs: 2, button: 1)
      expect(ports.read_b(0xff, 0xff)).to eq(0b11101111)
    end
  end
end
