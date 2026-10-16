# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"
require_relative "../../support/blank_disk"

describe Badline::Snapshot::StorageSetup do
  include BlankDisk

  let(:dir) { Dir.mktmpdir }
  let(:disk) do
    File.join(dir, "disk.d64").tap { |file| blank_d64(file) }
  end

  after { FileUtils.remove_entry(dir) }

  def reopened(storage, detached:)
    out = Badline::Snapshot::Keyed::Writer.new
    described_class.write_fields(storage, out)
    described_class.read_fields(Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TRAPDOS")), detached:)
  end

  it "opens a disk image as it was" do
    expect(reopened(Badline::Storage::D64Image.new(disk), detached: false)).to be_writable
  end

  it "opens a disk image write-protected for a detached reader" do
    expect(reopened(Badline::Storage::D64Image.new(disk), detached: true)).not_to be_writable
  end

  { "an 8050's" => [Badline::Storage::D80Image, 1],
    "an 8250's" => [Badline::Storage::D82Image, 2] }.each do |name, (kind, sides)|
    it "opens #{name} disk image as the same kind" do
      image = kind.new(blank_d80(File.join(dir, "disk.d8#{2 * (sides - 1)}"), sides:))
      expect(reopened(image, detached: false).class).to be(kind)
    end
  end

  describe "a .t64 archive" do
    let(:archive) do
      entry = [1, 0x82, 0x01, 0x08, 0x03, 0x08, 0, 0, 0x60, 0, 0, 0, 0, 0, 0, 0]
      header = "C64S tape image file".ljust(0x20, "\0").b + [0x0100, 1, 1, 0].pack("vvvv") + "TAPE".ljust(24)
      File.join(dir, "tape.t64").tap do |file|
        File.binwrite(file, header + entry.pack("C*") + "PROG".ljust(16) + "\xea\x60".b)
      end
    end

    def reopened_without_file(detached:)
      out = Badline::Snapshot::Keyed::Writer.new
      described_class.write_fields(Badline::Storage::T64.new(archive), out)
      File.delete(archive)
      described_class.read_fields(Badline::Snapshot::Keyed::Reader.parse(out.section("BL-TRAPDOS")), detached:)
    end

    it "serves its files once the archive's file is gone" do
      expect(reopened_without_file(detached: false).read_file("PROG")).to eq([0x01, 0x08, 0xea, 0x60])
    end

    it "serves its files for a detached reader" do
      expect(reopened_without_file(detached: true).read_file("PROG")).to eq([0x01, 0x08, 0xea, 0x60])
    end
  end

  it "leaves a directory's files alone for a detached reader" do
    storage = reopened(Badline::Storage::HostDirectory.new(dir), detached: true)
    expect { storage.write_file("NEW", [1, 2], type: :prg) }.to raise_error(Badline::Storage::WriteError)
  end

  it "finds no files in a directory for a detached reader" do
    File.binwrite(File.join(dir, "prog.prg"), "\x01\x08".b)
    expect(reopened(Badline::Storage::HostDirectory.new(dir), detached: true).read_file("PROG")).to be_nil
  end
end
