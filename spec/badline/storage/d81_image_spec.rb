# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::D81Image do
  subject(:image) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "test.d81") }
  let(:bytes) { Array.new(819_200, 0) }
  let(:dir_offset) { ((39 * 40) + 3) * 256 } # track 40, sector 3
  let(:data_offset) { 49 * 40 * 256 } # track 50

  before do
    bytes[dir_offset + 2] = 0x82
    bytes[dir_offset + 3] = 50
    bytes[dir_offset + 4] = 0
    bytes[dir_offset + 5, 16] = "DATA".bytes + ([0xa0] * 12)
    bytes[data_offset, 6] = [0, 5, 0x00, 0xc0, 0xaa, 0xbb]
    File.binwrite(path, bytes.pack("C*"))
  end

  after { FileUtils.remove_entry(dir) }

  describe "#read_file" do
    it "reads the directory at track 40" do
      expect(image.read_file("data")).to eq([0x00, 0xc0, 0xaa, 0xbb])
    end

    it "returns nil for an unknown name" do
      expect(image.read_file("missing")).to be_nil
    end
  end

  describe "#read_block" do
    it "uses the flat 40-sector geometry" do
      expect(image.read_block(50, 0).first(6)).to eq([0, 5, 0x00, 0xc0, 0xaa, 0xbb])
    end

    it "returns nil past the track's sector count" do
      expect(image.read_block(50, 40)).to be_nil
    end
  end

  describe "#header_block" do
    it "starts the directory track" do
      expect(image.header_block).to eq([40, 0])
    end
  end

  describe "#new_entry_block" do
    it "starts at the first directory block" do
      expect(image.new_entry_block).to eq([40, 3])
    end
  end
end
