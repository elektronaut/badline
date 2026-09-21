# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

describe Badline::Storage::T64 do
  subject(:archive) { described_class.new(path) }

  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "test.t64") }
  let(:bytes) { Array.new(0x40 + (3 * 32), 0) }
  let(:data_offset) { 0x40 + (3 * 32) }

  before do
    bytes[0, 32] = "C64S tape image file".bytes + ([0x20] * 12)
    bytes[0x22, 2] = [3, 0] # directory size
    bytes[0x24, 2] = [2, 0] # used entries
    write_entry(0, type: 1, name: "DATA", load: 0xc000, size: 258)
    write_entry(1, type: 0, name: "FREE", load: 0x0801, size: 4)
    bytes.concat([0x11] * 258)
    bytes.concat([0x55] * 16)
    File.binwrite(path, bytes.pack("C*"))
  end

  after { FileUtils.remove_entry(dir) }

  def write_entry(index, type:, name:, load:, size:)
    at = 0x40 + (index * 32)
    bytes[at] = type
    bytes[at + 1] = 0x82
    bytes[at + 2, 4] = [load, load + size].pack("v2").bytes
    bytes[at + 8, 4] = [data_offset].pack("V").bytes
    bytes[at + 16, 16] = name.bytes + ([0x20] * (16 - name.length))
  end

  describe "#read_file" do
    it "prepends the load address from the directory entry" do
      expect(archive.read_file("data").first(2)).to eq([0x00, 0xc0])
    end

    it "reads the length given by the start and end addresses" do
      expect(archive.read_file("data").length).to eq(260)
    end

    it "reads the file data" do
      expect(archive.read_file("data").last(4)).to eq([0x11] * 4)
    end

    it "matches names with wildcards" do
      expect(archive.read_file("d*")).to eq(archive.read_file("data"))
    end

    it "returns the first file for a bare wildcard" do
      expect(archive.read_file("*").first(2)).to eq([0x00, 0xc0])
    end

    it "ignores free directory entries" do
      expect(archive.read_file("free")).to be_nil
    end

    it "returns nil for an unknown name" do
      expect(archive.read_file("missing")).to be_nil
    end

    context "when the entry name is NUL padded" do
      before do
        bytes[0x40 + 16, 16] = "NULS".bytes + ([0x00] * 12)
        File.binwrite(path, bytes.pack("C*"))
      end

      it "strips the padding" do
        expect(archive.read_file("nuls").length).to eq(260)
      end
    end

    context "when the end address runs past the archive" do
      before do
        bytes[0x40 + 4, 2] = [0xc6, 0xc3] # the classic bogus end address
        File.binwrite(path, bytes.pack("C*"))
      end

      it "stops at the end of the file" do
        expect(archive.read_file("data").length).to eq(276)
      end
    end

    context "when the used count understates the directory" do
      before do
        bytes[0x24, 2] = [0, 0]
        write_entry(2, type: 1, name: "LAST", load: 0x0801, size: 2)
        File.binwrite(path, bytes.pack("C*"))
      end

      it "still finds the entry" do
        expect(archive.read_file("last").first(2)).to eq([0x01, 0x08])
      end
    end
  end

  describe ".new" do
    it "rejects a file without the signature" do
      File.binwrite(path, "NOTAT64" * 16)
      expect { archive }.to raise_error(described_class::FormatError)
    end
  end

  it "does not respond to write_file" do
    expect(archive).not_to respond_to(:write_file)
  end
end
