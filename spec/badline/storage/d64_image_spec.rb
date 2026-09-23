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
    write_entry(2, type: 0x80, name: "GONE", track: 17, sector: 5)
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
    bytes[data_offset + (5 * 256), 4] = [0, 3, 0x33, 0x44]
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

    it "reads only PRG files by default" do
      expect(image.read_file("notes")).to be_nil
    end

    it "reads a SEQ file by its type" do
      expect(image.read_file("notes", type: :seq)).to eq([0x33, 0x44])
    end

    it "skips files of another type" do
      expect(image.read_file("*", type: :seq)).to eq([0x33, 0x44])
    end

    it "matches any type without one" do
      expect(image.read_file("n*", type: nil)).to eq([0x33, 0x44])
    end

    it "never reads a deleted file" do
      expect(image.read_file("gone", type: nil)).to be_nil
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

  describe "#block_error" do
    it "reports no error for an image without an error table" do
      expect(image.block_error(17, 0)).to be_nil
    end

    context "with an error table" do
      before do
        errors = Array.new(683, 1)
        errors[(17 * 21) + 18] = 5 # track 18, sector 18
        errors[(16 * 21) + 1] = 15 # track 17, sector 1
        File.binwrite(path, (bytes + errors).pack("C*"))
      end

      it "reports a clean block as readable" do
        expect(image.block_error(17, 0)).to be_nil
      end

      it "maps a checksum error to DOS error 23" do
        expect(image.block_error(18, 18)).to eq(23)
      end

      it "maps a missing drive to DOS error 74" do
        expect(image.block_error(17, 1)).to eq(74)
      end

      it "keeps the table out of the blocks" do
        expect(image.read_block(36, 0)).to be_nil
      end

      it "still reads files" do
        expect(image.read_file("data").length).to eq(258)
      end
    end

    context "with 40 tracks and no error table" do
      before do
        File.binwrite(path, (bytes + Array.new(85 * 256, 0)).pack("C*"))
      end

      it "reads the extra tracks as blocks" do
        expect(image.read_block(40, 16)).to eq(Array.new(256, 0))
      end

      it "reports no error" do
        expect(image.block_error(40, 16)).to be_nil
      end
    end

    context "with 40 tracks and an error table" do
      before do
        errors = Array.new(768, 1)
        errors[767] = 5 # track 40, sector 16
        File.binwrite(path, (bytes + Array.new(85 * 256, 0) + errors).pack("C*"))
      end

      it "maps the last block's error" do
        expect(image.block_error(40, 16)).to eq(23)
      end

      it "keeps the table out of the blocks" do
        expect(image.read_block(41, 0)).to be_nil
      end

      it "still reads files" do
        expect(image.read_file("data").length).to eq(258)
      end
    end

    context "with 42 tracks and no error table" do
      before do
        File.binwrite(path, (bytes + Array.new(119 * 256, 0)).pack("C*"))
      end

      it "reads the extra tracks as blocks" do
        expect(image.read_block(42, 16)).to eq(Array.new(256, 0))
      end

      it "stops at the 17th sector of track 42" do
        expect(image.read_block(42, 17)).to be_nil
      end

      it "reports no error" do
        expect(image.block_error(42, 16)).to be_nil
      end
    end

    context "with 42 tracks and an error table" do
      before do
        errors = Array.new(802, 1)
        errors[801] = 5 # track 42, sector 16
        errors[683] = 2 # track 36, sector 0
        File.binwrite(path, (bytes + Array.new(119 * 256, 0) + errors).pack("C*"))
      end

      it "maps the last block's error" do
        expect(image.block_error(42, 16)).to eq(23)
      end

      it "maps the first extra track's error" do
        expect(image.block_error(36, 0)).to eq(20)
      end

      it "keeps the table out of the blocks" do
        expect(image.read_block(43, 0)).to be_nil
      end

      it "still reads files" do
        expect(image.read_file("data").length).to eq(258)
      end
    end
  end
end
