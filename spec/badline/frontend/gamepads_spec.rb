# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::Gamepads do
  subject(:gamepads) { described_class.new(computer, false).tap(&:rescan) }

  let(:sdl) { Badline::SDL }
  let(:computer) { Badline::Computer.new }
  let(:controller) { Fiddle::Pointer.new(0x1000) }
  let(:buttons) { [] }
  let(:axes) { Hash.new(0) }

  before do
    allow(sdl).to receive_messages(SDL_InitSubSystem: 0, SDL_NumJoysticks: 1, SDL_IsGameController: 1,
                                   SDL_GameControllerOpen: controller, SDL_GameControllerName: "Pad")
    allow(sdl).to receive(:SDL_GameControllerClose)
    allow(sdl).to receive(:SDL_GameControllerGetButton) { |_, button| buttons.include?(button) ? 1 : 0 }
    allow(sdl).to receive(:SDL_GameControllerGetAxis) { |_, axis| axes[axis] }
  end

  # Joystick 2 sits on CIA 1 port A, low bits clear while pressed.
  def port2 = computer.control_ports.read_a(0xff, 0xff) & 0x1f

  it "steers joystick 2 with the D-pad" do
    buttons << 11
    gamepads.poll
    expect(port2).to eq(0b11110)
  end

  it "fires with a face button" do
    buttons << 0
    gamepads.poll
    expect(port2).to eq(0b01111)
  end

  it "steers with the left stick past the deadzone" do
    axes[Badline::Frontend::PadPort::LEFT_X] = -20_000
    gamepads.poll
    expect(port2).to eq(0b11011)
  end

  it "lets go of a direction once released" do
    buttons << 11
    gamepads.poll
    buttons.clear
    gamepads.poll
    expect(port2).to eq(0b11111)
  end

  it "drives joystick 1 with a second controller" do
    allow(sdl).to receive(:SDL_NumJoysticks).and_return(2)
    buttons << 0
    gamepads.poll
    expect(computer.control_ports.read_b(0xff, 0xff) & 0x1f).to eq(0b01111)
  end

  it "closes the controllers it opened" do
    gamepads.close
    expect(sdl).to have_received(:SDL_GameControllerClose).with(controller)
  end

  it "skips a device that isn't a game controller" do
    allow(sdl).to receive(:SDL_IsGameController).and_return(0)
    gamepads.poll
    expect(sdl).not_to have_received(:SDL_GameControllerOpen)
  end

  it "skips a controller that won't open" do
    allow(sdl).to receive(:SDL_GameControllerOpen).and_return(nil)
    expect { gamepads.poll }.not_to raise_error
  end

  it "names the controllers it opens with verbose" do
    expect { described_class.new(computer, true).rescan }.to output(/Gamepad on joystick 2: Pad/).to_stdout
  end

  it "does nothing when SDL has no controller support" do
    allow(sdl).to receive(:SDL_InitSubSystem).and_return(-1)
    gamepads.poll
    expect(sdl).not_to have_received(:SDL_GameControllerOpen)
  end

  it "steers another machine's joystick once wired to it" do
    other = Badline::Computer.new
    gamepads.computer = other
    buttons << 0
    gamepads.poll
    expect(other.control_ports.read_a(0xff, 0xff) & 0x1f).to eq(0b01111)
  end
end
