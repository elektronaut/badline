# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::D64Image do
  subject(:image) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "test.d64") }
  let(:bytes) { Array.new(174_848, 0) }
  let(:dir_offset) { ((17 * 21) + 1) * 256 } # track 18, sector 1
  let(:data_offset) { 16 * 21 * 256 } # track 17, sector 0

  before do
    write_entry(0, type: 0x82, name: "DATA", track: 17, sector: 0)
    write_entry(1, type: 0x81, name: "NOTES", track: 17, sector: 5)
    write_chain
    File.binwrite(path, bytes.pack("C*"))
  end

  after { FileUtils.remove_entry(dir) }

  def write_entry(index, type:, name:, track:, sector:)
    offset = dir_offset + (index * 32)
    bytes[offset + 2] = type
    bytes[offset + 3] = track
    bytes[offset + 4] = sector
    bytes[offset + 5, 16] = name.bytes + ([0xa0] * (16 - name.length))
  end

  def write_chain
    bytes[data_offset, 2] = [17, 1] # next: track 17, sector 1
    bytes[data_offset + 2, 254] = [0x00, 0xc0] + ([0x11] * 252)
    bytes[data_offset + 256, 6] = [0, 5, 0x22, 0x22, 0x22, 0x22]
  end

  describe "#read_file" do
    it "follows the sector chain" do
      expect(image.read_file("data").length).to eq(258)
    end

    it "starts with the load address" do
      expect(image.read_file("DATA").first(2)).to eq([0x00, 0xc0])
    end

    it "reads up to the last-byte marker in the final sector" do
      expect(image.read_file("data").last(4)).to eq([0x22] * 4)
    end

    it "matches names with wildcards" do
      expect(image.read_file("d*")).to eq(image.read_file("data"))
    end

    it "returns the first PRG for a bare wildcard" do
      expect(image.read_file("*").first(2)).to eq([0x00, 0xc0])
    end

    it "ignores non-PRG files" do
      expect(image.read_file("notes")).to be_nil
    end

    it "returns nil for an unknown name" do
      expect(image.read_file("missing")).to be_nil
    end
  end

  describe "#read_block" do
    it "returns the whole sector" do
      expect(image.read_block(17, 0).length).to eq(256)
    end

    it "reads the sector's own bytes" do
      expect(image.read_block(17, 0).first(4)).to eq([17, 1, 0x00, 0xc0])
    end

    it "addresses the last sector of a track" do
      expect(image.read_block(17, 1).first(2)).to eq([0, 5])
    end

    it "returns nil past the track's sector count" do
      expect(image.read_block(25, 18)).to be_nil
    end

    it "returns nil for track 0" do
      expect(image.read_block(0, 0)).to be_nil
    end

    it "returns nil past the end of the image" do
      expect(image.read_block(36, 0)).to be_nil
    end
  end
end
