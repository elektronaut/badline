# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require "badline/c128"

describe Badline::Media::TrueDrive do
  let(:dir) { Dir.mktmpdir }
  let(:machine) { Badline::C128.new }

  after { FileUtils.remove_entry(dir) }

  def image(name, size)
    File.join(dir, name).tap { |path| File.binwrite(path, "\x00".b * size) }
  end

  context "with a C128" do
    it "plugs in the C128D's 1571" do
      expect(described_class.plug(machine)).to be_a(Badline::Drive1571)
    end

    it "puts a .d71 in the 1571" do
      path = image("disk.d71", 349_696)
      expect(described_class.insert(machine, path)).to eq("Inserted #{path} in the 1571 as device 8")
    end

    it "takes a .d71 once the 1571 is device 8" do
      described_class.plug(machine)
      expect(described_class.takes?(machine, image("disk.d71", 349_696))).to be(true)
    end

    it "puts a .d81 in a 1581" do
      path = image("disk.d81", 819_200)
      expect(described_class.insert(machine, path)).to eq("Inserted #{path} in the 1581 as device 8")
    end

    it "makes the 1581 the true drive" do
      described_class.insert(machine, image("disk.d81", 819_200))
      expect(machine.true_drive).to equal(machine.drive1581)
    end

    it "swaps the 1571 out for the 1581" do
      described_class.plug(machine)
      described_class.insert(machine, image("disk.d81", 819_200))
      expect(machine.drive1571).to be_nil
    end

    it "swaps the 1571 back in for a .d71" do
      described_class.insert(machine, image("disk.d81", 819_200))
      described_class.insert(machine, image("disk.d71", 349_696))
      expect([machine.drive1581, machine.true_drive]).to eq([nil, machine.drive1571])
    end

    it "refuses a .t64" do
      described_class.plug(machine)
      expect { described_class.insert(machine, image("tape.t64", 64)) }
        .to raise_error(described_class::Error, /\.d64, \.g64, \.d71, \.g71 or \.d81/)
    end

    it "makes the 1571 the true drive" do
      described_class.plug(machine)
      expect(machine.true_drive).to equal(machine.drive1571)
    end
  end

  context "with a C64" do
    let(:machine) { Badline::Computer.new }

    it "plugs in a 1581 for a .d81" do
      described_class.insert(machine, image("disk.d81", 819_200))
      expect(machine.true_drive).to be_a(Badline::Drive1581)
    end

    it "unplugs the 1541 it takes the place of" do
      described_class.plug(machine)
      described_class.insert(machine, image("disk.d81", 819_200))
      expect(machine.drive1541).to be_nil
    end

    it "puts a .d64 back in a 1541" do
      described_class.insert(machine, image("disk.d81", 819_200))
      described_class.insert(machine, image("disk.d64", 174_848))
      expect(machine.true_drive).to be_a(Badline::Drive1541)
    end
  end
end
