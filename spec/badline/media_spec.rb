# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Media do
  let(:computer) { Badline::Computer.new }
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def sid_tune(songs: 1, flags: 0x0004)
    File.join(dir, "tune.sid").tap do |path|
      header = "PSID".b + [2, 0x7c, 0x1000, 0x1000, 0x1020, songs, 1].pack("n7") +
               ("\x00" * 4) + "TUNE".ljust(96, "\x00") + [flags, 0, 0].pack("n3")
      File.binwrite(path, header + [0xa9, 0x00, 0x60].pack("C*"))
    end
  end

  describe ".sid_model" do
    it "takes a tune's own model" do
      expect(described_class.sid_model(sid_tune(flags: 0x0024))).to eq(:mos8580)
    end

    it "fits a 6581 for a tune that doesn't insist on an 8580" do
      expect(described_class.sid_model(sid_tune(flags: 0x0034))).to eq(:mos6581)
    end

    it "fits a 6581 for other media" do
      expect(described_class.sid_model(File.join(dir, "game.d64"))).to eq(:mos6581)
    end

    it "fits a 6581 with no media" do
      expect(described_class.sid_model(nil)).to eq(:mos6581)
    end
  end

  describe ".attach" do
    context "with a directory" do
      it "mounts it as device 8" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, dir)
        expect(computer)
          .to have_received(:mount)
          .with(instance_of(Badline::Storage::HostDirectory))
      end

      it "returns a mount message" do
        expect(described_class.attach(computer, dir)).to include("device 8")
      end
    end

    context "with a D64 image" do
      let(:d64_path) do
        File.join(dir, "disk.d64").tap do |path|
          File.binwrite(path, "\x00" * 174_848)
        end
      end

      it "mounts it as device 8" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, d64_path)
        expect(computer)
          .to have_received(:mount)
          .with(instance_of(Badline::Storage::D64Image))
      end

      it "types the autostart command" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, d64_path)
        expect(computer)
          .to have_received(:type_text).with(%(lO"*",8,1\rrun\r))
      end

      it "skips autostart when disabled" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, d64_path, autostart: false)
        expect(computer).not_to have_received(:type_text)
      end

      it "returns a mount message" do
        expect(described_class.attach(computer, d64_path))
          .to include("device 8")
      end

      it "mounts it read-write" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, d64_path)
        expect(computer).to have_received(:mount).with(having_attributes(read_only?: false))
      end

      it "mounts it write-protected with disk: { read_only: true }" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, d64_path, disk: { read_only: true })
        expect(computer).to have_received(:mount).with(having_attributes(read_only?: true))
      end
    end

    context "with a G64 image" do
      let(:g64_path) do
        File.join(dir, "disk.g64").tap do |path|
          Badline::Storage::G64Image.create(path, { 34 => [Array.new(7142, 0x55), 2] })
        end
      end

      it "plugs in a true drive as device 8 and puts the disk in it" do
        described_class.attach(computer, g64_path)
        expect([computer.drive1541.device, computer.drive1541.disk.track(36).length]).to eq([8, 7142])
      end

      it "mounts nothing through the traps" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, g64_path)
        expect(computer).not_to have_received(:mount)
      end

      it "keeps a true drive already plugged in" do
        drive = Badline::Drive1541.new
        computer.attach_drive1541(drive)
        described_class.attach(computer, g64_path)
        expect([computer.drive1541.equal?(drive), drive.disk.nil?]).to eq([true, false])
      end

      it "types the autostart command" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, g64_path)
        expect(computer).to have_received(:type_text).with(%(lO"*",8,1\rrun\r))
      end

      it "returns a message naming the drive" do
        expect(described_class.attach(computer, g64_path, autostart: false)).to include("1541", "device 8")
      end

      it "puts the disk in writable" do
        described_class.attach(computer, g64_path)
        expect(computer.drive1541.disk.write_protected?).to be(false)
      end

      it "puts the disk in write-protected with disk: { read_only: true }" do
        described_class.attach(computer, g64_path, disk: { read_only: true })
        expect(computer.drive1541.disk.write_protected?).to be(true)
      end
    end

    context "with a D71 image" do
      let(:d71_path) do
        File.join(dir, "disk.d71").tap do |path|
          File.binwrite(path, "\x00" * 349_696)
        end
      end

      it "mounts it as device 8" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, d71_path)
        expect(computer)
          .to have_received(:mount)
          .with(instance_of(Badline::Storage::D71Image))
      end
    end

    context "with a D81 image" do
      let(:d81_path) do
        File.join(dir, "disk.d81").tap do |path|
          File.binwrite(path, "\x00" * 819_200)
        end
      end

      it "mounts it as device 8" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, d81_path)
        expect(computer)
          .to have_received(:mount)
          .with(instance_of(Badline::Storage::D81Image))
      end

      it "mounts it write-protected with disk: { read_only: true }" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, d81_path, disk: { read_only: true })
        expect(computer).to have_received(:mount).with(having_attributes(read_only?: true))
      end
    end

    context "with a T64 archive" do
      let(:t64_path) do
        File.join(dir, "tape.t64").tap do |path|
          File.binwrite(path, "C64S tape image file".ljust(0x40, "\x00"))
        end
      end

      it "mounts it as device 8" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, t64_path)
        expect(computer)
          .to have_received(:mount)
          .with(instance_of(Badline::Storage::T64))
      end

      it "mounts it with disk: { read_only: true }" do
        allow(computer).to receive(:mount)
        described_class.attach(computer, t64_path, disk: { read_only: true })
        expect(computer).to have_received(:mount).with(instance_of(Badline::Storage::T64))
      end

      it "types the autostart command" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, t64_path)
        expect(computer)
          .to have_received(:type_text).with(%(lO"*",8,1\rrun\r))
      end
    end

    context "with a TAP image" do
      let(:tap_path) do
        File.join(dir, "game.tap").tap do |path|
          header = "C64-TAPE-RAW".b + [1, 0, 0, 0].pack("C4") + [3].pack("V")
          File.binwrite(path, header + [0x30, 0x30, 0x30].pack("C*"))
        end
      end

      it "loads the tape into the datasette" do
        described_class.attach(computer, tap_path)
        expect(computer.datasette.tape).to be_a(Badline::Storage::TAP)
      end

      it "presses play" do
        described_class.attach(computer, tap_path)
        expect(computer.datasette).to be_playing
      end

      it "types the tape autostart command" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, tap_path)
        expect(computer).to have_received(:type_text).with(%(lO\rrun\r))
      end

      it "skips autostart when disabled" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, tap_path, autostart: false)
        expect(computer).not_to have_received(:type_text)
      end

      it "returns an insert message" do
        expect(described_class.attach(computer, tap_path)).to include("game.tap")
      end
    end

    context "with a CRT file" do
      let(:crt_path) do
        File.join(dir, "game.crt").tap do |path|
          header = "C64 CARTRIDGE   ".b + [0x40, 0x0100, 0, 0, 1].pack("NnnCC") +
                   ("\x00" * 6) + ("\x00" * 32)
          chip = "CHIP".b + [0x2010, 0, 0, 0x8000, 0x2000].pack("Nn4") +
                 ([0x42] * 0x2000).pack("C*")
          File.binwrite(path, header + chip)
        end
      end

      it "attaches the cartridge" do
        allow(computer).to receive(:attach_cartridge)
        described_class.attach(computer, crt_path)
        expect(computer)
          .to have_received(:attach_cartridge)
          .with(instance_of(Badline::Cartridge::Standard))
      end

      it "returns an attach message" do
        allow(computer).to receive(:attach_cartridge)
        expect(described_class.attach(computer, crt_path))
          .to include("game.crt")
      end

      it "sets the cartridge's jumpers" do
        allow(computer).to receive(:attach_cartridge)
        allow(Badline::Cartridge).to receive(:from_file)
        described_class.attach(computer, crt_path, cartridge: { flash_jumper: true })
        expect(Badline::Cartridge).to have_received(:from_file).with(crt_path, flash_jumper: true)
      end

      it "leaves the disk options to disk images" do
        allow(computer).to receive(:attach_cartridge)
        allow(Badline::Cartridge).to receive(:from_file)
        described_class.attach(computer, crt_path, disk: { read_only: true })
        expect(Badline::Cartridge).to have_received(:from_file).with(crt_path)
      end
    end

    context "with a SID tune" do
      let(:sid_path) { sid_tune(songs: 3) }

      before { allow(computer).to receive(:on_init).and_yield }

      it "loads the tune at its load address" do
        described_class.attach(computer, sid_path)
        expect(computer.ram.read(0x1000, 3)).to eq([0xa9, 0x00, 0x60])
      end

      it "installs the player stub" do
        described_class.attach(computer, sid_path)
        expect(computer.ram.read(0x0334, 3)).to eq([0x4c, 0x4c, 0x03])
      end

      it "SYSes the player stub" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, sid_path)
        expect(computer).to have_received(:type_text).with("sys820\r")
      end

      it "skips the SYS when autostart is disabled" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, sid_path, autostart: false)
        expect(computer).not_to have_received(:type_text)
      end

      it "returns the tune name" do
        expect(described_class.attach(computer, sid_path)).to include("TUNE")
      end

      it "plays the header's own song by default" do
        described_class.attach(computer, sid_path)
        expect(computer.ram.read(0x0354, 2)).to eq([0xa9, 0x00])
      end

      it "plays the requested song" do
        described_class.attach(computer, sid_path, song: 3)
        expect(computer.ram.read(0x0354, 2)).to eq([0xa9, 0x02])
      end

      it "clamps the requested song" do
        described_class.attach(computer, sid_path, song: 9)
        expect(computer.ram.read(0x0354, 2)).to eq([0xa9, 0x02])
      end

      it "names the song it picked" do
        expect(described_class.attach(computer, sid_path, song: 2))
          .to include("song 2")
      end
    end

    context "with a machine-language PRG file" do
      let(:prg_path) do
        File.join(dir, "test.prg").tap do |path|
          File.binwrite(path, [0x00, 0x10, 0x99].pack("C*"))
        end
      end

      before { allow(computer).to receive(:on_init).and_yield }

      it "loads the program on init" do
        described_class.attach(computer, prg_path)
        expect(computer.ram.read(0x1000, 1)).to eq([0x99])
      end

      it "does not type RUN" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path)
        expect(computer).not_to have_received(:type_text)
      end

      it "returns a loading message" do
        expect(described_class.attach(computer, prg_path))
          .to include("test.prg")
      end
    end

    context "with a BASIC PRG file" do
      let(:prg_path) do
        File.join(dir, "basic.prg").tap do |path|
          File.binwrite(path, [0x01, 0x08, 0x99, 0x00].pack("C*"))
        end
      end

      before { allow(computer).to receive(:on_init).and_yield }

      it "types RUN after loading" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path)
        expect(computer).to have_received(:type_text).with("run\r")
      end

      it "points VARTAB past the program" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path)
        expect(computer.ram.read(0x2d, 2)).to eq([0x03, 0x08])
      end

      # Pinned by C64/autostart/basic (basictest, printpoint, printpoint2)
      it "leaves the end address where the KERNAL's LOAD does" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path)
        expect(computer.ram.read(0xae, 2)).to eq([0x03, 0x08])
      end

      it "skips RUN when autostart is disabled" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path, autostart: false)
        expect(computer).not_to have_received(:type_text)
      end
    end

    context "with a BASIC PRG file loaded a byte ahead of BASIC start" do
      let(:prg_path) do
        File.join(dir, "early.prg").tap do |path|
          File.binwrite(path, [0x00, 0x08, 0x00, 0x99, 0x00].pack("C*"))
        end
      end

      before { allow(computer).to receive(:on_init).and_yield }

      it "types RUN after loading" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path)
        expect(computer).to have_received(:type_text).with("run\r")
      end
    end

    context "with a PRG file that starts itself through a vector" do
      let(:prg_path) do
        File.join(dir, "vector.prg").tap do |path|
          File.binwrite(path, ([0x26, 0x03] + ([0xea] * 0x600)).pack("C*"))
        end
      end

      before { allow(computer).to receive(:on_init).and_yield }

      it "does not type RUN, though it runs past BASIC start" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path)
        expect(computer).not_to have_received(:type_text)
      end

      it "leaves VARTAB alone" do
        vartab = computer.ram.read(0x2d, 2)
        described_class.attach(computer, prg_path)
        expect(computer.ram.read(0x2d, 2)).to eq(vartab)
      end
    end

    context "with a P00 file" do
      let(:p00_path) do
        File.join(dir, "game.p00").tap do |path|
          header = "C64File\x00GAME#{"\x00" * 14}".b
          File.binwrite(path, header + [0x00, 0x10, 0x42].pack("C*"))
        end
      end

      it "strips the header before loading" do
        allow(computer).to receive(:on_init).and_yield
        described_class.attach(computer, p00_path)
        expect(computer.ram.read(0x1000, 1)).to eq([0x42])
      end
    end
  end

  describe ".insert_disk" do
    let(:d64_path) do
      File.join(dir, "disk.d64").tap { |path| File.binwrite(path, "\x00" * 174_848) }
    end

    before { allow(computer).to receive(:mount) }

    it "mounts a disk image" do
      described_class.insert_disk(computer, d64_path)
      expect(computer).to have_received(:mount).with(instance_of(Badline::Storage::D64Image))
    end

    it "inserts a disk image write-protected with read_only" do
      described_class.insert_disk(computer, d64_path, read_only: true)
      expect(computer).to have_received(:mount).with(having_attributes(read_only?: true))
    end

    it "mounts a directory" do
      described_class.insert_disk(computer, dir)
      expect(computer).to have_received(:mount).with(instance_of(Badline::Storage::HostDirectory))
    end

    it "loads nothing" do
      allow(computer).to receive(:type_text)
      described_class.insert_disk(computer, d64_path)
      expect(computer).not_to have_received(:type_text)
    end

    it "returns a message" do
      expect(described_class.insert_disk(computer, d64_path)).to eq("Inserted #{d64_path} in device 8")
    end

    it "refuses anything but a disk" do
      path = File.join(dir, "tape.t64")
      expect { described_class.insert_disk(computer, path) }.to raise_error(ArgumentError)
    end

    context "with a G64 image" do
      let(:g64_path) do
        File.join(dir, "disk.g64").tap do |path|
          Badline::Storage::G64Image.create(path, { 34 => [Array.new(7142, 0x55), 2] })
        end
      end

      before { allow(computer).to receive(:unmount) }

      it "puts it in the true drive, plugging one in" do
        described_class.insert_disk(computer, g64_path)
        expect([computer.drive1541.disk.track(36).length, computer.drive1541.device]).to eq([7142, 8])
      end

      it "takes out what was mounted through the traps" do
        described_class.insert_disk(computer, g64_path)
        expect(computer).to have_received(:unmount)
      end

      it "inserts it write-protected with read_only" do
        described_class.insert_disk(computer, g64_path, read_only: true)
        expect(computer.drive1541.disk.write_protected?).to be(true)
      end
    end

    context "with a true drive in device 8" do
      before do
        computer.attach_drive1541(Badline::Drive1541.new)
        allow(computer).to receive(:unmount)
      end

      it "puts a D64 image in the drive" do
        described_class.insert_disk(computer, d64_path)
        expect(computer.drive1541.disk.image).to be_a(Badline::Storage::D64Image)
      end

      it "mounts nothing through the traps" do
        described_class.insert_disk(computer, d64_path)
        expect(computer).not_to have_received(:mount)
      end

      it "inserts a D64 image write-protected with read_only" do
        described_class.insert_disk(computer, d64_path, read_only: true)
        expect(computer.drive1541.disk.write_protected?).to be(true)
      end

      it "refuses a disk the 1541 can't read" do
        expect { described_class.insert_disk(computer, dir) }.to raise_error(ArgumentError, /\.d64 or \.g64/)
      end
    end
  end
end
