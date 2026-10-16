# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Storage::D80Image do
  include BlankDisk

  subject(:image) { described_class.new(blank_d80(path, name: "BLANK80", id: "AB")) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "blank.d80") }

  after { FileUtils.remove_entry(dir) }

  describe "#sectors_in" do
    it "holds 29, 27, 25 and 23 sectors in the four zones" do
      expect([1, 39, 40, 53, 54, 64, 65, 77].map { |track| image.sectors_in(track) })
        .to eq([29, 29, 27, 27, 25, 25, 23, 23])
    end
  end

  describe "#directory" do
    it "reads the name and the ID from the header at 39/0" do
      expect([image.directory.name, image.directory.id])
        .to eq(["BLANK80".bytes + ([0xa0] * 9), "AB".bytes + [0xa0, 0x32, 0x43]])
    end

    it "counts the free blocks of every track but the directory's" do
      expect(image.directory.blocks_free).to eq(2052)
    end
  end

  describe "#read_block" do
    it "finds the last track's last block" do
      expect(image.read_block(77, 22)).to eq(Array.new(256, 0))
    end

    it "has no block past the last track's sectors" do
      expect(image.read_block(77, 23)).to be_nil
    end
  end

  describe "#block_free?" do
    it "keeps the BAM's blocks on track 38 in use and frees the rest of it" do
      expect((0..4).map { |sector| image.block_free?(38, sector) }).to eq([false, true, true, false, true])
    end
  end

  describe "#write_file" do
    before { image.write_file("game", (0...600).map { |i| i & 0xff }) }

    it "reads the file back" do
      expect(described_class.new(path).read_file("game")).to eq((0...600).map { |i| i & 0xff })
    end

    it "takes its three blocks from the free count" do
      expect(described_class.new(path).directory.blocks_free).to eq(2049)
    end
  end
end
