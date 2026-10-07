# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "badline/ffi"
require "badline/frontend"
require_relative "../../support/blank_disk"

describe Badline::Frontend::Timeline do
  include BlankDisk

  subject(:timeline) { described_class.new(Badline::Options.parse(argv)) }

  let(:computer) { Badline::Computer.new }
  let(:argv) { [] }

  def at(*events) = events.flat_map { |event| ["--at", event] }

  # Runs the timeline's events from frame 1 to the last one given.
  def run_to(frame)
    (1..frame).each { |number| timeline.run(computer, number) }
  end

  def quietly
    stdout = $stdout
    stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
  ensure
    $stdout = stdout
    $stderr = stderr
  end

  describe ".error" do
    def error(*events) = described_class.error(Badline::Options.parse(at(*events)).timeline)

    it "takes C64 keys, RESTORE and the joysticks' switches" do
      expect(error("1:key=space", "1:key=cursor_up", "1:key=restore", "1:key=joy1-fire")).to eq("")
    end

    it "names the first key that names nothing" do
      expect(error("1:key=a", "2:key=joy3-up", "3:key=hyper")).to eq("no such key: joy3-up")
    end

    it "takes the pause menu's pages, or none" do
      expect(error("1:menu", "2:menu=snapshots", "3:menu=expansion", "4:menu=power")).to eq("")
    end

    it "names a menu page that names nothing" do
      expect(error("1:menu=drive", "2:menu=printer")).to eq("no such menu page: printer")
    end
  end

  describe ".path" do
    {
      "shot.bmp" => "shot.bmp", "shot%d.bmp" => "shot42.bmp", "shot%05d.bmp" => "shot00042.bmp",
      "shot%4d.bmp" => "shot  42.bmp", "shot%s.bmp" => "shot%s.bmp"
    }.each do |pattern, path|
      it "names frame 42 of #{pattern} #{path}" do
        expect(described_class.path(pattern, 42)).to eq(path)
      end
    end
  end

  describe "a key" do
    let(:argv) { at("2:key=space") }

    it "is pressed once its frame has run" do
      run_to(2)
      expect(computer.keyboard.keys).to eq([:space])
    end

    it "is let go five frames later" do
      run_to(7)
      expect(computer.keyboard.keys).to be_empty
    end

    it "waits for its frame" do
      run_to(1)
      expect(computer.keyboard.keys).to be_empty
    end
  end

  describe "a joystick switch" do
    let(:argv) { at("1:key=joy1-up") }

    it "is pressed on its joystick" do
      run_to(1)
      expect(computer.joystick1.port_bits & 0x1f).to eq(0b11110)
    end

    it "is let go" do
      run_to(6)
      expect(computer.joystick1.port_bits & 0x1f).to eq(0b11111)
    end
  end

  describe "RESTORE" do
    let(:argv) { at("1:key=restore") }

    it "pulses NMI" do
      allow(computer).to receive(:press_restore)
      run_to(1)
      expect(computer).to have_received(:press_restore)
    end

    it "is let go five frames later" do
      allow(computer).to receive(:release_restore)
      run_to(6)
      expect(computer).to have_received(:release_restore)
    end
  end

  describe "typing" do
    let(:argv) { at('1:type=print 6*7\n') }

    it "types through the keyboard buffer, with \\n for RETURN" do
      allow(computer).to receive(:type_text)
      run_to(1)
      expect(computer).to have_received(:type_text).with("print 6*7\r")
    end
  end

  describe "media" do
    let(:dir) { Dir.mktmpdir }
    let(:disk) { blank_d64(File.join(dir, "second.d64")) }

    after { FileUtils.remove_entry(dir) }

    context "when a disk goes in" do
      let(:argv) { at("1:insert=#{disk}") }

      it "mounts it in device 8 without loading anything" do
        expect { run_to(1) }.to output(/Mounted .*second\.d64 as device 8/).to_stdout
      end
    end

    context "when a list of disks goes in" do
      let(:list) { File.join(dir, "disks.vfl") }
      let(:argv) { at("1:insert=#{list}") }

      it "mounts its first disk in device 8" do
        File.write(list, "UNIT 8\n#{File.basename(disk)}\n")
        expect { run_to(1) }.to output(/Mounted .*second\.d64 as device 8/).to_stdout
      end
    end

    context "when the disk comes out" do
      let(:argv) { at("1:insert=#{disk}", "2:eject=disk") }

      it "leaves device 8 empty" do
        quietly { run_to(1) }
        expect { timeline.run(computer, 2) }.to output(/Ejected the disk/).to_stdout
                                                                          .and(change(computer, :mounted?).to(false))
      end
    end

    context "when the true drive's disk comes out" do
      let(:argv) { at("1:eject=disk") }

      it "empties the drive" do
        drive = Badline::Media::TrueDrive.plug(computer)
        drive.insert(Badline::Drive1541::Disk.open(disk))
        expect { run_to(1) }.to output.to_stdout.and(change(drive, :disk).to(nil))
      end
    end

    context "when the tape comes out" do
      let(:argv) { at("1:eject=tape") }

      it "ejects the datasette's" do
        computer.datasette.insert(Badline::Storage::TAP.new(tape))
        expect { run_to(1) }.to output(/Ejected the tape/).to_stdout.and(change(computer.datasette, :tape).to(nil))
      end

      def tape
        File.join(dir, "game.tap").tap { |path| File.binwrite(path, "C64-TAPE-RAW".b + ("\0" * 8)) }
      end
    end

    %w[disk tape cartridge].each do |what|
      context "when there's no #{what} to take out" do
        let(:argv) { at("1:eject=#{what}") }

        it "says so" do
          expect { run_to(1) }.to output("No #{what} to eject\n").to_stdout
        end

        it "runs on" do
          quietly { run_to(1) }
          expect(timeline).not_to be_failed
        end
      end
    end

    context "when the true drive is empty" do
      let(:argv) { at("1:eject=disk") }

      it "has no disk to take out" do
        Badline::Media::TrueDrive.plug(computer)
        expect { run_to(1) }.to output("No disk to eject\n").to_stdout
      end
    end

    context "when a file won't go in" do
      let(:argv) do
        File.write(File.join(dir, "bad.crt"), "junk")
        at("1:insert=#{File.join(dir, 'bad.crt')}", "1:reset")
      end

      it "warns" do
        expect { run_to(1) }.to output(/badline-ruby: .*bad\.crt: Missing CRT signature/).to_stderr
      end

      it "fails, ending the run" do
        quietly { run_to(1) }
        expect(timeline).to be_failed
      end

      it "skips the frame's other events" do
        allow(computer).to receive(:reset!)
        quietly { run_to(1) }
        expect(computer).not_to have_received(:reset!)
      end
    end
  end

  describe "the cartridge" do
    let(:argv) { at("1:eject=cartridge") }

    it "power-cycles the machine without it" do
      computer.connect_cartridge(Badline::Cartridge.from_file(cartridge))
      allow(computer).to receive(:power_cycle!)
      expect { run_to(1) }.to output.to_stdout.and(change { computer.address_bus.cartridge }.to(nil))
    end

    it "leaves a machine without one running" do
      allow(computer).to receive(:power_cycle!)
      quietly { run_to(1) }
      expect(computer).not_to have_received(:power_cycle!)
    end

    def cartridge
      crt = Badline::Storage::CRTFile
      chip = crt::Chip.new(chip_type: 0, bank: 0, address: 0x8000, data: Array.new(8192, 0))
      image = crt::Image.new(hardware_type: 0, subtype: 0, exrom: 0, game: 1, name: "GAME", chips: [chip])
      File.join(Dir.mktmpdir, "game.crt").tap { |path| crt.write(path, image) }
    end
  end

  describe "the reset" do
    let(:argv) { at("3:reset") }

    it "pulls the RES line" do
      allow(computer).to receive(:reset!)
      run_to(3)
      expect(computer).to have_received(:reset!)
    end
  end

  describe "the freeze button" do
    let(:argv) { at("1:freeze") }

    it "is pressed and let go" do
      allow(computer).to receive_messages(press_cartridge_button: nil, release_cartridge_button: nil)
      run_to(6)
      expect(computer).to have_received(:release_cartridge_button)
    end
  end

  describe "#press_freeze" do
    it "presses the freeze button for the pause menu, and lets go of it as an event does" do
      allow(computer).to receive_messages(press_cartridge_button: nil, release_cartridge_button: nil)
      timeline.press_freeze(computer, 3)
      (4..9).each { |frame| timeline.run(computer, frame) }
      expect(computer).to have_received(:release_cartridge_button).once
    end
  end

  describe "screenshots and quitting" do
    let(:argv) { %w[--frames 9 --screenshot last.bmp --at 3,6:screenshot=shot%d.bmp --at 7:quit] }

    it "names the frame's screenshots" do
      expect([timeline.screenshots(6), timeline.screenshots(9), timeline.screenshots(5)])
        .to eq([["shot6.bmp"], ["last.bmp"], []])
    end

    it "quits at quit's frame" do
      expect([timeline.quit?(6), timeline.quit?(7)]).to eq([false, true])
    end
  end

  describe "the pause menu" do
    let(:argv) { at("3:menu", "5:menu=sound", "8:resume") }

    it "opens at menu's frames" do
      expect([2, 3, 5].map { |frame| timeline.menu?(frame) }).to eq([false, true, true])
    end

    it "opens on the page it names, or on the first" do
      expect([timeline.menu_section(3), timeline.menu_section(5)]).to eq([0, 5])
    end

    it "closes at resume's frame" do
      expect([timeline.resume?(5), timeline.resume?(8)]).to eq([false, true])
    end
  end
end
