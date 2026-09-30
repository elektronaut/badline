# frozen_string_literal: true

require "spec_helper"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/sdl_dummy_drivers"

# The window both builds run, on CRuby against SDL's dummy drivers.
describe Badline::Frontend::App do
  let(:sdl) { Badline::SDL }
  let(:computer) { Badline::Computer.new }
  let(:frame_cycles) { Badline::Region::PAL.cycles_per_line * Badline::Region::PAL.lines_per_frame }

  include_context "with SDL's dummy drivers"

  def options(*argv) = Badline::Options.parse(["--unpaced", *argv])

  # Opens the window, queues the events and runs until the frame limit or
  # a quit.
  def run(*events, argv: %w[--frames 2])
    app = described_class.new(computer, options(*argv))
    events.each { |event| sdl.SDL_PushEvent(event.ljust(56, "\0")) }
    app.run
  end

  # type, timestamp and window id, then the rest of the event.
  def event(type, rest = "") = [type, 0, 1].pack("L3") + rest.b

  # state, repeat and padding, then the keysym: scancode, sym and mod.
  def key(scancode, down: true, mod: 0)
    event(down ? sdl::KEYDOWN : sdl::KEYUP, [down ? 1 : 0, 0, 0, 0, scancode, 0, mod].pack("C4l2S"))
  end

  def tab = key(Badline::Frontend::Keys::TAB)

  it "quits after --frames" do
    run
    expect(computer.cycles).to eq(2 * frame_cycles)
  end

  it "quits when the window closes" do
    run(event(sdl::QUIT), argv: [])
    expect(computer.cycles).to eq(frame_cycles)
  end

  it "saves --screenshot's frame as a BMP" do
    run(argv: %w[--frames 2 --screenshot ready.bmp])
    expect(File.binread("ready.bmp", 2)).to eq("BM")
  end

  it "saves --save-snapshot after the last frame" do
    run(argv: %w[--frames 2 --save-snapshot ready.vsf])
    expect(Badline::Snapshot.load("ready.vsf").cycles).to eq(2 * frame_cycles)
  end

  describe "the timeline" do
    it "quits at --at's quit" do
      run(argv: %w[--frames 5 --at 1:quit])
      expect(computer.cycles).to eq(frame_cycles)
    end

    it "saves --at's screenshots, numbered by frame" do
      run(argv: %w[--frames 3 --at 1,2:screenshot=shot%d.bmp])
      expect(Dir.glob("shot*.bmp")).to eq(%w[shot1.bmp shot2.bmp])
    end

    it "presses --at's keys once their frame has run" do
      allow(computer.keyboard).to receive(:press)
      run(argv: %w[--frames 2 --at 1:key=q])
      expect(computer.keyboard).to have_received(:press).with(:q)
    end
  end

  it "types on the C64 keyboard" do
    allow(computer.keyboard).to receive(:press)
    run(key(4))
    expect(computer.keyboard).to have_received(:press).with(:a)
  end

  it "drives joystick 2 with the arrows in joystick mode" do
    run(tab, key(82))
    expect(computer.joystick2.port_bits & 0x1f).to eq(0b11110)
  end

  it "swaps the arrows to joystick 1 with F9" do
    run(tab, key(Badline::Frontend::Keys::F9), key(82))
    expect(computer.joystick1.port_bits & 0x1f).to eq(0b11110)
  end

  it "presses the 1351's button with the mouse's" do
    run(tab, tab, event(sdl::MOUSEBUTTONDOWN, [0, 1, 1].pack("LC2")))
    expect(computer.control_ports.device1.port_bits & 0x1f).to eq(0b01111)
  end

  it "steps back through the modes with shift-Tab" do
    run(key(Badline::Frontend::Keys::TAB, mod: sdl::KMOD_SHIFT))
    expect(computer.control_ports.device2).to be_a(Badline::Input::Paddles)
  end

  describe "snapshots" do
    it "saves one with F11" do
      run(key(Badline::Frontend::Keys::F11))
      expect(Dir.glob("badline-*.vsf").size).to eq(1)
    end

    it "runs the one F12 restores in place of the machine before" do
      expect { run(key(Badline::Frontend::Keys::F11), key(Badline::Frontend::Keys::F12)) }
        .to output(/Restored badline-.*\.vsf/).to_stdout
    end

    it "has nothing to restore before one is saved" do
      expect { run(key(Badline::Frontend::Keys::F12)) }.to output(/No snapshot to restore/).to_stdout
    end
  end

  describe "with --verbose" do
    it "reports the frame rate and the sound every 50 frames" do
      expect { run(argv: %w[--frames 50 --verbose --sound]) }
        .to output(%r{fps, per frame ms: events .*\n  sound \d+ samples/s}).to_stdout
    end

    it "mutes with F10" do
      expect { run(key(Badline::Frontend::Keys::F10), argv: %w[--frames 50 --verbose --sound]) }
        .to output(%r{sound 0 samples/s}).to_stdout
    end
  end

  describe "a true drive" do
    it "draws its LED in the border, lit as the drive powers on" do
      Badline::Media::TrueDrive.plug(computer)
      run(argv: %w[--frames 1 --screenshot led.bmp])
      expect(led_pixel("led.bmp")).to eq([0x20, 0x20, 0xff])
    end

    # The blue, green and red of the pixel at the LED's centre, from a
    # bottom-up 24-bit BMP at twice the texture's size.
    def led_pixel(path)
      bmp = File.binread(path)
      offset, width, height = bmp.unpack("@10L@18l2")
      x = (Badline::Frontend::DriveLed::LEFT + 6) * 2
      y = height - 1 - ((Badline::Frontend::DriveLed::TOP + 2) * 2)
      bmp.unpack("@#{offset + (y * (((width * 3) + 3) / 4) * 4) + (x * 3)}C3")
    end
  end
end
