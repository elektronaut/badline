# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::MenuPages do
  subject(:pages) { described_class.new(nil, nil, "", Badline::Options.parse([]), nil) }

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

  describe "with a C128" do
    subject(:pages) do
      options = Badline::Options.parse(["c128"])
      described_class.new(painter, buttons, "", options, Badline::Frontend::Snapshots.new(computer, options))
    end

    let(:computer) { Badline::C128.new(model: "c128dcr") }
    let(:painter) { instance_double(Badline::Frontend::Painter, text: 0) }
    let(:buttons) { instance_double(Badline::Frontend::Buttons, row: nil, toggle: nil) }

    before { pages.machine(computer, Badline::Frontend::Controls.new(computer), sound) }

    it "names the model and its mode on the power page" do
      pages.draw(:power, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "C128DCR, C64 MODE", anything)
    end

    it "names its keyboard on the keys' toggle" do
      pages.draw(:ports, 0, 0)
      expect(buttons).to have_received(:toggle).with(anything, "KEYS", :keys, [%w[C128 JOYSTICK], anything, 0])
    end

    it "powers it off and on" do
      computer.run_cycles(1_000)
      pages.perform(:power_cycle)
      expect(computer.cpu.program_counter).to eq(0xfce2)
    end
  end

  describe "with a VIC-20" do
    subject(:pages) do
      options = Badline::Options.parse(["vic20"])
      described_class.new(painter, buttons, "", options, Badline::Frontend::Snapshots.new(computer, options))
    end

    let(:computer) { Badline::Vic20.new(ram: :"8k") }
    let(:painter) { instance_double(Badline::Frontend::Painter, text: 0) }
    let(:buttons) { instance_double(Badline::Frontend::Buttons, row: nil, toggle: nil) }
    let(:sound) { instance_double(Badline::Frontend::Sound, on?: true, muted?: false) }

    before { pages.machine(computer, Badline::Frontend::Controls.new(computer), sound) }

    it "leaves the SID's model out of the sound" do
      pages.draw(:sound, 0, 0)
      expect(buttons).to have_received(:toggle).once
    end

    it "shows the RAM expansion on the expansion port" do
      pages.draw(:expansion, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "8K", anything)
    end

    it "names its keyboard on the keys' toggle" do
      pages.draw(:ports, 0, 0)
      expect(buttons).to have_received(:toggle).with(anything, "KEYS", :keys, [%w[VIC-20 JOYSTICK], anything, 0])
    end

    it "saves and loads snapshots" do
      pages.draw(:snapshots, 0, 0)
      expect(buttons).to have_received(:row).with(anything, "QUICKSAVE", :quicksave_now, anything)
    end
  end
end
