# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::MenuPages do
  subject(:pages) { described_class.new(nil, nil, "", Badline::Options.parse([])) }

  let(:computer) { Badline::Computer.new }
  let(:controls) { Badline::Frontend::Controls.new(computer) }
  let(:sound) { instance_double(Badline::Frontend::Sound, toggle_mute: nil, muted?: false) }

  before { pages.machine(computer, controls, sound) }

  it "plugs a mouse into the port picked" do
    pages.perform(:port2_mouse)
    expect(controls.pot).to eq(:mouse2)
  end

  it "leaves the other port's mouse in when a joystick is picked" do
    pages.perform(:port2_mouse)
    pages.perform(:port1_joystick)
    expect(controls.pot).to eq(:mouse2)
  end

  it "takes the mouse out when its port gets a joystick" do
    pages.perform(:port2_mouse)
    pages.perform(:port2_joystick)
    expect(controls.pot).to eq(:none)
  end

  it "sends the keys to the joysticks" do
    pages.perform(:keys_joystick)
    expect(controls.joystick_mode?).to be(true)
  end

  it "swaps the SID's model" do
    pages.perform(:sid8580)
    expect(computer.sid.model).to eq(:mos8580)
  end

  it "mutes the sound, and leaves it muted" do
    pages.perform(:mute)
    allow(sound).to receive(:muted?).and_return(true)
    pages.perform(:mute)
    expect(sound).to have_received(:toggle_mute).once
  end

  it "presses the datasette's PLAY" do
    pages.perform(:tape_down)
    expect(computer.datasette.playing?).to be(true)
  end
end
