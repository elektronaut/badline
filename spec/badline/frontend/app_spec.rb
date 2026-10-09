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

  def app(*argv)
    parsed = options(*argv)
    described_class.new(computer, parsed, Badline::Frontend::Timeline.new(parsed))
  end

  # Opens the window, queues the events and runs until the frame limit or
  # a quit.
  def run(*events, argv: %w[--frames 2])
    window = app(*argv)
    events.each { |event| sdl.SDL_PushEvent(event.ljust(56, "\0")) }
    window.run
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

    it "stops at an --at insert that fails" do
      File.write("bad.crt", "junk")
      allow($stderr).to receive(:write)
      run(argv: %w[--frames 5 --at 1:insert=bad.crt])
      expect(computer.cycles).to eq(frame_cycles)
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

  it "switches the keys back to the keyboard with a second Tab" do
    allow(computer.keyboard).to receive(:press)
    run(tab, tab, key(82))
    expect(computer.keyboard).to have_received(:press).with(:cursor_up)
  end

  describe "the pause menu" do
    def f9 = key(Badline::Frontend::Keys::F9)

    it "holds the machine while it's open" do
      run(f9, key(41))
      expect(computer.cycles).to eq(2 * frame_cycles)
    end

    it "keeps the keys after F9 from the machine" do
      allow(computer.keyboard).to receive(:press)
      run(f9, key(4), key(41))
      expect(computer.keyboard).not_to have_received(:press)
    end

    it "opens at --at's menu and holds the machine" do
      run(argv: %w[--frames 5 --at 2:menu])
      expect(computer.cycles).to eq(2 * frame_cycles)
    end

    it "counts the frames it's open for towards --frames" do
      allow(computer).to receive(:reset!)
      run(argv: %w[--frames 6 --at 2:menu --at 4:reset])
      expect(computer).to have_received(:reset!)
    end

    it "saves --at's screenshots of it" do
      run(argv: %w[--frames 4 --at 2:menu=ports --at 3:screenshot=menu.bmp])
      expect(File.binread("menu.bmp", 2)).to eq("BM")
    end

    it "draws it over the frozen picture in the screenshot" do
      run(argv: %w[--frames 3 --at 2:screenshot=running.bmp --at 2:menu --at 3:screenshot=menu.bmp])
      expect(File.binread("menu.bmp")).not_to eq(File.binread("running.bmp"))
    end

    it "runs the machine on at --at's resume" do
      run(argv: %w[--frames 6 --at 2:menu --at 4:resume])
      expect(computer.cycles).to eq(4 * frame_cycles)
    end

    it "plugs a 1351 into port 1, whose button the mouse's presses" do
      keys = [81, 81, 81, 81, 79, 40, 41].map { |scancode| key(scancode) }
      run(f9, *keys, event(sdl::MOUSEBUTTONDOWN, [0, 1, 1].pack("LC2")))
      expect(computer.control_ports.device1.port_bits & 0x1f).to eq(0b01111)
    end
  end

  describe "snapshots" do
    around do |example|
      Dir.mktmpdir do |dir|
        Badline.data_path = dir
        example.run
      end
    ensure
      Badline.data_path = nil
    end

    it "quicksaves with F11" do
      run(key(Badline::Frontend::Keys::F11))
      expect(Dir.children(Badline.data_folder("quicksaves"))).to eq(["quicksave-1.vsf"])
    end

    it "runs the one F12 restores in place of the machine before" do
      expect { run(key(Badline::Frontend::Keys::F11), key(Badline::Frontend::Keys::F12)) }
        .to output(/Restored quicksave 1 from /).to_stdout
    end

    it "swaps in a VIC-20 F12 restores, in the VIC-20's window" do
      Badline::Vic20.new.save_snapshot(File.join(Badline.data_folder("saves"), "vic20.vsf"))
      run(key(Badline::Frontend::Keys::F12), argv: %w[--frames 2 --screenshot swapped.bmp])
      expect(File.binread("swapped.bmp").unpack("@18l2")).to eq([284 * 2 * 2, 284 * 2])
    end

    it "has nothing to restore before one is saved" do
      expect { run(key(Badline::Frontend::Keys::F12)) }.to output(/No quicksave to restore/).to_stdout
    end
  end

  describe "with --verbose", :slow do
    it "reports the frame rate and the sound every 50 frames" do
      expect { run(argv: %w[--frames 50 --verbose --sound]) }
        .to output(%r{fps, per frame ms: events .*\n  sound \d+ samples/s}).to_stdout
    end

    it "mutes with F10" do
      expect { run(key(Badline::Frontend::Keys::F10), argv: %w[--frames 50 --verbose --sound]) }
        .to output(%r{sound 0 samples/s}).to_stdout
    end
  end

  describe "with a VIC-20" do
    let(:computer) { Badline::Vic20.new }
    let(:frame_cycles) { 71 * 312 }

    def options(*argv) = Badline::Options.parse(["vic20", "--unpaced", *argv])

    it "runs its frames" do
      run
      expect(computer.cycles).to eq(2 * frame_cycles)
    end

    it "shows its 284 by 284 picture with each pixel two wide" do
      run(argv: %w[--frames 1 --screenshot vic20.bmp])
      expect(File.binread("vic20.bmp").unpack("@18l2")).to eq([284 * 2 * 2, 284 * 2])
    end

    it "lets go of RESTORE as the key comes up" do
      restore = Badline::Frontend::Keys::OTHERS.key(:restore)
      allow(computer).to receive(:release_restore)
      run(key(restore), key(restore, down: false))
      expect(computer).to have_received(:release_restore)
    end

    it "drives its one joystick with both sets of keys" do
      run(tab, key(82), key(22))
      expect(computer.joystick1.port_bits & 0x1f).to eq(0b11100)
    end

    describe "snapshots" do
      around do |example|
        Dir.mktmpdir do |dir|
          Badline.data_path = dir
          example.run
        end
      ensure
        Badline.data_path = nil
      end

      def f11 = key(Badline::Frontend::Keys::F11)

      it "quicksaves it with F11, as a VIC20 snapshot" do
        run(f11)
        quicksave = File.join(Badline.data_folder("quicksaves"), "quicksave-1.vsf")
        expect(Badline::Snapshot.read(quicksave).container.machine).to eq("VIC20")
      end

      it "runs the one F12 restores in its place" do
        expect { run(f11, key(Badline::Frontend::Keys::F12)) }.to output(/Restored quicksave 1 from /).to_stdout
      end
    end
  end

  describe "with a C128" do
    let(:computer) { Badline::C128.new }

    def options(*argv) = Badline::Options.parse(["c128", "--unpaced", *argv])

    def f8 = key(Badline::Frontend::Keys::F8)

    def size(path) = File.binread(path).unpack("@18l2")

    # The VDC programmed for one line of 80 characters of 8 dots, the
    # horizontal sync 8 characters long, and 25 rows of 8 lines with 4
    # lines of vertical sync, as the C128's editor sets it up.
    def program_vdc
      { 0 => 126, 1 => 80, 2 => 102, 3 => 0x48, 4 => 38, 6 => 25, 7 => 32, 9 => 7, 22 => 0x78 }.each do |reg, value|
        computer.vdc.poke(0xd600, reg)
        computer.vdc.poke(0xd601, value)
      end
    end

    it "shows the VIC-IIe's screen" do
      run(argv: %w[--frames 1 --screenshot vic.bmp])
      expect(size("vic.bmp")).to eq([384 * 2, 272 * 2])
    end

    it "switches to the VDC with F8, rendering it in place of the VIC-IIe" do
      run(f8)
      expect([computer.vdc.render, computer.vic.render?]).to eq([true, false])
    end

    it "switches back to the VIC-IIe with F8 again" do
      run(f8, f8)
      expect([computer.vdc.render, computer.vic.render?]).to eq([false, true])
    end

    it "switches to the VDC once the machine prints there" do
      allow(computer).to receive(:active_screen).and_return(:vdc)
      run(argv: %w[--frames 4])
      expect(computer.vdc.render).to be(true)
    end

    it "fits the window to the VDC's display at a display event, a dot a window pixel and its lines doubled" do
      program_vdc
      run(argv: %w[--frames 3 --at 1:display=vdc --screenshot vdc.bmp])
      expect(size("vdc.bmp")).to eq([(127 - 8) * 8, 308 * 2])
    end

    it "presses the C128's keypad keys" do
      run(key(89), argv: %w[--frames 1])
      expect(computer.keyboard.keys).to eq([:keypad1])
    end

    describe "snapshots" do
      around do |example|
        Dir.mktmpdir do |dir|
          Badline.data_path = dir
          example.run
        end
      ensure
        Badline.data_path = nil
      end

      it "quicksaves it with F11, as a C128 snapshot" do
        run(key(Badline::Frontend::Keys::F11))
        quicksave = File.join(Badline.data_folder("quicksaves"), "quicksave-1.vsf")
        expect(Badline::Snapshot.read(quicksave).container.machine).to eq("C128")
      end
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
      x = (384 - 8 - 12 + 6) * 2
      y = height - 1 - ((272 - 6 - 4 + 2) * 2)
      bmp.unpack("@#{offset + (y * (((width * 3) + 3) / 4) * 4) + (x * 3)}C3")
    end
  end
end
