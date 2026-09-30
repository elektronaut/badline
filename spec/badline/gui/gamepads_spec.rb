# frozen_string_literal: true

require "spec_helper"
require "badline/gui"

describe Badline::GUI::Gamepads do
  subject(:gamepads) { described_class.new(computer) }

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

  it "names the controllers it opened" do
    expect(gamepads.names).to eq(["Pad"])
  end

  it "steers joystick 2 with the d-pad" do
    buttons << described_class::BUTTON_DPAD_UP
    gamepads.poll
    expect(port2).to eq(0b11110)
  end

  it "fires with a face button" do
    buttons << described_class::BUTTON_A
    gamepads.poll
    expect(port2).to eq(0b01111)
  end

  it "steers with the left stick past the deadzone" do
    axes[described_class::AXIS_LEFTX] = -20_000
    gamepads.poll
    expect(port2).to eq(0b11011)
  end

  it "ignores the stick inside the deadzone" do
    axes[described_class::AXIS_LEFTX] = -2_000
    gamepads.poll
    expect(port2).to eq(0b11111)
  end

  it "lets go of a direction once released" do
    buttons << described_class::BUTTON_DPAD_UP
    gamepads.poll
    buttons.clear
    gamepads.poll
    expect(port2).to eq(0b11111)
  end

  it "closes the controllers it opened" do
    gamepads.close
    expect(sdl).to have_received(:SDL_GameControllerClose).with(controller)
  end

  it "skips a device that isn't a game controller" do
    allow(sdl).to receive(:SDL_IsGameController).and_return(0)
    expect(gamepads.names).to be_empty
  end

  it "steers another machine's joystick once wired to it" do
    other = Badline::Computer.new
    gamepads.computer = other
    buttons << described_class::BUTTON_A
    gamepads.poll
    expect(other.control_ports.read_a(0xff, 0xff) & 0x1f).to eq(0b01111)
  end
end
