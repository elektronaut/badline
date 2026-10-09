# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Drive1541::Disk, ".open" do
  let(:dir) { Dir.mktmpdir }
  let(:side) { described_class::SIDE }
  let(:reader) { Badline::Drive1541::SectorReader }

  after { FileUtils.remove_entry(dir) }

  context "with a .d71" do
    subject(:disk) { described_class.open(path) }

    let(:path) { File.join(dir, "disk.d71") }

    # A .d71 whose blocks of track 36 hold +fill+, or their sector number.
    def d71(at, fill = nil)
      bytes = Array.new(349_696, 0)
      21.times { |sector| bytes[(683 + sector) * 256, 256] = Array.new(256, fill || sector) }
      File.binwrite(at, bytes.pack("C*"))
      at
    end

    before { d71(path) }

    it "puts track 36 on the second side's track 1" do
      expect(reader.read(disk.track(side + 2).bytes, 36).length).to eq(21)
    end

    it "lays track 36 out at track 1's rate" do
      expect(disk.track(side + 2).zone).to eq(3)
    end

    it "holds track 36's blocks there" do
      expect(reader.read(disk.track(side + 2).bytes, 36)[5].data[1, 256]).to eq(Array.new(256, 5))
    end

    it "leaves the first side's track 1 to track 1" do
      expect(reader.read(disk.track(2).bytes, 1).length).to eq(21)
    end

    it "stores a second side's track written back as track 36" do
      other = described_class.open(d71(File.join(dir, "other.d71"), 0x77))
      disk.write(side + 2, other.track(side + 2))
      disk.written(side + 2)
      disk.flush
      expect(Badline::Storage::D71Image.new(path).read_block(36, 3)).to eq(Array.new(256, 0x77))
    end
  end

  context "with a .g71" do
    subject(:disk) { described_class.open(path) }

    let(:path) { File.join(dir, "disk.g71") }
    let(:tracks) { { 0 => [Array.new(7692, 0x11), 3], 84 => [Array.new(7692, 0x22), 3] } }

    before do
      Badline::Storage::G64Image.create(path, tracks, half_tracks: 168)
      data = File.binread(path)
      data[0, 8] = "GCR-1571"
      File.binwrite(path, data)
    end

    it "puts entry 84 on the second side's track 1" do
      expect(disk.track(side + 2).bytes).to eq(tracks[84].first)
    end

    it "puts entry 0 on the first side's track 1" do
      expect(disk.track(2).bytes).to eq(tracks[0].first)
    end

    it "writes the second side's track 1 back to entry 84" do
      disk.write(side + 2, Badline::Drive1541::Track.new(Array.new(7692, 0x33), 3))
      disk.written(side + 2)
      disk.flush
      expect(Badline::Storage::G64Image.new(path).track(84).first.first(2)).to eq([0x33, 0x33])
    end
  end

  context "with a .d64" do
    it "has a blank second side" do
      path = File.join(dir, "disk.d64")
      File.binwrite(path, "\x00".b * 174_848)
      expect(described_class.open(path).track(side + 2)).to be_nil
    end
  end
end
