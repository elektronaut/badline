# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/frontend/media_slots"
require_relative "../../support/blank_disk"

describe Badline::Frontend::MediaSlots do
  include BlankDisk

  let(:computer) { Badline::Computer.new }
  let(:dir) { Dir.mktmpdir }
  let(:disk) { blank_d64(File.join(dir, "game.d64")) }

  after { FileUtils.remove_entry(dir) }

  context "with a disk mounted through the traps" do
    before { Badline::Media.insert_disk(computer, disk) }

    it "has a disk in" do
      expect(described_class.disk?(computer)).to be(true)
    end

    it "gives the disk's expanded path" do
      expect(described_class.disk_path(computer)).to eq(File.expand_path(disk))
    end

    it "ejects it" do
      expect { described_class.eject_disk(computer) }.to change(computer, :mounted?).to(false)
    end
  end

  context "with a disk in the true drive" do
    let(:drive) { Badline::Media::TrueDrive.plug(computer) }

    before { drive.insert(Badline::Drive1541::Disk.open(disk)) }

    it "has a disk in" do
      expect(described_class.disk?(computer)).to be(true)
    end

    it "gives the disk's path" do
      expect(described_class.disk_path(computer)).to eq(disk)
    end

    it "ejects it" do
      expect { described_class.eject_disk(computer) }.to change(drive, :disk).to(nil)
    end
  end

  context "with a true drive on another device than 8" do
    before do
      drive = Badline::Drive1541.new(device: 9)
      computer.attach_drive1541(drive)
      drive.insert(Badline::Drive1541::Disk.open(disk))
    end

    it "looks at device 8's traps instead" do
      expect([described_class.disk?(computer), described_class.disk_path(computer)]).to eq([false, ""])
    end
  end

  context "with nothing in device 8" do
    it "has no disk in" do
      expect(described_class.disk?(computer)).to be(false)
    end

    it "gives an empty path" do
      expect(described_class.disk_path(computer)).to eq("")
    end
  end

  it "takes the cartridge out and power cycles the machine" do
    allow(computer).to receive(:power_cycle!)
    described_class.remove_cartridge(computer)
    expect(computer).to have_received(:power_cycle!)
  end
end
