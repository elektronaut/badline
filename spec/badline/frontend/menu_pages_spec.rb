# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"

describe Badline::Frontend::MenuPages do
  subject(:pages) { described_class.new(nil, nil, "", Badline::Options.parse([]), nil) }

  let(:computer) { Badline::C64.new }
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
      expect(painter).to have_received(:text).with(0, 42, "8K", anything)
    end

    it "shows the cartridge on the expansion port" do
      pages.draw(:expansion, 0, 0)
      expect(painter).to have_received(:text).with(0, 0, "CARTRIDGE", anything)
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

  describe "with a PET" do
    subject(:pages) { described_class.new(painter, buttons, "", Badline::Options.parse([]), nil) }

    let(:computer) { Badline::PET.new(model: "3032") }
    let(:painter) { instance_double(Badline::Frontend::Painter, text: 0) }
    let(:buttons) { instance_double(Badline::Frontend::Buttons, row: nil, toggle: nil) }

    it "names its keyboard on the ports page" do
      pages.draw(:ports, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "GRAPHICS", anything)
    end

    it "says where RUN/STOP is" do
      pages.draw(:ports, 0, 0)
      expect(painter).to have_received(:text).with(0, anything, "ESC: RUN/STOP", anything)
    end

    it "says Alt types the graphics on the symbol keys" do
      pages.draw(:ports, 0, 0)
      expect(painter).to have_received(:text).with(0, anything, "ALT+SYMBOL: GRAPHIC", anything)
    end

    it "offers no joysticks" do
      pages.draw(:ports, 0, 0)
      expect(buttons).not_to have_received(:toggle)
    end

    it "names its model, RAM and frame rate on the power page" do
      pages.draw(:power, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "3032, 32K RAM, 60 HZ", anything)
    end

    it "shows its RAM on the expansion page" do
      pages.draw(:expansion, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "32K", anything)
    end

    it "offers no cartridge on the expansion page" do
      pages.draw(:expansion, 0, 0)
      expect(buttons).not_to have_received(:row)
    end

    context "with the business keyboard" do
      let(:computer) { Badline::PET.new(model: "8032") }

      it "says where REPEAT is" do
        pages.draw(:ports, 0, 0)
        expect(painter).to have_received(:text).with(0, anything, "PAGE UP: REPEAT", anything)
      end

      it "says Alt adds SHIFT" do
        pages.draw(:ports, 0, 0)
        expect(painter).to have_received(:text).with(0, anything, "ALT+KEY: SHIFT+KEY", anything)
      end
    end

    context "with an 8296" do
      let(:computer) { Badline::PET.new(model: "8296", jumpers: %w[ram9 rama]) }

      it "names all 128K on the power page" do
        pages.draw(:power, 0, 0)
        expect(painter).to have_received(:text).with(0, 12, "8296, 128K RAM, 50 HZ", anything)
      end

      it "names its jumpers on the expansion page" do
        pages.draw(:expansion, 0, 0)
        expect(painter).to have_received(:text).with(0, anything, "RAM9, RAMA", anything)
      end
    end
  end

  describe "with a CBM-II" do
    subject(:pages) { described_class.new(painter, buttons, "", Badline::Options.parse([]), nil) }

    let(:computer) { Badline::CBM2.new(model: "720", kernal: "03b", mains_hz: 60) }
    let(:painter) { instance_double(Badline::Frontend::Painter, text: 0) }
    let(:buttons) { instance_double(Badline::Frontend::Buttons, row: nil, toggle: nil) }

    it "names its model, RAM and mains on the power page" do
      pages.draw(:power, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "720, 256K RAM, 60 HZ", anything)
    end

    it "names its KERNAL on the power page" do
      pages.draw(:power, 0, 0)
      expect(painter).to have_received(:text).with(0, anything, "901244-03B", anything)
    end

    it "says where RUN/STOP is" do
      pages.draw(:ports, 0, 0)
      expect(painter).to have_received(:text).with(0, anything, "F12: RUN/STOP", anything)
    end

    it "says where NORM/GRAPH is" do
      pages.draw(:ports, 0, 0)
      expect(painter).to have_received(:text).with(0, anything, "ALT+G: NORM/GRAPH", anything)
    end

    it "offers no joysticks" do
      pages.draw(:ports, 0, 0)
      expect(buttons).not_to have_received(:toggle)
    end

    it "shows its RAM on the expansion page" do
      pages.draw(:expansion, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "256K", anything)
    end

    it "shows no tape and offers none on the datasette page" do
      pages.draw(:datasette, 0, 0)
      expect(buttons).not_to have_received(:row)
    end
  end

  describe "with a Plus/4" do
    subject(:pages) { described_class.new(painter, buttons, "", Badline::Options.parse([]), nil) }

    let(:computer) { Badline::Plus4.new }
    let(:controls) { Badline::Frontend::Controls.new(computer) }
    let(:painter) { instance_double(Badline::Frontend::Painter, text: 0) }
    let(:buttons) { instance_double(Badline::Frontend::Buttons, row: nil, toggle: nil) }
    let(:sound) { instance_double(Badline::Frontend::Sound, on?: true, muted?: false) }

    it "names its keyboard on the keys' toggle" do
      pages.draw(:ports, 0, 0)
      expect(buttons).to have_received(:toggle).with(anything, "KEYS", :keys, [%w[PLUS/4 JOYSTICK], anything, 0])
    end

    it "offers no mouse or paddles" do
      pages.draw(:ports, 0, 0)
      expect(buttons).to have_received(:toggle).once
    end

    it "names the joystick each set of keys drives" do
      pages.perform(:keys_joystick)
      pages.perform(:swap)
      pages.draw(:ports, 0, 0)
      expect(painter).to have_received(:text).with(0, anything, "JOYSTICK 1", anything)
    end

    it "swaps the joysticks the keys drive" do
      pages.perform(:keys_joystick)
      pages.perform(:swap)
      expect(controls.arrows_port).to eq(1)
    end

    it "leaves the SID's model out of the sound" do
      pages.draw(:sound, 0, 0)
      expect(buttons).to have_received(:toggle).once
    end

    it "names its model and RAM on the power page" do
      pages.draw(:power, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "PLUS/4 PAL, 64K RAM", anything)
    end

    it "names no RAM expansion without one" do
      pages.draw(:power, 0, 0)
      expect(painter).not_to have_received(:text).with(anything, anything, "RAM EXPANSION", anything)
    end

    context "with a RAM expansion" do
      let(:computer) { Badline::Plus4.new(ram_expansion: :hannes256) }

      it "names it on the power page" do
        pages.draw(:power, 0, 0)
        expect(painter).to have_received(:text).with(anything, anything, "HANNES, 256 KB", anything)
      end
    end

    context "with a SID card" do
      let(:computer) { Badline::Plus4.new(sid_card: :mos6581) }

      it "offers the card's SID model on the sound page" do
        pages.draw(:sound, 0, 0)
        expect(buttons).to have_received(:toggle).with(anything, "SID CARD", :sid, [%w[6581 8580], anything, 0])
      end

      it "swaps the card's SID model" do
        pages.perform(:sid8580)
        expect(computer.sid_card.model).to eq(:mos8580)
      end
    end

    it "names the cartridge slots filled on the expansion port" do
      computer.attach_cartridge([Badline::Storage::CRTFile::Chip.new(0, 0, 0x8000, [0x11])])
      pages.draw(:expansion, 0, 0)
      expect(painter).to have_received(:text).with(0, 12, "C1LO", anything)
    end

    it "offers no freezer or REU on the expansion port" do
      pages.draw(:expansion, 0, 0)
      expect(buttons).to have_received(:row).twice
    end
  end
end
