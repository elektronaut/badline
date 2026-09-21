# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::D71Image do
  subject(:image) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "test.d71") }
  let(:bytes) { Array.new(349_696, 0) }
  let(:dir_offset) { ((17 * 21) + 1) * 256 } # track 18, sector 1
  let(:data_offset) { (683 + (4 * 21)) * 256 } # track 40, second side

  before do
    bytes[dir_offset + 2] = 0x82
    bytes[dir_offset + 3] = 40
    bytes[dir_offset + 4] = 0
    bytes[dir_offset + 5, 16] = "DATA".bytes + ([0xa0] * 12)
    bytes[data_offset, 6] = [0, 5, 0x00, 0xc0, 0xaa, 0xbb]
    File.binwrite(path, bytes.pack("C*"))
  end

  after { FileUtils.remove_entry(dir) }

  describe "#read_file" do
    it "reads files stored on the second side" do
      expect(image.read_file("data")).to eq([0x00, 0xc0, 0xaa, 0xbb])
    end

    it "returns nil for an unknown name" do
      expect(image.read_file("missing")).to be_nil
    end
  end

  describe "#read_block" do
    it "reads blocks on the second side" do
      expect(image.read_block(40, 0).first(6)).to eq([0, 5, 0x00, 0xc0, 0xaa, 0xbb])
    end

    it "returns nil past the end of the image" do
      expect(image.read_block(71, 0)).to be_nil
    end
  end
end
