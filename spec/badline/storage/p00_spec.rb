# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::P00 do
  let(:header) { "C64File\x00".bytes + "GAME".bytes + ([0] * 12) + [0, 0] }
  let(:file_bytes) { header + [0x01, 0x08, 0x99] }

  describe ".wraps?" do
    it "recognizes the magic" do
      expect(described_class.wraps?(file_bytes)).to be(true)
    end

    it "rejects a bare PRG" do
      expect(described_class.wraps?([0x01, 0x08, 0x99])).to be(false)
    end
  end

  describe ".name" do
    it "returns the embedded filename" do
      expect(described_class.name(file_bytes)).to eq("game")
    end
  end

  describe ".data" do
    it "returns the payload after the header" do
      expect(described_class.data(file_bytes)).to eq([0x01, 0x08, 0x99])
    end
  end

  describe ".load_address" do
    let(:path) { File.join(Dir.mktmpdir, "game") }

    after { FileUtils.remove_entry(File.dirname(path)) }

    def load_address(bytes)
      File.binwrite(path, bytes.pack("C*"))
      described_class.load_address(path)
    end

    it "reads a bare PRG's" do
      expect(load_address([0x01, 0x1c, 0x99])).to eq(0x1c01)
    end

    it "reads the one after a P00's header" do
      expect(load_address(file_bytes)).to eq(0x0801)
    end

    it "is -1 for a file too short to have one" do
      expect(load_address([0x01])).to eq(-1)
    end

    it "is -1 for a P00 header with no program after it" do
      expect(load_address(header)).to eq(-1)
    end
  end
end
