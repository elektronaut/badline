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

    it "refuses a .d81" do
      expect { described_class.insert(machine, image("disk.d81", 819_200)) }
        .to raise_error(described_class::Error, /\.d64, \.g64, \.d71 or \.g71/)
    end

    it "makes the 1571 the true drive" do
      described_class.plug(machine)
      expect(machine.true_drive).to equal(machine.drive1571)
    end
  end
end
