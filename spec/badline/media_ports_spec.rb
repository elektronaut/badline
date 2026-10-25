# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Media do
  let(:dir) { Dir.mktmpdir }
  let(:d64_path) { File.join(dir, "game.d64").tap { |path| File.binwrite(path, "\x00" * 174_848) } }
  let(:tap_path) do
    File.join(dir, "game.tap").tap do |path|
      File.binwrite(path, "C64-TAPE-RAW".b + [1, 0, 0, 0].pack("C4") + [3].pack("V") + [0x30, 0x30, 0x30].pack("C*"))
    end
  end

  after { FileUtils.remove_entry(dir) }

  def machine(model) = Badline::Machine.build(:c64, model:)

  describe "the C64GS, which has no serial port or cassette port" do
    let(:computer) { machine("c64gs") }

    it "refuses a disk image" do
      expect { described_class.attach(computer, d64_path) }
        .to raise_error(Badline::Machine::Unsupported, "#{d64_path} needs the serial port, and the C64GS has none")
    end

    it "refuses a host directory" do
      expect { described_class.attach(computer, dir) }.to raise_error(Badline::Machine::Unsupported, /serial port/)
    end

    it "refuses a disk swapped in while it runs" do
      expect { described_class.insert_disk(computer, d64_path) }
        .to raise_error(Badline::Machine::Unsupported, /serial port/)
    end

    it "refuses a true drive" do
      expect { Badline::Media::TrueDrive.plug(computer) }.to raise_error(Badline::Machine::Unsupported, /C64GS/)
    end

    it "refuses a tape" do
      expect { described_class.attach(computer, tap_path) }.to raise_error(Badline::Drives::Datasette::Missing)
    end
  end

  describe "the MAX Machine, which has a cassette port and no serial port" do
    let(:computer) { machine("ultimax") }

    it "refuses a disk image" do
      expect { described_class.attach(computer, d64_path) }
        .to raise_error(Badline::Machine::Unsupported, /the MAX Machine has none/)
    end

    it "takes a tape" do
      described_class.attach(computer, tap_path, autostart: false)
      expect(computer.datasette.tape).to be_a(Badline::Storage::TAP)
    end
  end

  describe "the PET 64, on a C64's board" do
    it "mounts a disk image as device 8" do
      expect(described_class.attach(machine("pet64"), d64_path, autostart: false)).to include("device 8")
    end
  end
end
