# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Media do
  let(:computer) { Badline::Computer.new }
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

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

      it "types the autostart command" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, t64_path)
        expect(computer)
          .to have_received(:type_text).with(%(lO"*",8,1\rrun\r))
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
    end

    context "with a SID tune" do
      let(:sid_path) do
        File.join(dir, "tune.sid").tap do |path|
          header = "PSID".b + [2, 0x7c, 0x1000, 0x1000, 0x1020, 1, 1].pack("n7") +
                   ("\x00" * 4) + "TUNE".ljust(96, "\x00") + [0x0004, 0, 0].pack("n3")
          File.binwrite(path, header + [0xa9, 0x00, 0x60].pack("C*"))
        end
      end

      before { allow(computer).to receive(:on_init).and_yield }

      it "loads the tune at its load address" do
        described_class.attach(computer, sid_path)
        expect(computer.ram.read(0x1000, 3)).to eq([0xa9, 0x00, 0x60])
      end

      it "installs the player stub" do
        described_class.attach(computer, sid_path)
        expect(computer.ram.read(0x0334, 3)).to eq([0x4c, 0x42, 0x03])
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

      it "skips RUN when autostart is disabled" do
        allow(computer).to receive(:type_text)
        described_class.attach(computer, prg_path, autostart: false)
        expect(computer).not_to have_received(:type_text)
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
end
