# frozen_string_literal: true

require "spec_helper"
require "badline/gui"
require_relative "../../support/fake_sink"

describe Badline::GUI::Application do
  let(:computer) { Badline::Computer.new }
  let(:window) do
    instance_double(
      Badline::GUI::Window,
      refresh_rate: Badline::Region::PAL.clock_hz, draw: nil, "title=": nil, close: nil
    )
  end
  let(:gamepads) { instance_double(Badline::GUI::Gamepads, names: [], poll: nil, close: nil, "computer=": nil) }
  let(:ports) { computer.control_ports }

  before do
    allow(Badline::Computer).to receive(:new).and_return(computer)
    allow(Badline::GUI::Window).to receive(:new).and_return(window)
    allow(Badline::GUI::Gamepads).to receive(:new).and_return(gamepads)
    allow(Badline::SDL::SetRelativeMouseMode).to receive(:call)
    allow($stdout).to receive(:puts)
  end

  def tab
    Badline::SDL::KeyDown.new(sym: Badline::SDL::KEY_TAB, mod: 0)
  end

  def mouse_down(button) = Badline::SDL::MouseButton.new(button:, pressed: true)

  # Tab steps keyboard, joystick, mouse 1, mouse 2, paddles 1, paddles 2.
  def run_with(tabs:, button:)
    events = Array.new(tabs) { tab } + [mouse_down(button), Badline::SDL::Quit.new]
    allow(Badline::SDL).to receive(:poll_event) { events.shift }
    described_class.new.run
  end

  describe "the SID model" do
    it "fits the machine with the one asked for" do
      described_class.new(machine: { sid_model: :mos8580 })
      expect(Badline::Computer).to have_received(:new).with(sid_model: :mos8580)
    end

    it "fits a 6581 by default" do
      described_class.new
      expect(Badline::Computer).to have_received(:new).with(sid_model: :mos6581)
    end
  end

  describe "the REU" do
    it "fits the machine with one of the size asked for" do
      described_class.new(machine: { reu: 256 })
      expect(Badline::Computer).to have_received(:new).with(sid_model: :mos6581, reu: 256)
    end
  end

  describe "the true drive" do
    it "plugs a 1541 in as device 8" do
      described_class.new(machine: { true_drive: true })
      expect(computer.drive1541.device).to eq(8)
    end

    it "draws its LED over the screen" do
      allow(Badline::SDL).to receive(:poll_event).and_return(Badline::SDL::Quit.new, nil)
      described_class.new(machine: { true_drive: true }).run
      expect(window).to have_received(:draw)
        .with([instance_of(Badline::GUI::ScreenPane), instance_of(Badline::GUI::DriveLedPane)])
    end

    it "draws no LED without one" do
      allow(Badline::SDL).to receive(:poll_event).and_return(Badline::SDL::Quit.new, nil)
      described_class.new.run
      expect(window).to have_received(:draw).with([instance_of(Badline::GUI::ScreenPane)])
    end
  end

  describe "the setup report" do
    let(:gamepads) { instance_double(Badline::GUI::Gamepads, names: ["Pad"], poll: nil, close: nil) }

    it "stays quiet by default" do
      described_class.new
      expect($stdout).not_to have_received(:puts)
    end

    it "names the display rate with verbose" do
      described_class.new(verbose: true)
      expect($stdout).to have_received(:puts).with(/\ADisplay \d+ Hz/)
    end

    it "names the gamepads with verbose" do
      described_class.new(verbose: true)
      expect($stdout).to have_received(:puts).with("Gamepad: Pad")
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

  describe "the host keyboard" do
    # SDL keycodes for keys KeyMap finds by name.
    def page_up = 0x4000_004b

    def up = 0x4000_0052

    def press(sym, repeat: false)
      events = [Badline::SDL::KeyDown.new(sym:, mod: 0, repeat:), Badline::SDL::Quit.new]
      allow(Badline::SDL).to receive(:poll_event) { events.shift }
      described_class.new.run
    end

    it "presses RESTORE with Page Up" do
      allow(computer).to receive(:press_restore)
      press(page_up)
      expect(computer).to have_received(:press_restore)
    end

    it "ignores Page Up's key repeats" do
      allow(computer).to receive(:press_restore)
      press(page_up, repeat: true)
      expect(computer).not_to have_received(:press_restore)
    end

    it "types cursor up with Up" do
      allow(computer).to receive(:cycle!)
      press(up)
      expect(computer.keyboard.keys).to eq([:cursor_up])
    end
  end

  describe "sound" do
    let(:sink) { FakeSink.new(rate: 44_100) }

    before do
      allow(Badline::Audio::SDLSink).to receive(:new).and_return(sink)
      allow(window).to receive(:refresh_rate).and_return(50)
    end

    def key_down(sym) = Badline::SDL::KeyDown.new(sym:, mod: 0)

    # One frame per event, and one more for the quit.
    def run_sound(*events, sound: true)
      events += [Badline::SDL::Quit.new]
      allow(Badline::SDL).to receive(:poll_event) { events.shift }
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

    it "paces the frames by the display without sound" do
      run_sound(sound: false)
      expect(Badline::GUI::Window).to have_received(:new).with(hash_including(vsync: true))
    end

    it "paces the frames by the audio device with sound" do
      run_sound
      expect(Badline::GUI::Window).to have_received(:new).with(hash_including(vsync: false))
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
      run_sound(key_down(Badline::SDL::KEY_F10))
      expect(sink.queued).to eq(0)
    end

    it "shows the mute in the title" do
      run_sound(key_down(Badline::SDL::KEY_F10))
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

      it "paces the frames by the display" do
        run_sound
        expect(Badline::GUI::Window).to have_received(:new).with(hash_including(vsync: true))
      end

      it "runs without sound" do
        run_sound
        expect(computer.sid.synthesizing?).to be(false)
      end
    end
  end

  describe "a mouse button let go in paddle mode" do
    it "releases paddle A on port 1" do
      release = Badline::SDL::MouseButton.new(button: 1, pressed: false)
      events = Array.new(4) { tab } + [mouse_down(1), release, Badline::SDL::Quit.new]
      allow(Badline::SDL).to receive(:poll_event) { events.shift }
      described_class.new.run
      expect(ports.read_b(0xff, 0xff)).to eq(0b11111111)
    end
  end

  describe "quitting" do
    it "closes the window" do
      run_with(tabs: 0, button: 1)
      expect(window).to have_received(:close)
    end

    it "stores what the 1541 wrote in its disk's image" do
      drive = instance_double(Badline::Drive1541, flush: nil)
      allow(computer).to receive(:drive1541).and_return(drive)
      run_with(tabs: 0, button: 1)
      expect(drive).to have_received(:flush)
    end
  end

  describe "snapshots" do
    def keys(*syms)
      events = syms.map { |sym| Badline::SDL::KeyDown.new(sym:, mod: 0) } + [Badline::SDL::Quit.new]
      allow(Badline::SDL).to receive(:poll_event) { events.shift }
      described_class.new.run
    end

    around { |example| Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } } }

    # A machine of its own, which Computer.new doesn't hand out.
    let(:restored) do
      allow(Badline::Computer).to receive(:new).and_call_original
      Badline::Computer.new.tap { allow(Badline::Computer).to receive(:new).and_return(computer) }
    end

    it "saves one with F11" do
      keys(Badline::SDL::KEY_F11)
      expect(Dir.glob("badline-*.vsf").length).to eq(1)
    end

    it "restores the one saved with F12" do
      allow(Badline::Snapshot).to receive(:load).and_return(restored)
      keys(Badline::SDL::KEY_F11, Badline::SDL::KEY_F12)
      expect(Badline::Snapshot).to have_received(:load).with(Dir.glob("badline-*.vsf").first)
    end

    it "runs the restored machine in place of the one before" do
      allow(Badline::Snapshot).to receive(:load).and_return(restored)
      keys(Badline::SDL::KEY_F11, Badline::SDL::KEY_F12)
      expect([restored.cycles, computer.cycles]).to eq([computer.region.clock_hz / window.refresh_rate, 0])
    end

    it "has nothing to restore before one is saved" do
      allow(Badline::Snapshot).to receive(:load)
      keys(Badline::SDL::KEY_F12)
      expect(Badline::Snapshot).not_to have_received(:load)
    end

    it "warns when it can't save" do
      allow(computer).to receive(:save_snapshot).and_raise(Errno::EACCES)
      expect { keys(Badline::SDL::KEY_F11) }.to output(/Permission denied/).to_stderr
    end

    it "warns when it can't restore, and runs on" do
      allow(Badline::Snapshot).to receive(:load).and_raise(Badline::Snapshot::FormatError, "damaged")
      expect { keys(Badline::SDL::KEY_F11, Badline::SDL::KEY_F12) }.to output(/damaged/).to_stderr
    end

    it "boots from a .vsf file" do
      allow(Badline::Snapshot).to receive(:load).and_return(computer)
      described_class.new(media_path: "game.vsf")
      expect(Badline::Snapshot).to have_received(:load).with("game.vsf")
    end
  end

  describe "a mouse button in 1351 mode" do
    it "puts the left button on the fire line" do
      run_with(tabs: 2, button: 1)
      expect(ports.read_b(0xff, 0xff)).to eq(0b11101111)
    end
  end
end
